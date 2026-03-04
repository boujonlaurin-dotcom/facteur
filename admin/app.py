"""Facteur Backoffice — Entry point Streamlit."""

import streamlit as st

st.set_page_config(
    page_title="Facteur Backoffice",
    page_icon="\U0001f4ee",
    layout="wide",
)

st.sidebar.title("\U0001f4ee Facteur Backoffice")
st.sidebar.markdown("---")
st.sidebar.info(
    "Dashboard de monitoring pour Facteur.\n\n"
    "**Pages** :\n"
    "1. Source Health\n"
    "2. Users Overview\n"
    "3. Feed Quality\n"
    "4. User Config\n"
    "5. Curation"
)

st.title("Bienvenue sur Facteur Backoffice")
st.markdown(
    "Utilisez la navigation dans la sidebar pour acceder aux dashboards.\n\n"
    "- **Source Health** : Sources cassees ou en retard\n"
    "- **Users Overview** : Activite des utilisateurs\n"
    "- **Feed Quality** : Qualite du feed par utilisateur\n"
    "- **User Config** : Configuration detaillee d'un utilisateur\n"
    "- **Curation** : Annotation interactive des recommandations"
)
