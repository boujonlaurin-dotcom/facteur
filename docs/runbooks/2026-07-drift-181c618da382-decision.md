# Décision — Drift Alembic prod (`181c618da382`)

**Date** : 2026-07-21
**Statut** : Analyse terminée, read-only, aucune action bloquante.

## Constat

La DB prod partagée (`ykuadtelnzavrqzbfdve`) a `alembic_version = 181c618da382`, une
révision `main`-only absente du code `origin/production` (#940). Au boot des services
prod, `alembic upgrade head` logue `Can't locate revision '181c618da382'` (toléré par le
`CMD` du Dockerfile, l'API reste up).

## Diagnostic

- Gap = exactement 6 révisions entre le head prod (`ue01`) et `181c618da382`, toutes
  additives / backward-compat / idempotentes (`cv01`, `me01`, `me02`, `es01`, `wl01`,
  merge no-op `181c618da382`). Aucun `DROP`/rename joué en prod.
- Exactement 1 head sur `main` (`181c618da382`, confirmé via `alembic heads`).
- Schéma DB == head `181c618da382` (vérifié live via Supabase MCP read-only) : les 9
  tables `media_eval_*`, `sources.coverage_themes`, CHECK `niveau` 0-4,
  `essentiel_mode` (2 tables), `waitlist_entries.motivation`/`methode_complete` sont
  tous présents. Prod = préfixe strict de `main`, rien à rattraper côté schéma.
- Le prochain **Weekly Release** (`git merge --ff-only origin/main`) apporte le code des
  6 migrations à `production` → `alembic upgrade head` deviendra un no-op propre.

## Décision

**Ne pas lancer le [runbook de re-baseline](recover-from-alembic-drift.md)**
(Phases 0–7, pg_dump/squash/stamp --purge) : il traite une vraie divergence
schéma↔chaîne, absente ici. La chaîne est linéaire, additive, 1 head, DB déjà au head.
Un `stamp` manuel serait futile (le prochain boot staging re-stamperait de toute façon)
et irait à l'encontre du runbook.

⇒ Laisser le prochain Weekly Release réconcilier naturellement. Le fix worker classif
(déjà mergé sur `main`) arrivera en prod par le même release qui apporte les 6
migrations : boot propre garanti au même moment.

## Cause-racine

Comportement attendu du modèle shared-DB (`main` staging + `production` sur la même DB
Supabase, `alembic upgrade head` au boot des deux services). Le skew `alembic_version`
en avance sur le code prod est transitoire par design, tant que les migrations restent
additives / expand-contract (invariant CLAUDE.md). Aucune remédiation structurelle
requise.

## Vérification post-release (à jouer après le prochain « Weekly Production Release »)

- [ ] Logs Railway boot prod (`WEB` + `Api`) : `No revisions to upgrade` / `Uvicorn
      running`, plus de `Can't locate revision '181c618da382'`.
- [ ] Supabase MCP read-only : `SELECT version_num FROM alembic_version;` = toujours
      `181c618da382` (réconciliation côté code, pas côté DB).
- [ ] Si une migration a été mergée sur `main` après `181c618da382` d'ici le release :
      re-vérifier `alembic heads` (1 seul head) et que ces migrations sont additives.

## Vérifications faites (2026-07-21)

- `cd packages/api && alembic heads` → `181c618da382 (head)` unique. ✓
- `comm -13` prod↔main = 6 fichiers ; `comm -23` = vide. ✓
- Supabase MCP read-only : objets des 6 migrations présents + `alembic_version =
  181c618da382`. ✓
