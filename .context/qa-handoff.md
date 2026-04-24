# QA Handoff — Well-Informed NPS (Story 14.3)

> Feature branch : `boujonlaurin-dotcom/sprint2-feature-events`
> Story : `docs/stories/core/14.3.well-informed-self-report.story.md`
> Plan : `/Users/laurinboujon/.claude/plans/system-instruction-you-are-working-lively-river.md`

## Feature développée

Prompt inline NPS-style (1-10) dans le scroll du digest, demandant *"À quel point te sens-tu bien informé·e en ce moment ?"*. Skip autorisé via icône `x` (cooldown 5j), soumission d'une note impose un cooldown 14j. Données persistées dans `user_well_informed_ratings` + 3 events PostHog (shown / skipped / submitted).

## PR associée

À remplir après `gh pr create --base main`.

## Écrans impactés

| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Digest (sliver inline inséré) | `/digest` | **Modifié** (nouveau sliver entre success banner et briefing) |
| `WellInformedPrompt` widget | — | **Nouveau** |

## Scénarios de test

### Scénario 1 : Happy path — première soumission
**Parcours** :
1. Fresh install, compléter onboarding + welcome tour.
2. Attendre 24h+ (contrainte `kGlobalNonCriticalCooldown` du NudgeCoordinator) OU clear le nudge state côté test.
3. Ouvrir `/digest` → scroll léger pour atteindre la carte (placée sous le success banner, avant la briefing section).
4. Vérifier visuellement : question, helper text 1=/10=, 10 pills 1..10, croix discrete en haut-droite, texte italique explicatif en bas.
5. Tap sur le pill **7**.
**Résultat attendu** :
- La carte disparaît instantanément (fade out via invalidation provider).
- Vibration tactile medium-impact.
- `POST /api/well-informed/ratings` → 201 avec body `{score: 7, context: "digest_inline"}`.
- Event PostHog `well_informed_score_submitted` avec `score=7, context="digest_inline"` émis.
- Event analytics backend `well_informed_score_submitted` stocké dans `analytics_events`.
- Row dans `user_well_informed_ratings` (vérifier via Supabase SQL Editor).
- La carte ne réapparaît pas lors des ouvertures `/digest` suivantes pendant 14 jours.

### Scénario 2 : Skip — cooldown court 5j
**Parcours** :
1. Fresh state (comme scénario 1, après cooldown global 24h).
2. Ouvrir `/digest`, repérer la carte.
3. Tap sur l'icône `x` en haut-droite.
**Résultat attendu** :
- La carte disparaît.
- Vibration tactile light-impact.
- Aucun POST `/api/well-informed/ratings` émis (vérifier Network inspector Chrome DevTools).
- Event `well_informed_prompt_skipped` émis vers analytics + PostHog.
- Aucune row insérée dans `user_well_informed_ratings`.
- La carte réapparaît après 5 jours (simuler en forçant `nudge.well_informed_poll.lastShown` 6 jours dans le passé via SharedPreferences).
- Avant les 5 jours, la carte ne revient pas.

### Scénario 3 : Bornes 1 et 10
**Parcours** :
1. Fresh state → tap sur le pill **1**. Reset state. Tap sur le pill **10**.
**Résultat attendu** :
- Les deux valeurs sont acceptées (201 API).
- `user_well_informed_ratings` contient une row avec `score=1` et une avec `score=10`.
- Aucune erreur de validation.

### Scénario 4 : Validation API — score hors bornes
**Parcours (test API direct, pas UI)** :
1. `curl -X POST .../api/well-informed/ratings -H 'Authorization: Bearer $JWT' -d '{"score": 0}'`
2. Idem avec `score: 11`, `score: -5`.
**Résultat attendu** : HTTP 422 (Unprocessable Entity) avec détail Pydantic mentionnant la contrainte `ge=1, le=10`.

### Scénario 5 : Cooldown long domine le court
**Parcours** :
1. Skip le prompt → attendre 6 jours (simulé).
2. La carte reparaît → tap sur un score (soumission).
3. Simuler 10 jours plus tard : la carte doit **encore être cachée** (car submit → 14j > 10j).
**Résultat attendu** : cohérent avec la règle "après submit, 14j obligatoire même si le nudge cooldown 5j est écoulé".

### Scénario 6 : Fail silencieux réseau
**Parcours** :
1. Désactiver le réseau (offline mode ou kill API).
2. Tap un score.
**Résultat attendu** :
- La carte disparaît quand même (meilleure UX que de laisser bloqué).
- Aucune erreur visible à l'utilisateur (repository catch silencieux).
- `well_informed_poll_last_submitted_at_ms` est mis à jour en SharedPreferences → cooldown 14j avance, même sans row en DB.
- Event PostHog `well_informed_score_submitted` parti (PostHog a son propre buffer).

## Critères d'acceptation

- [ ] La carte s'affiche dans le scroll du digest après 24h+ d'install (nudge global cooldown).
- [ ] Tap sur un pill 1-10 : carte disparaît, row en DB, event PostHog, cooldown 14j respecté.
- [ ] Tap sur `x` : carte disparaît, event skipped, cooldown 5j respecté.
- [ ] Bornes 1 et 10 acceptées ; 0 et 11 rejetés (422).
- [ ] Aucune régression visible sur les tests existants backend + mobile (hook `stop-verify-tests.sh` passe).
- [ ] `flutter analyze` sur mes fichiers : 0 issue.
- [ ] Migration Alembic `wi01` applique proprement (1 head unique).

## Zones de risque

- **Double prefix routers** : le router `analytics` avait `prefix="/analytics"` combiné à `include_router(prefix="/api/analytics")` → double prefix `/api/analytics/analytics/events`. Mon router `well_informed` évite ce piège (prefix uniquement dans `include_router`). Route finale : `/api/well-informed/ratings`.
- **Nudge budget session** : priority `low` → consomme le budget `kSessionNonCriticalBudget = 1`. Si un autre low/normal nudge a déjà été affiché dans la session, le prompt ne s'affichera PAS ce jour-là (attendu, pas bug).
- **SharedPreferences key collision** : `well_informed_poll_last_submitted_at_ms` est notre clé custom. Ne pas la confondre avec `nudge.well_informed_poll.lastShown` (gérée par NudgeStorage, sert au cooldown 5j des skips).
- **Timezone** : `submitted_at` est en UTC côté backend (SQLAlchemy DateTime(timezone=True) + now()). Pas de bug de décalage.

## Dépendances

- **Backend** : nouvelle table `user_well_informed_ratings` (migration `wi01`). Dépend de `lp02` (déjà mergée en 14.2).
- **Mobile** : dépend du module unifié `core/nudges/` (shipped en PR #468, déjà sur main).
- **PostHog** : project `Default project` (id 129581), org Facteur. Les nouveaux events apparaîtront automatiquement dans l'event explorer.

## Commandes rapides de vérification

```bash
# Backend — tests unitaires ciblés
cd packages/api && PYTHONPATH=. pytest tests/test_well_informed_service.py -v

# Mobile — tests ciblés
cd apps/mobile && flutter test test/features/well_informed/ test/core/services/analytics_service_sprint2_test.dart

# Migration Alembic
cd packages/api && alembic heads  # → wi01 (head unique)
cd packages/api && alembic upgrade head

# Query DB
psql -c "SELECT score, COUNT(*) FROM user_well_informed_ratings GROUP BY score ORDER BY score;"
```
