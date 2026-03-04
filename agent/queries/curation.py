"""Templates SQL — Curation et gap analysis."""

QUERIES = {
    "curation_precision_recall": """
        SELECT
            COUNT(*) FILTER (WHERE label = 'good') AS thumbs_up,
            COUNT(*) FILTER (WHERE label = 'bad') AS thumbs_down,
            COUNT(*) FILTER (WHERE label = 'missing') AS missing,
            ROUND(
                COUNT(*) FILTER (WHERE label = 'good')::numeric /
                NULLIF(COUNT(*) FILTER (WHERE label IN ('good', 'bad')), 0) * 100, 1
            ) AS precision_pct,
            ROUND(
                COUNT(*) FILTER (WHERE label = 'good')::numeric /
                NULLIF(COUNT(*) FILTER (WHERE label IN ('good', 'missing')), 0) * 100, 1
            ) AS recall_pct
        FROM curation_annotations
        WHERE user_id = :user_id
          AND feed_date >= :start_date
    """,
    "curation_by_source": """
        SELECT s.name,
            COUNT(*) FILTER (WHERE ca.label = 'good') AS good,
            COUNT(*) FILTER (WHERE ca.label = 'bad') AS bad,
            COUNT(*) FILTER (WHERE ca.label = 'missing') AS missing
        FROM curation_annotations ca
        JOIN contents c ON c.id = ca.content_id
        JOIN sources s ON s.id = c.source_id
        WHERE ca.feed_date >= :start_date
        GROUP BY s.id, s.name
        ORDER BY bad DESC
    """,
    "curation_trend": """
        SELECT feed_date,
            COUNT(*) AS total_annotations,
            COUNT(*) FILTER (WHERE label = 'good') AS good,
            COUNT(*) FILTER (WHERE label = 'bad') AS bad,
            COUNT(*) FILTER (WHERE label = 'missing') AS missing,
            ROUND(
                COUNT(*) FILTER (WHERE label = 'good')::numeric /
                NULLIF(COUNT(*) FILTER (WHERE label IN ('good', 'bad')), 0) * 100, 1
            ) AS daily_precision
        FROM curation_annotations
        WHERE user_id = :user_id
        GROUP BY feed_date
        ORDER BY feed_date
    """,
    "curation_gap_candidates": """
        SELECT
            c.id AS content_id,
            c.title,
            c.url,
            s.name AS source_name,
            c.published_at
        FROM contents c
        JOIN sources s ON s.id = c.source_id
        JOIN user_sources us ON us.source_id = s.id AND us.user_id = :user_id
        WHERE DATE(c.published_at) = :feed_date
          AND c.id NOT IN (
              SELECT (item->>'content_id')::uuid
              FROM daily_digest dd,
                   jsonb_array_elements(dd.items) AS item
              WHERE dd.user_id = :user_id AND dd.target_date = :feed_date
          )
        ORDER BY c.published_at DESC
        LIMIT 50
    """,
}
