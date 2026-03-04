"""Page 4 — User Config.

Inspecter la configuration d'un utilisateur : sources, topics, preferences.
"""

import streamlit as st
import pandas as pd

from admin.utils.db import run_query

st.set_page_config(page_title="User Config", page_icon="\u2699\ufe0f", layout="wide")
st.title("\u2699\ufe0f User Config")

# --- User list ---

USERS_LIST_QUERY = """
SELECT user_id, display_name
FROM user_profiles
WHERE onboarding_completed = true
ORDER BY display_name
"""


@st.cache_data(ttl=300)
def load_users_list():
    return run_query(USERS_LIST_QUERY)


users_list = load_users_list()

if not users_list:
    st.info("Aucun utilisateur avec onboarding complete.")
    st.stop()

user_options = {
    f"{u['display_name'] or 'Sans nom'} ({str(u['user_id'])[:8]})": str(u["user_id"])
    for u in users_list
}
selected_label = st.selectbox("Utilisateur", options=list(user_options.keys()))
selected_user_id = user_options[selected_label]

# --- Profile ---

PROFILE_QUERY = """
SELECT
    up.user_id,
    up.display_name,
    up.onboarding_completed,
    up.gamification_enabled,
    up.weekly_goal,
    (SELECT COUNT(*) FROM user_sources us WHERE us.user_id = up.user_id) AS total_sources,
    COALESCE(array_length(uperso.muted_sources, 1), 0) AS muted_sources_count,
    (SELECT COUNT(*) FROM user_interests ui WHERE ui.user_id = up.user_id) AS interests_count,
    (SELECT COUNT(*) FROM user_subtopics ust WHERE ust.user_id = up.user_id) AS subtopics_count,
    (SELECT COUNT(*) FROM user_topic_profiles utp WHERE utp.user_id = up.user_id) AS custom_topics_count,
    uperso.hide_paid_content,
    uperso.muted_themes,
    uperso.muted_topics,
    uperso.muted_content_types
FROM user_profiles up
LEFT JOIN user_personalization uperso ON uperso.user_id = up.user_id
WHERE up.user_id = :user_id
"""


@st.cache_data(ttl=60)
def load_profile(user_id: str):
    rows = run_query(PROFILE_QUERY, {"user_id": user_id})
    return rows[0] if rows else None


profile = load_profile(selected_user_id)

if profile:
    st.subheader("Profil & Preferences")
    c1, c2, c3, c4 = st.columns(4)
    active_sources = profile["total_sources"] - profile["muted_sources_count"]
    c1.metric("Sources actives / masquees", f"{active_sources} / {profile['muted_sources_count']}")
    total_topics = profile["interests_count"] + profile["subtopics_count"] + profile["custom_topics_count"]
    c2.metric("Topics suivis", total_topics)
    c3.metric("Objectif hebdo", profile["weekly_goal"])
    c4.metric("Articles payants", "Masques" if profile.get("hide_paid_content") else "Affiches")

    # Muted info
    muted_themes = profile.get("muted_themes") or []
    muted_topics = profile.get("muted_topics") or []
    muted_types = profile.get("muted_content_types") or []
    if muted_themes or muted_topics or muted_types:
        with st.expander("Filtres actifs (muted)"):
            if muted_themes:
                st.write(f"**Themes masques** : {', '.join(muted_themes)}")
            if muted_topics:
                st.write(f"**Topics masques** : {', '.join(muted_topics)}")
            if muted_types:
                st.write(f"**Types masques** : {', '.join(muted_types)}")

# --- Sources ---

SOURCES_QUERY = """
SELECT
    s.name AS source_name,
    s.type::text AS source_type,
    us.added_at,
    CASE WHEN s.id = ANY(
        COALESCE((SELECT muted_sources FROM user_personalization WHERE user_id = :user_id), ARRAY[]::uuid[])
    ) THEN 'Muted' ELSE 'Active' END AS status,
    (
        SELECT COUNT(*)
        FROM user_content_status ucs
        JOIN contents c ON c.id = ucs.content_id
        WHERE ucs.user_id = :user_id
          AND c.source_id = s.id
          AND ucs.status = 'consumed'
    ) AS articles_read
FROM user_sources us
JOIN sources s ON s.id = us.source_id
WHERE us.user_id = :user_id
ORDER BY articles_read DESC
"""


@st.cache_data(ttl=60)
def load_user_sources(user_id: str):
    return run_query(SOURCES_QUERY, {"user_id": user_id})


st.markdown("---")
st.subheader("Sources")
user_sources = load_user_sources(selected_user_id)

if user_sources:
    df_sources = pd.DataFrame(user_sources)
    display_cols = {
        "source_name": "Source",
        "source_type": "Type",
        "status": "Statut",
        "articles_read": "Articles lus",
        "added_at": "Ajoutee le",
    }
    st.dataframe(
        df_sources[list(display_cols.keys())].rename(columns=display_cols),
        use_container_width=True,
        hide_index=True,
    )
else:
    st.info("Aucune source configuree.")

# --- Topics ---

TOPICS_QUERY = """
SELECT 'interest' AS type, ui.interest_slug AS topic_name, ui.weight AS priority, ui.created_at
FROM user_interests ui WHERE ui.user_id = :user_id
UNION ALL
SELECT 'subtopic', ust.topic_slug, ust.weight, ust.created_at
FROM user_subtopics ust WHERE ust.user_id = :user_id
UNION ALL
SELECT 'custom', utp.topic_name, utp.priority_multiplier, utp.created_at
FROM user_topic_profiles utp WHERE utp.user_id = :user_id
ORDER BY priority DESC
"""


@st.cache_data(ttl=60)
def load_user_topics(user_id: str):
    return run_query(TOPICS_QUERY, {"user_id": user_id})


st.markdown("---")
st.subheader("Topics")
user_topics = load_user_topics(selected_user_id)

if user_topics:
    df_topics = pd.DataFrame(user_topics)
    display_cols = {
        "topic_name": "Topic",
        "type": "Type",
        "priority": "Priorite",
        "created_at": "Ajoute le",
    }
    st.dataframe(
        df_topics[list(display_cols.keys())].rename(columns=display_cols),
        use_container_width=True,
        hide_index=True,
    )
else:
    st.info("Aucun topic configure.")
