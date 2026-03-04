"""Contexte metier injecte dans le prompt systeme de l'agent."""

BUSINESS_CONTEXT = """
## Facteur — Contexte Metier

Facteur est une app mobile de digest quotidien : 5 articles selectionnes par un algo,
conçus pour etre lus en 2-4 minutes ("moment de fermeture").

### Schema BDD (tables principales)

- **sources** : catalogues de sources RSS/YouTube/Podcast (name, url, feed_url, type, theme, is_active, last_synced_at)
- **contents** : articles/contenus (source_id, title, url, published_at, topics[], theme, is_paid, is_serene)
- **user_profiles** : profils utilisateurs (user_id UUID Supabase, display_name, onboarding_completed, weekly_goal)
- **user_sources** : abonnements user→source (user_id, source_id, added_at)
- **user_personalization** : filtres (muted_sources UUID[], muted_themes[], hide_paid_content)
- **user_content_status** : interactions (user_id, content_id, status='unseen'/'seen'/'consumed', is_saved, is_liked, time_spent_seconds, seen_at)
- **daily_digest** : digest quotidien (user_id, target_date, items JSONB [{content_id, rank, reason, source_slug}])
- **digest_completions** : fermeture du digest (user_id, target_date, completed_at, articles_read, articles_saved)
- **analytics_events** : evenements (user_id, event_type, event_data JSONB, created_at)
- **curation_annotations** : annotations qualite (user_id, content_id, feed_date, label='good'/'bad'/'missing', note)
- **user_interests** / **user_subtopics** / **user_topic_profiles** : topics suivis

### Seuils et Regles

**Sante source** :
- delta <= 2x avg_interval → OK (✅)
- delta <= 4x avg_interval → Retard (⚠️)
- delta > 4x avg_interval → KO (❌)
- Source sans article = KO

**Activite utilisateur** :
- Derniere activite < 24h → Actif (🟢)
- < 7 jours → Ralenti (🟡)
- > 7 jours → Inactif (🔴)
- Taux sain = > 3 articles/semaine

**Qualite feed** :
- diversity_score < 0.3 → alerte (une source domine)
- freshness > 48h → articles trop vieux
- top_source_pct > 50% → desequilibre
- < 5 articles servis/jour → feed insuffisant

**Config degradee** :
- < 3 sources actives (total - muted) → mauvaise experience
- Plus de muted que d'actives → signal de mecontentement

**Curation** :
- Precision = 👍 / (👍 + 👎) → qualite des recommandations
- Recall = 👍 / (👍 + ⭐) → couverture des bons articles
- Sources avec beaucoup de 👎 → baisser le poids
- Sources avec beaucoup de ⭐ → augmenter le poids

### Notes techniques

- user_id partout = UUID Supabase Auth (pas l'id PK de user_profiles)
- Pas de table feed_items : les articles servis sont dans daily_digest.items (JSONB)
- Pas de last_login_at : utiliser MAX(analytics_events.created_at) comme proxy
- Pas de session_time : utiliser SUM(user_content_status.time_spent_seconds) comme proxy
- status enum lowercase : 'unseen', 'seen', 'consumed'
"""
