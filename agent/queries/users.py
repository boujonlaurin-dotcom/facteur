"""Templates SQL — Activite et configuration utilisateurs."""

QUERIES = {
    "user_activity_summary": """
        SELECT
            up.user_id,
            up.display_name,
            (SELECT MAX(ae.created_at) FROM analytics_events ae
             WHERE ae.user_id = up.user_id) AS last_activity_at,
            COALESCE((SELECT SUM(ucs.time_spent_seconds) FROM user_content_status ucs
                      WHERE ucs.user_id = up.user_id AND ucs.seen_at > NOW() - INTERVAL '7 days'), 0)
                AS time_spent_7d_seconds,
            (SELECT COUNT(*) FROM user_content_status ucs
             WHERE ucs.user_id = up.user_id AND ucs.status = 'consumed'
               AND ucs.seen_at > NOW() - INTERVAL '7 days') AS articles_read_7d,
            (SELECT COUNT(*) FROM user_content_status ucs
             WHERE ucs.user_id = up.user_id AND ucs.is_saved = true
               AND ucs.saved_at > NOW() - INTERVAL '7 days') AS articles_saved_7d
        FROM user_profiles up
        WHERE up.onboarding_completed = true
        ORDER BY last_activity_at DESC NULLS LAST
    """,
    "inactive_users": """
        SELECT up.user_id, up.display_name,
            (SELECT MAX(ae.created_at) FROM analytics_events ae
             WHERE ae.user_id = up.user_id) AS last_activity_at
        FROM user_profiles up
        WHERE up.onboarding_completed = true
          AND NOT EXISTS (
              SELECT 1 FROM analytics_events ae
              WHERE ae.user_id = up.user_id
                AND ae.created_at > NOW() - INTERVAL :days_threshold
          )
        ORDER BY last_activity_at ASC NULLS FIRST
    """,
    "user_engagement_detail": """
        SELECT
            DATE(ucs.seen_at) AS day,
            COUNT(*) FILTER (WHERE ucs.status = 'consumed') AS articles_read,
            COUNT(*) FILTER (WHERE ucs.is_saved = true) AS articles_saved,
            SUM(ucs.time_spent_seconds) AS time_spent_seconds
        FROM user_content_status ucs
        WHERE ucs.user_id = :user_id
          AND ucs.seen_at > NOW() - INTERVAL '30 days'
        GROUP BY DATE(ucs.seen_at)
        ORDER BY day DESC
    """,
    "user_config_overview": """
        SELECT
            up.user_id,
            up.display_name,
            up.gamification_enabled,
            up.weekly_goal,
            (SELECT COUNT(*) FROM user_sources us WHERE us.user_id = up.user_id) AS total_sources,
            COALESCE(array_length(uperso.muted_sources, 1), 0) AS muted_sources_count,
            (SELECT COUNT(*) FROM user_interests ui WHERE ui.user_id = up.user_id) AS interests_count,
            (SELECT COUNT(*) FROM user_subtopics ust WHERE ust.user_id = up.user_id) AS subtopics_count,
            (SELECT COUNT(*) FROM user_topic_profiles utp WHERE utp.user_id = up.user_id) AS custom_topics_count,
            uperso.hide_paid_content,
            uperso.muted_themes,
            uperso.muted_topics
        FROM user_profiles up
        LEFT JOIN user_personalization uperso ON uperso.user_id = up.user_id
        WHERE up.user_id = :user_id
    """,
    "user_top_sources": """
        SELECT s.name, s.type::text AS source_type, us.added_at,
            CASE WHEN s.id = ANY(
                COALESCE((SELECT muted_sources FROM user_personalization WHERE user_id = :user_id), ARRAY[]::uuid[])
            ) THEN 'Muted' ELSE 'Active' END AS status,
            (
                SELECT COUNT(*)
                FROM user_content_status ucs
                JOIN contents c ON c.id = ucs.content_id
                WHERE ucs.user_id = :user_id AND c.source_id = s.id AND ucs.status = 'consumed'
            ) AS articles_read
        FROM user_sources us
        JOIN sources s ON s.id = us.source_id
        WHERE us.user_id = :user_id
        ORDER BY articles_read DESC
    """,
    "users_with_degraded_config": """
        SELECT up.user_id, up.display_name,
            (SELECT COUNT(*) FROM user_sources us WHERE us.user_id = up.user_id) AS total_sources,
            COALESCE(array_length(uperso.muted_sources, 1), 0) AS muted_sources_count
        FROM user_profiles up
        LEFT JOIN user_personalization uperso ON uperso.user_id = up.user_id
        WHERE up.onboarding_completed = true
        GROUP BY up.user_id, up.display_name, uperso.muted_sources
        HAVING (SELECT COUNT(*) FROM user_sources us WHERE us.user_id = up.user_id)
            - COALESCE(array_length(uperso.muted_sources, 1), 0) < 3
    """,
}
