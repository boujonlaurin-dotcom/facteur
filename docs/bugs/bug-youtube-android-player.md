# Bug: YouTube Player Error 152-4 on Android

## Status: FIXED

## Problem
YouTube videos show "This video is unavailable - Error code: 152 - 4" on Android.
The player works fine on Web but fails on Android devices.

## Root Cause
The `youtube_player_flutter` package (v9.1.1) uses the **deprecated Android YouTube Player API**.
Error 152-4 is an API restriction error from this deprecated player.

## Solution
Replaced `youtube_player_flutter` with `youtube_player_iframe` for all platforms.
The iframe-based approach uses a WebView under the hood and works reliably on both Android and Web.

### Changes
- **`apps/mobile/pubspec.yaml`**: Removed `youtube_player_flutter` dependency
- **`apps/mobile/lib/features/detail/widgets/youtube_player_widget.dart`**: Unified player to use `youtube_player_iframe` for all platforms (removed platform-specific branching with `kIsWeb`)

## Files Modified
- `apps/mobile/pubspec.yaml`
- `apps/mobile/lib/features/detail/widgets/youtube_player_widget.dart`

## Verification
1. Open the app on an Android device
2. Navigate to a YouTube video article in the digest/feed
3. Verify the video plays correctly without Error 152-4
4. Verify progress tracking still works (25%, 50%, 75%, 100% milestones)
5. Verify the Web version still works as before
