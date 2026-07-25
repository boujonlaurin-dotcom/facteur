# Navigation Matrix - Agent Brain

**Guide de navigation codebase selon type de tâche. Suit cet ordre pour éviter l'overload.**

---

## 🎯 Matrice de Navigation

### 1. FEATURE / EVOLUTION

**Workflow**:
1. Contexte Business → 2. Specs Techniques → 3. Codebase → 4. Implémentation

| Phase | Docs à Lire | Chemins Codebase | Actions |
|-------|------------|------------------|---------|
| **1. Contexte** | [PRD](../prd.md) (section concernée)<br>[Story README](../stories/README.md) | - | Comprendre le "pourquoi" |
| **2. Specs Tech** | [Architecture](../architecture.md) (API concernée)<br>[Front-end Spec](../front-end-spec.md) (composants) → design-system-first + minimalisme + respect du layout sont des contraintes **LOCKED** (cf. FES §5.1) | - | Identifier contraintes techniques |
| **3. Codebase** | [Mobile Map](#mobile-feature-map)<br>[Backend Map](#backend-feature-map) | Voir maps ci-dessous | Localiser fichiers à modifier |
| **4. Story** | Crée `docs/stories/core/{epic}.{story}.{nom}.md`<br>Template: [Story Template](../stories/README.md#template) | - | Document plan d'implémentation |

**Exemple: "Ajouter un bouton de partage sur la digest card"**
1. PRD → Epic 10 section "Actions sur articles"
2. Front-end Spec → Design tokens, composants boutons
3. Mobile Map → `features/digest/widgets/digest_card.dart`
4. Story → `docs/stories/core/10.XX.share-button.md`

---

### 2. BUG FIX

**Workflow**:
1. Reproduction → 2. Root Cause → 3. Fix → 4. Regression Prevention

| Phase | Docs à Lire | Chemins Codebase | Actions |
|-------|------------|------------------|---------|
| **1. Repro** | [Bug Template](../bugs/README.md)<br>Issues similaires: `docs/bugs/` | Logs, Sentry traces | Document steps to reproduce |
| **2. Root Cause** | [Retrospectives](../retrospective-*.md) (patterns)<br>[Tech Guardrails](tech-guardrails.md) | [Workflows Map](#common-workflows) | Utilise debugger, logs structlog |
| **3. Fix** | [Architecture](../architecture.md) (zone concernée) | Voir maps par zone | Implémente fix minimal |
| **4. Prevention** | [QA Scripts](../qa/scripts/) (inspiration) | `docs/qa/scripts/` | Crée `verify_<bug>.sh` |

**Exemple: "Digest ne se génère pas pour certains users"**
1. Bug Template → `docs/bugs/bug-digest-not-generated.md`
2. Retrospectives → Patterns d'erreur scheduler
3. Backend Map → `packages/api/app/services/digest_selector.py`
4. Crée `docs/qa/scripts/verify_digest_generation.sh`

---

### 3. MAINTENANCE / REFACTORING

**Workflow**:
1. État Actuel → 2. Impact Analysis → 3. Migration Plan → 4. Rollback Strategy

| Phase | Docs à Lire | Chemins Codebase | Actions |
|-------|------------|------------------|---------|
| **1. État** | [Maintenance](../maintenance/) (status actuel)<br>[Architecture](../architecture.md) | Voir maps | Cartographie code existant |
| **2. Impact** | [Tech Debt](../architecture.md#tech-debt)<br>[Safety Protocols](safety-protocols.md#danger-zones) | Tous fichiers impactés | Liste breaking changes |
| **3. Plan** | [Migration patterns](../handoffs/) | - | `implementation_plan.md` détaillé |
| **4. Rollback** | [Git isolation](../maintenance/maintenance-git-branch-isolation.md) | `.git/worktrees/` | Plan de rollback ready |

**Exemple: "Migrer SQLAlchemy 1.4 → 2.0"**
1. Maintenance → Check si migration déjà documentée
2. Architecture → Tous usages de SQLAlchemy
3. Plan → Breaking changes API, migrations Alembic
4. Rollback → Branch isolation, `git restore` prêt

---

## 🗺️ Codebase Maps

### Mobile Feature Map

**Racine**: `/apps/mobile/lib/`

#### Ajouter une Feature Complète

```
features/{nom}/
├── screens/{nom}_screen.dart         ← UI principale
├── providers/{nom}_provider.dart     ← State management (Riverpod)
├── repositories/{nom}_repository.dart ← Data layer (API calls)
├── widgets/{composant}.dart          ← Composants réutilisables
└── models/{model}.dart               ← Data classes (Freezed)
```

**Après création**: `dart run build_runner build --delete-conflicting-outputs`

#### Modifier une Feature Existante

| Besoin | Fichier | Chemin |
|--------|---------|--------|
| **Digest UI** | Écran principal | `features/digest/screens/digest_screen.dart` |
| | Card article | `features/digest/widgets/digest_card.dart` |
| | State | `features/digest/providers/digest_provider.dart` |
| | API calls | `features/digest/repositories/digest_repository.dart` |
| **Feed** | Écran | `features/feed/screens/feed_screen.dart` |
| | Card | `features/feed/widgets/content_card.dart` |
| **Auth** | Login | `features/auth/screens/login_screen.dart` |
| | State | `core/auth/auth_state.dart` (⚠️ FRAGILE) |
| **Sources** | Catalogue | `features/sources/screens/sources_screen.dart` |
| | Add custom | `features/sources/screens/add_custom_source_screen.dart` |
| **Settings** | Préférences | `features/settings/screens/settings_screen.dart` |
| **Detail** | Article reader | `features/detail/screens/detail_screen.dart` |
| | YouTube player | `features/detail/widgets/youtube_player.dart` |

#### Composants Partagés

| Type | Localisation |
|------|-------------|
| **Design System** | `widgets/` (boutons, cards, inputs) |
| **Navigation** | `shared/navigation/` + `config/routes.dart` |
| **API Client** | `core/api/api_client.dart` |
| **Auth** | `core/auth/auth_state.dart` |
| **Modèles Partagés** | `models/` (user.dart, content.dart, etc.) |

---

### Backend Feature Map

**Racine**: `/packages/api/app/`

#### Ajouter un Endpoint Complet

```
1. Model (DB) → models/{entity}.py
2. Schema (DTO) → schemas/{entity}.py
3. Service (Logic) → services/{entity}_service.py
4. Router (API) → routers/{entity}.py
5. Migration → alembic revision --autogenerate -m "add {entity}"
6. Test → tests/test_{entity}.py
```

**Enregistrer router**: Dans `main.py`, `app.include_router(entity.router, prefix="/api/{entity}", tags=["{entity}"])`

#### Modifier une Feature Existante

| Besoin | Couche | Fichier |
|--------|--------|---------|
| **Digest** | Router | `routers/digest.py` |
| | Service | `services/digest_service.py`, `services/digest_selector.py` |
| | Model | `models/daily_digest.py`, `models/digest_completion.py` |
| | Schema | `schemas/digest.py` |
| **Feed (Legacy)** | Router | `routers/feed.py` |
| | Service | `services/recommendation_service.py` |
| | Scoring | `services/recommendation/layers/*.py` |
| **Sources** | Router | `routers/sources.py` |
| | Service | `services/source_service.py` |
| | Model | `models/source.py` |
| **Auth** | Router | `routers/auth.py` |
| | Dependency | `dependencies.py` (⚠️ JWT validation FRAGILE) |
| **Users** | Router | `routers/users.py` |
| | Service | `services/user_service.py` |
| | Model | `models/user.py` |

#### Background Jobs

| Job | Scheduler | Worker |
|-----|-----------|--------|
| **RSS Sync** | `workers/scheduler.py` (30min) | `workers/rss_sync.py` |
| **Digest Generation** | `workers/scheduler.py` (8am) | `services/digest_selector.py` |
| **Top 3 Daily** | `workers/top3_job.py` (8am) | `services/briefing/top3_selector.py` |
| **ML Classification** | `workers/classification_worker.py` | `services/ml/classification_service.py` |

---

### Common Workflows

#### 1. Flux Complet Feature (Mobile → API → DB)

**Exemple**: Ajouter un champ "notes" aux articles du digest

```
1. DB Schema
   └─ models/daily_digest.py → Ajoute colonne `notes: str`
   └─ alembic revision --autogenerate -m "add notes to digest"
   └─ alembic upgrade head

2. Backend API
   └─ schemas/digest.py → Ajoute `notes: str` au DigestResponse
   └─ routers/digest.py → Endpoint PATCH /digest/{id}/notes
   └─ services/digest_service.py → update_notes(digest_id, notes)

3. Mobile App
   └─ models/digest.dart → Ajoute `notes` au DigestModel (Freezed)
   └─ repositories/digest_repository.dart → patchNotes(id, notes)
   └─ providers/digest_provider.dart → updateNotes() method
   └─ widgets/digest_card.dart → TextField pour éditer notes
   └─ dart run build_runner build --delete-conflicting-outputs

4. Verification
   └─ docs/qa/scripts/verify_digest_notes.sh
```

#### 2. Flux Authentication

**Mobile Login → Supabase → API Validation → Data Fetch**

```
1. Mobile
   └─ features/auth/screens/login_screen.dart
   └─ core/auth/auth_state.dart (⚠️ FRAGILE, cf. Safety Protocols)
   └─ Supabase.auth.signInWithPassword()

2. Token Storage
   └─ JWT stocké dans Hive (local storage)
   └─ core/api/api_client.dart → Authorization: Bearer <token>

3. Backend Validation
   └─ dependencies.py → get_current_user_id() valide JWT
   └─ Vérifie signature via SUPABASE_JWT_SECRET

4. Data Access
   └─ Tous routers utilisent Depends(get_current_user_id)
   └─ Query DB avec user_id filtré
```

#### 3. Flux Digest Quotidien

**Scheduler → Scoring → Diversité → Stockage → Mobile Fetch**

```
1. Trigger (8am Europe/Paris)
   └─ workers/scheduler.py → run_digest_generation()

2. Scoring & Selection
   └─ services/digest_selector.py
   └─ Récupère contenus scorés (last 7 days)
   └─ Applique diversité sources (decay 0.70, min 3 sources)
   └─ Sélectionne top 5 articles

3. Stockage
   └─ models/daily_digest.py → Insert 5 rows (user_id, content_id, date, position)

4. Mobile Fetch
   └─ features/digest/repositories/digest_repository.dart → fetchTodayDigest()
   └─ GET /api/digest/ → Return DigestResponse
   └─ features/digest/providers/digest_provider.dart → Cache state
   └─ features/digest/screens/digest_screen.dart → Display
```

#### 4. Flux Feed Generation (Legacy)

**User Request → Scoring Layers → Diversity Ranking → Response**

```
1. API Call
   └─ GET /api/feed/?limit=20
   └─ routers/feed.py → recommendation_service.get_feed()

2. Candidate Fetching
   └─ services/recommendation_service.py
   └─ Query 500 candidates (last 7 days, user sources)

3. Scoring
   └─ services/recommendation/scoring_engine.py
   └─ Apply layers: static_prefs, behavioral, quality, article_topic
   └─ Each content gets composite score

4. Diversity Ranking
   └─ In-memory diversity algorithm (source decay 0.70)
   └─ Top 20 returned via schemas/feed.py
```

---

## 🛡️ Safety Checklist by Zone

### Auth / Security Changes
**AVANT toute modif**:
- [ ] Lis [Safety Protocols - Auth](safety-protocols.md#auth-security)
- [ ] Lis [Retrospective Auth Bugs](../retrospective-auth-bugs.md)
- [ ] Test manuel: `curl` sur route protégée BEFORE/AFTER
- [ ] Vérifie `dependencies.py` (JWT validation)

### Router / Navigation (Mobile)
**AVANT toute modif**:
- [ ] Lis [Safety Protocols - Router](safety-protocols.md#router-core-mobile)
- [ ] Map tous les paths dans `config/routes.dart`
- [ ] Test: Tous flows user (logged in, logged out, confirmed, unconfirmed)

### Database / Migrations
**AVANT toute modif**:
- [ ] Lis [Safety Protocols - Migrations](safety-protocols.md#alembic-migrations)
- [ ] Test migration sur copie DB prod (si disponible)
- [ ] Plan de rollback (`alembic downgrade -1`)
- [ ] Fenêtre de maintenance si destructive

### UI / Design
**AVANT toute modif UI** (contrainte **LOCKED**, cf. [Front-end Spec §5.1](../front-end-spec.md)) :
- [ ] Réutiliser les tokens (`context.facteurColors`, `FacteurSpacing/Radius/Typography`) et les composants existants avant d'en inventer.
- [ ] Respecter l'échelle d'espacement/rayons et le layout de l'écran ; minimalisme > décor.
- [ ] Ne jamais ajouter de contenu **non budgété sous les cartes** du Flux Continu → casse les budgets snap/fit (`section_fit.dart` / `_recomputeSnapAnchors`) — cf. le CTA « Ajouter à l'Essentiel » relocalisé dans le banner (story 22.6 redesign).
- [ ] Justifier toute UI *net-new* ; cibles tap ≥ 44px (FES §7.2).

---

## 📋 Quick Reference Commands

### Mobile
```bash
# Run app (local API)
cd apps/mobile
flutter run -d chrome \
  --dart-define=SUPABASE_URL=$SUPABASE_URL \
  --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY \
  --dart-define=API_BASE_URL=http://localhost:8080/api/

# Code generation (after Freezed/Riverpod changes)
dart run build_runner build --delete-conflicting-outputs

# Tests
flutter test
flutter analyze
```

### Backend
```bash
# Run API (local)
cd packages/api
source venv/bin/activate
uvicorn app.main:app --reload --port 8080

# Health check
curl http://localhost:8080/api/health

# Migrations
alembic revision --autogenerate -m "description"
alembic upgrade head
alembic downgrade -1  # Rollback

# Tests
pytest -v
pytest --cov=app
```

### Git Worktree (OBLIGATOIRE)
```bash
# Setup isolation
cd /Users/laurinboujon/Desktop/Projects/Work\ Projects/Facteur
git checkout main && git pull origin main
git checkout -b dev-feature-x
git worktree add ../dev-feature-x dev-feature-x
cd ../dev-feature-x

# Cleanup après merge
cd /Users/laurinboujon/Desktop/Projects/Work\ Projects/Facteur
git worktree remove ../dev-feature-x
```

---

*Dernière MAJ: 2026-02-14*
