"""Page 3 — Feed Quality.

Quels utilisateurs ont un feed desequilibre ou de mauvaise qualite ?
"""

import streamlit as st
import pandas as pd
import altair as alt

from admin.utils.db import run_query
from admin.utils.config import (
    DIVERSITY_SCORE_WARNING,
    FRESHNESS_HOURS_WARNING,
    MIN_ARTICLES_SERVED_24H,
    TOP_SOURCE_PCT_WARNING,
)

st.set_page_config(page_title="Feed Quality", page_icon="\U0001f4ca", layout="wide")
st.title("\U0001f4ca Feed Quality")

# --- Queries ---

FEED_QUALITY_QUERY = """
WITH digest_items AS (
    SELECT
        dd.user_id,
        (item->>'content_id')::uuid AS content_id
    FROM daily_digest dd,
         jsonb_array_elements(dd.items) AS item
    WHERE dd.target_date = CURRENT_DATE
)
SELECT
    up.user_id,
    up.display_name,
    COUNT(DISTINCT di.content_id) AS articles_served_today,
    CASE
        WHEN (SELECT COUNT(*) FROM user_sources us WHERE us.user_id = up.user_id) = 0 THEN 0
        ELSE COUNT(DISTINCT c.source_id)::float / (SELECT COUNT(*) FROM user_sources us WHERE us.user_id = up.user_id)
    END AS diversity_score,
    COALESCE(AVG(EXTRACT(EPOCH FROM (NOW() - c.published_at)) / 3600), 0) AS avg_freshness_hours
FROM user_profiles up
LEFT JOIN digest_items di ON di.user_id = up.user_id
LEFT JOIN contents c ON c.id = di.content_id
WHERE up.onboarding_completed = true
GROUP BY up.user_id, up.display_name
ORDER BY diversity_score ASC NULLS FIRST
"""

TOP_SOURCE_QUERY = """
WITH digest_items AS (
    SELECT
        dd.user_id,
        (item->>'content_id')::uuid AS content_id
    FROM daily_digest dd,
         jsonb_array_elements(dd.items) AS item
    WHERE dd.target_date = CURRENT_DATE
),
source_counts AS (
    SELECT
        di.user_id,
        s.name AS source_name,
        COUNT(*) AS cnt,
        ROUND(COUNT(*)::numeric / NULLIF(SUM(COUNT(*)) OVER (PARTITION BY di.user_id), 0) * 100, 1) AS pct
    FROM digest_items di
    JOIN contents c ON c.id = di.content_id
    JOIN sources s ON s.id = c.source_id
    GROUP BY di.user_id, s.name
)
SELECT DISTINCT ON (user_id)
    user_id, source_name AS top_source_name, pct AS top_source_pct
FROM source_counts
ORDER BY user_id, pct DESC
"""

# --- Data ---

@st.cache_data(ttl=120)
def load_feed_quality():
    quality = run_query(FEED_QUALITY_QUERY)
    top_sources = run_query(TOP_SOURCE_QUERY)
    top_map = {str(r["user_id"]): r for r in top_sources}
    for q in quality:
        ts = top_map.get(str(q["user_id"]), {})
        q["top_source_name"] = ts.get("top_source_name", "-")
        q["top_source_pct"] = float(ts.get("top_source_pct", 0))
        q["diversity_score"] = round(float(q["diversity_score"] or 0), 2)
        q["avg_freshness_hours"] = round(float(q["avg_freshness_hours"] or 0), 1)
    return quality


data = load_feed_quality()

# --- Alerts ---

low_diversity = [d for d in data if d["diversity_score"] < DIVERSITY_SCORE_WARNING and d["articles_served_today"] > 0]
zero_articles = [d for d in data if d["articles_served_today"] == 0]
stale_feed = [d for d in data if d["avg_freshness_hours"] > FRESHNESS_HOURS_WARNING and d["articles_served_today"] > 0]

if low_diversity:
    names = ", ".join(d["display_name"] or str(d["user_id"])[:8] for d in low_diversity)
    st.warning(f"Diversite faible (<{DIVERSITY_SCORE_WARNING}) : {names}")
if zero_articles:
    names = ", ".join(d["display_name"] or str(d["user_id"])[:8] for d in zero_articles)
    st.warning(f"0 articles servis aujourd'hui : {names}")
if stale_feed:
    names = ", ".join(d["display_name"] or str(d["user_id"])[:8] for d in stale_feed)
    st.warning(f"Fraicheur >{FRESHNESS_HOURS_WARNING}h : {names}")

# --- Table ---

if data:
    df = pd.DataFrame(data)
    display_cols = {
        "display_name": "Nom",
        "articles_served_today": "Articles servis",
        "diversity_score": "Diversite",
        "avg_freshness_hours": "Fraicheur (h)",
        "top_source_pct": "Source dom. %",
        "top_source_name": "Source dominante",
    }
    df_display = df[list(display_cols.keys())].rename(columns=display_cols)
    st.dataframe(df_display, use_container_width=True, hide_index=True)

    # --- Scatter chart ---
    st.markdown("---")
    st.subheader("Diversite vs Fraicheur")

    df_chart = df[df["articles_served_today"] > 0].copy()
    if not df_chart.empty:
        chart = (
            alt.Chart(df_chart)
            .mark_circle()
            .encode(
                x=alt.X("diversity_score:Q", title="Score diversite", scale=alt.Scale(domain=[0, 1])),
                y=alt.Y("avg_freshness_hours:Q", title="Fraicheur moyenne (heures)"),
                size=alt.Size("articles_served_today:Q", title="Articles servis"),
                tooltip=["display_name", "diversity_score", "avg_freshness_hours", "articles_served_today"],
            )
            .properties(width=700, height=400)
        )
        # Add warning zones
        rules = (
            alt.Chart(pd.DataFrame({"x": [DIVERSITY_SCORE_WARNING]}))
            .mark_rule(color="orange", strokeDash=[5, 5])
            .encode(x="x:Q")
        )
        hrule = (
            alt.Chart(pd.DataFrame({"y": [FRESHNESS_HOURS_WARNING]}))
            .mark_rule(color="orange", strokeDash=[5, 5])
            .encode(y="y:Q")
        )
        st.altair_chart(chart + rules + hrule, use_container_width=True)
    else:
        st.info("Pas de donnees de feed pour aujourd'hui.")
else:
    st.info("Aucun utilisateur avec onboarding complete.")
