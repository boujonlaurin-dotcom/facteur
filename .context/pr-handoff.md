# PR — fix(veille): empêcher configs sans source + filets historique

## Summary

Coupe à la racine le pipeline qui aboutissait à des digests vides : sans validation, le mobile soumettait des configs avec `source_selections=[]` (filtre interne sur les mocks sans `apiSourceId`), le backend acceptait, et le digest builder rendait `items=[]` instantanément. 4 des 7 livraisons des 14 derniers jours étaient dans cet état (cf. `bug-veille-config-without-sources.md`).

- **A1 — Backend 422 si config sans source** : `VeilleConfigUpsert.source_selections` passe à `min_length=1` (`packages/api/app/schemas/veille.py`) + filet final post-dedup dans `upsert_config` qui rollback puis lève `HTTPException(422)` (`packages/api/app/routers/veille.py`).
- **A2/A3 — Mobile Step 3** : `realSelectedSourceCount` (sources avec `apiSourceId`) gate le CTA « Continuer » + hint « Sélectionne au moins une source ». La liste mock cliquable du fallback est supprimée (piège UX : tous filtrés au submit) — remplacée par `_SuggestionsUnavailable` (texte sobre + bouton « Réessayer »). Le bouton « + Ajouter une source » reste disponible.
- **A4 — Mobile 422 ciblé** : `veille_config_screen.dart` distingue `e.statusCode == 422` (message validation) du reste.
- **B2 — Drop `lastError` UI** : `_DeliveryFailedView` n'affiche plus le texte technique brut (`watchdog_backfill: stuck running …` etc.) ; il reste dans Sentry/logs.
- **C1 — Watchdog cleanup `*/5 min`** : `cleanup_stuck_running_deliveries` marque FAILED toute row RUNNING > 15 min (`packages/api/app/jobs/veille_generation_job.py`) + Sentry `capture_message` par row + job ajouté au scheduler (`packages/api/app/workers/scheduler.py`).
- **C2 — PostHog `veille_config_submitted`** avec `source_count` pour mesurer 0% post-A1.

## Tests

- Backend : `pytest tests/routers/test_veille_routes.py tests/test_veille_generation_job.py tests/test_veille_first_delivery_failure.py tests/test_veille_digest_builder.py` → 46/46 OK (2 nouveaux tests 422, 2 nouveaux tests cleanup stuck).
- Mobile : `flutter test test/features/veille/screens/step3_sources_screen_test.dart` → 2/2 OK (fallback texte + CTA disabled state).
- Lint : `ruff check` + `ruff format --check` OK sur les fichiers touchés ; `flutter analyze` OK sur les écrans veille touchés.
- Alembic : 1 head, aucune migration ajoutée.

## Action manuelle PO post-merge — cleanup historique (B1)

MCP Supabase est en read-only ; à exécuter via Supabase SQL Editor :

```sql
DELETE FROM veille_deliveries WHERE id IN (
  'e508b4cd-95f0-47a4-b5fc-5de09893c055',
  '44a569dd-a72f-41de-970e-98c6d1cda27f',
  '5902a90e-7126-47bc-9f4c-81ca595dbea9',
  'f48e57dc-30b6-4ad5-81c0-3b6ae635bf01',
  '06280b22-de15-4c1b-8219-f11b03106e95',
  '90adb2e5-da1a-46f6-8fb1-38f6d54ad62c',
  'ef6e0f7e-1a2d-4341-a698-16baebe238eb'
);
```

Vérification SELECT pré-DELETE déjà faite : 6 succeeded `item_count=0` + 1 failed `watchdog_backfill`. Décision PO : DELETE pur, pas de donnée user de valeur.

Vérification post-fix :

```sql
-- Doit retourner 0 :
SELECT COUNT(*) FROM veille_configs vc
WHERE NOT EXISTS (SELECT 1 FROM veille_sources vs WHERE vs.veille_config_id = vc.id);

-- Doit rester à 0 :
SELECT COUNT(*) FROM veille_deliveries
WHERE generation_state='running' AND started_at < NOW() - INTERVAL '15 minutes';
```

## Hors scope

- Stabilisation `/api/veille/suggestions/sources` (cause racine `IdleInTransactionSessionTimeout`, à traiter dans un sprint dédié — A1+A3 protègent l'utilisateur indépendamment).
- Mapping LLM-slug → taxonomie canonique (déjà tracé dans `bug-veille-empty-digests-and-no-wow.md`).
