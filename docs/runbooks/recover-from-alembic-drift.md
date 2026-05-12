# Runbook : récupérer d'un drift Alembic (re-baseline depuis prod)

> **À lire avant tout le reste**
>
> Depuis le squash de baseline (mai 2026), **un drift entre la chaîne Alembic et le schéma prod ne devrait plus se produire**. Les garde-fous en place :
>
> - Alembic est la seule source de vérité pour le schéma — pas de SQL manuel via Supabase SQL Editor (cf. CLAUDE.md "Contraintes Techniques").
> - Le `Dockerfile` exécute `alembic upgrade head` au boot Railway, donc une migration cassée plante le déploiement (visible dans les logs).
> - La CI `alembic-smoke.yml` rejoue `alembic upgrade head` contre une Postgres vide à chaque PR — toute chaîne qui ne se rejoue pas tape rouge avant le merge.
>
> Ce runbook existe **par précaution**, pour le cas où ces filets craqueraient. Si tu te retrouves à le suivre, ce n'est pas la fin du parcours : c'est le début. **Trouve aussi la cause-racine du drift** (qui a été contournée ? quel garde-fou n'a pas tenu ? pourquoi ?) et adresse-la avant de clore l'incident, sinon le re-baseline ne sera qu'un sparadrap qui se redécollera dans 3 mois.

> **Quand utiliser ce runbook**
>
> - `make bootstrap` plante à l'étape `[4/6] Migrations Alembic`.
> - Une migration référence un objet (table, colonne, index) qui n'existe pas localement mais existe en prod (ou inversement).
> - `alembic upgrade head` contre une DB vide échoue alors que prod tourne.
> - `alembic revision --autogenerate` produit un diff massif et inattendu contre prod.
>
> Ces symptômes ont une cause unique : la chaîne `versions/` ne décrit plus le schéma réel de prod. Ce runbook reconstruit la chaîne depuis le schéma réel.

Ce playbook reproduit pas-à-pas ce qu'on a fait pendant l'incident d'avril–mai 2026 (PR [#515](https://github.com/boujonlaurin-dotcom/facteur/pull/515), cf. [`docs/maintenance/maintenance-alembic-baseline-squash.md`](../maintenance/maintenance-alembic-baseline-squash.md) pour le récit complet).

---

## Pré-requis

- Accès à la chaîne de connexion **directe** prod (port 5432, **pas** le pooler 6543) — Supabase Dashboard → Project Settings → Database → "Direct connection".
- `pg_dump` ≥ 14 installé localement (`brew install postgresql@17` si besoin).
- `psql` accessible depuis le terminal.
- `packages/api/.venv` configuré (alembic + psycopg installés).
- Un Docker démarré (pour la DB locale de vérification).
- Capacité d'annoncer une **fenêtre de gel** (~30–60 min) sur les merges qui touchent `packages/api/alembic/`. Pendant ce temps, personne ne mergera de nouvelle migration sur `main`.

---

## Vue d'ensemble

```
[Phase 0] Geler les merges + capturer l'état actuel de prod
   ↓
[Phase 1] pg_dump prod → sanitize → committer comme nouvelle baseline
   ↓
[Phase 2] Archiver toute la chaîne actuelle dans _archive/
   ↓
[Phase 3] Vérifier localement (DB vide → upgrade head → pytest)
   ↓
[Phase 4] CI green sur la PR
   ↓
[Phase 5] Stamp prod (alembic stamp 00000_baseline --purge)
   ↓
[Phase 6] Merger immédiatement, surveiller le déploiement Railway
```

Le seul moment fragile, c'est le **gap entre stamp et merge** : pendant cette fenêtre, prod est stampée à `00000_baseline` mais le code déployé sur Railway ne contient pas encore le fichier `versions/00000_baseline.py`. Un redéploiement involontaire (autre PR mergée, redémarrage manuel, crash conteneur) loggera des erreurs alembic mais l'API reste up grâce au fallback du `Dockerfile` CMD. Stamp puis merge le plus vite possible.

---

## Phase 0 — Préparer

### 0.1 Geler les merges

Annonce dans le canal dev :

> Freeze sur `main` pour les PRs qui touchent `packages/api/alembic/`. Re-baseline en cours, durée ~45 min.

### 0.2 Vérifier que `main` est propre

```bash
git fetch origin
git checkout main
git pull --ff-only
git log --oneline -5    # confirme que main est cohérent
```

### 0.3 Capturer l'état actuel de prod (rollback target)

```bash
export PSQL_URL="postgresql://postgres.<ref>:<password>@<host>:5432/postgres"

psql "$PSQL_URL" -c "SELECT version_num FROM alembic_version;"
```

**Note la valeur** retournée — c'est ton point de retour si tout part en vrille. Stocke-la dans un fichier ou un message épinglé, pas juste dans le scrollback du terminal.

### 0.4 Backup de prod (best effort)

L'idéal : prendre un backup managé via Supabase (les noms de menu changent — cherche du côté de la section *Backups* dans le dashboard du projet). C'est un snapshot stocké hors de ton poste, restaurable rapidement.

Sinon, un dump local fait office de filet de sécurité :

```bash
pg_dump --no-owner --no-privileges --no-tablespaces \
  "$PSQL_URL" \
  > "facteur-prod-backup-$(date +%Y%m%d-%H%M).sql"
```

Stocke le fichier hors du repo (par ex. `~/Downloads/`). Ce dump n'est PAS la source pour la baseline — il sert uniquement de filet de sécurité en cas de catastrophe.

---

## Phase 1 — Nouvelle baseline

### 1.1 Créer une branche

```bash
git checkout -b <ton-handle>/rebaseline-alembic-$(date +%Y%m%d)
```

### 1.2 pg_dump schéma prod

```bash
pg_dump --schema-only --schema=public --no-owner --no-privileges --no-tablespaces \
  --no-security-labels --no-comments \
  "$PSQL_URL" \
  > packages/api/alembic/baseline/prod-schema-raw.sql
```

`prod-schema-raw.sql` est gitignored — il contient des objets Supabase-spécifiques (RLS, FK vers `auth.users`, fonctions edge) qu'il ne faut pas committer.

### 1.3 Sanitize

```bash
cd packages/api/alembic/baseline
python3 sanitize.py prod-schema-raw.sql > prod-schema-$(date +%Y-%m-%d).sql
```

Le sanitize :
- strippe `OWNER`/`GRANT`/`SET`/`REVOKE`/RLS/policies (objets Supabase, pas dans Postgres vanilla),
- drop la FK vers `auth.users` (schéma Supabase absent en local),
- drop la fonction `handle_new_user_notion_sync` (appelle `extensions.net.http_post`, Supabase-only),
- drop le bloc `CREATE TABLE alembic_version` + son ADD CONSTRAINT (alembic recrée cette table lui-même),
- préfixe le dump avec `CREATE SCHEMA IF NOT EXISTS extensions;` + `CREATE EXTENSION uuid-ossp/pg_trgm WITH SCHEMA extensions;`,
- réécrit `CREATE SCHEMA public;` → `CREATE SCHEMA IF NOT EXISTS public;` (Postgres ship toujours avec `public`),
- pour pg_dump ≥ 17 : strippe `\restrict <token>` / `\unrestrict <token>` (meta-commands psql que `op.execute()` ne comprend pas).

### 1.4 Vérifier le sanitize

```bash
# Tous ces grep doivent retourner 0
for pattern in "OWNER TO" "^GRANT " "^SET " "auth\.users" "CREATE POLICY " "ENABLE ROW LEVEL SECURITY" "handle_new_user_notion_sync" "^\\\\restrict" "^\\\\unrestrict"; do
  count=$(grep -c "$pattern" prod-schema-$(date +%Y-%m-%d).sql || true)
  echo "  $pattern: $count"
done
```

Si un compteur est > 0, c'est probablement que `pg_dump` a sorti une variante de syntaxe pas couverte par `sanitize.py`. Lis le bloc concerné et ajoute la règle dans `sanitize.py`.

### 1.5 Diff vs ancienne baseline (sanity)

```bash
# Liste les tables ajoutées / supprimées
extract_tables() {
  python3 -c '
import re, sys
text = open(sys.argv[1]).read()
for m in re.finditer(r"CREATE TABLE\s+(?:IF NOT EXISTS\s+)?([\"\w.]+)", text):
    name = m.group(1).replace("\"", "").split(".", 1)[-1]
    print(name)
' "$1" | sort -u
}

extract_tables packages/api/alembic/baseline/prod-schema-<ANCIENNE_DATE>.sql > /tmp/before.txt
extract_tables packages/api/alembic/baseline/prod-schema-$(date +%Y-%m-%d).sql > /tmp/after.txt

echo "Nouvelles tables :"
comm -13 /tmp/before.txt /tmp/after.txt
echo "Tables supprimées (devrait être vide) :"
comm -23 /tmp/before.txt /tmp/after.txt
```

Tables supprimées non-vides = drapeau rouge. Investigue avant de continuer.

---

## Phase 2 — Archiver et pointer la baseline

### 2.1 Mettre à jour `00000_baseline.py`

Ouvre `packages/api/alembic/versions/00000_baseline.py` et change la date dans :
- la docstring du module ("baseline — prod schema snapshot YYYY-MM-DD"),
- le compteur d'archivées (texte de la docstring "Replaces the N pre-existing migrations"),
- la variable `_BASELINE_SQL_PATH` (filename du nouveau dump).

### 2.2 Archiver les migrations qui ne sont pas la baseline

```bash
cd packages/api/alembic
# Lister tout sauf 00000_baseline.py
ls versions/*.py | grep -v "00000_baseline.py" | xargs -I {} git mv {} _archive/
git rm baseline/prod-schema-<ANCIENNE_DATE>.sql   # supprime l'ancien snapshot
```

### 2.3 Mettre à jour `_archive/README.md`

Ajuster les compteurs (ex. "73 fichiers" → "81 fichiers"), la date du squash, et tout lien vers la baseline.

### 2.4 Commit

```bash
git add -A
git commit -m "fix(db): re-baseline alembic from fresh prod schema snapshot"
```

---

## Phase 3 — Vérifier localement

### 3.1 DB locale propre

Si la DB de test (`facteur-postgres-test`, port 54322) est déjà up et utilisable :

```bash
make db-reset   # docker volume vide + alembic upgrade head
```

Si la DB tourne ailleurs (autre projet Supabase local sur 54322), spinne un Postgres jetable :

```bash
docker rm -f baseline-verify 2>/dev/null
docker run -d --rm --name baseline-verify \
  -p 54399:5432 -e POSTGRES_PASSWORD=t -e POSTGRES_DB=facteur_test \
  postgres:15

# attends qu'il soit prêt
until docker exec baseline-verify pg_isready -U postgres -d facteur_test >/dev/null 2>&1; do sleep 1; done

cd packages/api
DATABASE_URL="postgresql+psycopg://postgres:t@localhost:54399/facteur_test?sslmode=disable" \
  .venv/bin/alembic upgrade head
```

Sortie attendue :
```
INFO  [alembic.runtime.migration] Running upgrade  -> 00000_baseline, baseline — prod schema snapshot YYYY-MM-DD.
[alembic] Migrations completed successfully
```

### 3.2 Sanity check tables

```bash
# Si DB de test :
docker exec facteur-postgres-test psql -U facteur -d facteur_test -tAc \
  "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';"

# Si DB jetable :
docker exec baseline-verify psql -U postgres -d facteur_test -tAc \
  "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';"
```

Doit retourner ~le nombre de tables qu'on a comptées dans le diff Phase 1.5 + 1 (alembic_version).

### 3.3 `alembic heads` et `alembic current`

```bash
.venv/bin/alembic heads     # → 00000_baseline (head)
.venv/bin/alembic current   # → 00000_baseline (head)
```

Les deux doivent matcher.

### 3.4 pytest

Pytest a besoin d'une DB **vide** (le fixture `create_tables` fait `Base.metadata.drop_all + create_all`). Si tu utilises la DB jetable, crée une 2e database :

```bash
docker exec baseline-verify psql -U postgres -d postgres -c "CREATE DATABASE facteur_test_clean;"

DATABASE_URL="postgresql+psycopg://postgres:t@localhost:54399/facteur_test_clean?sslmode=disable" \
  PYTHONPATH="$(pwd)" .venv/bin/pytest tests/ -q
```

Doit passer 100% (ou au moins le même % qu'avant le re-baseline — les tests `test_veille_*` et autres dépendent de modèles à jour).

### 3.5 Cleanup container jetable

```bash
docker rm -f baseline-verify
```

---

## Phase 4 — Pousser et obtenir CI green

```bash
git push -u origin <ton-handle>/rebaseline-alembic-<date>
gh pr create --base main --title "[DO NOT MERGE BEFORE PROD STAMP] fix(db): re-baseline alembic from fresh prod schema" \
  --body-file .context/pr-handoff.md   # ou rédige le body inline, voir PR #515 pour modèle
```

CI à surveiller :
- `Alembic smoke (upgrade head from empty)` — la sécu majeure. Doit être vert.
- API tests, lint, build Docker — habituels.

Si `alembic-smoke` échoue avec `ModuleNotFoundError`, le workflow installe peut-être trop peu de deps : confirmer que `.github/workflows/alembic-smoke.yml` fait `pip install -r packages/api/requirements.txt` (et non un sous-set). `env.py` importe `app.database` et `app.models`, qui transitivement requièrent fastapi/pydantic/structlog/etc.

---

## Phase 5 — Stamp prod

**À ce stade :** CI green, reviewer (idéalement) approve, fenêtre de gel toujours active. Tu es à 5 minutes de la fin.

### 5.1 S'assurer d'être sur la branche de la PR

```bash
git checkout <ton-handle>/rebaseline-alembic-<date>
git status   # propre
```

C'est important : `alembic stamp 00000_baseline` regarde le fichier `versions/00000_baseline.py` dans le working tree pour valider que la révision existe. Si tu es sur `main`, il n'y existe pas encore.

### 5.2 Connectivity test

```bash
export PROD_DB_URL="postgresql+psycopg://postgres.<ref>:<password>@<host>:5432/postgres"
PSQL_URL="${PROD_DB_URL/+psycopg/}"

psql "$PSQL_URL" -c "SELECT current_database(), inet_server_addr(), inet_server_port();"
psql "$PSQL_URL" -c "SELECT version_num FROM alembic_version;"
```

Le 2e SELECT doit afficher la valeur que tu as captée à la Phase 0.3 (rollback target).

### 5.3 Stamper

```bash
cd packages/api
DATABASE_URL="$PROD_DB_URL" .venv/bin/alembic stamp 00000_baseline --purge
```

**`--purge` est obligatoire.** Sans lui, alembic essaie de résoudre la révision courante (qui est dans `_archive/`, pas dans `versions/`) et plante avec `Can't locate revision identified by '<old_rev>'`. `--purge` fait `DELETE FROM alembic_version` puis `INSERT INTO alembic_version (version_num) VALUES ('00000_baseline')`. Aucun changement de schéma, juste cette ligne.

Sortie attendue :
```
INFO  [alembic.runtime.migration] Running stamp_revision  -> 00000_baseline
[alembic] Migrations completed successfully
```

### 5.4 Vérifier

```bash
DATABASE_URL="$PROD_DB_URL" .venv/bin/alembic current
```

Doit afficher : `00000_baseline (head)` (sans erreur "Can't locate", sans warning).

---

## Phase 6 — Merger et surveiller

### 6.1 Merger immédiatement

```bash
gh pr merge <PR_NUMBER> --squash --delete-branch
```

(Ou via le UI GitHub si tu préfères. Le strategy peu importe ; squash est plus propre.)

**Ne traîne pas** entre la 5.4 et la 6.1 : tant que la PR n'est pas mergée, prod est stampée à `00000_baseline` mais le code déployé n'a pas le fichier `versions/00000_baseline.py`. Tout redéploiement involontaire dans cette fenêtre loggera l'erreur `Can't locate revision identified by '00000_baseline'`. Le `Dockerfile` CMD a un fallback qui démarre uvicorn malgré tout (avec un WARNING), donc l'API reste up — mais l'erreur dans les logs est bruyante.

### 6.2 Surveiller le prochain déploiement Railway

```bash
railway logs    # ou via le dashboard Railway
```

Cherche dans les logs du conteneur qui boote :

- ✅ Bon : `INFO  [alembic.runtime.migration] No revisions to upgrade` (alembic voit que prod est déjà au head, no-op), suivi de `Uvicorn running on http://0.0.0.0:8080`.
- ⚠️ Inattendu : `Can't locate revision identified by ...` ou autre message rouge → Phase 7 (rollback).

### 6.3 Lever le freeze

Annonce :

> Re-baseline mergée et déployée OK. Freeze levé. Toute nouvelle migration chaîne après `00000_baseline`.

---

## Phase 7 — Rollback (si quelque chose plante)

### 7.1 Si le stamp lui-même a échoué

Le stamp est un single SQL (`UPDATE alembic_version`) — soit il réussit, soit il n'a rien changé. En cas d'erreur, prod est intacte, pas de rollback nécessaire ; debug et reprends à la Phase 5.

### 7.2 Si le déploiement post-merge plante

```bash
psql "$PSQL_URL" -c "UPDATE alembic_version SET version_num = '<rollback_target_capté_phase_0>';"
```

Puis fais un revert de la PR sur `main` :

```bash
git revert -m 1 <merge_commit_sha>
git push origin main
```

Railway redéploie automatiquement, et alembic retrouve une chaîne dont il connaît la révision courante.

### 7.3 Cas pathologique

Si pour une raison X le revert ne suffit pas (ex. le code applicatif a déjà été appliqué et nécessite des colonnes que prod a, mais le revert les supprime), restore depuis le backup Phase 0.4 :

- Restaure depuis le backup managé Supabase (cf. section *Backups* dans le dashboard du projet — l'UI change, cherche l'option "Restore"/"Restaurer").
- Ou en dernier recours, `psql "$PSQL_URL" < facteur-prod-backup-*.sql` (long, et risque de couper l'API plus longtemps).

---

## Pièges connus

| Symptôme | Cause | Fix |
|---|---|---|
| `Can't locate revision identified by 'XYZ'` au stamp | Tu n'as pas passé `--purge` | Réessaie avec `--purge` |
| `password authentication failed for user "facteur"` | Tu utilises la DB locale par erreur (port 54322 pris par un autre projet Supabase) | Spinne un Postgres jetable sur un autre port (54399 par ex.) |
| `pg_dump version mismatch: server has version 17, pg_dump version 14` | Ton `pg_dump` local est trop vieux | `brew install postgresql@17 && brew link --overwrite postgresql@17` |
| Le sanitizé contient encore `auth.users` ou `handle_new_user_notion_sync` | pg_dump 17.x produit des syntaxes que sanitize.py ne couvre pas (identifiants non quotés, `CREATE FUNCTION` sans `OR REPLACE`) | Voir les règles déjà ajoutées dans `sanitize.py:60-115`, étendre si nécessaire |
| `DependentObjectsStillExist: cannot drop table contents` au pytest | conftest fait `drop_all` mais des FK depuis des tables non-modélisées (`app_config`, `nps_responses`) bloquent | Use une DB vide pour pytest, ne réutilise pas la DB peuplée par alembic upgrade |
| `unsupported startup parameter: ...` | Tu utilises l'URL pooler (port 6543) au lieu de la directe (5432) — pg_dump et alembic stamp ne marchent pas via le pooler | Récupère la "Direct connection" depuis Supabase Dashboard → Settings → Database |
| CI smoke pète sur `ModuleNotFoundError: No module named 'X'` | `.github/workflows/alembic-smoke.yml` n'installe pas tous les imports d'`env.py` | Installer `requirements.txt` complet plutôt qu'une liste cherry-picked |

---

## À ne PAS faire pendant la procédure

- **Pas de `git push --force` sur `main`.** Le hook `pre-bash-no-staging.sh` bloque déjà beaucoup, mais reste vigilant.
- **Pas de `alembic upgrade head` contre prod manuellement.** Le `Dockerfile` le fait au prochain boot Railway ; tu duppliquerais et risquerais des conflits si une autre instance redémarre en même temps.
- **Pas de SQL manuel via Supabase SQL Editor.** C'est le pattern qui a causé l'incident initial. Toute correction de schéma passe par une migration Alembic forward, point.
- **Pas de "petite migration corrective vite faite avant le stamp".** Tout doit chaîner après le baseline. Si tu veux corriger un drift modèle ↔ prod, fais-le en PR forward séparée *après* que la PR de re-baseline soit mergée.

---

## Liens

- Récit complet de l'incident : [`docs/maintenance/maintenance-alembic-baseline-squash.md`](../maintenance/maintenance-alembic-baseline-squash.md)
- PR de référence : [#515](https://github.com/boujonlaurin-dotcom/facteur/pull/515)
- Workflow CI : `.github/workflows/alembic-smoke.yml`
- Sanitize script : `packages/api/alembic/baseline/sanitize.py`
