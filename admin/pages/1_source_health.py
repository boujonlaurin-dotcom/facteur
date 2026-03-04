"""Page 1 — Source Health Monitor.

Repond en <10s a : "Est-ce qu'une source est cassee ou en retard ?"
"""

import streamlit as st
import pandas as pd

from admin.utils.db import run_query
from admin.utils.status import compute_source_status, source_status_emoji

st.set_page_config(page_title="Source Health", page_icon="\U0001f4e1", layout="wide")
st.title("\U0001f4e1 Source Health Monitor")

# --- Queries ---

SOURCES_QUERY = """
SELECT
    s.id,
    s.name,
    s.url,
    s.type::text AS source_type,
    s.is_active,
    s.last_synced_at,
    MAX(c.published_at) AS last_article_at,
    COUNT(c.id) FILTER (WHERE c.created_at > NOW() - INTERVAL '24 hours') AS articles_24h
FROM sources s
LEFT JOIN contents c ON c.source_id = s.id
WHERE s.is_active = true
GROUP BY s.id
ORDER BY MAX(c.published_at) ASC NULLS FIRST
"""

AVG_INTERVAL_QUERY = """
SELECT
    source_id,
    AVG(EXTRACT(EPOCH FROM (published_at - prev_published_at)) / 3600) AS avg_interval_hours
FROM (
    SELECT
        source_id,
        published_at,
        LAG(published_at) OVER (PARTITION BY source_id ORDER BY published_at) AS prev_published_at
    FROM contents
    WHERE published_at > NOW() - INTERVAL '30 days'
) sub
WHERE prev_published_at IS NOT NULL
GROUP BY source_id
"""

# --- Data ---

@st.cache_data(ttl=120)
def load_data():
    sources = run_query(SOURCES_QUERY)
    intervals = run_query(AVG_INTERVAL_QUERY)
    interval_map = {str(r["source_id"]): r["avg_interval_hours"] for r in intervals}
    return sources, interval_map


sources, interval_map = load_data()

# Compute status for each source
for s in sources:
    avg_h = interval_map.get(str(s["id"]))
    status = compute_source_status(s["last_article_at"], avg_h)
    s["status"] = status
    s["status_display"] = f"{source_status_emoji(status)} {status}"

# --- KPIs ---

ok_count = sum(1 for s in sources if s["status"] == "OK")
alert_count = sum(1 for s in sources if s["status"] != "OK")
total_articles_24h = sum(s["articles_24h"] for s in sources)
last_sync_dates = [s["last_synced_at"] for s in sources if s["last_synced_at"]]
last_sync_global = max(last_sync_dates) if last_sync_dates else None

col1, col2, col3, col4 = st.columns(4)
col1.metric("Sources OK", f"{ok_count}/{len(sources)}")
col2.metric("Sources en alerte", alert_count)
col3.metric("Derniere sync", str(last_sync_global)[:19] if last_sync_global else "N/A")
col4.metric("Articles 24h", total_articles_24h)

# --- Filters ---

st.markdown("---")
col_filter, col_search = st.columns([1, 2])
with col_filter:
    status_filter = st.multiselect(
        "Filtrer par statut",
        options=["OK", "Retard", "KO"],
        default=["OK", "Retard", "KO"],
    )
with col_search:
    search = st.text_input("Rechercher une source", "")

# Filter data
filtered = [
    s for s in sources
    if s["status"] in status_filter
    and (not search or search.lower() in s["name"].lower())
]

# --- Table ---

if filtered:
    df = pd.DataFrame(filtered)
    display_cols = {
        "name": "Source",
        "source_type": "Type",
        "last_synced_at": "Derniere sync",
        "last_article_at": "Dernier article",
        "articles_24h": "Articles 24h",
        "status_display": "Statut",
    }
    df_display = df[list(display_cols.keys())].rename(columns=display_cols)

    # Sort: KO first, then Retard, then OK
    status_order = {"\u274c KO": 0, "\u26a0\ufe0f Retard": 1, "\u2705 OK": 2}
    df_display["_sort"] = df_display["Statut"].map(status_order).fillna(3)
    df_display = df_display.sort_values("_sort").drop(columns=["_sort"])

    st.dataframe(df_display, use_container_width=True, hide_index=True)
else:
    st.info("Aucune source ne correspond aux filtres.")
