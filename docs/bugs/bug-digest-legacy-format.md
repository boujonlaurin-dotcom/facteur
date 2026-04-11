# Bug: Digest reverts to legacy flat_v1 format

## Symptom
User sees the old legacy digest layout ("N°1 / SUJET TENDANCE / Couvert par X sources") instead of the current editorial format, even though the digest was correctly generated earlier in the day.

## Root Cause
Multiple code paths can **destroy a valid editorial_v1 digest** and replace it with `flat_v1`:

1. **Background regen with `force_regenerate=True`** (`digest_service.py:134-148`): Deletes the existing editorial_v1 digest before attempting regeneration. If the editorial pipeline is degraded at that moment, the cascade falls through to `flat_v1`.

2. **Build crash deletes digest** (`digest_service.py:384-394`): If `_build_editorial_response()` throws, the existing digest is deleted and regeneration is attempted. Same cascade risk.

3. **Emergency fallback hardcodes flat_v1** (`digest_service.py:547-559, 1147`): When both editorial and topics pipelines fail, emergency candidates are stored as `flat_v1`.

4. **Yesterday fallback ignores format** (`digest_service.py:400-425`): Serves yesterday's digest regardless of its `format_version`, potentially serving `flat_v1`.

## Fix
- Background regen: skip if editorial_v1/topics_v1 already exists
- Build crash: preserve existing digest, don't delete on render failure
- Emergency fallback: wrap items in topics_v1 format
- Yesterday fallback: skip flat_v1 digests

## Files Modified
- `packages/api/app/services/digest_service.py`
