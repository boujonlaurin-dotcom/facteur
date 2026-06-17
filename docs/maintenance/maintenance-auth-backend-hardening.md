# Auth Backend Hardening

Date: 2026-06-17

## Scope

- Protected all `/api/internal/*` routes with the existing `X-Admin-Token` admin
  dependency at router level.
- Kept `ADMIN_API_TOKEN` as the sole admin secret for internal/admin maintenance
  endpoints.
- Switched admin token comparison to `hmac.compare_digest` while preserving
  fail-closed behavior: missing or invalid token returns `401`, absent
  `ADMIN_API_TOKEN` returns `503`.
- Hardened API JWT auth to accept only Supabase ES256 tokens verified through
  JWKS with `algorithms=["ES256"]` and `audience="authenticated"`.
- Removed the `SUPABASE_JWT_SECRET` / HS256 fallback from API auth.
- Updated `python-jose[cryptography]` in `requirements.txt` to `3.5.0`.

## Validation

- Added focused tests for `/api/internal/admin/ner-health`, `/api/internal/sync`,
  admin token failure modes, and ES256-only JWT decoding.
- `packages/api/uv.lock` already resolved `python-jose` to `3.5.0`, so no lock
  regeneration was needed for this maintenance change.

Recommended commands:

```bash
cd packages/api
python -m pytest -q tests/test_auth_jwt_algorithms.py tests/routers/test_internal_ner_health.py tests/routers/test_admin_cohorts.py
python -m pytest -v
curl -i -X POST http://localhost:8080/api/internal/sync
```

Expected local curl result without `X-Admin-Token`: `401` when
`ADMIN_API_TOKEN` is configured, or `503` when it is absent. It must not return
`200`.

## Exclusions

- RLS migrations and schema files are intentionally excluded and handled
  separately.
- SSRF/url-safety work from the original workspace branch is intentionally
  excluded from this PR.
- Existing email-confirmation fallback behavior in `dependencies.py` is
  unchanged.
