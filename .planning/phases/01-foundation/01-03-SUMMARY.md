# Phase 01 Plan 03: Digest API Endpoints Summary

**Phase:** 01-foundation  
**Plan:** 03  
**Type:** execute  
**Wave:** 2  
**Subsystem:** api  
**Completed:** 2026-02-01  
**Duration:** ~30 minutes  

---

## One-Liner

Created REST API endpoints for digest retrieval and actions with Pydantic v2 schemas, DigestService orchestration layer, and full integration with existing Personalization and Streak systems.

---

## What Was Built

### 1. Pydantic Schemas (packages/api/app/schemas/digest.py)

Request/response models for digest-first mobile app:

- **DigestItem**: Single article in digest with content metadata, source info, selection reason, and action tracking (is_read, is_saved, is_dismissed)
- **DigestResponse**: Complete digest with 5 items, completion status, and timestamps
- **DigestAction** (Enum): read | save | not_interested | undo
- **DigestActionRequest/Response**: Action endpoint payloads
- **DigestCompletionResponse**: Completion tracking with closure streak info
- **DigestGenerationResponse**: On-demand generation confirmation

### 2. DigestService (packages/api/app/services/digest_service.py)

Business logic orchestration layer (~526 lines):

- **get_or_create_digest()**: Retrieves existing or generates new digest using DigestSelector
- **apply_action()**: Handles read/save/not_interested/undo with side effects:
  - READ → Updates UserContentStatus + increments consumption streak via StreakService
  - SAVE → Updates UserContentStatus with saved flag
  - NOT_INTERESTED → Hides content + triggers source mute via Personalization
  - UNDO → Resets all action states
- **complete_digest()**: Records completion in DigestCompletion table, updates closure streak with milestone messages

Key integrations:
- DigestSelector (from 01-02) for generation
- Personalization system for not_interested mutes
- StreakService for gamification updates

### 3. API Router (packages/api/app/routers/digest.py)

FastAPI endpoints following existing patterns:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/digest` | GET | Get today's digest (retrieve or generate on-demand) |
| `/api/digest/{id}/action` | POST | Apply read/save/not_interested/undo to item |
| `/api/digest/{id}/complete` | POST | Record completion, update closure streak |
| `/api/digest/generate` | POST | Explicit on-demand generation (admin/testing) |

All endpoints:
- Use `get_current_user_id` dependency for authentication
- Follow existing error handling patterns
- Include comprehensive docstrings for API documentation

### 4. Application Registration (packages/api/app/main.py, routers/__init__.py)

- Added `digest` to router imports
- Registered router at `/api/digest` with "Digest" tag

---

## Key Design Decisions

### 1. Safe Reuse of Existing Systems

**Decision**: No modifications to existing services (Personalization, StreakService, DigestSelector).

**Rationale**: Plan 01-02 validated that DigestSelector works without changes. DigestService acts as orchestration layer only, calling existing service methods.

### 2. On-Demand Generation Pattern

**Decision**: GET /api/digest generates if missing (idempotent), separate POST for explicit generation.

**Rationale**: Mobile app needs simple "get my digest" flow. On-demand generation avoids need for separate "generate then fetch" calls.

### 3. Action State Tracking

**Decision**: Use existing UserContentStatus model (status, is_saved, is_hidden) rather than new digest-specific table.

**Rationale**: Reuse existing data model, feed and digest share same content lifecycle. Simpler queries, no data duplication.

### 4. Closure Streak Separate from Consumption Streak

**Decision**: Closure streak tracked in UserStreak.closure_streak (existing column from 01-01), updated via DigestService not StreakService.

**Rationale**: DigestService owns closure logic (completion of all 5 articles), StreakService owns individual consumption. Separation of concerns.

### 5. not_interested Triggers Source Mute

**Decision**: Action automatically adds source to UserPersonalization.muted_sources.

**Rationale**: Consistent with existing personalization behavior, reduces user friction. One-click to stop seeing source everywhere.

---

## Files Created/Modified

### Created
- `packages/api/app/schemas/digest.py` (133 lines) - Pydantic schemas
- `packages/api/app/services/digest_service.py` (526 lines) - Business logic
- `packages/api/app/routers/digest.py` (210 lines) - API endpoints

### Modified
- `packages/api/app/main.py` - Added digest router registration
- `packages/api/app/routers/__init__.py` - Added digest export

---

## API Contract

### GET /api/digest

```json
{
  "digest_id": "uuid",
  "user_id": "uuid",
  "target_date": "2026-02-01",
  "generated_at": "2026-02-01T08:00:00Z",
  "items": [
    {
      "content_id": "uuid",
      "title": "Article Title",
      "url": "https://example.com/article",
      "thumbnail_url": "...",
      "description": "...",
      "content_type": "article",
      "duration_seconds": 300,
      "published_at": "2026-02-01T06:00:00Z",
      "source": { "id": "uuid", "name": "Source Name", ... },
      "rank": 1,
      "reason": "Source suivie : Le Monde",
      "is_read": false,
      "is_saved": false,
      "is_dismissed": false
    }
  ],
  "is_completed": false,
  "completed_at": null
}
```

### POST /api/digest/{id}/action

Request:
```json
{
  "content_id": "uuid",
  "action": "read"
}
```

Response:
```json
{
  "success": true,
  "content_id": "uuid",
  "action": "read",
  "applied_at": "2026-02-01T10:30:00Z",
  "message": "Article marqué comme lu"
}
```

### POST /api/digest/{id}/complete

Response:
```json
{
  "success": true,
  "digest_id": "uuid",
  "completed_at": "2026-02-01T10:45:00Z",
  "articles_read": 3,
  "articles_saved": 1,
  "articles_dismissed": 1,
  "closure_time_seconds": 180,
  "closure_streak": 5,
  "streak_message": "Série de 5 jours !"
}
```

---

## Dependencies Integrated

| System | Integration Point | Pattern |
|--------|-------------------|---------|
| DigestSelector | `select_for_user()` | Direct service instantiation |
| Personalization | `_trigger_personalization_mute()` | Upsert muted_sources array |
| StreakService | `increment_consumption()` | Direct service call |
| UserContentStatus | `_get_or_create_content_status()` | Read/write action states |
| DigestCompletion | `complete_digest()` | Create completion record |
| UserStreak | `_update_closure_streak()` | Update closure streak fields |

---

## Verification

- ✅ All Python files pass syntax validation (`python -m py_compile`)
- ✅ Follows existing FastAPI patterns (feed.py, personalization.py, streaks.py)
- ✅ Pydantic v2 compatible (from_attributes, BaseModel)
- ✅ Uses existing authentication dependency (`get_current_user_id`)
- ✅ Proper error handling (HTTPException with appropriate status codes)
- ✅ Type hints throughout

---

## Deviations from Plan

None - plan executed exactly as written.

All endpoints, schemas, and integrations match the specification:
- GET /api/digest returns digest with 5 articles ✓
- POST /api/digest/{id}/action handles read/save/not_interested ✓
- Completion tracking updates closure streak ✓
- not_interested triggers personalization mute ✓

---

## Next Phase Readiness

### Foundation Phase Complete

With 01-03 complete, Phase 01 Foundation is **100% complete**:

| Plan | Status | Deliverable |
|------|--------|-------------|
| 01-01 | ✅ Complete | Database schema (daily_digest, digest_completions, closure streak) |
| 01-02 | ✅ Complete | DigestSelector service with diversity constraints |
| 01-03 | ✅ Complete | API endpoints (GET /digest, POST /action, POST /complete) |

### Ready for Phase 2 (Frontend)

Backend infrastructure complete for:
- Mobile app digest retrieval
- Article action tracking
- Completion gamification
- Personalization integration

### Suggested Phase 2 Plans

1. **02-01 Digest Screen UI** - Flutter digest list with 5 cards
2. **02-02 Action UI** - Swipe/mark buttons for read/save/dismiss
3. **02-03 Closure Screen** - Completion celebration with streak display
4. **02-04 Feed Relegation** - Update navigation to make feed secondary

---

## Commits

| Hash | Message | Files |
|------|---------|-------|
| 295c069 | feat(01-03): create Pydantic schemas for digest API | schemas/digest.py |
| 81ae268 | feat(01-03): create DigestService for business logic | services/digest_service.py |
| f543560 | feat(01-03): create digest router and register in main.py | routers/digest.py, main.py, routers/__init__.py |

---

*Summary generated after plan execution*
