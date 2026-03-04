"""Templates SQL — Qualite du feed et algorithme."""

QUERIES = {
    "feed_quality_diagnostic": """
        WITH digest_items AS (
            SELECT
                dd.user_id,
                (item->>'content_id')::uuid AS content_id
            FROM daily_digest dd,
                 jsonb_array_elements(dd.items) AS item
            WHERE dd.user_id = :user_id
              AND dd.target_date = :target_date
        )
        SELECT
            COUNT(DISTINCT di.content_id) AS articles_served,
            CASE
                WHEN (SELECT COUNT(*) FROM user_sources us WHERE us.user_id = :user_id) = 0 THEN 0
                ELSE COUNT(DISTINCT c.source_id)::float / (SELECT COUNT(*) FROM user_sources us WHERE us.user_id = :user_id)
            END AS diversity_score,
            AVG(EXTRACT(EPOCH FROM (NOW() - c.published_at)) / 3600) AS avg_freshness_hours,
            MAX(c.published_at) AS newest_article,
            MIN(c.published_at) AS oldest_article
        FROM digest_items di
        JOIN contents c ON c.id = di.content_id
    """,
    "feed_source_distribution": """
        WITH digest_items AS (
            SELECT (item->>'content_id')::uuid AS content_id
            FROM daily_digest dd,
                 jsonb_array_elements(dd.items) AS item
            WHERE dd.user_id = :user_id AND dd.target_date = :target_date
        )
        SELECT
            s.name,
            COUNT(*) AS articles_served,
            ROUND(COUNT(*)::numeric / NULLIF(SUM(COUNT(*)) OVER (), 0) * 100, 1) AS pct_of_feed
        FROM digest_items di
        JOIN contents c ON c.id = di.content_id
        JOIN sources s ON s.id = c.source_id
        GROUP BY s.id
        ORDER BY articles_served DESC
    """,
    "users_with_poor_diversity": """
        WITH user_digest AS (
            SELECT
                dd.user_id,
                COUNT(DISTINCT c.source_id) AS distinct_sources,
                COUNT(*) AS total_items
            FROM daily_digest dd,
                 jsonb_array_elements(dd.items) AS item
            JOIN contents c ON c.id = (item->>'content_id')::uuid
            WHERE dd.target_date = :target_date
            GROUP BY dd.user_id
        )
        SELECT
            up.display_name,
            ud.user_id,
            ud.distinct_sources,
            ud.total_items,
            ROUND(ud.distinct_sources::numeric / NULLIF(ud.total_items, 0), 2) AS diversity_ratio
        FROM user_digest ud
        JOIN user_profiles up ON up.user_id = ud.user_id
        WHERE ud.distinct_sources::float / NULLIF(ud.total_items, 0) < 0.3
        ORDER BY diversity_ratio ASC
    """,
    "digest_history": """
        SELECT
            dd.target_date,
            dd.mode,
            jsonb_array_length(dd.items) AS item_count,
            dd.generated_at,
            dc.completed_at,
            dc.articles_read,
            dc.articles_saved,
            dc.articles_dismissed
        FROM daily_digest dd
        LEFT JOIN digest_completions dc ON dc.user_id = dd.user_id AND dc.target_date = dd.target_date
        WHERE dd.user_id = :user_id
        ORDER BY dd.target_date DESC
        LIMIT :limit
    """,
}
