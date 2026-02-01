# Technology Stack

**Analysis Date:** 2026-02-01

## Languages

**Primary:**
- **Python 3.12** - Backend API (`packages/api/`)
- **Dart** - Mobile application (`apps/mobile/`)
- **SQL** - Database queries (PostgreSQL)

**Secondary:**
- **YAML** - Configuration files, CI/CD workflows, pubspec
- **Dockerfile** - Container build instructions

## Runtime

**Backend:**
- **Python 3.12+** (3.13+ explicitly NOT supported due to pydantic-core limitations)
- Virtual environment in `packages/api/venv/`

**Mobile:**
- **Dart SDK** >=3.0.0 <4.0.0
- **Flutter** stable channel

**Package Manager:**
- **pip** - Python dependencies (`requirements.txt`, `pyproject.toml`)
- **pub** - Dart/Flutter dependencies (`pubspec.yaml`)

## Frameworks

**Backend:**
- **FastAPI 0.109.2** - Web framework with async support
- **Pydantic 2.6.1** - Data validation and settings management
- **SQLAlchemy 2.0.25** - ORM with async support
- **Alembic 1.13.1** - Database migrations
- **APScheduler 3.10.4** - Background job scheduling

**Mobile:**
- **Flutter** - UI framework
- **Riverpod 2.5.1** - State management with code generation
- **go_router 17.0.1** - Navigation/routing
- **Freezed** - Immutable data classes with code generation

**Testing:**
- **pytest 8.0.0** - Python test runner (async support via `pytest-asyncio`)
- **mocktail/mockito** - Dart mocking
- **flutter_test** - Flutter widget testing

**Build/Dev:**
- **uvicorn** - ASGI server (production)
- **ruff** - Python linting and formatting
- **mypy** - Python type checking
- **build_runner** - Dart code generation

## Key Dependencies

**Backend Critical:**
| Package | Version | Purpose |
|---------|---------|---------|
| `fastapi` | 0.109.2 | API framework |
| `uvicorn[standard]` | 0.27.1 | ASGI server with websockets |
| `pydantic` | 2.6.1 | Validation & config |
| `pydantic-settings` | 2.1.0 | Environment-based config |
| `sqlalchemy[asyncio]` | 2.0.25 | Async ORM |
| `psycopg[binary,pool]` | 3.1.18 | PostgreSQL driver |
| `alembic` | 1.13.1 | Migrations |
| `httpx` | 0.26.0 | HTTP client for external APIs |
| `feedparser` | 6.0.10 | RSS/Atom parsing |
| `python-jose[cryptography]` | 3.3.0 | JWT handling (Supabase) |
| `passlib[bcrypt]` | 1.7.4 | Password hashing |
| `structlog` | 24.1.0 | Structured logging |
| `sentry-sdk[fastapi]` | 1.40.0 | Error tracking |
| `transformers` | 4.38.0+ | ML classification (HuggingFace) |
| `torch` | 2.2.0+ | PyTorch for ML |

**Mobile Critical:**
| Package | Version | Purpose |
|---------|---------|---------|
| `flutter_riverpod` | ^2.5.1 | State management |
| `go_router` | ^17.0.1 | Routing |
| `dio` | ^5.4.3+1 | HTTP client |
| `hive` | ^2.2.3 | Local storage |
| `supabase_flutter` | ^2.5.0 | Auth & backend sync |
| `purchases_flutter` | ^9.10.5 | RevenueCat in-app purchases |
| `flutter_html` | ^3.0.0-beta.2 | Article content rendering |
| `just_audio` | ^0.9.36 | Podcast audio player |
| `youtube_player_flutter` | ^9.1.1 | YouTube video player |
| `sentry_flutter` | ^9.9.2 | Error tracking |
| `cached_network_image` | ^3.3.1 | Image caching |

## Configuration

**Backend Environment (`.env`):**
- `ENVIRONMENT` - development/staging/production
- `DEBUG` - true/false
- `DATABASE_URL` - Supabase PostgreSQL connection
- `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_JWT_SECRET` - Supabase config
- `REVENUECAT_API_KEY`, `REVENUECAT_WEBHOOK_SECRET` - Subscription management
- `RSS_SYNC_INTERVAL_MINUTES`, `RSS_SYNC_ENABLED` - Feed sync settings
- `CORS_ORIGINS` - Allowed origins
- `SENTRY_DSN` - Error tracking (production)
- `ML_ENABLED` - Toggle ML classification
- `TRANSFORMERS_CACHE` - ML model cache path

**Mobile Environment:**
- `API_BASE_URL` - Backend API endpoint
- `SUPABASE_URL` - Supabase instance URL
- `SUPABASE_ANON_KEY` - Supabase public key
- `REVENUECAT_IOS_KEY` - RevenueCat API key

**Build Configuration:**
- `pyproject.toml` - Python project metadata, tool configs (ruff, mypy, pytest)
- `alembic.ini` - Database migration configuration
- `railway.json` - Railway deployment configuration

## Platform Requirements

**Development:**
- Python 3.12.8 (recommended via pyenv)
- PostgreSQL (via Supabase local or cloud)
- Flutter SDK >=3.0.0
- Docker (optional, for containerized builds)

**Production:**
- **Railway** - Primary deployment platform (Docker-based)
- **Supabase** - Managed PostgreSQL + Auth
- Docker image with Python 3.12-slim base
- Health check endpoint: `/api/health`

**Mobile Platforms:**
- iOS (iPhone/iPad)
- Android
- Web (Flutter Web)

---

*Stack analysis: 2026-02-01*
