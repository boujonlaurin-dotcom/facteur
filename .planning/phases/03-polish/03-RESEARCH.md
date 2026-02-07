# Phase 3: Polish - Research

**Researched:** 2026-02-08
**Domain:** Unified content analytics, push notifications, async testing, SQLAlchemy performance
**Confidence:** HIGH (codebase analysis) / MEDIUM (industry patterns) / HIGH (libraries)

## Summary

This phase covers four distinct technical domains: (1) unified content interaction analytics, (2) local push notifications, (3) DigestSelector unit testing, and (4) SQLAlchemy eager loading optimization. The user's core directive is to build a **single content interaction event system** that treats feed and digest as two surfaces of the same data, following GAFAM industry patterns.

Research investigated how major platforms (YouTube, Meta/Facebook, Spotify) model content interaction signals, distinguishing between implicit and explicit feedback. The key finding is that the industry standard is a **multi-signal weighted scoring model** where each interaction type (read, save, dismiss, pass/skip) carries a weight, and implicit negative signals (seen-but-skipped) are treated as weaker than explicit negatives (actively dismissed). The existing Facteur `analytics_events` table with its JSONB `event_data` column is well-suited for the unified `content_interaction` event — no schema migration needed for the table itself, only new event types and richer payloads.

For notifications, `flutter_local_notifications` v20.0.0 is current (published Jan 2026) and is a Flutter Favorite. The scheduled notification API is well-suited for the "Digest prêt" notification at 8am. For testing, the existing test patterns in `digest_selector_test.py` are solid — they use `AsyncMock(spec=AsyncSession)` and Mock factories, which is the correct approach for unit-testing async SQLAlchemy services. For performance, `selectinload` is already correctly used throughout the codebase and is the recommended approach for Facteur's use case per SQLAlchemy 2.0 official documentation.

**Primary recommendation:** Implement a single `content_interaction` event type with `action` enum (`read`, `save`, `dismiss`, `pass`) and `surface` enum (`feed`, `digest`), leveraging the existing `analytics_events` JSONB table. Use time-in-viewport thresholds for implicit pass detection.

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `flutter_local_notifications` | ^20.0.0 | Local push notifications (iOS/Android) | Flutter Favorite, 7.2k likes, cross-platform |
| SQLAlchemy | 2.0.25 (in requirements.txt) | Async ORM with eager loading | Already in stack, `selectinload` recommended |
| pytest-asyncio | 0.23.5 | Async test support | Already in stack, required for service testing |
| pytest (unittest.mock) | 8.0.0 | Mocking async sessions | Already in stack, `AsyncMock(spec=AsyncSession)` pattern established |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `timezone` (Flutter) | built-in | Timezone handling for 8am notification | Scheduling daily notification |
| `permission_handler` | ^11.x | Request notification permissions (Android 13+) | First notification setup |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `flutter_local_notifications` | Firebase Cloud Messaging (FCM) | FCM requires server infrastructure, overkill for local "digest ready" notification. User decision: local notifications for MVP. |
| Custom analytics service | Mixpanel/Amplitude SDK | External dependency, cost, data ownership. User decision: extend existing AnalyticsService. |

**Installation (Mobile):**
```yaml
# pubspec.yaml additions
dependencies:
  flutter_local_notifications: ^20.0.0
```

**Installation (Backend):**
No new dependencies needed — extend existing `AnalyticsService` and `analytics_events` table.

## Architecture Patterns

### Pattern 1: Unified Content Interaction Event (GAFAM-Aligned)

**What:** One event type `content_interaction` for all content actions across all surfaces. This follows the industry pattern where platforms track a single interaction record per user-content pair, with metadata distinguishing context.

**When to use:** Every time a user interacts with content on any surface (digest or feed).

**Industry basis (MEDIUM confidence):**
- **YouTube Recommendations (Google, 2016):** Two-stage system where candidate generation and ranking both consume the same pool of user interaction signals. Interactions are modeled as `(user, video, context)` tuples regardless of how the video was surfaced. Watch time is the primary signal, with implicit signals (impressions without clicks) as negative training data.
- **Meta News Feed Ranking (2021):** Multiple prediction models score content using observable signals (like, comment, share, time spent). Each prediction Yijtk is weighted into a single value Vijt. The key insight: "actions a person rarely engages in automatically get a minimal role in ranking, as Yijtk for that event is very low."
- **Spotify Intent Modeling (2022):** Users modeled by intent signals across surfaces. Actions are classified by signal strength rather than by surface.

**Facteur adaptation:** 

```python
# Event schema for content_interaction
{
    "event_type": "content_interaction",
    "event_data": {
        "action": "read",        # enum: read, save, dismiss, pass
        "surface": "digest",     # enum: feed, digest
        "content_id": "uuid",
        "source_id": "uuid",
        "topics": ["tech", "AI"],
        "atomic_themes": null,   # nullable, forward-compatible for Camembert
        "position": 2,           # position in digest (1-5) or feed rank
        "time_spent_seconds": 45,
        "session_id": "uuid"
    }
}
```

### Pattern 2: Implicit vs Explicit Signal Classification

**What:** Classify user signals by strength and intent, following the GAFAM pattern of weighting signals differently.

**Industry pattern (MEDIUM confidence):**

| Signal Type | Examples | Weight Class | Industry Approach |
|-------------|----------|-------------|-------------------|
| **Explicit Positive** | Save/bookmark, share | Strongest positive | YouTube: "like" is strongest. Meta: "share" weighted highest in meaningful interactions |
| **Explicit Positive (consumption)** | Read (clicked + time spent) | Strong positive | YouTube: watch time is primary metric. Meta: "time spent" as ranking signal |
| **Implicit Positive** | Seen (impression) | Weak/neutral | YouTube: impression without click = weak negative. Meta: impression counted for pass-through |
| **Explicit Negative** | Dismiss ("not interested") | Strong negative | YouTube: "not interested" directly penalizes. Meta: "hide" reduces similar content |
| **Implicit Negative (Pass)** | Seen but skipped (no action within threshold) | Moderate negative | YouTube: impression without click after exposure threshold. This is the key research question |

**Pass detection thresholds (MEDIUM confidence — synthesized from multiple sources):**

For Facteur's digest context (sequential card-based UI where user explicitly advances):
- **Digest "pass":** User advances to next card without any action (read/save/dismiss). This is EXPLICIT because the digest UI forces a decision per card — it's not a scroll-past.
- **Feed "pass":** Content was in viewport for ≥2 seconds but user scrolled past without interaction. This is IMPLICIT and should carry a lighter penalty than digest pass.

**Recommended penalty weights:**

| Action | Signal Weight | Rationale |
|--------|--------------|-----------|
| `read` (>30s time spent) | +1.0 (strong positive) | Deep engagement |
| `read` (<10s time spent) | +0.3 (weak positive) | Clicked but bounced — still showed interest |
| `save` | +1.5 (strongest positive) | Explicit intent to return |
| `dismiss` | -1.0 (strong negative) | Active rejection |
| `pass` (digest) | -0.5 (moderate negative) | Explicit skip in sequential UI |
| `pass` (feed, >2s viewport) | -0.2 (weak negative) | Implicit skip, may have been scroll momentum |

These weights are for FUTURE recommendation tuning (deferred). This phase only RECORDS the events; it does not act on them. The schema should capture enough data for future scoring.

### Pattern 3: Session-Level Events (Surface-Specific)

**What:** Digest sessions and feed sessions are tracked separately with different shapes, but both reference the unified `content_interaction` events.

```python
# Digest session completion event
{
    "event_type": "digest_session",
    "event_data": {
        "session_id": "uuid",
        "digest_date": "2026-02-08",
        "articles_read": 3,
        "articles_saved": 1,
        "articles_dismissed": 0,
        "articles_passed": 1,
        "total_time_seconds": 180,
        "closure_achieved": true,
        "streak": 5
    }
}

# Feed session event
{
    "event_type": "feed_session",
    "event_data": {
        "session_id": "uuid",
        "scroll_depth_percent": 45.5,
        "items_viewed": 12,
        "items_interacted": 3,
        "total_time_seconds": 120
    }
}
```

### Pattern 4: Flutter Local Notification Scheduling

**What:** Schedule a daily notification at 8am Europe/Paris when digest is ready.

**Source:** flutter_local_notifications v20.0.0 pub.dev documentation (HIGH confidence)

```dart
// Initialization (in main.dart or notification service)
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

final DarwinInitializationSettings initializationSettingsDarwin =
    DarwinInitializationSettings();

final InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsDarwin,
);

await flutterLocalNotificationsPlugin.initialize(
    settings: initializationSettings,
    onDidReceiveNotificationResponse: onNotificationTapped,
);

// Schedule daily at 8am
await flutterLocalNotificationsPlugin.zonedSchedule(
    id: 0,
    title: 'Votre digest est prêt !',
    body: '5 articles sélectionnés pour vous',
    scheduledDate: _nextInstanceOf8AM(),
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    matchDateTimeComponents: DateTimeComponents.time,  // daily repeat
    notificationDetails: notificationDetails,
);
```

**Key API change in v20:** The `initialize` method now uses named parameter `settings:` instead of positional. The `zonedSchedule` also uses named parameters (`id:`, `title:`, `body:`, `scheduledDate:`). Older code examples using positional parameters will not compile with v20.

### Pattern 5: DigestSelector Unit Testing with Mocked Sessions

**What:** Test async service methods that depend on SQLAlchemy `AsyncSession` using `unittest.mock.AsyncMock`.

**Established pattern in codebase (HIGH confidence — from `digest_selector_test.py`):**

```python
@pytest.fixture
def mock_session():
    """Mock de session SQLAlchemy async."""
    return AsyncMock(spec=AsyncSession)

@pytest.fixture
def selector(mock_session, mock_rec_service):
    """Instance de DigestSelector avec mocks."""
    selector = DigestSelector(mock_session)
    selector.rec_service = mock_rec_service  # Override injected dependency
    return selector

# For testing methods that call session.execute():
async def mock_execute(stmt):
    mock_result = Mock()
    mock_result.scalars.return_value.all.return_value = fake_contents
    return mock_result

selector.session.execute = AsyncMock(side_effect=mock_execute)
```

**Key insight from existing tests:** The `_select_with_diversity` method is purely synchronous (no async, no DB) — it's the easiest to test directly. The async methods (`_build_digest_context`, `_get_candidates`, `_score_candidates`) require mocking `session.execute` return values.

### Pattern 6: SQLAlchemy selectinload vs joinedload

**What:** Choose the right eager loading strategy for Content → Source relationships.

**Source:** SQLAlchemy 2.0 official documentation (HIGH confidence)

**Recommendation: Use `selectinload` (already in use)**

| Strategy | How It Works | Best For | Avoid When |
|----------|-------------|----------|------------|
| `selectinload` | Emits second SELECT with `WHERE id IN (...)` | Collections and many-to-one refs. Default recommendation. | Composite primary keys on SQL Server |
| `joinedload` | Adds LEFT OUTER JOIN to main query | Simple many-to-one scalars where you always need the related object | Collections (causes row multiplication, requires `.unique()`) |
| `subqueryload` | Emits second SELECT with subquery wrapping original query | Legacy, replaced by `selectinload` in most cases | Generally avoided in new code |

**From SQLAlchemy docs:** "In most cases, selectin loading is the most simple and efficient way to eagerly load collections of objects."

**Current codebase pattern (verified):** All digest/recommendation services already use `selectinload(Content.source)` which is correct. The `recommendation_service.py` uses `joinedload` for `UserProfile.interests` and `UserProfile.preferences` — this is also correct since those are loaded once per user query.

**Performance optimization for POLISH-04:**
```python
# Current pattern (already correct):
select(Content).options(selectinload(Content.source)).where(...)

# For chained loading (Content → Source needed for scoring):
select(Content).options(
    selectinload(Content.source)  # Batched IN query for sources
).where(Content.published_at >= since)

# For user profile (loaded once, small collections):
select(UserProfile).options(
    selectinload(UserProfile.interests),   # Few interests per user
    selectinload(UserProfile.preferences)  # Few prefs per user
).where(UserProfile.user_id == user_id)
```

### Anti-Patterns to Avoid
- **Separate event types per surface:** Don't create `digest_read` and `feed_read` as separate event types. Use one `content_interaction` with `surface` field. The user was explicit about this.
- **Lazy loading in async context:** SQLAlchemy async mode does not support implicit lazy loading. Always use explicit `selectinload`/`joinedload`. Accessing an unloaded relationship in async will raise `MissingGreenlet` error.
- **Committing inside hot loops:** The current `AnalyticsService.log_event()` calls `await self.session.commit()` after each event. For batch analytics (e.g., 5 digest interactions), consider batching or using `flush()` instead of `commit()` per event.
- **Mutable default in SQLAlchemy model:** The `AnalyticsEvent.event_data` has `default={}` — this is a mutable default antipattern. Should be `default_factory=dict` or use `server_default` only.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Local notifications | Custom platform channels | `flutter_local_notifications` v20 | Handles iOS/Android differences, permission requests, scheduling, background wakeup |
| Notification permissions | Manual permission request code | `flutter_local_notifications` built-in `requestNotificationsPermission()` | Android 13+ requires runtime permission, plugin handles this |
| Time zone scheduling | Manual UTC offset calculation | `flutter_local_notifications` `zonedSchedule` + `timezone` package | Daylight saving time edge cases are handled |
| Event schema validation | Manual dict validation | Pydantic schemas for event payloads | Validate `action`, `surface`, required fields before storing |
| N+1 query prevention | Manual query joining | SQLAlchemy `selectinload()` | Batches related object loading automatically |

**Key insight:** The analytics event infrastructure already exists. Don't rebuild `analytics_events` table — extend the event types and payload structure. The JSONB `event_data` column is flexible enough for the new unified schema.

## Common Pitfalls

### Pitfall 1: Analytics Event Explosion
**What goes wrong:** Firing analytics events on every scroll frame or viewport change creates thousands of events per session.
**Why it happens:** Treating implicit signals (scroll past) the same as explicit signals (button tap).
**How to avoid:** Debounce viewport tracking. Fire `pass` events only when user explicitly advances (digest: tap "next") or after viewport dwell time threshold (feed: >2 seconds in viewport without interaction, fire once per content item).
**Warning signs:** `analytics_events` table growing faster than expected, API latency on event endpoint.

### Pitfall 2: flutter_local_notifications v20 Breaking Changes
**What goes wrong:** Code compiles but notifications don't fire or crash at runtime.
**Why it happens:** v20 changed to named parameters (`settings:`, `id:`, `title:`, `body:`, `scheduledDate:`). Old positional-parameter examples from blogs/tutorials won't work. Also requires Android Gradle AGP 8.6.0+ with desugaring enabled.
**How to avoid:** Follow the pub.dev README exactly for v20. Enable desugaring in `build.gradle`. Set `compileSdk` to 35+.
**Warning signs:** `MissingPluginException` or silent notification failure on Android.

### Pitfall 3: Android Notification Permission (API 33+)
**What goes wrong:** Notifications silently fail on Android 13+ because permission wasn't requested.
**Why it happens:** Android 13 introduced runtime notification permission (`POST_NOTIFICATIONS`). Apps must request it explicitly.
**How to avoid:** Call `requestNotificationsPermission()` at an appropriate UX moment (e.g., after onboarding, not on first launch). Handle the case where user denies.
**Warning signs:** Notifications work on iOS but not on Android 13+ devices.

### Pitfall 4: Async Mock Session Return Value Mismatch
**What goes wrong:** Tests pass but test a different code path than production, or `AttributeError` on mock return values.
**Why it happens:** SQLAlchemy `session.execute()` returns a `Result` object, and calling `.scalars().all()` or `.scalar_one_or_none()` on it requires the mock chain to be set up precisely.
**How to avoid:** Use the established pattern from `digest_selector_test.py`: mock `execute` with a side_effect function that returns a Mock with the correct `.scalars().all()` or `.scalar_one_or_none()` chain.
**Warning signs:** Tests pass but actual DB queries fail differently.

### Pitfall 5: Existing Test Signature Drift
**What goes wrong:** Tests in `digest_selector_test.py` unpack 3 values (`content, score, reason`) from `_select_with_diversity` but the method now returns 4 values (`content, score, reason, breakdown`).
**Why it happens:** The method was updated to include `breakdown` in its return tuple but some tests weren't updated.
**How to avoid:** When writing new tests, use the current 4-tuple signature. Fix existing tests that use the 3-tuple unpacking.
**Warning signs:** `ValueError: too many values to unpack` in existing tests.

### Pitfall 6: iOS Notification Configuration
**What goes wrong:** Notifications work in debug but fail in release builds.
**Why it happens:** Missing `UNUserNotificationCenter.current().delegate = self` in AppDelegate.swift.
**How to avoid:** Follow the iOS setup section of flutter_local_notifications README exactly. Add delegate assignment in AppDelegate.swift.
**Warning signs:** Notification tap callbacks don't fire on iOS.

## Code Examples

### Unified Content Interaction Event — Backend Schema

```python
# packages/api/app/schemas/analytics.py
# Source: Codebase analysis + GAFAM pattern synthesis

from enum import Enum
from pydantic import BaseModel, Field
from typing import Optional
from uuid import UUID


class InteractionAction(str, Enum):
    """Actions possibles sur un contenu."""
    READ = "read"
    SAVE = "save"
    DISMISS = "dismiss"
    PASS = "pass"


class InteractionSurface(str, Enum):
    """Surface d'interaction."""
    FEED = "feed"
    DIGEST = "digest"


class ContentInteractionPayload(BaseModel):
    """Payload pour un événement content_interaction.
    
    Schema unifié suivant les patterns GAFAM:
    - Un seul type d'événement pour toutes les interactions contenu
    - Le champ 'surface' distingue le contexte
    - Forward-compatible avec atomic_themes (Camembert)
    """
    action: InteractionAction
    surface: InteractionSurface
    content_id: UUID
    source_id: UUID
    topics: list[str] = Field(default_factory=list)
    atomic_themes: list[str] | None = None  # Forward-compatible for Camembert
    position: int | None = None  # 1-5 for digest, rank for feed
    time_spent_seconds: int = 0
    session_id: str | None = None

    class Config:
        from_attributes = True
```

### Unified Content Interaction Event — Mobile Service

```dart
// apps/mobile/lib/core/services/analytics_service.dart
// Extend existing AnalyticsService with unified tracking

/// Track a content interaction (unified across feed & digest)
Future<void> trackContentInteraction({
  required String action,     // read, save, dismiss, pass
  required String surface,    // feed, digest
  required String contentId,
  required String sourceId,
  List<String> topics = const [],
  int? position,
  int timeSpentSeconds = 0,
}) async {
  await _logEvent('content_interaction', {
    'session_id': _sessionId,
    'action': action,
    'surface': surface,
    'content_id': contentId,
    'source_id': sourceId,
    'topics': topics,
    'atomic_themes': null,  // Forward-compatible
    'position': position,
    'time_spent_seconds': timeSpentSeconds,
  });
}

/// Track digest session completion
Future<void> trackDigestSession({
  required String digestDate,
  required int articlesRead,
  required int articlesSaved,
  required int articlesDismissed,
  required int articlesPassed,
  required int totalTimeSeconds,
  required bool closureAchieved,
  required int streak,
}) async {
  await _logEvent('digest_session', {
    'session_id': _sessionId,
    'digest_date': digestDate,
    'articles_read': articlesRead,
    'articles_saved': articlesSaved,
    'articles_dismissed': articlesDismissed,
    'articles_passed': articlesPassed,
    'total_time_seconds': totalTimeSeconds,
    'closure_achieved': closureAchieved,
    'streak': streak,
  });
}
```

### DigestSelector Test Pattern — Comprehensive

```python
# Recommended test structure for new DigestSelector tests
# Source: Existing digest_selector_test.py patterns (HIGH confidence)

import pytest
from unittest.mock import Mock, AsyncMock
from uuid import uuid4
from datetime import datetime, timezone, timedelta

from sqlalchemy.ext.asyncio import AsyncSession
from app.services.digest_selector import DigestSelector, DigestContext


@pytest.fixture
def mock_session():
    return AsyncMock(spec=AsyncSession)


@pytest.fixture
def mock_rec_service():
    mock = Mock()
    mock.scoring_engine = Mock()
    mock.scoring_engine.compute_score = Mock(return_value=10.0)
    return mock


@pytest.fixture
def selector(mock_session, mock_rec_service):
    sel = DigestSelector(mock_session)
    sel.rec_service = mock_rec_service
    return sel


def make_content(source=None, topics=None, published_at=None):
    """Factory for test Content objects."""
    content = Mock()
    content.id = uuid4()
    content.source = source or make_source()
    content.source_id = content.source.id
    content.published_at = published_at or datetime.now(timezone.utc)
    content.topics = topics
    content.content_type = None
    return content


def make_source(name="Test", theme="tech", is_curated=False):
    """Factory for test Source objects."""
    source = Mock()
    source.id = uuid4()
    source.name = name
    source.theme = theme
    source.is_curated = is_curated
    source.reliability_score = None
    return source


class TestSelectWithDiversity:
    """Test _select_with_diversity returns 4-tuples (content, score, reason, breakdown)."""

    def test_returns_four_tuple(self, selector):
        source = make_source()
        content = make_content(source=source)
        scored = [(content, 100.0, [])]  # Note: 3-tuple input
        
        selected = selector._select_with_diversity(scored, target_count=1)
        
        assert len(selected) == 1
        # Verify 4-tuple: (content, decayed_score, reason, breakdown)
        content_out, score_out, reason_out, breakdown_out = selected[0]
        assert score_out == 100.0
        assert isinstance(reason_out, str)
```

### Notification Service — Flutter

```dart
// apps/mobile/lib/core/services/notification_service.dart
// Source: flutter_local_notifications v20 pub.dev docs (HIGH confidence)

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz_data.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
  }

  Future<bool> requestPermission() async {
    // Android 13+ requires explicit permission
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      return await androidPlugin.requestNotificationsPermission() ?? false;
    }
    
    // iOS: permission requested during init via DarwinInitializationSettings
    return true;
  }

  Future<void> scheduleDailyDigestNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'digest_channel',
      'Digest quotidien',
      channelDescription: 'Notification quotidienne quand votre digest est prêt',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _plugin.zonedSchedule(
      id: 0,
      title: 'Votre digest est prêt !',
      body: '5 articles sélectionnés pour vous ce matin',
      scheduledDate: _nextInstanceOf8AM(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      notificationDetails: details,
    );
  }

  tz.TZDateTime _nextInstanceOf8AM() {
    final paris = tz.getLocation('Europe/Paris');
    final now = tz.TZDateTime.now(paris);
    var scheduledDate = tz.TZDateTime(paris, now.year, now.month, now.day, 8);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }

  void _onNotificationTapped(NotificationResponse response) {
    // Navigate to digest screen
    // This will be wired via go_router deep link
  }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Separate `article_read`, `feed_scroll` events | Unified `content_interaction` event with `surface` field | Industry trend since ~2020 | Single data model for all recommendation signals |
| `flutter_local_notifications` positional params | Named params (`settings:`, `id:`, etc.) | v20 (Jan 2026) | All code examples using positional params are outdated |
| `subqueryload` for related objects | `selectinload` | SQLAlchemy 1.4+ (2021) | Simpler, more efficient in most cases |
| Manual notification permission handling | Plugin-integrated permission APIs | Android 13 (API 33, 2022) | Must call `requestNotificationsPermission()` on Android |

**Deprecated/outdated:**
- `flutter_local_notifications` v18 and earlier: ProGuard rules had to be manually configured. v19+ handles this automatically via GSON.
- `subqueryload` in SQLAlchemy: Still works but `selectinload` is recommended for new code.
- The story 10.16 draft uses separate event types (`digest_viewed`, `digest_item_actioned`, `digest_completed`) — this should be unified per the user's context decision.

## Open Questions

1. **Backward compatibility with existing analytics events**
   - What we know: Current events are `session_start`, `session_end`, `article_read`, `feed_scroll`, `feed_complete`, `source_add`, `source_remove`, `app_first_launch`
   - What's unclear: Should we maintain backward compatibility (wrapper functions that translate old event types to new unified type) or clean break?
   - Recommendation (Claude's Discretion): **Clean break with deprecation**. Add new unified methods alongside old ones. Mark old methods `@deprecated`. Old events in the DB remain queryable. New code uses unified events only. No migration of historical data needed since it's all in the same JSONB table.

2. **Event naming: `content_interaction` vs `content_event`**
   - What we know: User suggested `content_interaction` as example
   - Recommendation (Claude's Discretion): Use `content_interaction` — it's more specific than `content_event` and clearly describes what happened. Aligns with Meta's terminology ("meaningful interactions").

3. **Metrics endpoint structure**
   - What we know: User asked for backend query helpers
   - What's unclear: What specific aggregation queries are needed?
   - Recommendation (Claude's Discretion): Add a `/api/analytics/digest-metrics` endpoint that returns daily/weekly aggregates (completion rate, avg time, action breakdown). Use raw SQL via `text()` for aggregation queries rather than ORM for performance.

4. **When to fire mobile events**
   - What we know: Events should fire at the moment of action
   - Recommendation (Claude's Discretion): 
     - `read`: When user returns from article detail (with time_spent calculated)
     - `save`: Immediately on tap
     - `dismiss`: Immediately on tap
     - `pass`: When user advances to next card in digest; for feed, debounced after 2s in viewport without interaction

5. **iOS notification scheduling reliability**
   - What we know: iOS has a 64 pending notification limit
   - What's unclear: Does daily repeat with `matchDateTimeComponents: DateTimeComponents.time` count as 1 or many?
   - Recommendation: It counts as 1 pending notification. This is fine for our single daily notification use case. Verify during implementation.

## Sources

### Primary (HIGH confidence)
- **Codebase analysis:** `analytics_service.py`, `analytics_service.dart`, `digest_selector.py`, `digest_selector_test.py`, `analytics.py` (model), `content.py`, `daily_digest.py`, `enums.py`
- **SQLAlchemy 2.0 docs:** https://docs.sqlalchemy.org/en/20/orm/queryguide/relationships.html — "In most cases, selectin loading is the most simple and efficient way to eagerly load collections"
- **flutter_local_notifications v20.0.0:** https://pub.dev/packages/flutter_local_notifications — Current version, Flutter Favorite, 7.2k likes

### Secondary (MEDIUM confidence)
- **Meta Engineering Blog (2021):** https://engineering.fb.com/2021/01/26/ml-applications/news-feed-ranking/ — Multi-signal ranking with Vijt = wijt1Yijt1 + ... + wijtkYijtk. Confirmed: unified signal model, linear combination, action-specific predictions.
- **Google Research (2016):** https://research.google/pubs/deep-neural-networks-for-youtube-recommendations/ — YouTube two-stage recommendation system. Impressions without clicks used as negative training signal.
- **Industry consensus:** Multiple platforms use impression-without-interaction as implicit negative signal, with explicit "not interested" as stronger negative.

### Tertiary (LOW confidence)
- **Pass threshold timing (2s viewport dwell):** Synthesized from general recommendation system literature. Specific thresholds are proprietary at GAFAM companies. 2s is a reasonable starting point, should be validated with user testing.
- **Signal weight values (-0.5 for pass, +1.5 for save, etc.):** These are illustrative, not sourced from any specific implementation. Actual tuning is deferred to recommendation engine phase.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries verified via official docs, versions confirmed
- Architecture (unified event schema): MEDIUM — based on GAFAM patterns, synthesized from multiple credible sources, adapted to Facteur's specific context
- Architecture (notification scheduling): HIGH — official docs with code examples
- Architecture (testing patterns): HIGH — based on existing codebase patterns that work
- Pitfalls: HIGH — combination of official docs warnings and codebase-specific knowledge
- Signal weights/thresholds: LOW — illustrative values, actual tuning is future work

**Research date:** 2026-02-08
**Valid until:** 2026-03-08 (30 days — stable domain, unlikely to change significantly)
