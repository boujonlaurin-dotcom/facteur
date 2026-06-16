# Bug — 2 heads Alembic (au01 + b75132e0c6b5) : staging ne déploie plus

## Symptômes
- Tous les déploiements Railway staging depuis le merge de PR #818 (2026-06-12 16:23Z) plantent au boot : `alembic upgrade head` → "Multiple head revisions are present".
- Staging sert encore le code d'avant #818 : les PRs #818 (observabilité scaling), #833 (lettres 3-4 + backfill) et #834 ne sont pas live.
- `api_usage_events` absente de la DB partagée (`version_num = b75132e0c6b5`) → zéro donnée pour gouverner la phase 2 scaling.

## Cause racine
PR #828 (`b75132e0c6b5_create_event_rsvps_table`, mergée le 11/06, déployée) et PR #818 (`au01_api_usage_events`, mergée le 12/06) descendent toutes deux de `gr02_grille_featured_article` → branchpoint, 2 heads. Le hook `post-edit-alembic-heads.sh` ne voit pas les merges GitHub parallèles. Récurrence exacte de l'incident `5de67819bc61` (2026-05-18).

## Fix
Révision de merge sans DDL : `packages/api/alembic/versions/mg01_merge_au01_event_rsvps.py` (`down_revision = ("au01_api_usage_events", "b75132e0c6b5")`). Au prochain boot, Alembic applique `au01_api_usage_events` puis le merge.

## Plan de test
- [x] `alembic heads` → exactement 1 head (`mg01_merge_au01_rsvps`)
- [x] `upgrade head` sur DB vide (facteur_test 54322)
- [x] Simulation état prod : `stamp b75132e0c6b5` puis `upgrade head` → applique `au01` + merge ; re-run = no-op
- [x] `pytest -v`

## Post-merge
- Vérifier boot Railway staging OK.
- `SELECT provider, model, count(*) FROM api_usage_events GROUP BY 1,2` après quelques heures.
- Confirmer exécution du backfill lettres (#833).

## Prévention (suivi, hors PR)
Envisager un check CI sur `main` (`alembic heads | wc -l == 1`) — le hook local ne couvre pas ce cas.
