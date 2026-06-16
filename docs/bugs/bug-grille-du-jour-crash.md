# Bug — La Grille du jour : écran gris silencieux en prod

**Statut** : Corrigé (en attente de PR)
**Branche** : `claude/grille-du-jour-crash-oDgO8`
**Sévérité** : 🔴 Critique (prod — feature inutilisable + crash de l'onglet Essentiel)
**Release impactée** : `beta-20260531-0230` (Story 24.2 — module mobile La Grille)
**Plateforme remontée** : Android 16 (SM-A546E), Flutter 3.38.6 / Dart 3.10.7
**Fichiers critiques** :
- `apps/mobile/lib/features/grille/widgets/grille_cta_card.dart`
- `apps/mobile/lib/features/grille/providers/grille_provider.dart`
- `packages/api/app/main.py`
- `packages/api/app/services/grille_seed.py` (nouveau)
- `packages/api/scripts/seed_grille_puzzles.py`
- `packages/api/app/data/grille_puzzles_seed.json`

## Symptôme

Le matin du 2026-05-31, La Grille du jour (« mot du jour »), tout juste mise en
prod, ne fonctionne pas : l'onglet « L'Essentiel du jour » affiche un **très long
écran gris**, sans aucun message d'erreur (cf. screenshot utilisateur).

Sentry :

```
GrilleNotFoundException: GrilleNotFoundException
  File "grille_cta_card.dart", line 28, in _GrilleCtaCardState.build
  File "consumer.dart", line 539, in ConsumerStatefulElement.build
  File "common.dart", line 495, in AsyncError.value
handled = no · level = fatal · release = beta-20260531-0230
```

## Diagnostic — double cause, défaillance silencieuse

### #1 — Cause racine (backend / données) : `grille_puzzles` vide en prod

La migration `gr01_la_grille_du_jour` (jouée au boot Railway via le `Dockerfile`)
crée la table `grille_puzzles` mais **ne seed aucune donnée** (DDL pure, conforme
au principe « Alembic = schéma seulement »).

Le seed des puzzles (`scripts/seed_grille_puzzles.py`) était **manuel uniquement**
— absent du `Dockerfile`, du scheduler et du lifespan. Il n'a jamais été exécuté
en prod. Vérification Supabase au moment de l'incident :

```sql
SELECT count(*) FROM grille_puzzles;          -- 0
SELECT version_num FROM alembic_version;        -- gr01_la_grille_du_jour
```

Conséquence : `GET /api/grille/today` lève `PuzzleNotFound` →
**HTTP 404 pour tous les utilisateurs** (`grille_service.get_today`, `grille.py`).

### #2 — Amplificateur (frontend) : `.value` re-lève au lieu d'absorber

`grille_cta_card.dart:28` (avant correctif) :

```dart
final today = ref.watch(grilleProvider).value?.today;
if (today == null) return const SizedBox.shrink();
```

La docstring de la carte promet « en loading/erreur, ne rend **rien** ». Mais en
Riverpod, `AsyncValue.value` **re-lève** l'exception quand le provider est en état
erreur (seul `.valueOrNull` rend `null` sans lever) — c'est exactement la frame
Sentry `common.dart:495 in AsyncError.value`.

Le 404 (mappé en `GrilleNotFoundException` par `GrilleRepository.getToday`)
s'échappait donc de `build()`. Non capturée, Flutter remplace le sous-arbre par
l'`ErrorWidget` par défaut (en release : un **conteneur gris** plein écran). La
carte CTA étant insérée comme sliver en bas de la Tournée
(`flux_continu_screen.dart:829`), c'est **tout le corps de l'onglet Essentiel**
qui s'effondre → long écran gris, sans message.

**Pourquoi « ce matin » et pas avant** : tant qu'un puzzle existait, `getToday()`
renvoyait des données et le bug restait latent. Le 31 mai, l'API renvoie 404 pour
la première fois en prod → premier passage par le chemin `AsyncError` → crash.

Un **second chemin latent** existait avec le même anti-pattern :
`grilleKeyboardStatesProvider` (`grille_provider.dart:205`, `async.value?.today`).
Non déclenché en prod (lu uniquement dans la branche `data` de l'écran Grille),
mais corrigé par cohérence pour fermer le risque.

## Correctifs

### Immédiat — débloquer la prod (fait)

Seed idempotent des 15 puzzles (30 mai → 13 juin) exécuté directement sur la DB
prod (upsert `ON CONFLICT (puzzle_date)`). `GET /grille/today` repasse 200, La
Grille refonctionne sans attendre un redéploiement de l'app.

### Durable #1 — frontend : crash supprimé définitivement

`grille_cta_card.dart:28` et `grille_provider.dart:205` (clavier) :
`.value?.today` → `.valueOrNull?.today`. La carte redevient `SizedBox.shrink()`
en erreur/loading comme documenté. **Robustifie l'app quel que soit l'état
backend** : même si un jour le puzzle manque à nouveau, plus de crash de
l'onglet — la carte disparaît simplement.

### Durable #2 — backend : seed automatique au démarrage

La logique d'upsert est extraite dans `app/services/grille_seed.py`
(`seed_puzzles(db)`), réutilisée par :
- `main.lifespan` (après le check migrations, best-effort, loggé + Sentry sur
  échec) → une table vide ne peut plus passer en prod silencieusement ;
- `scripts/seed_grille_puzzles.py` (devenu un simple wrapper d'exécution one-off).

Idempotent (upsert par `puzzle_date`), garde-fou dictionnaire conservé
(`SeedInvalidWord` si un `word` est hors `grille_words_fr.txt`).

## Tests

- `apps/mobile/test/features/grille/widgets/grille_cta_card_test.dart` :
  provider en erreur (`GrilleNotFoundException`) → aucune exception ne fuit de
  `build()`, `CarteCta` absente ; loading → rien ; data → carte rendue.
- `packages/api/tests/test_grille_seed.py` : seed peuple la table, est
  idempotent, calcule les dates affichées depuis le calendrier.

## Prévention

- Tout futur module à données seedées doit câbler son seed au démarrage (ou via
  migration de données dédiée), jamais le laisser manuel-only.
- Pattern Riverpod : dans un `build()` qui veut « disparaître » en erreur,
  utiliser `.valueOrNull`, jamais `.value` (qui re-lève).
