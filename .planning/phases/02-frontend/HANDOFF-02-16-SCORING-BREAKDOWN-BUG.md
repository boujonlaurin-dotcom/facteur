# GSD Hand-Off: Critical Scoring Breakdown Bug

## Problem Statement

**Status:** Production-blocking bug  
**Impact:** "Pourquoi cet article?" feature completely non-functional  
**User Experience:** Users see "Information non disponible" instead of scoring transparency

## Evidence

### Frontend Logs (Critical)
```
DigestItem(contentId: 8e09c3be-..., 
  reason: "Sélection de la rédaction",
  recommendationReason: null  <-- ALWAYS NULL
)
```

All 5 items in the digest have `recommendationReason: null` even though:
- Digest was generated at `2026-02-06 17:42:05` (after plan 02-11)
- Backend logging (from 02-15) shows breakdown IS being generated and stored
- The `reason` string (legacy field) is present: `"Sélection de la rédaction"`

## Root Cause Analysis

The breakdown data exists in the database (verified by 02-15 logging), but the **API response does not include `recommendation_reason`**.

Probable causes:
1. **Pydantic schema** - `DigestItem` schema may not include `recommendation_reason` field
2. **Response serialization** - `_build_digest_response()` may not be adding `recommendation_reason` to the response dict
3. **API router** - Response model may be excluding the field

## Investigation Path

### Step 1: Verify Pydantic Schema
File: `packages/api/app/schemas/digest.py`
- Check if `DigestItem` schema has `recommendation_reason: Optional[DigestRecommendationReason]` field
- Verify `DigestRecommendationReason` schema is properly defined

### Step 2: Verify Response Building
File: `packages/api/app/services/digest_service.py`
- Check `_build_digest_response()` method around line 500
- Verify `recommendation_reason` is being assigned to the response object
- The `DigestItem` Pydantic model (line ~520+) must receive `recommendation_reason`

### Step 3: Verify API Endpoint
File: `packages/api/app/routers/digest.py`
- Check GET `/api/digest` endpoint response model
- Ensure it returns the full `DigestResponse` with nested `DigestItem` including `recommendation_reason`

## Key Code Locations

### 1. Schema Definition
```python
# packages/api/app/schemas/digest.py
class DigestItem(BaseModel):
    # ... other fields ...
    recommendation_reason: Optional[DigestRecommendationReason] = Field(
        default=None, 
        description="Detailed scoring breakdown (new, full transparency)"
    )
```

### 2. Response Building
```python
# packages/api/app/services/digest_service.py ~line 520-545
items.append(DigestItem(
    content_id=content_id,
    # ... other fields ...
    reason=item_data["reason"],
    recommendation_reason=recommendation_reason,  # <-- MUST BE HERE
    is_read=action_state["is_read"],
    # ...
))
```

### 3. API Response
```python
# packages/api/app/routers/digest.py
@router.get("/api/digest", response_model=DigestResponse)
async def get_digest(...):
    # ...
    return digest_response  # Must include recommendation_reason
```

## Success Criteria

- [ ] API response includes `recommendation_reason` for each item
- [ ] `recommendation_reason` has `label`, `score_total`, and `breakdown` array
- [ ] Frontend receives non-null `recommendationReason`
- [ ] Personalization sheet shows "Pourquoi cet article?" with scoring details

## Files to Check

1. `packages/api/app/schemas/digest.py` - Pydantic schemas
2. `packages/api/app/services/digest_service.py` - Response building (line ~500-550)
3. `packages/api/app/routers/digest.py` - API endpoint

## Notes

- Backend logging from 02-15 confirms breakdown IS stored in database
- The issue is specifically in API response serialization
- Flutter models are correct (tested working with mock data)
- This is NOT a frontend issue - backend is not sending the field

## Quick Verification

Run this curl command to inspect raw API response:
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
  https://your-api/api/digest | jq '.items[0].recommendation_reason'
```

Expected: JSON object with breakdown  
Actual: `null`

## Related Plans

- 02-11: Backend scoring transparency (implemented)
- 02-12: Frontend UI (implemented)
- 02-15: Diagnostic logging (verified data IS stored)
- **02-16:** THIS PLAN - Fix API response serialization
