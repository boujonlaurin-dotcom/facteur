# PostHog — Setup dashboards & alertes (Story 14.1)

> Guide reproductible pour configurer le projet PostHog EU. Tout est manuel côté UI PostHog, on versionne ici la recette.

## 1. Projet & clés

- **Projet** : `Facteur Prod` (région EU).
- **Clés à injecter** :
  - Backend (Railway) : `POSTHOG_API_KEY`, `POSTHOG_HOST=https://eu.i.posthog.com`, `POSTHOG_ENABLED=true`.
  - Mobile (CI + dart-define) : `POSTHOG_API_KEY`, `POSTHOG_HOST=https://eu.i.posthog.com`.

## 2. Events à vérifier

Après un build avec les clés en place, vérifier dans PostHog → *Activity* que ces events arrivent :

| Event | Source | Usage dashboard |
|-------|--------|------------------|
| `app_open` | Mobile (`session_start` mirror) | DAU, Retention D1/D7/D30 |
| `article_read` | Mobile (`content_interaction action=read`) | Funnel activation |
| `article_completed` | Mobile (≥ 30 s de lecture) | Taux de complétion |
| `digest_session` | Mobile (fin du digest) | Closure rate |
| `comparison_viewed` | Mobile (Ground News screen) | Signal H2 |
| `source_added` | Mobile (`trackSourceAdd`) | Personnalisation |
| `signup_completed` | Backend (onboarding save) | Cohort anchor pour rétention |
| `waitlist_signup` | Backend (public `/api/waitlist`) | Qualité du canal |
| `digest_generated` | Backend (job quotidien) | Ops / capacity |

## 3. User properties

Positionnées via `identify()` :

- `acquisition_source` : `waitlist` | `invite` | `creator` | `organic` (via `PATCH /api/admin/users/{id}/cohorts`).
- `is_creator_ytbeur` : bool, dérivé de `POSTHOG_CREATOR_EMAILS`.
- `is_close_to_laurin` : bool, dérivé de `POSTHOG_CLOSE_CIRCLE_EMAILS`.

## 4. Insights à créer

### Tier 1 — La survie

1. **DAU**
   - Type : *Trends* → *Unique users*
   - Event : `app_open`
   - Interval : *Day*
   - Filter : last 30 days

2. **Rétention D1 / D7 / D30**
   - Type : *Retention*
   - Target event : `app_open`
   - Cohortize by : `signup_completed` (*First time user performed event*)
   - Period : *Day*, intervals 1 / 7 / 30
   - Viser : D1 > 30 %, D7 > 15 %, D30 > 10 %.

### Tier 2 — L'engagement

3. **Sessions / user / jour**
   - Type : *Trends* → *Total count* of `app_open`
   - Math : *Average by user*
   - Interval : *Day*

4. **Taux de complétion du flux**
   - Type : *Funnels*
   - Steps : `app_open` → `article_read` → `digest_session (closure_achieved=true)`
   - Conversion window : 1 day

5. **Temps moyen par session**
   - *Trends* → `session_end.duration_seconds` average.

6. **Sources ajoutées**
   - *Trends* → total `source_added` / DAU.

### Tier 3 — Cohortes spéciales

Créer 3 cohortes dans *People → Cohorts* :

- **YTbeurs** : `is_creator_ytbeur = true`
- **Proches de Laurin** : `is_close_to_laurin = true`
- **Waitlist vs Invite** : filter sur `acquisition_source`

Dupliquer les insights Tier 1/2 en breakdown par cohorte pour comparer.

## 5. Alertes

- **Chute DAU > 30 % day-over-day** :
  - Dashboard DAU → kebab → *Create alert*
  - Condition : *Value changes by more than 30 % decreasing*
  - Frequency : daily 09:00 Europe/Paris
  - Channel : webhook Slack `#facteur-alerts` (ou email Laurin si pas de Slack)

- **Digest job failures** :
  - Insight : `digest_generated` → breakdown `stats.failed`
  - Alert : `stats.failed > 10` déclenche même canal.

## 6. Funnel recommandé

```
signup_completed → article_read → digest_session → app_open (lendemain)
```

À utiliser pour quantifier le drop entre "inscrit" et "activé habituel".

## 7. Rollout

1. Activer `POSTHOG_ENABLED=true` sur Railway staging.
2. Lancer un run manuel `/api/internal/briefing` + ouvrir l'app sur device dev.
3. Vérifier que les 9 events de la section 2 apparaissent.
4. Activer en production (`POSTHOG_ENABLED=true`).
5. Créer les insights de la section 4 dans l'ordre.
6. Documenter l'URL du dashboard dans `docs/etat-avancement-mvp.md`.

## 8. Kill-switch

- Désactiver rapidement : sur Railway, mettre `POSTHOG_ENABLED=false` + redeploy.
- Côté mobile : un build sans `POSTHOG_API_KEY` (dart-define vide) désactive le SDK.
