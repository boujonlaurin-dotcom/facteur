"""Templates SQL — Sante des sources."""

QUERIES = {
    "source_health_summary": """
        SELECT
            s.id, s.name, s.url, s.type::text AS source_type,
            s.is_active, s.last_synced_at,
            MAX(c.published_at) AS last_article_at,
            COUNT(c.id) FILTER (WHERE c.created_at > NOW() - INTERVAL '24 hours') AS articles_24h,
            (SELECT COUNT(*) FROM user_sources us WHERE us.source_id = s.id) AS subscriber_count
        FROM sources s
        LEFT JOIN contents c ON c.source_id = s.id
        WHERE s.is_active = true
        GROUP BY s.id
        ORDER BY last_article_at ASC NULLS FIRST
    """,
    "source_publish_frequency": """
        SELECT
            source_id,
            AVG(EXTRACT(EPOCH FROM (published_at - prev_published_at)) / 3600) AS avg_interval_hours
        FROM (
            SELECT source_id, published_at,
                LAG(published_at) OVER (PARTITION BY source_id ORDER BY published_at) AS prev_published_at
            FROM contents
            WHERE published_at > NOW() - INTERVAL '30 days'
        ) sub
        WHERE prev_published_at IS NOT NULL
        GROUP BY source_id
    """,
    "source_sync_staleness": """
        SELECT s.name, s.last_synced_at,
            EXTRACT(EPOCH FROM (NOW() - s.last_synced_at)) / 3600 AS hours_since_sync
        FROM sources s
        WHERE s.is_active = true
          AND s.last_synced_at < NOW() - INTERVAL '6 hours'
        ORDER BY s.last_synced_at ASC
    """,
    "source_detail": """
        SELECT
            s.id, s.name, s.url, s.feed_url, s.type::text AS source_type,
            s.theme, s.granular_topics, s.secondary_themes,
            s.is_curated, s.is_active, s.last_synced_at,
            s.bias_stance::text, s.reliability_score::text,
            MAX(c.published_at) AS last_article_at,
            COUNT(c.id) AS total_articles,
            COUNT(c.id) FILTER (WHERE c.created_at > NOW() - INTERVAL '7 days') AS articles_7d
        FROM sources s
        LEFT JOIN contents c ON c.source_id = s.id
        WHERE s.name ILIKE :search_term
        GROUP BY s.id
    """,
}
