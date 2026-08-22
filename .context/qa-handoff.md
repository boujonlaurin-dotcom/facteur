# QA Handoff — Reader « Analyse des angles (6C) » front (Story 35.3)

> Input pour /validate-feature (agent QA, Playwright Agent CLI + skill
> `facteur-qa-web`). Compte de test : mémoire `reference_qa_staging_account`.
> ⚠️ Viewport web bloqué 1680px (mémoire `project_qa_web_viewport_stuck…`) :
> le layout mobile est validé par widget tests + getRect ; ici on valide
> textes, interactions et absence d'erreurs console/réseau.

## Feature développée
Le Reader câble le contrat 6C de #1109 (`consensus` + `display` sur
`GET /contents/{id}/perspectives`) : CTA « Comparer les {N} angles » en haut
d'article (avec les 2 constats du bloc `cta`), section basse renommée
« Analyse des angles ({qualificatif}) » réordonnée (constats → footnote →
barre de biais → « N médias en parlent » → carrousel), carte « Analyse
complète IA » déplacée en fin de carrousel, encart solo sans cloche, état
`throttled` du POST analyze rendu en message sans « Réessayer ».

## PR associée
Branche `boujonlaurin-dotcom/reader-consensus-6c-front-plan` → PR vers `main`
(voir `gh pr view`).

## Écrans impactés
| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Reader article | `/flaner/content/:id` (ou depuis l'Essentiel) | Modifié (CTA haut + section basse) |
| Bottom sheet « Analyse Facteur » | ouvert depuis la carte IA | Modifié (état throttled) |

## Scénarios de test

### Scénario 1 : Happy path — sujet couvert 3+ médias avec analyse
**Parcours** :
1. Se connecter avec le compte QA, ouvrir un article de la Tournée couvert par
   3+ médias (pastille « N sources »).
2. Attendre le chargement des perspectives (le CTA haut apparaît en fondu).
3. Vérifier le CTA haut : « Comparer les {N} angles », pile de logos, puis 1
   accord (icône ✓) et/ou 1 désaccord (icône ⇄) si l'analyse est disponible.
4. Taper le CTA → scroll animé vers la section « Analyse des angles » + flash
   orangé bref.
5. Vérifier l'ordre de la section : constats (≤3 ✓ puis ≤2 ⇄, logos inline,
   « +N ») → barre de biais → « {N} médias en parlent » → carrousel.
6. Scroller le carrousel jusqu'au bout → carte « Analyse complète IA » en
   DERNIÈRE position, bouton « Lancer » → le bottom sheet s'ouvre.
**Résultat attendu** : header « Analyse des angles (polarisé|avis variés|avis
convergents) » ; AUCUN badge « POLARISÉ » sous la barre ; `{N}` identique
partout (CTA, sous-titre, carte IA) = `coverage_count`.

### Scénario 2 : Edge — analyse pending / sujet 2 médias
**Parcours** :
1. Ouvrir un article couvert par exactement 2 médias.
2. Vérifier : CTA haut « Comparer les 2 angles » (ligne d'entrée seule ou +
   sablier si analyse en cours) ; section basse SANS barre de biais et SANS
   carte IA ; carrousel présent.
3. Si analyse en cours : footnote sablier « Les accords et désaccords… pas
   encore disponibles ».
**Résultat attendu** : gates backend respectées (2 médias → pas de barre, pas
de carte IA) ; pas de skeleton pour le CTA haut avant chargement (rien, puis
fade-in).

### Scénario 3 : Cas limite — source unique / erreur réseau
**Parcours** :
1. Ouvrir un article couvert par 1 seul média.
2. Vérifier le CTA haut : encart texte « {Source} est pour l'instant la seule
   rédaction… », SANS cloche « Me prévenir », sans carrousel en bas.
3. (Si simulable) Couper le réseau avant l'ouverture d'un article : ni CTA ni
   encart solo ne doivent apparaître (erreur ≠ solo).
**Résultat attendu** : encart informatif sobre ; jamais d'encart solo sur une
erreur réseau.

### Scénario 4 : Throttle du POST analyze (si cap atteint)
**Parcours** :
1. Lancer l'analyse via la carte « Analyse complète IA ».
2. Si le backend renvoie `throttled: true` : le sheet affiche « Beaucoup de
   demandes aujourd'hui… », sans bouton « Réessayer » ni shimmer.
**Résultat attendu** : message seul, articles restent consultables.

## Critères d'acceptation
- [ ] CTA haut présent dans les DEUX modes de lecture (scroll-to-site et
      lecture in-app), après le titre/temps de lecture, avant le corps.
- [ ] Tap CTA → scroll fluide vers la section + flash, pas de saut brutal.
- [ ] Aucune valeur `{N}` divergente entre CTA, sous-titre, carte IA.
- [ ] Qualificatif affiché UNE seule fois (header) ; badge POLARISÉ absent.
- [ ] Carte IA en fin de carrousel ; tap → sheet « Analyse Facteur ».
- [ ] Console sans erreurs, réseau sans 4xx/5xx inattendus ; UN seul GET
      perspectives par article (CTA et section partagent le fetch).

## Zones de risque
- Cohabitation brève possible « Recherche en cours… » (partial) × footnote
  sablier (pending) : acceptée, ne pas FAIL pour ça.
- Logos = favicons Google s2 : fallback initiale si non chargés (OK).
- Vieux backend sans blocs → gates dérivées localement du coverage_count
  (comportement proche de l'existant).

## Dépendances
- `GET /api/contents/{id}/perspectives` (blocs `consensus` + `display`, #1109).
- `POST /api/contents/{id}/perspectives/analyze` (`throttled`).
- Staging `api-staging-40d3` post-merge #1109.

## Gate restant (hors QA web)
- **Dry-run copy PO** : `PYTHONPATH=. python scripts/dryrun_consensus.py
  --tag 6c-pr1` (~20 appels mistral-large, read-only) — non exécutable depuis
  ce workspace (pas de `MISTRAL_API_KEY` ni de `DATABASE_URL` applicatif ;
  rôle RO sans grant sur `coverage_analyses`). À lancer par Laurin ou un
  agent avec les secrets backend.
