# Architecture

**Analysis Date:** 2026-02-01

## Pattern Overview

**Overall:** Layered Architecture with Clean Architecture principles

**Key Characteristics:**
- Separation of concerns across mobile (Flutter) and backend (FastAPI)
- Repository pattern for data access
- Service-oriented backend with clear layer boundaries
- Feature-based organization in mobile app
- Dependency injection via Riverpod (Flutter) and FastAPI Depends (Python)

## Layers

**Mobile Frontend (Flutter):**

**Presentation Layer:**
- Purpose: UI rendering and user interaction handling
- Location: `apps/mobile/lib/features/`
- Contains: Screen widgets, feature-specific UI components
- Depends on: Core layer (API clients, auth, providers)
- Used by: Entry point `main.dart`

**Core Layer:**
- Purpose: Business logic orchestration and state management
- Location: `apps/mobile/lib/core/`
- Contains: API clients, auth state providers, service abstractions
- Depends on: Config layer, external packages (Supabase, Dio, Hive)
- Used by: Features layer

**Config Layer:**
- Purpose: Application configuration and routing
- Location: `apps/mobile/lib/config/`
- Contains: Routes, theme definitions, constants
- Depends on: Core providers
- Used by: App entry point and screens

**Shared Layer:**
- Purpose: Reusable UI components and utilities
- Location: `apps/mobile/lib/shared/` and `apps/mobile/lib/widgets/`
- Contains: Common widgets, navigation components
- Depends on: Config layer (for theming)
- Used by: Feature screens

**Models:**
- Purpose: Data models and domain entities
- Location: `apps/mobile/lib/models/`
- Contains: Onboarding result, user profile models
- Used by: Core layer, features

**Backend API (FastAPI):**

**Presentation Layer (Routers):**
- Purpose: HTTP request handling and routing
- Location: `packages/api/app/routers/`
- Contains: API endpoints, request validation, response formatting
- Depends on: Services layer, Dependencies (auth)
- Used by: FastAPI main application

**Service Layer:**
- Purpose: Business logic implementation
- Location: `packages/api/app/services/`
- Contains: Recommendation engine, feed generation, user management, RSS parsing
- Depends on: Models layer, external services (Supabase, RevenueCat)
- Used by: Routers layer

**Models Layer:**
- Purpose: Database entities and ORM definitions
- Location: `packages/api/app/models/`
- Contains: SQLAlchemy models, enums
- Depends on: Database base class
- Used by: Services, Routers

**Schemas Layer:**
- Purpose: Pydantic models for request/response validation
- Location: `packages/api/app/schemas/`
- Contains: DTOs, response models
- Depends on: Enums from models
- Used by: Routers layer

**Workers Layer:**
- Purpose: Background job processing
- Location: `packages/api/app/workers/`
- Contains: RSS sync workers, classification workers, scheduled jobs
- Depends on: Services, Models
- Used by: Scheduler (started in main.py lifespan)

## Data Flow

**Feed Generation Flow:**

1. User requests feed via `GET /api/feed/` (router: `packages/api/app/routers/feed.py`)
2. Router calls `RecommendationService.get_feed()` (service: `packages/api/app/services/recommendation_service.py`)
3. Service applies scoring layers from `packages/api/app/services/recommendation/layers/`
4. Service queries database via SQLAlchemy models in `packages/api/app/models/`
5. Response serialized via schemas in `packages/api/app/schemas/content.py`

**Authentication Flow:**

1. Mobile app authenticates via Supabase Auth (state: `apps/mobile/lib/core/auth/auth_state.dart`)
2. JWT token passed to API in Authorization header
3. FastAPI dependency `get_current_user_id()` validates JWT (file: `packages/api/app/dependencies.py`)
4. User ID injected into router handlers
5. User-specific data fetched from Supabase PostgreSQL

**State Management:**

**Mobile:** Riverpod state management
- Global providers: `apps/mobile/lib/core/providers/`
- Auth state: `apps/mobile/lib/core/auth/auth_state.dart`
- API providers: `apps/mobile/lib/core/api/api_provider.dart`

**Backend:** FastAPI dependency injection with async context
- Database sessions: `packages/api/app/database.py` (get_db)
- Current user: `packages/api/app/dependencies.py` (get_current_user_id)

## Key Abstractions

**Recommendation Engine:**
- Purpose: Scoring and ranking content for personalized feed
- Examples: `packages/api/app/services/recommendation_service.py`, `packages/api/app/services/recommendation/layers/`
- Pattern: Layered scoring with composable scoring functions

**API Client:**
- Purpose: HTTP communication between mobile and backend
- Examples: `apps/mobile/lib/core/api/api_client.dart`
- Pattern: Dio with retry interceptor, centralized error handling

**Auth Provider:**
- Purpose: Authentication state management and Supabase integration
- Examples: `apps/mobile/lib/core/auth/auth_state.dart`, `packages/api/app/dependencies.py`
- Pattern: StateNotifier pattern (Flutter), JWT validation (API)

**Router Pattern:**
- Purpose: Navigation and routing
- Examples: `apps/mobile/lib/config/routes.dart` (go_router)
- Pattern: Shell routes for bottom navigation, guarded routes with auth redirects

## Entry Points

**Mobile App:**
- Location: `apps/mobile/lib/main.dart`
- Triggers: App launch
- Responsibilities: Initialize Hive, Supabase, Riverpod, set system UI styles

**Backend API:**
- Location: `packages/api/app/main.py`
- Triggers: Uvicorn server start
- Responsibilities: FastAPI app initialization, router registration, lifespan management (startup checks, scheduler)

**Background Workers:**
- Location: `packages/api/app/workers/scheduler.py`
- Triggers: FastAPI lifespan startup
- Responsibilities: APScheduler job scheduling (RSS sync, content classification)

## Error Handling

**Strategy:** Exception-based with centralized logging

**Patterns:**
- FastAPI: HTTPException with appropriate status codes, Sentry integration via `structlog`
- Flutter: Try-catch blocks with user-friendly error messages via `NotificationService`
- Auth errors: Translated via `apps/mobile/lib/features/auth/utils/auth_error_messages.dart`

## Cross-Cutting Concerns

**Logging:** `structlog` (backend), debugPrint (Flutter debug mode), Sentry (both)

**Validation:** Pydantic models (backend), form validation (Flutter)

**Authentication:** Supabase Auth with JWT tokens, JWKS validation for ES256

---

*Architecture analysis: 2026-02-01*
