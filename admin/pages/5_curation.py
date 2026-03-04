"""Page 5 — Curation Workbench.

Annoter les articles recommandes pour mesurer l'ecart algo vs ideal.
"""

import uuid
from datetime import date, datetime, timezone

import streamlit as st
import pandas as pd
from sqlalchemy import text

from admin.utils.db import get_connection, run_query

st.set_page_config(page_title="Curation", page_icon="\U0001f3af", layout="wide")
st.title("\U0001f3af Curation Workbench")

# --- User & date selectors ---

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

col_user, col_date = st.columns([2, 1])
with col_user:
    selected_label = st.selectbox("Utilisateur", options=list(user_options.keys()))
with col_date:
    selected_date = st.date_input("Date du feed", value=date.today())

selected_user_id = user_options[selected_label]

# --- Digest articles ---

DIGEST_ARTICLES_QUERY = """
SELECT
    (item->>'content_id')::uuid AS content_id,
    (item->>'rank')::int AS rank,
    item->>'reason' AS reason,
    item->>'source_slug' AS source_slug,
    c.title,
    c.url,
    s.name AS source_name
FROM daily_digest dd,
     jsonb_array_elements(dd.items) AS item
JOIN contents c ON c.id = (item->>'content_id')::uuid
JOIN sources s ON s.id = c.source_id
WHERE dd.user_id = :user_id
  AND dd.target_date = :feed_date
ORDER BY (item->>'rank')::int
"""

ANNOTATIONS_QUERY = """
SELECT content_id, label, note
FROM curation_annotations
WHERE user_id = :user_id
  AND feed_date = :feed_date
"""


def load_digest_articles(user_id: str, feed_date: date):
    return run_query(DIGEST_ARTICLES_QUERY, {"user_id": user_id, "feed_date": str(feed_date)})


def load_annotations(user_id: str, feed_date: date):
    rows = run_query(ANNOTATIONS_QUERY, {"user_id": user_id, "feed_date": str(feed_date)})
    return {str(r["content_id"]): r for r in rows}


articles = load_digest_articles(selected_user_id, selected_date)
existing_annotations = load_annotations(selected_user_id, selected_date)

# --- KPI ---

annotated_count = len(existing_annotations)
st.markdown(
    f"**{len(articles)}** articles servis | "
    f"**{annotated_count}** annotes | "
    f"**{sum(1 for a in existing_annotations.values() if a['label'] == 'missing')}** manquants ajoutes"
)

st.markdown("---")

# --- Annotation form ---

UPSERT_ANNOTATION = """
INSERT INTO curation_annotations (id, user_id, content_id, feed_date, label, note, annotated_by, created_at)
VALUES (:id, :user_id, :content_id, :feed_date, :label, :note, 'admin', :created_at)
ON CONFLICT ON CONSTRAINT uq_curation_user_content_date
DO UPDATE SET label = EXCLUDED.label, note = EXCLUDED.note
"""

if articles:
    for art in articles:
        cid = str(art["content_id"])
        existing = existing_annotations.get(cid, {})
        current_label = existing.get("label", "")
        current_note = existing.get("note", "") or ""

        with st.container():
            col_info, col_label, col_note = st.columns([3, 1, 2])
            with col_info:
                st.markdown(f"**#{art['rank']}** [{art['title']}]({art['url']})")
                st.caption(f"{art['source_name']} | {art.get('reason', '')}")
            with col_label:
                label_options = ["--", "\U0001f44d good", "\U0001f44e bad"]
                default_idx = 0
                if current_label == "good":
                    default_idx = 1
                elif current_label == "bad":
                    default_idx = 2
                label_choice = st.radio(
                    "Annotation",
                    options=label_options,
                    index=default_idx,
                    key=f"label_{cid}",
                    horizontal=True,
                    label_visibility="collapsed",
                )
            with col_note:
                note_value = st.text_input("Note", value=current_note, key=f"note_{cid}", label_visibility="collapsed")

            # Save on change
            if label_choice != "--":
                label_clean = label_choice.split(" ")[-1]  # "good" or "bad"
                if label_clean != current_label or note_value != current_note:
                    with get_connection() as conn:
                        conn.execute(
                            text(UPSERT_ANNOTATION),
                            {
                                "id": str(uuid.uuid4()),
                                "user_id": selected_user_id,
                                "content_id": cid,
                                "feed_date": str(selected_date),
                                "label": label_clean,
                                "note": note_value or None,
                                "created_at": datetime.now(timezone.utc).isoformat(),
                            },
                        )
                        conn.commit()

            st.divider()
else:
    st.info("Pas de digest pour cet utilisateur a cette date.")

# --- Add missing article ---

st.markdown("---")
st.subheader("Ajouter un article manquant")

SEARCH_MISSING_QUERY = """
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
"""

with st.expander("Chercher des articles non recommandes"):
    if st.button("Charger les articles disponibles"):
        missing_candidates = run_query(
            SEARCH_MISSING_QUERY,
            {"user_id": selected_user_id, "feed_date": str(selected_date)},
        )
        if missing_candidates:
            for mc in missing_candidates:
                mcid = str(mc["content_id"])
                already = mcid in existing_annotations
                col_info, col_btn = st.columns([4, 1])
                with col_info:
                    st.markdown(f"[{mc['title']}]({mc['url']}) — {mc['source_name']}")
                with col_btn:
                    if already:
                        st.caption("Deja annote")
                    elif st.button("Ajouter", key=f"add_{mcid}"):
                        with get_connection() as conn:
                            conn.execute(
                                text(UPSERT_ANNOTATION),
                                {
                                    "id": str(uuid.uuid4()),
                                    "user_id": selected_user_id,
                                    "content_id": mcid,
                                    "feed_date": str(selected_date),
                                    "label": "missing",
                                    "note": None,
                                    "created_at": datetime.now(timezone.utc).isoformat(),
                                },
                            )
                            conn.commit()
                        st.rerun()
        else:
            st.info("Aucun article non-recommande trouve pour cette date.")
