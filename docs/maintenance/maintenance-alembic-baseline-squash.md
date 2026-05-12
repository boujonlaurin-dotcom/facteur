# Maintenance : Squash Alembic vers une baseline (prod schema snapshot)

**Date** : 2026-04-30
**Auteur** : @lucasbeef
**Type** : Infra / Database / Alembic
**Branche** : `lucasbeef/fix-dev-db-migration-drift`

---

## Contexte

`make bootstrap` échoue à l'étape `[4/6] Migrations Alembic…` sur une machine vierge :

```
Running upgrade 752ae6586a6f -> 4d497ce7bcc2
psycopg.errors.UndefinedObject: index "ix_contents_entities" does not exist
[SQL: DROP INDEX ix_contents_entities]
```

L'environnement de dev *de facto* est la prod parce que **personne n'arrive à monter une DB locale**. Plusieurs années de "SQL manuel via Supabase SQL Editor" + `--autogenerate` contre des DB déjà drifted ont pourri la chaîne Alembic. Rejouer la chaîne contre une DB vide explose.

### Pourquoi la chaîne est cassée

1. **Migrations no-op** : `p1q2r3s4t5u6_add_content_entities.py` a un `def upgrade(): pass` parce que la feature NER a été reportée (cf. `docs/maintenance/maintenance-ner-disabled.md`). Le SQL équivalent a été appliqué à la main sur prod via Supabase SQL Editor. Résultat : prod a des objets que la chaîne n'a jamais créés (`entities` column, `ix_contents_entities` index).
2. **Autogenerate contre une DB drifted** : `4d497ce7bcc2` est le résultat d'un `alembic revision --autogenerate` lancé contre une DB où des étapes manuelles avaient déjà eu lieu. Il essaie de `DROP INDEX ix_contents_entities`, ce qui ne fonctionne que sur prod.
3. **Modèles désalignés** : `Content.entities` est toujours dans `packages/api/app/models/content.py:89` avec son index, alors que `4d497ce7bcc2` les *supprime* dans son `upgrade()`. La migration n'a jamais été cohérente avec le modèle.

---

## Décision

**Squash vers une baseline migration unique** (pattern brownfield standard) :

1. Snapshot complet du schéma prod (`pg_dump --schema-only`) → `packages/api/alembic/baseline/prod-schema-2026-04-30.sql`.
2. Une seule migration `00000_baseline.py` (revision = `00000_baseline`, down_revision = `None`) qui exécute ce SQL.
3. Les 74 anciennes migrations sont déplacées dans `packages/api/alembic/_archive/` (gardées dans git pour le blame, mais Alembic ne les scanne plus).
4. Sur prod : **`alembic stamp 00000_baseline`** (un `UPDATE alembic_version` — zéro changement de schéma, zéro downtime).
5. Désormais, toute nouvelle migration chaîne après `00000_baseline`.

### Pourquoi pas d'autres options

- **"Patcher juste la migration cassée avec `IF EXISTS`"** : règle le blocage immédiat, mais d'autres migrations dans la chaîne sont probablement aussi drifted (ex. `c6d7e8f9a0b1_repair_missing_theme_columns.py`). On rejoue la même histoire dans 3 mois.
- **Reconstruire prod (drop public + alembic upgrade head + restore data)** : envisagé, mais inutile. `stamp` donne la même convergence local/prod sans toucher aux données. On garde l'enveloppe "evening of downtime" en réserve si l'audit Phase 4 révèle un drift qu'on veut nettoyer côté prod.

---

## Plan d'exécution

Détail dans `~/.claude/plans/this-is-the-error-sharded-pine.md`. Résumé :

| Phase | Action | Owner |
|-------|--------|-------|
| 1 | `pg_dump --schema-only` de prod, sanitization, validation locale | @lucasbeef (commande prod) + Claude (sanitize/validate) |
| 2 | Créer `00000_baseline.py`, déplacer 74 migrations dans `_archive/` | Claude |
| 3 | `make db-reset` → vérifier `alembic upgrade head` + `pytest -v` | Claude |
| 4 | Drift audit (`alembic revision --autogenerate -m drift-audit-DO-NOT-COMMIT`) | Claude |
| 5 | **Stamp prod** (`alembic stamp 00000_baseline`) | @lucasbeef (post-merge) |
| 6 | Garde-fous CI + docs (smoke test, schema diff, conventions) | Claude |

---

## Garde-fous (Phase 6)

Pour éviter que la chaîne se re-pourrisse :

1. **CI smoke test** (`.github/workflows/alembic-smoke.yml`) : à chaque PR, `alembic upgrade head` contre une Postgres vide. Si ça pète, la PR est rouge.
2. **Schema diff CI** : compare la sortie de `alembic upgrade head` à un fichier de référence committé. Tout drift = PR rouge.
3. **Convention** dans `docs/agent-brain/safety-guardrails.md` : tout DDL appliqué à prod via Supabase SQL Editor DOIT atterrir comme migration Alembic dans la même PR.
4. **`QUICK_START.md`** : déclare `make bootstrap` comme workflow officiel. Plus de dev-against-prod.

---

## Ce qu'on perd / ce qu'on gagne

**Gagné** : chaîne Alembic propre, `make bootstrap` qui marche sur une machine vierge, drift modèle↔DB visible avec `--autogenerate`, garde-fous CI permanents, fin du workflow "SQL appliqué à la main".

**Perdu** : l'historique migration-par-migration. Les 74 fichiers restent dans `_archive/` (utiles pour `git blame` et la lecture archéologique), mais ils ne se rejouent plus.

**Risque** : un environnement avec une DB en état non-prod (staging stale, fixture custom) sera incompatible et devra être reset à la baseline. À notre connaissance, seul `staging` était dans ce cas, et `staging` est déjà déprécié.

---

## Rollback

Si le stamp prod tourne mal :

1. Supabase Dashboard → Database → Backups → restaurer le snapshot pris juste avant.
2. OU : `UPDATE alembic_version SET version_num = '<ancien_head>'` (l'ancien head sera consigné dans la PR description avant le stamp).

Aucune donnée ne change pendant le stamp ; seul `alembic_version` est touché. Le rollback est trivial.

---

## Drift modèle ↔ baseline (Phase 4 — résultats)

`alembic revision --autogenerate -m drift_audit` lancé contre la baseline a sorti une liste non triviale de divergences entre les modèles SQLAlchemy et le snapshot prod. Le fichier généré N'EST PAS committé. Voici ce qui a été observé — chaque item est une **décision séparée à prendre**, pas un fix automatique.

### Tables en prod, absentes des modèles (probable code mort)

| Table | Action recommandée |
|---|---|
| `app_config` | Vérifier si encore lue/écrite. Si non, drop-table forward migration. |
| `article_feedback` | Idem — module feedback semble avoir été remplacé. |
| `nps_responses` | Edge function Brevo l'écrit. Garder, ajouter le modèle. |
| `source_search_cache` | Remplacé par `host_feed_resolutions` ? Vérifier puis drop. |

### Tables dans les modèles, absentes de prod

| Table | Action recommandée |
|---|---|
| `host_feed_resolutions` | Forward migration `op.create_table(...)` à ajouter. |

### Colonnes / nullability divergentes (modèle plus strict que prod)

- `contents.is_paid` — modèle NOT NULL, prod nullable.
- `user_personalization.muted_content_types`, `hide_paid_content` — modèle NOT NULL, prod nullable.
- `waitlist_entries.source`, `created_at` — idem.
- `waitlist_survey_responses.main_pain` (Text vs VARCHAR(100)), `created_at` (NOT NULL).

→ Forward migration : `ALTER COLUMN ... SET NOT NULL` après backfill des éventuels NULL.

### Colonnes en prod, absentes des modèles

- `sources.editorial_note`
- `waitlist_survey_responses.pain_detail`

→ Soit ajouter au modèle, soit drop forward migration si non utilisées.

### Index "fantômes" en prod (créés via SQL manuel)

- `ix_user_topic_profiles_user_id`, `ix_waitlist_entries_email`, `ix_waitlist_survey_entry_id`
- `idx_entity_prefs_user_mute` (partial), `idx_entity_prefs_user_pref`
- `ix_user_content_status_user_has_note` (partial), `ix_sources_secondary_themes` (gin)

→ Audit cas par cas : utiles ? Si oui, ajouter au `__table_args__` du modèle. Sinon, drop forward.

### Cosmétique / équivalences

- `ix_contents_*_published` — modèles utilisent `[col_a, col_b]` ; prod a `[col_a DESC, col_b]`. Plans EXPLAIN équivalents pour ORDER BY DESC, mais alembic n'aligne pas. Soit ajouter `desc()` aux modèles, soit accepter la divergence.
- `perspective_analyses` — contrainte `_key` (prod auto-généré) vs `uq_*` (modèle nommé). Cosmétique.

### Décision pour cette PR

**On ne corrige rien dans cette PR.** Le but est de débloquer `make bootstrap`. Chaque item ci-dessus est une PR forward de suivi, à prioriser :

1. **Critique** : `host_feed_resolutions` manque en prod → bug latent si du code l'attend.
2. **Sécurité données** : `nps_responses` non modélisé → écritures via edge function uniquement, à confirmer.
3. **Hygiène** : NOT NULL alignements, drop tables mortes, drop colonnes obsolètes.

---

## Liens

- Plan complet : `~/.claude/plans/this-is-the-error-sharded-pine.md`
- Doc associée NER : `docs/maintenance/maintenance-ner-disabled.md`
- Doc historique des collisions Alembic : `docs/maintenance/maintenance-alembic-revision-collisions-feb26.md`

---

## Closure (2026-05-05)

**Statut : LIVRÉ.** PR [#515](https://github.com/boujonlaurin-dotcom/facteur/pull/515) mergée le 2026-05-05. Prod stampée à `00000_baseline` ; déploiement Railway suivant : OK (alembic upgrade head = no-op, conteneur boote normalement).

### Différences vs le plan original

- **Refresh du snapshot.** Le `prod-schema-2026-04-30.sql` initialement préparé est devenu obsolète pendant les 5 jours où la PR a attendu une fenêtre calme : 8 migrations supplémentaires ont landé sur `main` (`en01`, `gn01`, `lf01`, `ls01`, `sp01`, `tr01`, `vl01`, `vp01`). On a re-dumpé prod le 2026-05-05 (`prod-schema-2026-05-05.sql`, 2004 lignes, 42 tables) et archivé ces 8 fichiers en plus → **81 migrations archivées au total** (vs 74 initialement prévues).
- **Sanitize.py durci pour pg_dump 17.x.** Le snapshot 04-30 venait du dashboard Supabase (syntax `CREATE TABLE IF NOT EXISTS "public"."foo"`). Le 05-05 a été pris via `pg_dump 17.9` (Homebrew), qui produit `CREATE TABLE public.foo` — moins idempotent et avec des particularités (`\restrict`/`\unrestrict` meta-commands, identifiants non quotés, `CREATE FUNCTION` au lieu de `CREATE OR REPLACE FUNCTION`). `sanitize.py` a été élargi pour gérer les deux dialectes.
- **`Dockerfile` exécute `alembic upgrade head` au boot.** La règle CLAUDE.md "jamais d'exécution sur Railway" était fausse depuis longtemps. Découvert pendant la cérémonie de stamp ; documenté dans le runbook + corrigé dans CLAUDE.md.
- **`alembic stamp` a nécessité `--purge`.** Sans `--purge`, alembic essaie de résoudre la révision courante (`ls01`, archivée) et plante avec `Can't locate revision identified by 'ls01'`. `--purge` vide `alembic_version` puis insère le stamp, ce qui contourne la résolution.

### Drift audit Phase 4 — encore à traiter

Les findings listés plus haut (host_feed_resolutions manquant en prod, tables orphelines `app_config`/`article_feedback`/`source_search_cache`, alignements NOT NULL, etc.) ne sont **pas adressés** par la PR #515. Ils restent ouverts comme PRs forward de suivi.

### Runbook de récupération

Si la chaîne re-drift dans le futur, suivre [`docs/runbooks/recover-from-alembic-drift.md`](../runbooks/recover-from-alembic-drift.md) — basé directement sur ce qu'on a fait ce coup-ci.
