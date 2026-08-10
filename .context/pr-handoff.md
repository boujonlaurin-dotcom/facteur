# feat(essentiel): objectif réglable et pile de tri design 2A

## Quoi

La pile de tri de « Ton Essentiel » adopte le design 2A : cible journalière
réglable, progression intégrée au contrôle cible, balises de carte et liste
« TU GARDES ». Le pied de tri terminé devient une zone pointillée « Plus
d’articles ? » qui ajoute deux articles du même pool, suivie de l’action
discrète « Trier à nouveau ».

Un tap sur la carte ouvre désormais l’article sans décider. Si cet article est
effectivement lu avant le retour au feed, il est gardé automatiquement avec la
modalité API `read`.

## Pourquoi

Le précédent tri n’offrait ni contrôle explicite de la quantité d’articles à
lire, ni progression compréhensible sans segments. Il empêchait aussi la
lecture avant une décision, et son pied de fin ne suivait pas la maquette
« Essentiel v2 - propositions ».

## Fichiers modifiés

- Mobile : `essentiel_triage_provider.dart`, `essentiel_triage_stack.dart`,
  `essentiel_hi_fi_card.dart`, `triage_swipe_card.dart`, le squelette et le
  budget de layout associé.
- API : schéma et contrainte `decided_via`, migration
  `tr02_widen_triage_decided_via.py`.
- Tests : provider, swipe card, carte Essentiel, fit/squelette et endpoint de
  tri.
- Docs : story 33.2 et handoff QA.

## Zones à risque

- `setTarget` ne retire que la queue non décidée du slate : aucune décision ne
  doit disparaître lors d’une baisse de cible.
- L’auto-garde dépend du set `_openedForRead` : un article lu auparavant ou
  depuis une autre surface ne doit pas être gardé au cold boot.
- Un slate étendu peut être restauré avant le carrousel ; la réconciliation doit
  compléter le même ordre, sans rebattre les articles.
- La migration élargit la contrainte PostgreSQL existante : son déploiement doit
  précéder les écritures `decided_via=read`.

## Points d’attention pour le reviewer

- Vérifier les bornes du contrôle `[3, taille du pool]`, puis le cas où la
  baisse rencontre une entrée déjà décidée.
- Vérifier le cycle tap → reader → retour avant/après lecture et le marquage de
  lecture dans « TU GARDES ».
- Vérifier que « Plus d’articles ? » est absent une fois le pool injectable
  épuisé, et qu’un tap rouvre la pile avec deux ids supplémentaires.

## Ce qui n’a pas changé

- Les éditions passées restent une liste éditoriale figée, sans pile ni
  contrôle de cible.
- `GET /api/essentiel` ne change pas : le pool reste le slate servi, suivi du
  carrousel déjà chargé.
- Les signaux design sans données disponibles (nouvelle source, compteur social,
  durée de lecture) ne sont pas inventés.

## Comment tester

- `set -a; . .env; set +a; cd packages/api && DATABASE_URL="postgresql+psycopg://$POSTGRES_TEST_USER:$POSTGRES_TEST_PASSWORD@localhost:${POSTGRES_TEST_PORT:-54322}/$POSTGRES_TEST_DB" PYTHONPATH=. pytest -q tests/routers/test_essentiel_triage.py`
- `cd apps/mobile && flutter test test/features/flux_continu/providers/essentiel_triage_provider_test.dart test/features/flux_continu/widgets/triage_swipe_card_test.dart test/features/flux_continu/widgets/essentiel_hi_fi_card_test.dart test/features/flux_continu/utils/section_fit_test.dart`
- `cd apps/mobile && flutter analyze lib/features/flux_continu/providers/essentiel_triage_provider.dart lib/features/flux_continu/utils/section_fit.dart lib/features/flux_continu/widgets/essentiel_hi_fi_card.dart lib/features/flux_continu/widgets/essentiel_triage_stack.dart lib/features/flux_continu/widgets/triage_stack_skeleton.dart lib/features/flux_continu/widgets/triage_swipe_card.dart`
- Sur un compte QA ayant un Essentiel du jour : régler la cible, finir le tri,
  utiliser « Plus d’articles ? », puis valider le cycle lecture auto-gardée.

## Vérifications effectuées

- Migration appliquée avec succès sur une base PostgreSQL locale vide ; une seule
  tête Alembic (`tr02_widen_triage_via`).
- Endpoint de tri : 10 tests API verts, dont `decided_via=read`.
- Tests Flutter ciblés et analyse des fichiers modifiés : verts.
- `ruff check` sur les fichiers API modifiés et `git diff --check` : verts.
- Le `flutter analyze` global remonte 525 diagnostics préexistants hors de ce
  périmètre ; aucun ne pointe les fichiers de cette story.
- La QA Playwright du build staging public ne peut pas atteindre le feed sans le
  compte QA référencé dans le handoff ; elle s’arrête à l’onboarding public.
