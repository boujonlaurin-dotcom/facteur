# External Integrations

**Analysis Date:** 2026-02-01

## APIs & External Services

**Supabase** - Auth & Database Backend
- **Usage:** User authentication (JWT), user management, PostgreSQL hosting
- **Backend SDK:** `supabase-py` (via direct REST/JWT handling in `python-jose`)
- **Mobile SDK:** `supabase_flutter: ^2.5.0`
- **Auth Flow:** 
  - Mobile: Supabase Auth → JWT token → API requests with Bearer token
  - Custom Hive storage (`apps/mobile/lib/core/auth/supabase_storage.dart`) for session persistence
- **Env vars:** `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_JWT_SECRET`
- **Files:** 
  - Backend: `packages/api/app/dependencies.py` (JWT validation)
  - Mobile: `apps/mobile/lib/core/auth/supabase_storage.dart`, `apps/mobile/lib/core/api/api_client.dart`

**RevenueCat** - In-App Purchase & Subscription Management
- **Usage:** Premium subscription handling, trial management
- **Mobile SDK:** `purchases_flutter: ^9.10.5`
- **Backend Integration:** Webhook endpoint for subscription events
- **Products:**
  - `facteur_premium_monthly` - Monthly subscription
  - `facteur_premium_yearly` - Yearly subscription
- **Webhook Events Handled:** `INITIAL_PURCHASE`, `RENEWAL`, `CANCELLATION`, `EXPIRATION`
- **Env vars:** `REVENUECAT_API_KEY`, `REVENUECAT_WEBHOOK_SECRET`
- **Files:**
  - Backend: `packages/api/app/routers/webhooks.py`, `packages/api/app/services/subscription_service.py`
  - Mobile: `apps/mobile/lib/config/constants.dart` (RevenueCatConstants)

**HuggingFace Transformers** - ML Content Classification
- **Usage:** Zero-shot classification of articles into 50 topic categories
- **Model:** `MoritzLaurer/mDeBERTa-v3-base-xnli-multilingual-nli-2mil7`
- **Framework:** `transformers>=4.38.0`, `torch>=2.2.0`
- **Activation:** Controlled by `ML_ENABLED` env var (disabled by default)
- **Topics:** 50 French labels (AI, Tech, Politics, Climate, Cinema, etc.)
- **File:** `packages/api/app/services/ml/classification_service.py`

**RSS/Atom Feeds** - Content Sources
- **Usage:** Fetch articles, podcasts, YouTube videos from external sources
- **Parser:** `feedparser==6.0.10`
- **HTTP Client:** `httpx==0.26.0` with custom User-Agent
- **Supported Types:**
  - Articles (standard RSS/Atom)
  - Podcasts (with iTunes tags, audio enclosures)
  - YouTube (media thumbnails, descriptions)
- **Features:** Thumbnail optimization, content extraction, audio URL parsing
- **Sync:** Background scheduler (`APScheduler`) every 30 minutes
- **File:** `packages/api/app/services/sync_service.py`

## Data Storage

**Primary Database:**
- **Type:** PostgreSQL 15+ (via Supabase)
- **Driver:** `psycopg[binary,pool]==3.1.18`
- **ORM:** SQLAlchemy 2.0.25 with async support
- **Connection:** Via PgBouncer transaction pooling (Supabase)
- **Migrations:** Alembic 1.13.1
- **File:** `packages/api/app/database.py`

**Local Storage (Mobile):**
- **Type:** Hive (NoSQL, local)
- **Usage:** Settings cache, auth preferences, offline data
- **Package:** `hive: ^2.2.3`, `hive_flutter: ^1.1.0`
- **Custom Implementation:** Supabase session persistence via Hive
- **Files:** `apps/mobile/lib/core/auth/supabase_storage.dart`

**File Storage:**
- Not applicable - No file uploads in current feature set
- Images served via external URLs (cached with `cached_network_image`)

**Caching:**
- **Mobile:** In-memory Riverpod providers, Hive boxes
- **Backend:** SQLAlchemy session cache, no external Redis

## Authentication & Identity

**Provider:** Supabase Auth
- **Method:** Email/password with optional confirmation
- **JWT:** RS256 tokens validated via `python-jose`
- **Token Flow:**
  1. User signs in via Supabase (mobile)
  2. Supabase returns JWT access token
  3. Mobile attaches token to API requests (`Authorization: Bearer <token>`)
  4. Backend validates JWT signature against Supabase JWT secret
- **Persistence:** Custom Hive-based storage (avoids iOS Keychain issues)
- **Files:** 
  - Backend: `packages/api/app/dependencies.py`
  - Mobile: `apps/mobile/lib/core/auth/supabase_storage.dart`

## Monitoring & Observability

**Error Tracking:**
- **Sentry** - Error tracking and performance monitoring
  - Backend: `sentry-sdk[fastapi]==1.40.0`
  - Mobile: `sentry_flutter: ^9.9.2`
  - Env var: `SENTRY_DSN` (production only)

**Logging:**
- **Backend:** `structlog==24.1.0` with JSON formatting
  - Configuration: `packages/api/app/main.py`
  - Includes Railway environment metadata

**Analytics:**
- Custom analytics service in backend
- Tracks: Content consumption, user engagement, feature usage
- File: `packages/api/app/services/analytics_service.py`

## CI/CD & Deployment

**Hosting:**
- **Primary:** Railway.app (Docker-based deployment)
  - Config: `railway.json`
  - Dockerfile: `packages/api/Dockerfile`
  - Health check: `/api/health`
  - Auto-migrations on deploy

**CI Pipeline (GitHub Actions):**
- **Workflows:**
  - `.github/workflows/build-docker.yml` - Build and test Docker image
  - `.github/workflows/build-web.yml` - Build Flutter web
  - `.github/workflows/build-apk.yml` - Build Android APK
  - `.github/workflows/qa-bmad.yml` - QA automation

**Build Process:**
- Docker image based on `python:3.12-slim`
- Non-root user (`appuser`)
- Runs migrations before starting uvicorn
- Uvicorn with `--proxy-headers` for Railway

## Environment Configuration

**Required env vars (Backend):**
```bash
DATABASE_URL=postgresql+psycopg://.../postgres
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_JWT_SECRET=your-jwt-secret
```

**Required env vars (Mobile Build):**
```bash
--dart-define=SUPABASE_URL=https://...
--dart-define=SUPABASE_ANON_KEY=...
--dart-define=API_BASE_URL=https://...
```

**Secrets location:**
- Backend: `.env` file (not committed), Railway environment variables
- Mobile: Compiled into binary via `--dart-define` at build time

## Webhooks & Callbacks

**Incoming Webhooks:**
- **RevenueCat Webhook** (`POST /api/webhooks/revenuecat`)
  - Handles subscription lifecycle events
  - Signature verification with `X-RevenueCat-Signature` header
  - Events: INITIAL_PURCHASE, RENEWAL, CANCELLATION, EXPIRATION
  - File: `packages/api/app/routers/webhooks.py`

**Outgoing Callbacks:**
- None currently implemented

**Internal Scheduler:**
- **APScheduler** triggers RSS sync every 30 minutes
- Configurable via `RSS_SYNC_INTERVAL_MINUTES`
- File: `packages/api/app/workers/scheduler.py`

## Network Architecture

**Data Flow:**
```
Mobile App (Flutter)
    ↕ (Dio HTTP + JWT Auth)
FastAPI Backend (Railway)
    ↕ (SQLAlchemy + psycopg)
Supabase PostgreSQL
    ↕
RevenueCat (webhooks)
RSS Sources (httpx feed fetching)
```

**Security:**
- JWT token validation on all protected endpoints
- RevenueCat webhook signature verification
- CORS configured for Flutter Web
- No SQL injection (SQLAlchemy ORM)
- No XSS (content served as external URLs only)

---

*Integration audit: 2026-02-01*
