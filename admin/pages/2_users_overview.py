"""Page 2 — Users Overview.

Qui est actif, qui decroche, comment ils utilisent l'app.
"""

import streamlit as st
import pandas as pd

from admin.utils.db import run_query
from admin.utils.status import compute_user_badge, user_badge_emoji

st.set_page_config(page_title="Users Overview", page_icon="\U0001f465", layout="wide")
st.title("\U0001f465 Users Overview")

# --- Queries ---

USERS_QUERY = """
SELECT
    up.user_id,
    up.display_name,
    (
        SELECT MAX(ae.created_at)
        FROM analytics_events ae
        WHERE ae.user_id = up.user_id
    ) AS last_activity_at,
    COALESCE((
        SELECT SUM(ucs.time_spent_seconds)
        FROM user_content_status ucs
        WHERE ucs.user_id = up.user_id
          AND ucs.seen_at > NOW() - INTERVAL '7 days'
    ), 0) AS time_spent_7d_seconds,
    (
        SELECT COUNT(*)
        FROM user_content_status ucs
        WHERE ucs.user_id = up.user_id
          AND ucs.status = 'consumed'
          AND ucs.seen_at > NOW() - INTERVAL '7 days'
    ) AS articles_read_7d,
    (
        SELECT COUNT(*)
        FROM user_content_status ucs
        WHERE ucs.user_id = up.user_id
          AND ucs.is_saved = true
          AND ucs.saved_at > NOW() - INTERVAL '7 days'
    ) AS articles_saved_7d,
    (
        SELECT COUNT(*)
        FROM user_sources us
        WHERE us.user_id = up.user_id
    ) AS total_sources
FROM user_profiles up
WHERE up.onboarding_completed = true
ORDER BY last_activity_at DESC NULLS LAST
"""

DAILY_READS_QUERY = """
SELECT
    DATE(ucs.seen_at) AS day,
    up.display_name AS user_name,
    COUNT(*) AS articles_read
FROM user_content_status ucs
JOIN user_profiles up ON up.user_id = ucs.user_id
WHERE ucs.status = 'consumed'
  AND ucs.seen_at > NOW() - INTERVAL '7 days'
GROUP BY DATE(ucs.seen_at), up.display_name
ORDER BY day
"""

# --- Data ---

@st.cache_data(ttl=120)
def load_users():
    return run_query(USERS_QUERY)


@st.cache_data(ttl=120)
def load_daily_reads():
    return run_query(DAILY_READS_QUERY)


users = load_users()
daily_reads = load_daily_reads()

# Compute badges
for u in users:
    badge = compute_user_badge(u["last_activity_at"])
    u["badge"] = badge
    u["badge_display"] = f"{user_badge_emoji(badge)} {badge}"
    u["time_spent_minutes"] = round(u["time_spent_7d_seconds"] / 60, 1)

# --- KPIs ---

active_count = sum(1 for u in users if u["badge"] in ("Actif", "Ralenti"))
inactive_count = sum(1 for u in users if u["badge"] == "Inactif")
total_reads = sum(u["articles_read_7d"] for u in users)
avg_reads = round(total_reads / len(users), 1) if users else 0
total_saves = sum(u["articles_saved_7d"] for u in users)

col1, col2, col3, col4 = st.columns(4)
col1.metric("Users actifs (7j)", active_count)
col2.metric("Users inactifs (>7j)", inactive_count)
col3.metric("Articles lus / user / sem", avg_reads)
col4.metric("Articles sauvegardes (7j)", total_saves)

# --- Filter ---

st.markdown("---")
badge_filter = st.multiselect(
    "Filtrer par statut",
    options=["Actif", "Ralenti", "Inactif"],
    default=["Actif", "Ralenti", "Inactif"],
)

filtered = [u for u in users if u["badge"] in badge_filter]

# --- Table ---

if filtered:
    df = pd.DataFrame(filtered)
    display_cols = {
        "display_name": "Nom",
        "badge_display": "Activite",
        "time_spent_minutes": "Temps contenu (min, 7j)",
        "articles_read_7d": "Articles lus (7j)",
        "articles_saved_7d": "Sauvegardes (7j)",
        "total_sources": "Sources",
    }
    df_display = df[list(display_cols.keys())].rename(columns=display_cols)
    st.dataframe(df_display, use_container_width=True, hide_index=True)
else:
    st.info("Aucun utilisateur ne correspond aux filtres.")

# --- Chart ---

st.markdown("---")
st.subheader("Articles lus par jour (7 derniers jours)")

if daily_reads:
    df_chart = pd.DataFrame(daily_reads)
    df_chart["day"] = pd.to_datetime(df_chart["day"])
    pivot = df_chart.pivot_table(index="day", columns="user_name", values="articles_read", fill_value=0)
    st.bar_chart(pivot)
else:
    st.info("Pas de donnees de lecture sur les 7 derniers jours.")
