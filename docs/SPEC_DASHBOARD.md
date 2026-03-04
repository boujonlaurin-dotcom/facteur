## 🎯 Objectif

Backoffice **agent-first** pour Facteur : un dashboard Streamlit minimal pour le monitoring visuel quotidien + un agent IA conversationnel qui accède à la BDD pour toutes les analyses, investigations et recommandations.

### Principes directeurs

- **Dashboard = coup d'œil** : uniquement ce qui nécessite un scan visuel rapide (santé sources, curation interactive)
- **Agent = intelligence** : toute question analytique, investigation, diagnostic, comparaison → l'agent query la BDD et raisonne
- **Modèle de données extensible** : chaque domaine métier est un module indépendant avec ses queries templates, prêt à être élargi

---

## 🏗️ Architecture

```jsx
admin/
├── app.py                      # Streamlit entry point + sidebar nav
├── pages/
│   ├── 1_source_health.py      # Dashboard — santé des sources
│   ├── 2_users_overview.py     # Dashboard — activité utilisateurs
│   ├── 3_feed_quality.py       # Dashboard — qualité du feed par user
│   ├── 4_user_config.py        # Dashboard — config détaillée par user
│   └── 5_curation.py           # Interface d'annotation interactive
├── utils/
│   ├── db.py                   # Connexion BDD (réutilise ORM existant)
│   ├── config.py               # Seuils d'alerte, constantes
│   └── status.py               # Logique de calcul de statut source
│
agent/
├── tools/
│   ├── query_db.py             # Tool principal : exécution SQL read-only
│   └── write_annotation.py     # Tool : écrire une annotation de curation
├── queries/                    # Templates SQL par domaine
│   ├── sources.py              # Queries santé sources
│   ├── users.py                # Queries activité & config utilisateurs
│   ├── feed.py                 # Queries qualité algo & feed
│   └── curation.py             # Queries gap analysis
├── context.py                  # Contexte métier injecté dans le prompt
└── instructions.md             # Instructions de l'agent
```

### Accès & auth

- **Streamlit** : `streamlit run admin/app.py` — local, aucune auth
- **Agent** : accessible via chat (Notion, CLI, ou interface custom) — accès read-only à la BDD + write sur `curation_annotations`

---

## 📊 Streamlit — Dashboards (5 pages)

### Page 1 — Source Health Monitor

**But** : Répondre en <10 secondes à *"Est-ce qu'une source est cassée ou en retard ?"*

<aside>
📐

**Layout simplifié** — KPIs + tableau, pas de charts

</aside>

**Header** — 4 `st.metric` en ligne :

| Métrique | Calcul |
| --- | --- |
| **Sources OK** | `count(status = ✅)` / total |
| **Sources en alerte** | `count(status = ⚠️ or ❌)` |
| **Dernière sync globale** | `max(last_sync_at)` |
| **Articles ingérés (24h)** | `count(articles) WHERE created_at > now() - 24h` |

**Tableau** — `st.dataframe`, triable, ❌ en premier :

| Colonne | Notes |
| --- | --- |
| `source_name` | Nom + lien |
| `last_sync_at` | Dernière sync réussie |
| `last_article_at` | Dernier article récupéré |
| `articles_24h` | Articles dans les dernières 24h |
| `status` | ✅ OK / ⚠️ Retard / ❌ KO |
| `error_log` | Dernier message d'erreur |

**Logique de statut** :

```python
def compute_status(last_article_at, avg_publish_interval):
    delta = now() - last_article_at
    if delta <= avg_publish_interval * 2:
        return "✅"
    elif delta <= avg_publish_interval * 4:
        return "⚠️"
    else:
        return "❌"
```

**Interactions** : filtre par statut (`st.multiselect`) + recherche (`st.text_input`)

---

### Page 2 — Users Overview

**But** : Voir d'un coup d'œil qui est actif, qui décroche, et comment chacun utilise l'app.

<aside>
📐

**Layout** — KPIs globaux + tableau utilisateurs + chart d'activité

</aside>

**Header** — 4 `st.metric` en ligne :

| Métrique | Calcul |
| --- | --- |
| **Users actifs (7j)** | `count(last_login_at > now() - 7d)` |
| **Users inactifs (>7j)** | `count(last_login_at <= now() - 7d)` |
| **Articles lus / user / semaine** | `avg(articles_read_7d)` |
| **Articles sauvegardés (7j)** | `sum(articles_saved_7d)` |

**Tableau utilisateurs** — `st.dataframe`, triable :

| Colonne | Notes |
| --- | --- |
| `name` | Nom de l'utilisateur |
| `last_login_at` | Dernière connexion (badge 🟢 <24h, 🟡 <7j, 🔴 >7j) |
| `session_time_7d` | Temps passé dans l'app (minutes, 7 derniers jours) |
| `articles_read_7d` | Articles lus (total) |
| `read_feed` / `read_digest` | Split lecture feed vs digest |
| `articles_saved_7d` | Articles sauvegardés |
| `active_sources` | Nb sources actives |

**Chart** — `st.bar_chart` : articles lus par jour (7 derniers jours), empilé par user. Permet de repérer les jours creux et les users qui décrochent.

**Interactions** :

- **Filtre activité** : `st.multiselect("Statut", ["🟢 Actif", "🟡 Ralenti", "🔴 Inactif"])`
- **Clic sur un user** → détail dans Page 4 (User Config)

---

### Page 3 — Feed Quality

**But** : Identifier en un coup d'œil les users dont le feed est déséquilibré ou pauvre.

<aside>
📐

**Layout** — Tableau de diagnostic par user + alertes visuelles

</aside>

**Tableau** — `st.dataframe`, trié par score de diversité ascendant (pires en premier) :

| Colonne | Notes |
| --- | --- |
| `name` | Nom de l'utilisateur |
| `articles_served_24h` | Nb articles dans le feed (⚠️ si < 5) |
| `diversity_score` | Sources distinctes / sources actives (⚠️ si < 0.3) |
| `freshness_hours` | Âge moyen des articles servis (⚠️ si > 48h) |
| `top_source_pct` | % de la source dominante (⚠️ si > 50%) |
| `top_source_name` | Nom de la source dominante |

**Alertes** — `st.warning` automatique en haut de page si :

- ≥1 user avec diversity < 0.3
- ≥1 user avec 0 articles servis en 24h
- ≥1 user avec freshness > 48h

**Chart** — `st.altair_chart` scatter plot : axe X = diversity_score, axe Y = freshness_hours, taille = articles servis. Les users "problématiques" sont visuellement isolés en bas à droite.

---

### Page 4 — User Config

**But** : Inspecter la configuration d'un utilisateur donné (sources, topics, préférences).

<aside>
📐

**Layout** — Sélecteur user + 3 sections : profil, sources, topics

</aside>

**Sélecteur** : `st.selectbox("Utilisateur", users)`

**Section 1 — Profil & préférences** (4 `st.metric` en ligne) :

| Métrique | Source |
| --- | --- |
| **Sources actives / masquées** | `user_sources` |
| **Topics suivis** | `user_topics` |
| **Digest** | Activé/désactivé + fréquence |
| **Articles payants** | Masqués ou non |

**Section 2 — Sources** — `st.dataframe` :

| Colonne | Notes |
| --- | --- |
| `source_name` | Nom de la source |
| `status` | Active / Masquée |
| `articles_read` | Nb articles lus depuis cette source |
| `added_at` | Date d'ajout |

Tri par défaut : articles lus (desc). Permet de voir quelles sources le user consomme vraiment vs. celles qu'il a ajoutées mais ignore.

**Section 3 — Topics** — `st.dataframe` :

| Colonne | Notes |
| --- | --- |
| `topic_name` | Nom du thème |
| `priority` | Priorité attribuée |
| `added_at` | Date d'ajout |

---

### Page 5 — Curation Workbench

**But** : Annoter les articles recommandés par l'algo pour mesurer le gap avec la curation idéale.

<aside>
📐

**Layout** — Sélecteur + liste interactive + compteurs

</aside>

**Sélecteur** :

- `st.selectbox("Utilisateur", users)`
- `st.date_input("Date", default=today)`
- KPI inline : *"X articles servis — Y annotés — Z manquants ajoutés"*

**Liste d'articles** — pour chaque article du feed du jour :

| Champ | Source |
| --- | --- |
| **Titre** | Lien cliquable vers l'article |
| **Source** | `source.name` |
| **Score algo** | Badge coloré |
| **Annotation** | 👍 / 👎 / ⭐ (radio buttons) |
| **Note** | `st.text_input` optionnel |

**Système d'annotation** :

| Label | Signification | Valeur stockée |
| --- | --- | --- |
| 👍 | Bon choix de l'algo | `good` |
| 👎 | Mauvais choix | `bad` |
| ⭐ | Article manquant (ajouté manuellement) | `missing` |

**Ajout d'articles manquants** : recherche parmi les articles ingérés non recommandés (mêmes sources actives du user, même date)

**Table de stockage** :

```sql
CREATE TABLE curation_annotations (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    article_id INTEGER REFERENCES articles(id),
    feed_date DATE NOT NULL,
    label VARCHAR(10) CHECK (label IN ('good', 'bad', 'missing')),
    note TEXT,
    annotated_by VARCHAR(50) DEFAULT 'admin',
    created_at TIMESTAMP DEFAULT NOW()
);
CREATE UNIQUE INDEX idx_curation_unique 
    ON curation_annotations(user_id, article_id, feed_date);
```

---

## 🤖 Agent — Modules de queries

L'agent accède à la BDD via un tool `query_db(sql, params)` read-only. Chaque **module** regroupe un domaine métier avec ses queries templates et son contexte. L'agent choisit, adapte et compose les queries selon la question posée.

### Module 1 — Santé des sources

**Questions types** :

- *"Y a-t-il des sources en panne ?"*
- *"Depuis quand Le Monde n'a pas publié ?"*
- *"Quelles sources ont eu des erreurs cette semaine ?"*

**Queries templates** :

```sql
-- source_health_summary : état global de toutes les sources
SELECT 
    s.name, s.url, s.last_sync_at,
    MAX(a.published_at) AS last_article_at,
    COUNT(*) FILTER (WHERE a.created_at > NOW() - INTERVAL '24 hours') AS articles_24h,
    s.last_error
FROM sources s
LEFT JOIN articles a ON a.source_id = s.id
GROUP BY s.id
ORDER BY last_article_at ASC NULLS FIRST;

-- source_publish_frequency : fréquence de parution par source
SELECT source_id, 
    AVG(published_at - LAG(published_at) 
        OVER (PARTITION BY source_id ORDER BY published_at)) AS avg_interval
FROM articles
WHERE published_at > NOW() - INTERVAL '30 days'
GROUP BY source_id;

-- source_errors_recent : erreurs des 7 derniers jours
SELECT s.name, s.last_error, s.last_sync_at, s.error_count_7d
FROM sources s
WHERE s.last_error IS NOT NULL
    AND s.last_sync_at > NOW() - INTERVAL '7 days';
```

**Contexte métier** :

- Statut : delta ≤ 2× avg_interval → OK, ≤ 4× → Retard, > 4× → KO
- Une source sans article depuis > 4× son intervalle habituel est considérée cassée
- Prioriser les sources avec le plus d'abonnés en cas de multiple alertes

---

### Module 2 — Activité utilisateurs

**Questions types** :

- *"Quels utilisateurs sont inactifs depuis plus de 7 jours ?"*
- *"Quel est le taux de lecture moyen de mes utilisateurs ?"*
- *"Paul est-il actif ? Combien d'articles lit-il par semaine ?"*

**Queries templates** :

```sql
-- user_activity_summary : vue d'ensemble de l'activité
SELECT
    u.id, u.name, u.email,
    u.last_login_at,
    u.total_session_time_minutes_7d,
    COUNT(DISTINCT r.article_id) FILTER (WHERE r.read_at > NOW() - INTERVAL '7 days') 
        AS articles_read_7d,
    COUNT(DISTINCT r.article_id) FILTER (WHERE r.source = 'feed') AS read_from_feed,
    COUNT(DISTINCT r.article_id) FILTER (WHERE r.source = 'digest') AS read_from_digest,
    COUNT(DISTINCT sv.article_id) FILTER (WHERE sv.saved_at > NOW() - INTERVAL '7 days') 
        AS articles_saved_7d
FROM users u
LEFT JOIN article_reads r ON r.user_id = u.id
LEFT JOIN article_saves sv ON sv.user_id = u.id
GROUP BY u.id
ORDER BY u.last_login_at DESC;

-- user_engagement_detail : détail pour un user spécifique
SELECT
    DATE(r.read_at) AS day,
    COUNT(DISTINCT r.article_id) AS articles_read,
    COUNT(DISTINCT r.article_id) FILTER (WHERE r.source = 'feed') AS from_feed,
    COUNT(DISTINCT r.article_id) FILTER (WHERE r.source = 'digest') AS from_digest,
    COUNT(DISTINCT sv.article_id) AS articles_saved
FROM article_reads r
LEFT JOIN article_saves sv ON sv.user_id = r.user_id 
    AND sv.article_id = r.article_id
WHERE r.user_id = :user_id
    AND r.read_at > NOW() - INTERVAL '30 days'
GROUP BY DATE(r.read_at)
ORDER BY day DESC;

-- inactive_users : utilisateurs inactifs
SELECT u.id, u.name, u.last_login_at,
    NOW() - u.last_login_at AS inactive_since
FROM users u
WHERE u.last_login_at < NOW() - INTERVAL '7 days'
ORDER BY u.last_login_at ASC;
```

**Contexte métier** :

- Inactif = pas de connexion depuis > 7 jours
- Taux de lecture sain = > 3 articles/semaine
- Distinguer lecture feed (engagement actif) vs digest (engagement passif)
- Un user qui sauvegarde régulièrement est un signal de satisfaction forte

---

### Module 3 — Configuration utilisateurs

**Questions types** :

- *"Quels topics suit Marie ?"*
- *"Combien de sources Paul a-t-il masquées ?"*
- *"Quels utilisateurs ont désactivé les articles payants ?"*
- *"Y a-t-il des utilisateurs avec trop peu de sources actives ?"*

**Queries templates** :

```sql
-- user_config_overview : configuration complète d'un user
SELECT
    u.id, u.name,
    COUNT(DISTINCT us.source_id) FILTER (WHERE us.is_active) AS active_sources,
    COUNT(DISTINCT us.source_id) FILTER (WHERE NOT us.is_active) AS masked_sources,
    COUNT(DISTINCT ut.topic_id) AS followed_topics,
    u.digest_enabled, u.digest_frequency,
    u.hide_paywalled_articles
FROM users u
LEFT JOIN user_sources us ON us.user_id = u.id
LEFT JOIN user_topics ut ON ut.user_id = u.id
GROUP BY u.id;

-- user_top_sources : sources les plus suivies par user
SELECT s.name, us.is_active, us.added_at,
    COUNT(r.id) AS articles_read_from_source
FROM user_sources us
JOIN sources s ON s.id = us.source_id
LEFT JOIN articles a ON a.source_id = s.id
LEFT JOIN article_reads r ON r.article_id = a.id AND r.user_id = us.user_id
WHERE us.user_id = :user_id
GROUP BY s.id, us.is_active, us.added_at
ORDER BY articles_read_from_source DESC;

-- user_topics : thèmes suivis par user
SELECT t.name AS topic, ut.priority, ut.added_at
FROM user_topics ut
JOIN topics t ON t.id = ut.topic_id
WHERE ut.user_id = :user_id
ORDER BY ut.priority DESC;

-- users_with_degraded_config : users à risque
SELECT u.id, u.name,
    COUNT(DISTINCT us.source_id) FILTER (WHERE us.is_active) AS active_sources,
    COUNT(DISTINCT us.source_id) FILTER (WHERE NOT us.is_active) AS masked_sources
FROM users u
LEFT JOIN user_sources us ON us.user_id = u.id
GROUP BY u.id
HAVING COUNT(DISTINCT us.source_id) FILTER (WHERE us.is_active) < 3;
```

**Contexte métier** :

- < 3 sources actives = config dégradée, expérience pauvre
- Sources masquées > sources actives = signal d'insatisfaction à investiguer
- `hide_paywalled_articles = true` peut expliquer un feed pauvre si beaucoup de sources sont payantes
- Digest : vérifier si la fréquence correspond au rythme de lecture du user

---

### Module 4 — Qualité du feed & algo

**Questions types** :

- *"Le feed de Marie est-il diversifié ?"*
- *"Quel est l'âge moyen des articles servis à Paul ?"*
- *"Quels utilisateurs ont un feed dominé par une seule source ?"*

**Queries templates** :

```sql
-- feed_quality_diagnostic : diagnostic complet pour un user
SELECT
    COUNT(DISTINCT f.article_id) AS articles_served_24h,
    COUNT(DISTINCT a.source_id)::float / NULLIF(
        (SELECT COUNT(*) FROM user_sources WHERE user_id = :user_id AND is_active), 0
    ) AS diversity_score,
    AVG(EXTRACT(EPOCH FROM (NOW() - a.published_at)) / 3600) AS avg_freshness_hours,
    MAX(a.published_at) AS newest_article,
    MIN(a.published_at) AS oldest_article
FROM feed_items f
JOIN articles a ON a.id = f.article_id
WHERE f.user_id = :user_id
    AND f.served_at > NOW() - INTERVAL '24 hours';

-- feed_source_distribution : répartition par source
SELECT 
    s.name, COUNT(*) AS articles_served,
    ROUND(COUNT(*)::numeric / SUM(COUNT(*)) OVER () * 100, 1) AS pct_of_feed,
    AVG(f.algo_score) AS avg_score
FROM feed_items f
JOIN articles a ON a.id = f.article_id
JOIN sources s ON s.id = a.source_id
WHERE f.user_id = :user_id
    AND f.served_at > NOW() - INTERVAL '24 hours'
GROUP BY s.id
ORDER BY articles_served DESC;

-- users_with_poor_diversity : tous les users avec feed déséquilibré
SELECT u.id, u.name,
    MAX(pct) AS max_source_pct
FROM users u
JOIN LATERAL (
    SELECT s.name,
        COUNT(*)::numeric / SUM(COUNT(*)) OVER () * 100 AS pct
    FROM feed_items f
    JOIN articles a ON a.id = f.article_id
    JOIN sources s ON s.id = a.source_id
    WHERE f.user_id = u.id
        AND f.served_at > NOW() - INTERVAL '24 hours'
    GROUP BY s.id
) sub ON true
GROUP BY u.id
HAVING MAX(pct) > 50;
```

**Contexte métier** :

- Diversity score < 0.3 = problème (une source domine le feed)
- Freshness > 48h = articles trop vieux, probable problème de source ou d'algo
- Si une source représente > 50% du feed → alerte, investiguer si c'est un choix utilisateur ou un biais algo

---

### Module 5 — Curation & gap analysis

**Questions types** :

- *"Quelle est la précision de l'algo pour Paul cette semaine ?"*
- *"Quelles sources génèrent le plus de 👎 ?"*
- *"L'algo s'améliore-t-il avec le temps ?"*

**Queries templates** :

```sql
-- curation_precision_recall : métriques principales
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
    AND feed_date >= :start_date;

-- curation_by_source : performance par source
SELECT s.name,
    COUNT(*) FILTER (WHERE ca.label = 'good') AS good,
    COUNT(*) FILTER (WHERE ca.label = 'bad') AS bad,
    COUNT(*) FILTER (WHERE ca.label = 'missing') AS missing
FROM curation_annotations ca
JOIN articles a ON a.id = ca.article_id
JOIN sources s ON s.id = a.source_id
WHERE ca.feed_date >= :start_date
GROUP BY s.id
ORDER BY bad DESC;

-- curation_trend : évolution dans le temps
SELECT feed_date,
    ROUND(
        COUNT(*) FILTER (WHERE label = 'good')::numeric /
        NULLIF(COUNT(*) FILTER (WHERE label IN ('good', 'bad')), 0) * 100, 1
    ) AS daily_precision
FROM curation_annotations
WHERE user_id = :user_id
GROUP BY feed_date
ORDER BY feed_date;
```

**Contexte métier** :

- Précision = `👍 / (👍 + 👎)` — qualité des recommandations
- Rappel = `👍 / (👍 + ⭐)` — couverture des bons articles
- Sources avec beaucoup de 👎 → candidats pour un ajustement de poids
- Sources avec beaucoup de ⭐ → sous-représentées, augmenter leur poids

---

## 🧠 Instructions de l'agent

L'agent reçoit dans son prompt système :

1. **Rôle** : *"Tu es l'analyste backoffice de Facteur. Tu aides à diagnostiquer les problèmes de sources, évaluer la qualité des feeds, comprendre l'activité des utilisateurs, et améliorer l'algorithme de recommandation."*
2. **Accès** : tool `query_db(sql, params)` read-only sur la BDD Facteur
3. **Modules** : les 5 modules ci-dessus avec leurs queries templates et contexte métier
4. **Format de réponse** :
    - Toujours commencer par un **résumé en 1-2 phrases** (verdict clair)
    - Puis les **données** (tableau ou liste)
    - Puis les **recommandations** si pertinent
    - Utiliser des emojis pour les statuts : ✅ ⚠️ ❌

---

## 🔮 Extensibilité

Le modèle modulaire permet d'ajouter facilement :

- **Module 6 — Monétisation** : conversion, churn, revenus par cohorte
- **Module 7 — Contenu** : qualité des articles, longueur, tags manquants, doublons
- **Module 8 — Performance technique** : temps de réponse API, erreurs, latence
- **Module 9 — A/B testing** : comparaison de variantes d'algo par cohorte

Chaque nouveau module = 1 fichier de queries + contexte métier dans les instructions de l'agent. Pas de nouvelle UI à construire.

---