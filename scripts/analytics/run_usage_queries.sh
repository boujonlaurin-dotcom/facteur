#!/usr/bin/env bash
# run_usage_queries.sh — Lance les requêtes KPI du rapport d'usage sur la DB Supabase.
#
# Prérequis : DATABASE_URL_RO exporté (rôle claude_analytics_ro, SELECT-only).
# Sortie : JSON sur stdout, un objet par requête ({ "T2_1": [...], "T2_2": [...], ... }).
#
# Usage :
#   export $(grep -v '^#' .env | xargs)  # charge .env
#   bash scripts/analytics/run_usage_queries.sh > /tmp/usage.json
#   # puis colle /tmp/usage.json dans le chat ou dans docs/analytics/usage-report-*.md
#
# Safe by design : refuse de tourner si DATABASE_URL_RO contient "service_role" ou "postgres:postgres".

set -euo pipefail

if [[ -z "${DATABASE_URL_RO:-}" ]]; then
  echo "ERROR: DATABASE_URL_RO non défini (voir .env.example)" >&2
  exit 1
fi

if [[ "$DATABASE_URL_RO" == *"service_role"* || "$DATABASE_URL_RO" == *"postgres:postgres"* ]]; then
  echo "ERROR: DATABASE_URL_RO semble pointer vers un rôle avec écriture. Utilise claude_analytics_ro." >&2
  exit 1
fi

# psql via docker si pas installé localement — évite d'installer PG client sur la machine.
PSQL="psql"
if ! command -v psql >/dev/null 2>&1; then
  PSQL="docker run --rm -e PGPASSWORD -i postgres:16 psql"
fi

query() {
  local label="$1"
  local sql="$2"
  local result
  result=$($PSQL "$DATABASE_URL_RO" -X -A -t -c "SELECT json_agg(row_to_json(q)) FROM ($sql) q;" 2>/dev/null || echo "null")
  echo "\"$label\": ${result:-null}"
}

echo "{"

# T2.1 — Closure rate digest 30j (SOURCE DE VÉRITÉ : analytics_events)
query "T2_1_digest_sessions_via_events" "
  SELECT
    DATE(created_at)::text AS day,
    COUNT(*) FILTER (WHERE (event_data->>'closure_achieved')::bool) AS closures,
    COUNT(*) AS digest_sessions,
    ROUND(100.0 * COUNT(*) FILTER (WHERE (event_data->>'closure_achieved')::bool) / NULLIF(COUNT(*), 0), 1) AS closure_rate_pct,
    ROUND(AVG((event_data->>'articles_read')::int), 2) AS avg_articles_read,
    ROUND(AVG((event_data->>'total_time')::int) / 60.0, 1) AS avg_minutes
  FROM analytics_events
  WHERE event_type = 'digest_session'
    AND created_at > NOW() - INTERVAL '30 days'
  GROUP BY 1 ORDER BY 1 DESC
"
echo ","

# T2.1b — Fallback : lire directement digest_completions (table métier)
query "T2_1b_digest_completions_direct" "
  SELECT
    DATE(completed_at)::text AS day,
    COUNT(*) AS completions,
    ROUND(AVG(articles_read), 2) AS avg_articles_read,
    ROUND(AVG(closure_time_seconds) / 60.0, 1) AS avg_minutes
  FROM digest_completions
  WHERE completed_at > NOW() - INTERVAL '30 days'
  GROUP BY 1 ORDER BY 1 DESC
"
echo ","

# T2.2 — Streaks (habitude)
query "T2_2_streaks" "
  SELECT
    COUNT(*) FILTER (WHERE current_streak >= 1) AS streak_1_plus,
    COUNT(*) FILTER (WHERE current_streak >= 3) AS streak_3_plus,
    COUNT(*) FILTER (WHERE current_streak >= 7) AS streak_7_plus,
    COUNT(*) FILTER (WHERE current_streak >= 14) AS streak_14_plus,
    COUNT(*) FILTER (WHERE longest_streak >= 7) AS has_hit_1_week_ever,
    MAX(longest_streak) AS max_ever,
    ROUND(AVG(current_streak)::numeric, 2) AS avg_current
  FROM user_streaks
"
echo ","

# T2.3 — Activité 7j
query "T2_3_activity_7d" "
  SELECT
    COUNT(DISTINCT user_id) AS active_users_7d,
    ROUND(SUM(time_spent_seconds) / 60.0, 1) AS total_minutes,
    ROUND(SUM(time_spent_seconds) / 60.0 / NULLIF(COUNT(DISTINCT user_id), 0), 1) AS avg_min_per_user,
    COUNT(*) FILTER (WHERE status = 'consumed') AS articles_consumed,
    ROUND(COUNT(*) FILTER (WHERE status = 'consumed') * 1.0 / NULLIF(COUNT(DISTINCT user_id), 0), 1) AS articles_per_user
  FROM user_content_status
  WHERE updated_at > NOW() - INTERVAL '7 days'
"
echo ","

# T2.4 — Bookmarks
query "T2_4_bookmarks" "
  SELECT
    COUNT(*) FILTER (WHERE is_saved) AS total_saved,
    COUNT(DISTINCT user_id) FILTER (WHERE is_saved) AS users_with_saves,
    COUNT(*) FILTER (WHERE is_saved AND status = 'consumed') AS saved_and_read,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_saved AND status = 'consumed')
          / NULLIF(COUNT(*) FILTER (WHERE is_saved), 0), 1) AS pct_saved_eventually_read
  FROM user_content_status
"
echo ","

# T3.1 — Mise en perspective
query "T3_1_perspectives" "
  SELECT
    COUNT(*) AS comparison_views_30d,
    COUNT(DISTINCT user_id) AS unique_users
  FROM analytics_events
  WHERE event_type = 'comparison_viewed' AND created_at > NOW() - INTERVAL '30 days'
"
echo ","

# T3.3 — Gamification on/off
query "T3_3_gamification" "
  SELECT
    p.gamification_enabled,
    COUNT(DISTINCT p.user_id) AS n_users,
    ROUND(AVG(s.current_streak)::numeric, 2) AS avg_current_streak,
    ROUND(AVG(s.longest_streak)::numeric, 2) AS avg_longest_streak
  FROM user_profiles p
  LEFT JOIN user_streaks s USING (user_id)
  GROUP BY 1
"
echo ","

# EXTRA — total users (dénominateur manquant dans R01)
query "EXTRA_users_total" "
  SELECT
    COUNT(*) AS total_profiles,
    COUNT(*) FILTER (WHERE onboarding_completed) AS onboarded,
    COUNT(*) FILTER (WHERE gamification_enabled) AS gamification_on
  FROM user_profiles
"
echo ","

# EXTRA — event types vus sur 30j (sanity check instrumentation)
query "EXTRA_event_types_30d" "
  SELECT event_type, COUNT(*) AS n, COUNT(DISTINCT user_id) AS unique_users
  FROM analytics_events
  WHERE created_at > NOW() - INTERVAL '30 days'
  GROUP BY 1 ORDER BY 2 DESC
"

echo "}"
