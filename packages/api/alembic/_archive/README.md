# Migrations archivées

Les 73 fichiers ici **ne font plus partie de la chaîne Alembic**. Ils sont gardés pour `git blame` / lecture archéologique uniquement.

## Pourquoi

Ces migrations ont été squashées le 2026-04-30 dans une **baseline migration** (`packages/api/alembic/versions/00000_baseline.py`) qui exécute un snapshot direct du schéma prod.

Raisons du squash :
- Plusieurs migrations no-op (NER deferred, etc.) qui assumaient un SQL manuel appliqué via Supabase SQL Editor.
- Migrations autogen contre des DB déjà drifted → impossible de rejouer la chaîne sur une DB vide.
- `make bootstrap` cassé → les devs utilisaient prod comme env de dev.

Détails complets : `docs/maintenance/maintenance-alembic-baseline-squash.md`.

## Comment alembic les ignore

`alembic.ini` n'a pas de `version_locations` custom, donc alembic ne scanne que `versions/`. Les fichiers ici sont invisibles pour `alembic upgrade`, `alembic heads`, etc.

## Si tu touches à un fichier ici

**Ne touche pas.** Toute nouvelle migration chaîne après `00000_baseline` dans `versions/`. Si tu trouves un bug dans une migration archivée, c'est qu'elle a déjà été appliquée à prod — corrige avec une migration forward, pas en éditant l'archive.
