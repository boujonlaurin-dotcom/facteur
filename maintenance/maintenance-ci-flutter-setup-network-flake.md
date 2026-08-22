# Maintenance — CI flaky : téléchargement Flutter SDK échoue (mobile-tests.yml)

## Contexte

CI rouge sur PR #1110, job **« Analyze + tests widget d'accueil »**
(`.github/workflows/mobile-tests.yml`), GitHub Job ID 97023186740.

## Root cause

Ce n'est **pas un bug de code**. L'étape `subosito/flutter-action@v2` (Setup
Flutter) télécharge l'archive du SDK Flutter via `curl` dans son
`setup.sh` interne, et ce téléchargement a échoué :

```
curl: (35) Recv failure: Connection reset by peer
##[error]Process completed with exit code 35.
```

Flutter n'a donc jamais été installé sur le runner, ce qui fait échouer en
cascade toutes les étapes suivantes avec `flutter: command not found`
(exit 127) :
- `Install dependencies` (implicite, jamais loggée car la panne est avant)
- `Tests du widget d'accueil`
- `Tests de composition de la Tournée`
- `Tests d'authentification`

C'est une panne réseau **transitoire** côté infra GitHub Actions / CDN de
téléchargement Flutter (`storage.googleapis.com`), pas un problème lié à la
PR #1110 ni au code du repo.

## Plan

1. **Immédiat** : relancer le job (« Re-run failed jobs ») — un simple retry
   suffit très probablement, aucune modif de code nécessaire.
2. **Durcissement** (évite que ça reproduise à chaque flake réseau) : ajouter
   un retry autour de l'étape `Setup Flutter` dans
   `.github/workflows/mobile-tests.yml`, via
   `nick-fields/retry@v3` (action déjà standard, pas de script maison) :
   - `max_attempts: 3`
   - `timeout_minutes: 10`
   - `command: flutter --version` (ou action composite existante)

   Comme `subosito/flutter-action@v2` est un `uses:` (pas un `run:`), on
   l'enveloppe avec `nick-fields/retry@v3` en `command:` invoquant l'action
   via un sous-job n'est pas possible directement (une `uses:` step ne
   s'enveloppe pas). Alternative retenue : garder `subosito/flutter-action@v2`
   tel quel (il est fiable à 99%+, cette panne est un flake ponctuel) et ne
   PAS sur-ingénierer un retry pour un incident isolé — cf. mémoire
   `feedback_minimal_prs_reuse_scoring` (moins de PRs, ne pas ajouter de
   complexité pour un cas non récurrent).

3. **Décision** : pas de changement de code/workflow. Action = relancer le
   job CI de la PR #1110. Si le flake se reproduit sur plusieurs PRs dans les
   jours qui viennent, revisiter avec un vrai mécanisme de retry.

## Fichiers concernés

- `.github/workflows/mobile-tests.yml` (lu, non modifié)
