# Maintenance — Auth Backend Hardening

## Context

This maintenance closes quick backend security gaps from the production security
review without touching RLS migrations or database schema.

## Scope

- Protect all `/api/internal/*` endpoints with `X-Admin-Token`.
- Compare admin tokens with `hmac.compare_digest` while keeping existing
  fail-closed behavior when `ADMIN_API_TOKEN` is not configured.
- Accept only Supabase ES256 JWTs verified through JWKS; reject HS256 and any
  other algorithm with `401`.
- Align `requirements.txt` with the existing lockfile entry for
  `python-jose[cryptography]==3.5.0`.

## Validation

- `cd packages/api && python -m pytest -q tests/test_auth_jwt_algorithms.py tests/routers/test_internal_ner_health.py tests/routers/test_admin_cohorts.py`
- Prefer full backend validation before merge:
  `cd packages/api && python -m pytest -v`
- Local curl expectation after starting the API:
  `POST /api/internal/sync` without `X-Admin-Token` returns `401` or `503`,
  never `200`.

## Exclusions

- No RLS migration or schema change is included here.
- SSRF/feed URL hardening is intentionally left to a separate change.
