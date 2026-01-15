-- DASHBOARD ANALYTICS FACTEUR BE

-- 1. DAU (Daily Active Users)
-- Evolution du nombre d'utilisateurs uniques par jour
SELECT 
  DATE(created_at) as day, 
  COUNT(DISTINCT user_id) as dau
FROM analytics_events
WHERE event_type = 'session_start'
GROUP BY 1
ORDER BY 1 DESC
LIMIT 30;

-- 2. Rétention (Cohortes J1, J7, J14)
-- % des users d'une date (cohort) qui reviennent à J+X
WITH first_launch AS (
  SELECT user_id, MIN(DATE(created_at)) as cohort_date
  FROM analytics_events 
  WHERE event_type = 'app_first_launch' OR event_type = 'session_start' -- fallback if app_first_launch missed
  GROUP BY 1
),
activity AS (
  SELECT DISTINCT user_id, DATE(created_at) as activity_date
  FROM analytics_events 
  WHERE event_type = 'session_start'
)
SELECT 
  fl.cohort_date,
  COUNT(DISTINCT fl.user_id) as cohort_size,
  ROUND((COUNT(DISTINCT CASE WHEN a.activity_date = fl.cohort_date + 1 THEN fl.user_id END) * 100.0 / NULLIF(COUNT(DISTINCT fl.user_id), 0))::numeric, 1) as "J1 %",
  ROUND((COUNT(DISTINCT CASE WHEN a.activity_date = fl.cohort_date + 7 THEN fl.user_id END) * 100.0 / NULLIF(COUNT(DISTINCT fl.user_id), 0))::numeric, 1) as "J7 %",
  ROUND((COUNT(DISTINCT CASE WHEN a.activity_date = fl.cohort_date + 14 THEN fl.user_id END) * 100.0 / NULLIF(COUNT(DISTINCT fl.user_id), 0))::numeric, 1) as "J14 %"
FROM first_launch fl
LEFT JOIN activity a ON fl.user_id = a.user_id
GROUP BY 1
ORDER BY 1 DESC
LIMIT 14;

-- 3. Engagement Global
-- Sessions par semaine, Durée, Articles lus
SELECT 
  COUNT(*) / NULLIF(COUNT(DISTINCT user_id), 0) as avg_sessions_per_user,
  AVG((event_data->>'duration_seconds')::int) as avg_session_duration_sec,
  (SELECT COUNT(*) FROM analytics_events WHERE event_type = 'article_read') * 1.0 / 
  NULLIF((SELECT COUNT(*) FROM analytics_events WHERE event_type = 'session_start'), 0) as avg_articles_per_session
FROM analytics_events
WHERE event_type = 'session_end' 
  AND created_at > NOW() - INTERVAL '7 days';

-- 4. Funnel de Lecture
-- Scroll Depth moyen vs Completion (Tu es à jour)
SELECT 
  ROUND((AVG((event_data->>'scroll_depth_percent')::float) * 100)::numeric, 1) as avg_scroll_depth_pct,
  ROUND(
    ((SELECT COUNT(*) FROM analytics_events WHERE event_type = 'feed_complete') * 100.0 / 
    NULLIF(COUNT(*), 0))::numeric
  , 1) as completion_rate_pct
FROM analytics_events
WHERE event_type = 'feed_scroll'
  AND created_at > NOW() - INTERVAL '7 days';

-- 5. Sources Populaires
-- Top sources ajoutées vs supprimées
WITH adds AS (
  SELECT event_data->>'source_id' as source_id, COUNT(*) as adds
  FROM analytics_events WHERE event_type = 'source_add' GROUP BY 1
),
removes AS (
  SELECT event_data->>'source_id' as source_id, COUNT(*) as removes
  FROM analytics_events WHERE event_type = 'source_remove' GROUP BY 1
)
SELECT 
  s.name, 
  COALESCE(a.adds, 0) as adds, 
  COALESCE(r.removes, 0) as removes,
  (COALESCE(a.adds, 0) - COALESCE(r.removes, 0)) as net_growth
FROM sources s
LEFT JOIN adds a ON s.id::text = a.source_id
LEFT JOIN removes r ON s.id::text = r.source_id
ORDER BY net_growth DESC
LIMIT 10;
