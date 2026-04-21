# Rapport d'usage & valeur — Facteur — 2026-04-20 (R01)

> **Premier rapport d'usage.** Objectif : démontrer où en est l'app en termes d'usage / création d'habitudes, identifier blocages et features "utiles vs superflues", et poser les fondations pour un monitoring exploitable sur la durée.

---

## 0. Avertissement méthodologique

Ce rapport R01 est **un audit d'instrumentation + framework KPI**, pas un rapport chiffré. Raisons :

1. La session de rédaction n'a pas d'accès DB/PostHog live (Supabase MCP absent, pas de `DATABASE_URL` injectée côté harness).
2. Avant de publier des chiffres, il faut valider **ce qui est mesurable** : sans ce cadrage, on risque d'exhiber des métriques trompeuses (ex. "taux de clôture = 72%" calculé sur un dénominateur buggé).

Le livrable est donc :
- Section 1 — **ce qu'on sait mesurer aujourd'hui** (instrumentation existante).
- Section 2 — **framework KPI** avec requêtes SQL/PostHog prêtes à exécuter (Laurin ou un agent avec accès DB complète les chiffres au prochain passage).
- Section 3 — **angles morts** (features en production non instrumentées → on ne peut RIEN dire de leur valeur).
- Section 4 — **hypothèses features qui marchent / superflues**, fondées sur la cartographie instrumentation × surface produit.
- Section 5 — **roadmap monitoring R02 → R04**.

Le rapport R02 (prochain) sera chiffré dès que Laurin lance les SQL de la Section 2 et colle les résultats.

---

## 1. Carte de l'instrumentation existante

### 1.1 Canaux de collecte

| Canal | Stockage | Couverture | Fraîcheur |
|---|---|---|---|
| `analytics_events` (DB Supabase) | Table Postgres JSONB | Events custom, digest-centrés | Temps réel |
| PostHog EU | Cloud PostHog | Retention, cohortes, funnels, user properties | Temps réel |
| `user_content_status` | Table Postgres | État consommé/sauvegardé/temps lu par article | Temps réel |
| `digest_completions` | Table Postgres | Fin de digest (read/saved/dismissed, closure_time) | Temps réel |
| `user_streaks` | Table Postgres | Streaks (lecture quotidienne + clôture digest) | Temps réel |
| Streamlit admin (`admin/app.py`) | Front sur DB | 5 pages opérateur (sources, users, feed, config, curation) | Temps réel |
| Sentry | Cloud | Erreurs prod (qualité, pas usage) | Temps réel |

### 1.2 Events captés (cross-check `analytics_events` + PostHog)

| Event | Source | KPI alimenté | Fiabilité |
|---|---|---|---|
| `session_start` / `app_open` | Mobile | DAU, MAU, sessions/user | ★★★★ (mirror PostHog OK) |
| `session_end` | Mobile | Durée session | ★★★ (dépend fermeture propre) |
| `content_interaction` (read/save/skip/swipe) | Mobile | Taux d'interaction, temps lecture | ★★★★ |
| `digest_session` | Mobile | Taux de clôture digest, articles lus/digest | ★★★★ |
| `feed_session` | Mobile | Scroll depth, engagement feed | ★★★ |
| `comparison_viewed` | Mobile | Usage "Mise en perspective" | ★★ (feature récente) |
| `article_completed` (≥30s) | Mobile | Lecture profonde | ★★★ |
| `signup_completed` | Backend | Cohortes rétention | ★★★★ |
| `source_added` | Mobile | Personnalisation | ★★★ |
| `digest_generated` | Backend (job) | Ops/capacity | ★★★★ |
| `waitlist_signup` | Backend public | Qualité canal acquisition | ★★★★ |

### 1.3 Events manquants (instrumentation à ajouter — cf. §5)

- ❌ `app_first_launch` dédié (on utilise `MIN(session_start)` en fallback → biais si user réinstalle)
- ❌ `onboarding_step_viewed` / `onboarding_step_completed` (pas de funnel onboarding granulaire)
- ❌ `onboarding_dropoff` (où sortent les users pendant les 10-12 questions ?)
- ❌ `paywall_viewed` / `paywall_dismissed` / `subscription_started` (Epic 6 draft → critique pour monétisation)
- ❌ `notification_received` / `notification_opened` (pas de mesure d'efficacité push)
- ❌ `bookmark_revisited` (saves-t-on utiles ? ou cimetière d'articles ?)
- ❌ `share_article` (pas de feature de partage instrumentée)
- ❌ `search_performed` (si search existe un jour)

---

## 2. Framework KPI — requêtes à exécuter pour R02

> **À faire par Laurin (ou agent avec DB access) :** exécuter ces requêtes sur la DB prod Supabase (SQL Editor) et PostHog, puis coller les résultats dans `docs/analytics/usage-report-2026-04-20-data.md`. Le R02 sera alors complété automatiquement.

### Tier 1 — Survie

**T1.1 — DAU / WAU / MAU** (PostHog Trends, `app_open`, intervalle Day/Week/Month, 30 derniers jours)
- **Attendu minimum avant de parler d'app "vivante"** : WAU > 30, ratio DAU/WAU > 0.2 (stickiness).

**T1.2 — Rétention D1/D7/D30** (PostHog Retention, event `app_open`, cohorte `signup_completed`)
- **Seuils healthy app news/digest** : D1 ≥ 30 %, D7 ≥ 15 %, D30 ≥ 10 % (source : PostHog setup Story 14.1).
- **Seuils d'alerte rouge** : D7 < 10 % = pas d'habitude formée, repenser le 8h wake-up ou le digest.

**T1.3 — Installations → inscription → 1er digest complété** (PostHog Funnel)
```
waitlist_signup OR first app_open → signup_completed → article_read → digest_session{closure_achieved=true}
```
- Mesure la **TTV (time-to-value)** du produit.

### Tier 2 — Engagement / habitude

Requêtes SQL à lancer dans Supabase SQL Editor (déjà présentes dans `scripts/analytics_dashboard.sql`, légèrement enrichies) :

**T2.1 — Taux de clôture du digest sur 30 jours** (la métrique nord Facteur)
```sql
SELECT
  DATE(created_at) AS day,
  COUNT(*) FILTER (WHERE (event_data->>'closure_achieved')::bool) AS closures,
  COUNT(*) AS digest_sessions,
  ROUND(100.0 * COUNT(*) FILTER (WHERE (event_data->>'closure_achieved')::bool) / NULLIF(COUNT(*), 0), 1) AS closure_rate_pct,
  ROUND(AVG((event_data->>'articles_read')::int), 2) AS avg_articles_read,
  ROUND(AVG((event_data->>'total_time')::int) / 60.0, 1) AS avg_minutes
FROM analytics_events
WHERE event_type = 'digest_session'
  AND created_at > NOW() - INTERVAL '30 days'
GROUP BY 1 ORDER BY 1 DESC;
```

**T2.2 — Streaks : combien d'users ont formé une habitude ?**
```sql
SELECT
  COUNT(*) FILTER (WHERE current_streak >= 1) AS streak_1_plus,
  COUNT(*) FILTER (WHERE current_streak >= 3) AS streak_3_plus,
  COUNT(*) FILTER (WHERE current_streak >= 7) AS streak_7_plus,
  COUNT(*) FILTER (WHERE current_streak >= 14) AS streak_14_plus,
  COUNT(*) FILTER (WHERE longest_streak >= 7) AS has_hit_1_week_ever,
  MAX(longest_streak) AS max_ever,
  ROUND(AVG(current_streak), 2) AS avg_current
FROM user_streaks;
```
> **Lecture** : `streak_7_plus / total_users` = % d'users pour qui Facteur est un rituel hebdo. Si < 10 %, l'habitude ne prend pas ; si > 20 %, PMF partiel.

**T2.3 — Temps passé / articles lus par user actif (7j)**
```sql
SELECT
  COUNT(DISTINCT user_id) AS active_users_7d,
  SUM(time_spent_seconds) / 60.0 AS total_minutes,
  ROUND(SUM(time_spent_seconds) / 60.0 / NULLIF(COUNT(DISTINCT user_id), 0), 1) AS avg_min_per_user,
  COUNT(*) FILTER (WHERE status = 'consumed') AS articles_consumed,
  ROUND(COUNT(*) FILTER (WHERE status = 'consumed') * 1.0 / NULLIF(COUNT(DISTINCT user_id), 0), 1) AS articles_per_user
FROM user_content_status
WHERE updated_at > NOW() - INTERVAL '7 days';
```

**T2.4 — Bookmarks : signal d'intérêt ou cimetière ?**
```sql
SELECT
  COUNT(*) FILTER (WHERE is_saved) AS total_saved,
  COUNT(DISTINCT user_id) FILTER (WHERE is_saved) AS users_with_saves,
  COUNT(*) FILTER (WHERE is_saved AND status = 'consumed') AS saved_and_read,
  ROUND(100.0 * COUNT(*) FILTER (WHERE is_saved AND status = 'consumed')
        / NULLIF(COUNT(*) FILTER (WHERE is_saved), 0), 1) AS pct_saved_eventually_read
FROM user_content_status;
```
> **Lecture** : si `pct_saved_eventually_read` < 15 %, les bookmarks sont un cimetière → reconsidérer la feature ou ajouter un rappel.

### Tier 3 — Valeur par feature (hypothèses marchent / superflues)

**T3.1 — Usage "Mise en perspective" (Ground News-like)**
```sql
SELECT
  COUNT(*) AS comparison_views_30d,
  COUNT(DISTINCT user_id) AS unique_users,
  ROUND(100.0 * COUNT(DISTINCT user_id) /
    NULLIF((SELECT COUNT(DISTINCT user_id) FROM analytics_events
            WHERE event_type = 'session_start' AND created_at > NOW() - INTERVAL '30 days'), 0), 1)
    AS adoption_pct_of_active_users
FROM analytics_events
WHERE event_type = 'comparison_viewed' AND created_at > NOW() - INTERVAL '30 days';
```
> **Lecture** : < 5 % d'adoption = feature potentiellement superflue pour le MVP. > 15 % = signal fort → investir Epic 7.

**T3.2 — Top/flop sources** (déjà dans `scripts/analytics_dashboard.sql` §5 — net_growth adds − removes).

**T3.3 — Gamification tire-t-elle l'engagement ?**
```sql
-- Compare comportement users gamification ON vs OFF
SELECT
  p.gamification_enabled,
  COUNT(DISTINCT p.user_id) AS n_users,
  AVG(s.current_streak) AS avg_current_streak,
  AVG(s.longest_streak) AS avg_longest_streak
FROM user_profiles p
LEFT JOIN user_streaks s USING (user_id)
GROUP BY 1;
```
> **Lecture** : si gamif ON ≈ gamif OFF sur streaks, la gamif est du bruit visuel → simplifier.

---

## 3. Angles morts — features en prod non instrumentées

Ces features tournent depuis N semaines mais on n'a **aucune donnée d'usage** → impossible de statuer sur leur valeur réelle.

| Feature | Instrumentation actuelle | Conséquence |
|---|---|---|
| **Onboarding 10-12 questions** | Complétion globale (`signup_completed`) seulement | On ignore les drop-offs par question → peut-être 60 % abandonnent à Q8 ? |
| **Notifications push 8h** | Zéro event `notification_opened` | On ne sait pas si la notif tire l'usage ou si les users reviendraient sans |
| **Bookmarks "À consulter plus tard"** | On voit les saves (T2.4), pas les retours | Cimetière probable (cf. stats usuelles : 85 % des read-later ne sont jamais ouverts) |
| **Collections custom** | Pas d'event `collection_created` / `collection_viewed` | Feature visible dans le code (Epic TBD) mais invisible analytics |
| **Mute source/topic** | Pas d'event dédié (mute silencieux) | On ignore si les users configurent activement leur feed |
| **Paywall detection** | Pas d'event `paywall_clicked` | On ignore si le marqueur aide ou agace |
| **Paywall premium / trial** | Pas d'instrumentation Epic 6 | Monétisation opaque |
| **Partage article** | Feature absente ou non trackée | Aucun signal viral |

---

## 4. Hypothèses — features qui marchent vs superflues

**Hypothèses à confirmer/infirmer par les chiffres de §2.** Ordre par risque-strat décroissant.

### 4.1 Features probablement qui marchent (à double-checker)

1. **Digest quotidien "5 articles + closure"** — c'est la promesse produit, et toute l'instrumentation converge (`digest_session`, `closure_achieved`, streaks). **Si closure_rate > 40 % et streak_7_plus > 15 % → PMF partiel confirmé.**
2. **Onboarding ludique** — 100 % stories complétées, et tous les users qui arrivent au feed ont accepté les 10-12 questions. Mais **le taux d'abandon est invisible** (cf. §3).
3. **Streaks** — présence d'une table dédiée + longest_streak suggère que des users ont déjà une habitude. À confirmer T2.2.

### 4.2 Features à défendre avec des chiffres — sinon tailler

1. **Mise en perspective (Ground News-like)** — Epic 7 à 40 %, feature coûteuse (clustering multi-sources). Si T3.1 < 5 % d'adoption → deprioriser jusqu'à signal.
2. **Gamification (points, level, weekly goals)** — si T3.3 ne montre pas de différentiel ON/OFF, c'est de la surface produit pour rien.
3. **Bookmarks / Collections** — si T2.4 < 15 % de retour et pas de `collection_viewed` → soit supprimer, soit ajouter un rappel "3 articles attendent dans vos favoris".
4. **Feed infini personnalisé** — paradoxe : l'app vend du "slow media" (digest borné) mais propose un feed infini. Si temps feed >> temps digest, la vraie valeur livrée est l'inverse de la promesse → repositionnement ou taille.

### 4.3 Features probablement superflues à court terme

1. **Custom topics / collections** — peu documentés, peu instrumentés → sandbox avancée pour power users qu'on n'a pas encore.
2. **Settings granulaires paywall / formats** — utile seulement si > 30 % des users les touchent.
3. **Badges d'inactivité** (détectés dans admin page 2) — feature admin, zéro valeur user.

---

## 5. Roadmap monitoring — R02 à R04

### R02 (sous 7 jours) — chiffrer

- [ ] Exécuter les 8 requêtes de §2 (Supabase SQL Editor + PostHog) → remplir `usage-report-2026-04-20-data.md`.
- [ ] Lancer Streamlit admin `admin/app.py` en local, screenshot des 2 pages "Users Overview" et "Feed Quality" pour narration.
- [ ] Publier R02 avec verdict Go/No-Go sur les 4 hypothèses §4.

### R03 (sous 3 semaines) — combler les angles morts critiques

- [ ] **Funnel onboarding granulaire** : ajouter `onboarding_step_viewed` / `onboarding_step_completed` avec `step_index` — 2h dev mobile.
- [ ] **Notifications push** : hook `onNotificationOpened` Firebase → event `notification_opened{digest_date}` — mesure l'uplift DAU les jours de push.
- [ ] **Bookmark revisit** : event `bookmark_opened` quand user ouvre un article depuis la liste saved — qualifie le cimetière.
- [ ] **Paywall** (si Epic 6 avance) : `paywall_viewed`, `paywall_dismissed`, `trial_started`, `subscription_activated`.

### R04 (sous 6 semaines) — industrialiser

- [ ] **Dashboard PostHog publié** : les 9 insights listés dans `posthog-dashboard-setup.md` effectivement créés et partagés (statut actuel : documentés mais non vérifiés).
- [ ] **Alerte Slack/email "chute DAU > 30 % D-1"** active (prévue dans la doc PostHog mais probablement pas encore câblée).
- [ ] **Rapport auto hebdo** : cron `GET /admin/usage-digest` qui poste un résumé dans un Slack `#facteur-metrics` — rend le monitoring automatique.
- [ ] **Single source of truth** : consolider `analytics_events` (custom) et PostHog dans une seule vue (BigQuery ou DuckDB + dbt). Le doublon actuel crée du travail de réconciliation.

### Corrections de fond recommandées

1. **Renommer / uniformiser les event types** : on voit `content_interaction{action=read}` côté mobile mais `article_read` côté PostHog. Une seule convention (snake_case, par event atomique) évite les bugs de requêtes.
2. **`device_id` vs `user_id`** : aujourd'hui `event_data.device_id` est dans le JSONB → indexer sur colonne dédiée pour pouvoir faire du "anonymous → signed-up" linking propre.
3. **Ajouter `app_first_launch` explicite** (côté Flutter, au premier lancement d'une install) pour éviter le fallback `MIN(session_start)` qui casse en cas de réinstall.
4. **Ajouter `schema_version` dans `event_data`** → si on change la structure d'un payload, on peut versionner sans casser les requêtes historiques.
5. **Ops digest** : instrumenter `digest_generated{stats.failed}` (déjà dans la doc PostHog, à vérifier en code) et poser l'alerte seuil `failed > 10`.

---

## 6. TL;DR pour Laurin

- **On ne peut pas encore répondre à "est-ce que Facteur crée des habitudes ?"** — mais on sait exactement quelles 3 requêtes lancer pour trancher (T1.2 Retention D7, T2.1 closure_rate 30j, T2.2 streak_7_plus).
- **L'instrumentation digest est solide** (4 events fiables). **L'instrumentation onboarding, notifications et monétisation est quasi-inexistante** → angles morts stratégiques.
- **4 features à mettre sous observation** : Mise en perspective, Gamification, Bookmarks/Collections, Feed infini. Chacune a une requête dédiée §2-3 pour décider maintien / suppression.
- **Prochaine action** : Laurin lance les SQL §2 dans Supabase SQL Editor (5 min) → je rédige R02 avec les vrais chiffres + verdicts.
