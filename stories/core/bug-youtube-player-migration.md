# Story: Migration youtube_player_iframe + Fix Issue 4 (2x speed)

**Type**: Bug Fix / Migration
**Agent**: @dev (Agent A)
**Branch**: `boujonlaurin-dotcom/dev-youtube-player-migration`
**Parent Bug**: `docs/bugs/bug-youtube-ux-e2e-regressions.md`
**Date**: 2026-03-30

---

## Problem

PR #302 introduced YouTube UX features but E2E tests revealed `youtube_player_flutter` is fundamentally limiting:
- Issue 4: `setPlaybackRate()` not available on mobile — 2x speed is visual-only
- Issues 1, 3: No aspect ratio control, no play state events on mobile

The widget currently has a dual-package architecture (`youtube_player_flutter` for mobile, `youtube_player_iframe` for web) that doubles maintenance and limits mobile capabilities.

## Solution

Unify on `youtube_player_iframe` for ALL platforms. This package already works on mobile via `webview_flutter` and supports all needed APIs natively.

## Technical Approach

1. Remove `youtube_player_flutter` from `pubspec.yaml`
2. Rewrite `youtube_player_widget.dart` — single code path, no `kIsWeb` fork
3. Expose `aspectRatio` + `onPlayStateChanged` params for Agent C
4. `setPlaybackRate()` now works on all platforms (fixes Issue 4)

## Tasks

- [x] Create story doc
- [x] Update `pubspec.yaml` — remove `youtube_player_flutter`
- [x] Rewrite `youtube_player_widget.dart`
- [x] Verify build (`flutter analyze`) — 0 new errors
- [x] Verify no remaining `youtube_player_flutter` references — clean

## Files Modified

- `apps/mobile/pubspec.yaml`
- `apps/mobile/lib/features/detail/widgets/youtube_player_widget.dart`

## Changelog

| Date | Change |
|------|--------|
| 2026-03-30 | Story created, implementation started |
