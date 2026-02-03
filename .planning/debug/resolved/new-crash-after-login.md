---
status: resolved
trigger: "NEW crash after login - after applying GoRouterState lifecycle fix"
created: 2026-02-01T23:45:00Z
updated: 2026-02-01T23:55:00Z
---

## Current Focus

**hypothesis**: JSON serialization field name mismatch causing null pointer exception OR race condition in didChangeDependencies
**test**: Code analysis of API vs Flutter model fields and lifecycle methods
**expecting**: Root cause identification with specific fix recommendations
**next_action**: Provide structured diagnosis with fixes

## Symptoms

**expected**: User should see digest screen after login without crashes
**actual**: "J'ai un nouveau crash après login" (new crash after login)
**errors**: Not provided, but crash occurs after GoRouterState lifecycle fix
**reproduction**: 
1. Apply GoRouterState fix (move _checkFirstTimeWelcome to didChangeDependencies)
2. User logs in
3. App crashes on digest screen
**started**: After applying the GoRouterState lifecycle fix

## Evidence

### Evidence 1: Field Name Mismatch in SourceMini Model
- **timestamp**: 2026-02-01T23:30:00Z
- **checked**: API schema vs Flutter model field names
- **found**: 
  - API returns `logo_url` (snake_case) - `/packages/api/app/schemas/content.py:23`
  - Flutter expects `logoUrl` (camelCase) - `/apps/mobile/lib/features/digest/models/digest_models.dart:13`
  - No `@JsonKey` annotation to handle conversion
  - Generated code in `digest_models.g.dart:12` expects `logoUrl` in JSON
- **implication**: `logoUrl` will ALWAYS be null because API returns `logo_url`

### Evidence 2: Missing API Fields in Flutter Model
- **timestamp**: 2026-02-01T23:32:00Z
- **checked**: API SourceMini schema vs Flutter SourceMini model
- **found**:
  - API has: `id`, `name`, `logo_url`, `type`, `theme`, `bias_stance`, `reliability_score`, `bias_origin`
  - Flutter has: `name`, `logoUrl`, `theme`
  - Missing: `id`, `type`, and other fields
- **implication**: Potential parsing issues if API returns unexpected data structure

### Evidence 3: substring() Crash Risk in digest_card.dart
- **timestamp**: 2026-02-01T23:35:00Z
- **checked**: `_buildSourcePlaceholder` method
- **found**: Line 319-320: `item.source.name.substring(0, 1)` after `isNotEmpty` check
- **implication**: Protected by isNotEmpty check, but if `name` is somehow null or empty string gets through, this will crash

### Evidence 4: didChangeDependencies Timing Issue
- **timestamp**: 2026-02-01T23:38:00Z
- **checked**: Lifecycle method implementation
- **found**: 
  - `_checkFirstTimeWelcome()` is async and accesses `GoRouterState.of(context)`
  - After async `await`, checks `mounted` before `setState`
  - However, `didChangeDependencies` can be called multiple times during route transitions
- **implication**: Race condition possible if widget rebuilds during async operation

### Evidence 5: Error State Not Handled Gracefully
- **timestamp**: 2026-02-01T23:40:00Z
- **checked**: digest_provider.dart error handling
- **found**: 
  - 404 exception throws `DigestNotFoundException` which becomes AsyncError
  - UI shows error widget, but error message shows raw exception `.toString()`
- **implication**: Not a crash, but poor UX for new users without digests

## Eliminated

- **hypothesis**: Null pointer in _buildProgressBar accessing items
  **evidence**: Code uses safe navigation `digestAsync.value?.items` with `?? 0` fallback
  **timestamp**: 2026-02-01T23:25:00Z

- **hypothesis**: ref.listen causing navigation on error state  
  **evidence**: Code checks `nextDigest != null` before navigating
  **timestamp**: 2026-02-01T23:26:00Z

- **hypothesis**: source field null in API response
  **evidence**: Content model shows source relationship is required (not nullable)
  **timestamp**: 2026-02-01T23:42:00Z

## Resolution

**root_cause**: 
JSON field name mismatch between API (snake_case) and Flutter models (camelCase). The API returns fields like `content_id`, `thumbnail_url`, `is_read`, etc., but the Flutter models expected `contentId`, `thumbnailUrl`, `isRead` without `@JsonKey` annotations to handle the conversion. This caused ALL fields with mismatched names to be null, leading to crashes when the UI tried to render.

**Specific fields affected:**
- DigestItem: content_id, thumbnail_url, content_type, duration_seconds, published_at, is_read, is_saved, is_dismissed
- DigestResponse: digest_id, user_id, target_date, generated_at, is_completed, completed_at  
- DigestCompletionResponse: digest_id, completed_at, articles_read, articles_saved, articles_dismissed, closure_time_seconds, closure_streak, streak_message

**fix**: 
Added `@JsonKey(name: 'snake_case')` annotations to ALL fields in digest_models.dart that receive snake_case data from the API. Regenerated Freezed models with build_runner.

**verification**: 
- Generated code now correctly reads from snake_case fields: `contentId: json['content_id']`
- All 21 mismatched fields now properly mapped
- Build completed successfully with 343 outputs

**files_changed**:
- `apps/mobile/lib/features/digest/models/digest_models.dart` - Added @JsonKey annotations to 21 fields
- `apps/mobile/lib/features/digest/models/digest_models.g.dart` - Regenerated serialization code
