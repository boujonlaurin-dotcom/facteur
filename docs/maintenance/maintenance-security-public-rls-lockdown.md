# Maintenance — Security Public RLS Lockdown

## Contexte

La revue de sécurité du 2026-05-29 a confirmé que plusieurs tables du schéma
`public` étaient exposées via Supabase/PostgREST sans RLS effectif et avec des
droits `anon`. La clé anon étant publique par design, le lancement public reste
gelé tant que ces tables ne sont pas protégées en production.

Périmètre de cette maintenance : finding critique RLS uniquement. Les autres
chantiers sécurité du rapport (JWT, SSRF, endpoints internes, dépendances) sont
hors scope et ne doivent pas être embarqués dans la PR.

## Plan Technique

- Ajouter une migration Alembic unique après `cl01_drop_daily_top3` :
  `sec01_lock_down_public_rls`.
- Activer RLS sur les tables user-owned et créer quatre policies
  `TO authenticated`, scopées par `auth.uid() = user_id` pour
  `SELECT`, `INSERT`, `UPDATE`, `DELETE`.
- Révoquer tous les droits `anon` sur les tables client-authenticated. Le rôle
  `authenticated` garde les grants DML directs, mais les policies RLS filtrent
  les lignes.
- Pour `collection_items` et `veille_keywords`, utiliser des policies via le
  parent (`collections.user_id`, `veille_configs.user_id`).
- Activer RLS sans policy et révoquer `anon, authenticated` sur les tables
  backend-only/cache/queue. Le backend continue d'y accéder via son rôle
  privilégié.
- Révoquer l'exécution anon/authenticated de `handle_new_user_notion_sync()`.
- Vérifier via métadonnées uniquement avec
  `packages/api/scripts/verify_security_rls_metadata.sql`.

## Matrice RLS

| Table | Classification | Accès direct client |
| --- | --- | --- |
| `collections` | User-owned via `user_id` | `authenticated` own rows |
| `collection_items` | Fille de `collections` | `authenticated` via collection owner |
| `article_feedback` | User-owned via `user_id` | `authenticated` own rows |
| `daily_digest` | User-owned via `user_id` | `authenticated` own rows |
| `digest_completions` | User-owned via `user_id` | `authenticated` own rows |
| `curation_annotations` | User-owned via `user_id` | `authenticated` own rows |
| `user_personalization` | User-owned via `user_id` | `authenticated` own rows |
| `user_entity_preferences` | User-owned via `user_id` | `authenticated` own rows |
| `user_topic_progress` | User-owned via `user_id` | `authenticated` own rows |
| `user_favorite_interests` | User-owned via `user_id` | `authenticated` own rows |
| `user_favorite_sources` | User-owned via `user_id` | `authenticated` own rows |
| `veille_keywords` | Fille de `veille_configs` | `authenticated` via veille owner |
| `grille_game_states` | User-owned via `user_id` | `authenticated` own rows |
| `serene_reports` | User-owned via `user_id`, si présente | `authenticated` own rows |
| `digest_generation_state` | Backend-only lifecycle | aucun grant `anon/authenticated` |
| `failed_source_attempts` | Backend-only telemetry | aucun grant `anon/authenticated` |
| `perspective_analyses` | Backend-only generated content | aucun grant `anon/authenticated` |
| `topic_quizzes` | Backend-only generated content | aucun grant `anon/authenticated` |
| `classification_queue` | Backend-only queue | aucun grant `anon/authenticated` |
| `source_search_cache` | Backend-only cache | aucun grant `anon/authenticated` |
| `editorial_highlights_history` | Backend-only cache/history | aucun grant `anon/authenticated` |
| `cluster_title_annotations` | Backend-only annotation cache | aucun grant `anon/authenticated` |
| `grille_puzzles` | Backend-only game content | aucun grant `anon/authenticated` |
| `event_rsvps` | Backend-only event emails | aucun grant `anon/authenticated` |
| `api_usage_events` | Backend-only telemetry | aucun grant `anon/authenticated` |

## Validation

- `cd packages/api && python -m alembic heads` doit retourner un seul head.
- `cd packages/api && python -m alembic upgrade head` doit passer sur DB locale
  ou Postgres éphémère avec `DATABASE_URL`/`MIGRATION_DATABASE_URL` explicite.
- Exécuter le script metadata-only :
  `psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f packages/api/scripts/verify_security_rls_metadata.sql`.
- Après déploiement, relancer Supabase Security Advisor.

## Checklist PR / Post-déploiement

- [ ] `python -m alembic heads` affiche un seul head.
- [ ] `alembic upgrade head` passe sur une base locale ou éphémère.
- [ ] Le script metadata-only passe sans lire de données métier.
- [ ] Supabase Advisor ne remonte plus `rls_disabled_in_public` pour les tables
      couvertes.
- [ ] Supabase Advisor ne remonte plus
      `anon_security_definer_function_executable` pour
      `handle_new_user_notion_sync()`.
- [ ] La PR cible `main`.
