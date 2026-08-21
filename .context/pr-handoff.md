# Volet B — carrousel « sources discrètes » en dernier recours

Grief PO n°2 (bug-curation-essentiel-personnalisation) : les articles de
sources discrètes **arrivaient trop tôt dans la pile, trop nombreux, et
revenaient tous les jours**. Une seule PR backend + mobile, **aucune migration
Alembic** (head unique `su03_support_link_delivery` inchangé).

## Quoi

Le carrousel devient un **filet de dernier recours** : 3 items max, jamais un
article déjà trié, jamais > 30 j, sous-ensemble stable la journée et tournant
d'un jour à l'autre, versé dans la pile **seulement** quand les articles frais
ET `/essentiel/more` sont épuisés.

### Backend (`packages/api`, sans migration)

- **B1 — mémoire de triage** : `fetch_triaged_ids(session, user_id, days=90)`
  (`carousel_catalog.py`) relit `essentiel_triage_decisions` (index
  `ix_essentiel_triage_user_date` existant). Champ **additif avec default**
  `CarouselBuildContext.triaged_ids`, appliqué aux 3 carrousels de découverte
  (`quiet_sources`, `new_source`, `community` en union avec `consumed_ids`) et
  **jamais** à `saved` : `decision=later` déclenche `set_save_status(...)`, le
  carrousel « Plus tard, c'est maintenant ! » doit re-servir ces articles
  (piège n°2, verrouillé par test). Peuplé **symétriquement** dans
  `routers/essentiel.py` (`_enrich_essentiel_carousel`) et
  `recommendation_service._build_carousels` (variable dédiée, `consumed_ids`
  intact car il sert aussi la Phase A) → l'éligibilité reste
  surface-indépendante, la complémentarité Essentiel/Flâner tient.
- **B2 — volume** : `QUIET_SOURCES_MAX_ITEMS = 3` dans le builder (les
  `excluding(..., MAX_CAROUSEL_ITEMS)` des routeurs deviennent des plafonds
  inertes, contrat inchangé).
- **B3 — seed stable** : `randomization.compute_stable_seed` (md5, pattern
  `_rotation_order`) sur `today_paris().isoformat()`. Découverte consignée :
  `compute_seed` repose sur `hash()` **randomisé par PYTHONHASHSEED** — un
  simple passage hourly→daily aurait laissé le sous-ensemble instable entre
  workers/redéploiements. `build_new_source` garde `compute_seed` (hors
  périmètre, follow-up).
- **B4 — fenêtre 60 j → 30 j** : `QUIET_SOURCE_WINDOW_DAYS = 30`, fenêtre de
  service alignée sur la sonde d'éligibilité. Sûr **uniquement** parce que la
  mémoire de triage arrive dans la même PR (piège n°3) : une source dont les
  articles récents sont tous consommés/triés sort du carrousel au lieu de
  servir un article de 45 j.

### Mobile (`apps/mobile`) — injection différée, tous types de carrousel

- **M1 — split des pools** : `essentielTriagePools` (ex-miroir mort
  `essentiel_deck.dart`, devenu la **vraie** source unique — M4) rend
  `(full, syncable)`. `full` = slate + rapatriés + carrousel : résolution
  (`_memoPoolById`, cold-boot d'un slate qui porte des ids carrousel versés),
  `renderPool`, exclusions de `/more` (le carrousel reste exclu même non
  versé). `syncable` = sans le carrousel tant que non versé : c'est lui que
  `syncSlate` snapshote.
- **M2 — latch `_carouselReleased`** (état de session, non persisté) : flip au
  plus 1×/session quand pile basse (`remainingToTriage ≤ 2`) + objectif non
  atteint + `/more` **à sec** (`hydrated && !isLoading && !canAutoFetch()` —
  un fetch en vol n'est PAS sec). Invalidate le memo (`_memoReleased`), le
  sync existant appende alors le carrousel **en queue** du slate gelé.
- **M3 — `pendingPoolIds` sur le pool syncable** : les items carrousel non
  versés ne comptent plus ⇒ `remainingToTriage` baisse vraiment et le prefetch
  `/more` se déclenche (c'était le fix « arrive trop tôt / bloque
  l'alimentation réseau »).

### Limite connue (assumée, hors périmètre)

Tri terminé par objectif atteint + « Plus d'articles ? » + backend à sec : le
carrousel non versé reste en réserve (le latch ne s'évalue que pendant le tri
actif). Cas rare ; à revoir avec PR 5 (pool perso) / PR 6-bis (moteur `/more`).

## Comment ça a été vérifié

- [ ] Backend : `pytest -v` complet (0 échec) ; suites ciblées
  `test_feed_carousels_quiet_sources.py` (17), `test_carousel_catalog.py`,
  `test_carousel_selection.py`, `test_essentiel_carousel.py`,
  `tests/routers/test_essentiel_triage.py`.
  - Tests neufs : triage exclu des 3 carrousels de découverte
    (keep/later/pass paramétrés), `saved` re-sert un `later`, seed md5 daily
    (spy sur `compute_stable_seed`), fenêtre de service réellement exercée
    (article 35 j non servi quand le récent est consommé), parité
    Essentiel/Flâner avec `triaged_ids` peuplé, `fetch_triaged_ids` fenêtré
    90 j + isolation user.
- [ ] Mobile : `flutter test` (baseline ~26-27 échecs pré-existants hors
  périmètre, cf. mémoire) + `flutter analyze` propre sur les fichiers touchés.
  - Tests neufs : carrousel absent du slate d'emblée (test 33.3 inversé),
    versement quand `/more` sec (cooldown) en **queue** du slate, fetch en vol
    ≠ sec, le carrousel ne bloque plus le prefetch (+ reste exclu de `/more`),
    cold-boot slate avec ids carrousel versés résolu sans prune ni silhouette.
- [ ] `alembic heads` : 1 head, inchangé (aucune migration).
- [ ] Uvicorn local + compte QA : `GET /api/essentiel` → carrousel ≤ 3 items.

## Zones à risque

- `recommendation_service._build_carousels` (Flâner) : +1 SELECT indexé par
  requête feed (`fetch_triaged_ids`, index `(user_id, digest_date)` existant).
- `essentiel_hi_fi_card.dart` : ordre du pool changé (rapatriés avant
  carrousel) — le préfixe du slate ne bouge jamais, y compris au versement.
- Invariant « Collecte seule » de `essentiel_triage_decisions` intact côté
  écriture (nouvel usage en **lecture** documenté dans le modèle).
