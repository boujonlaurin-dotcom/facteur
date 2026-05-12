# Migrations archivées

Les **81 fichiers** ici **ne font plus partie de la chaîne Alembic**. Ils sont gardés pour `git blame` / lecture archéologique uniquement.

## Pourquoi

Ces migrations ont été remplacées par une **baseline** unique (`packages/api/alembic/versions/00000_baseline.py`) qui exécute un snapshot direct du schéma prod (`packages/api/alembic/baseline/prod-schema-2026-05-05.sql`).

L'opération s'est faite en deux temps, suite à une dérive cumulée :
- 2026-04-30 : premier squash de 73 migrations (PR #515 préparée).
- 2026-05-05 : refresh du snapshot et absorption de 8 migrations supplémentaires landées entre-temps (`en01`, `gn01`, `lf01`, `ls01`, `sp01`, `tr01`, `vl01`, `vp01`). PR #515 mergée + prod stampée le même jour.

Raisons de la décision :
- Plusieurs migrations no-op (NER deferred, etc.) qui assumaient un SQL appliqué à la main via Supabase SQL Editor.
- Migrations `--autogenerate` lancées contre des DB déjà drifted → impossible de rejouer la chaîne sur une DB vide.
- `make bootstrap` cassé → les devs utilisaient prod comme env de dev.

Détails complets : [`docs/maintenance/maintenance-alembic-baseline-squash.md`](../../../../docs/maintenance/maintenance-alembic-baseline-squash.md).

## Comment alembic les ignore

`alembic.ini` n'a pas de `version_locations` custom, donc alembic ne scanne que `versions/`. Les fichiers ici sont invisibles pour `alembic upgrade`, `alembic heads`, `alembic current`, etc.

## Si tu touches à un fichier ici

**Ne touche pas.** Toute nouvelle migration chaîne après `00000_baseline` dans `versions/`, jamais ici. Si tu trouves un bug dans une migration archivée :
- elle a déjà été appliquée à prod (sinon prod serait cassée), donc inutile de la corriger ici ;
- corrige avec une **migration forward** (nouveau fichier dans `versions/` chaîné après `00000_baseline`).

Si tu te retrouves à vouloir réactiver l'archive ou regénérer la baseline, c'est probablement le signe que la chaîne a re-drifté — voir [`docs/runbooks/recover-from-alembic-drift.md`](../../../../docs/runbooks/recover-from-alembic-drift.md).
