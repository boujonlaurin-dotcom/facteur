# Codebase Structure

**Analysis Date:** 2026-02-01

## Directory Layout

```
[project-root]/
├── apps/
│   └── mobile/              # Flutter mobile application
├── packages/
│   └── api/                 # FastAPI backend
├── docs/                    # Project documentation
├── scripts/                 # Build and deployment scripts
├── sources/                 # RSS source definitions
└── web-bundles/             # Web deployment bundles
```

## Directory Purposes

**`apps/mobile/`:**
- Purpose: Flutter cross-platform mobile application
- Contains: Dart source files, platform-specific directories (iOS, Android, Web, macOS, Linux, Windows), assets, tests
- Key files: `pubspec.yaml`, `lib/main.dart`

**`packages/api/`:**
- Purpose: Python FastAPI backend service
- Contains: API routers, services, models, schemas, workers, tests
- Key files: `pyproject.toml`, `app/main.py`

**`docs/`:**
- Purpose: Project documentation and specifications
- Contains: PRDs, architecture docs, QA guides, stories, handoff notes
- Subdirectories: `config/`, `bugs/`, `qa/`, `stories/`, `maintenance/`, `handoffs/`, `guidelines/`

**`scripts/`:**
- Purpose: Utility scripts for development, build, and deployment
- Contains: Shell scripts, Python utilities

**`sources/`:**
- Purpose: RSS feed source definitions and configurations
- Contains: Source metadata files

## Key File Locations

**Entry Points:**
- Mobile: `apps/mobile/lib/main.dart`
- API: `packages/api/app/main.py`

**Configuration:**
- Mobile: `apps/mobile/lib/config/routes.dart`, `apps/mobile/lib/config/theme.dart`, `apps/mobile/lib/config/constants.dart`
- API: `packages/api/app/config.py`, `packages/api/pyproject.toml`

**Core Logic:**
- Mobile Auth: `apps/mobile/lib/core/auth/auth_state.dart`
- Mobile API: `apps/mobile/lib/core/api/api_client.dart`
- API Services: `packages/api/app/services/` (recommendation_service.py, feed.py, etc.)
- API Routers: `packages/api/app/routers/` (feed.py, contents.py, auth.py, etc.)

**Database:**
- Models: `packages/api/app/models/` (content.py, source.py, user.py, etc.)
- Schemas: `packages/api/app/schemas/` (content.py, user.py, source.py, etc.)
- Migrations: `packages/api/alembic/`

**Testing:**
- Mobile: `apps/mobile/test/`
- API: `packages/api/tests/`

**Workers/Background Jobs:**
- Location: `packages/api/app/workers/`
- Scheduler: `packages/api/app/workers/scheduler.py`
- RSS Sync: `packages/api/app/workers/rss_sync.py`
- Classification: `packages/api/app/workers/classification_worker.py`

## Naming Conventions

**Files:**
- Flutter: `snake_case.dart` (e.g., `feed_screen.dart`, `auth_state.dart`)
- Python: `snake_case.py` (e.g., `feed.py`, `recommendation_service.py`)
- Generated files: `*.g.dart` (Riverpod generators)

**Directories:**
- Feature-based organization: lowercase with underscores (e.g., `feed/`, `auth/`, `settings/`)
- Layer-based organization: `core/`, `config/`, `shared/`

**Classes:**
- Flutter: PascalCase (e.g., `FeedScreen`, `AuthStateNotifier`)
- Python: PascalCase for models (e.g., `Content`, `UserProfile`), snake_case for functions

## Where to Add New Code

**New Feature (Mobile):**
- Screens: `apps/mobile/lib/features/{feature}/screens/`
- Providers: `apps/mobile/lib/features/{feature}/providers/`
- Models: `apps/mobile/lib/models/` or feature-specific
- Tests: `apps/mobile/test/features/{feature}/`

**New API Endpoint:**
- Router: `packages/api/app/routers/{domain}.py` (add to main.py includes)
- Service: `packages/api/app/services/{domain}_service.py` (or extend existing)
- Model: `packages/api/app/models/{entity}.py`
- Schema: `packages/api/app/schemas/{domain}.py`
- Tests: `packages/api/tests/`

**New ML/Scoring Layer:**
- Implementation: `packages/api/app/services/recommendation/layers/`
- Registration: Add to scoring config in `packages/api/app/services/recommendation/scoring_config.py`

**Utilities:**
- Mobile: `apps/mobile/lib/shared/widgets/` or `apps/mobile/lib/core/services/`
- API: `packages/api/app/utils/`

## Special Directories

**`apps/mobile/lib/features/`:**
- Purpose: Feature-based module organization
- Each feature contains: screens/, providers/, models/ (if feature-specific)
- Features: auth, feed, sources, settings, onboarding, progress, subscription, detail, saved, gamification

**`packages/api/app/services/recommendation/layers/`:**
- Purpose: Pluggable scoring layers for recommendation engine
- Files: `article_topic.py`, `behavioral.py`, `core.py`, `personalization.py`, `quality.py`, `static_prefs.py`, `visual.py`

**`packages/api/alembic/`:**
- Purpose: Database migration scripts
- Generated: Yes (via alembic CLI)
- Committed: Yes (migration history)

**`apps/mobile/assets/`:**
- Purpose: Static assets (images, icons, fonts)
- Subdirectories: `images/`, `icons/`

---

*Structure analysis: 2026-02-01*
