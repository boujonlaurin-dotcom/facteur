---
phase: 02-frontend
plan: 06
type: gap_closure
status: complete
completed: 2026-02-01T23:25:00Z
duration: 3min
---

# Phase 02 Plan 06: Fix JSON Serialization Crash (Gap Closure)

**Issue:** App crashes after login due to JSON field name mismatch  
**Root Cause:** API returns `logo_url` (snake_case) but Flutter model expects `logoUrl` (camelCase) without proper `@JsonKey` mapping  
**Fix:** Added `@JsonKey` annotations to SourceMini model and regenerated Freezed code

---

## Changes Made

### File: `apps/mobile/lib/features/digest/models/digest_models.dart`

**Before (lines 9-19):**
```dart
@freezed
class SourceMini with _$SourceMini {
  const factory SourceMini({
    required String name,
    String? logoUrl,  // ❌ Looks for 'logoUrl' in JSON
    String? theme,
  }) = _SourceMini;
```

**After (lines 9-21):**
```dart
@freezed
class SourceMini with _$SourceMini {
  const factory SourceMini({
    @JsonKey(name: 'id') String? id,  // ✅ Maps API 'id' field
    required String name,
    @JsonKey(name: 'logo_url') String? logoUrl,  // ✅ Maps API 'logo_url' to Flutter 'logoUrl'
    @JsonKey(name: 'type') String? type,  // ✅ Maps API 'type' field
    String? theme,
  }) = _SourceMini;
```

### Regenerated Files

Ran `flutter pub run build_runner build --delete-conflicting-outputs` to regenerate:
- `digest_models.freezed.dart` - Updated constructor signatures
- `digest_models.g.dart` - Updated JSON serialization with proper field mappings

---

## Verification

### Static Analysis
```bash
$ flutter analyze lib/features/digest/models/digest_models.dart
Analyzing digest_models.dart...
No issues found!
```

### Build Runner Output
```
[INFO] Succeeded after 18.0s with 894 outputs (1828 actions)
```

✅ All Freezed models regenerated successfully  
✅ JSON serialization now correctly maps snake_case → camelCase  
✅ No analysis errors  

---

## Root Cause Explanation

**The Problem:**
Flutter's `json_serializable` package does NOT automatically convert between snake_case and camelCase by default. When the API returns:
```json
{
  "source": {
    "name": "Le Monde",
    "logo_url": "https://..."
  }
}
```

The generated code was looking for a field literally named `logoUrl` in the JSON, but the API sends `logo_url`. Result: `logoUrl` was always null, causing null pointer exceptions when the UI tried to display the logo.

**The Solution:**
`@JsonKey(name: 'logo_url')` tells the generated code: "When you see `logo_url` in the JSON, put it in the `logoUrl` field."

---

## Ready for Retest

**To verify the fix:**
1. Rebuild the app
2. Log in with test account
3. App should now load digest without crashing
4. Article cards should display source logos correctly

**Related:** See updated UAT.md for test checklist

---

## Technical Notes

**API Schema vs Flutter Model:**

| API Field | Flutter Field | Status |
|-----------|---------------|--------|
| `id` | `id` | ✅ Added @JsonKey |
| `name` | `name` | ✅ Same name, no mapping needed |
| `logo_url` | `logoUrl` | ✅ Added @JsonKey |
| `type` | `type` | ✅ Added @JsonKey |
| `theme` | `theme` | ✅ Same name, no mapping needed |

**Always remember:** When API uses snake_case and Flutter uses camelCase, you MUST add `@JsonKey` annotations for proper serialization.
