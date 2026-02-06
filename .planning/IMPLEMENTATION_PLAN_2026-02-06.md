# Implementation Plan: Phase 1 Fix + Phase 2 Enhancements

**Date:** 2026-02-06  
**Status:** Planning Complete  
**Author:** Development Team  

---

## Overview

Three critical enhancements identified for the Facteur digest system:

1. **Task 1 (CRITICAL):** Fix digest source selection algorithm
2. **Task 2 (BIG):** Align "Pourquoi cet article?" with feed implementation  
3. **Task 3 (Quick Win):** Add bookmarked articles navigation in Settings

---

## Task 1: Phase 1 - Digest Source Selection Algorithm (CRITICAL)

### Problem Statement

The digest algorithm searches user sources for only **48 hours**, then falls back to **curated sources** to fill the 5-article quota. This causes users to receive articles **NOT from their followed sources**, creating a mismatch between user expectations and actual content.

### Root Cause

```python
# Current problematic logic:
# 1. Query user sources (last 48h)
# 2. If < 5 articles found → fallback to curated sources
# 3. Result: Users see articles from sources they don't follow
```

### Solution: Extended Lookback with Aligned Recency Bonus

#### 1. Extend Search Window

- **From:** 48 hours
- **To:** 168 hours (7 days)

This allows the algorithm to find more articles from user's own sources before considering fallback.

#### 2. Aligned Recency Bonus System

Recency bonuses **aligned with existing ScoringWeights** to maintain consistency:

| Age | Bonus | Label (French) | Rationale |
|-----|-------|----------------|-----------|
| < 6h | +30 pts | "Article très récent (< 6h)" | Matches recency_base = 30.0 |
| 6-24h | +25 pts | "Article récent (< 24h)" | High freshness |
| 24-48h | +15 pts | "Publié aujourd'hui" | Current default window |
| 48-72h | +8 pts | "Publié hier" | Still relevant |
| 72-120h | +3 pts | "Article de la semaine" | Moderate relevance |
| 120-168h | +1 pt | "Article ancien" | Minimum to keep eligible |

#### 3. Modified Fallback Logic

**OLD (problematic):**
```
If user_sources < 5 articles:
    Fill remainder with curated sources
```

**NEW (user-centric):**
```
If user_sources < 3 articles (even after 7 days):
    Use curated fallback
Otherwise:
    Use only user sources (with recency penalties if old)
```

#### 4. Priority Guarantee

**User sources ALWAYS rank above curated sources**, even when user articles are 7 days old and curated articles are fresh.

### Files to Modify

1. **`packages/api/app/services/recommendation/scoring_config.py`**
   - Add 6 recency bonus constants

2. **`packages/api/app/services/digest_selector.py`**
   - Update `_get_candidates()`: Change hours_lookback 48 → 168
   - Modify fallback logic: Trigger only when user sources < 3
   - Add `_calculate_recency_bonus()` method
   - Add `_get_recency_label()` method
   - Update `_score_candidates()` to apply bonuses

3. **`packages/api/app/services/digest_service.py`**
   - Enhanced logging for transparency
   - Track: user_source_count, curated_fallback_used, recency_bonus_applied

### Implementation Details

```python
# New constants in ScoringWeights
RECENT_VERY_BONUS = 30.0      # < 6 hours
RECENT_BONUS = 25.0           # 6-24 hours
RECENT_DAY_BONUS = 15.0       # 24-48 hours
RECENT_YESTERDAY_BONUS = 8.0  # 48-72 hours
RECENT_WEEK_BONUS = 3.0       # 72-120 hours
RECENT_OLD_BONUS = 1.0        # 120-168 hours

# Modified fallback threshold
MIN_USER_SOURCES_BEFORE_FALLBACK = 3  # Changed from 5
```

### Success Criteria

- [ ] Digest searches user sources for 168 hours (7 days)
- [ ] Recency bonuses displayed in "+X pts" format (aligned with feed)
- [ ] Fallback to curated triggers only when user sources < 3 articles
- [ ] User sources always ranked above curated (even with age penalty)
- [ ] Logs show: `user_source_count`, `curated_fallback_used`, `recency_bonus_applied`

### Time Estimate

**3-4 hours**

---

## Task 2: Phase 2 - "Pourquoi cet article?" Full Alignment (BIG TASK)

### Current Gap Analysis

**Feed Implementation** (comprehensive):
- Full `RecommendationReason` object:
  - `label`: Top-level reason (e.g., "Vos intérêts : Tech")
  - `score_total`: Total calculated score
  - `breakdown`: Array of `ScoreContribution` with:
    - `label`: Detailed reason
    - `points`: Numeric contribution (+70, -30, etc.)
    - `is_positive`: Boolean for UI coloring

**Digest Implementation** (simplified):
- Simple `reason: String` only (e.g., "Source suivie : TechCrunch")
- No breakdown, no points, no transparency

### Solution: Full Reasoning Parity

#### Backend Changes

**1. Extend Pydantic Schemas** (`packages/api/app/schemas/digest.py`):

```python
class DigestScoreBreakdown(BaseModel):
    """Individual scoring contribution for transparency."""
    label: str           # e.g., "Thème matché : Tech"
    points: float        # e.g., 70.0
    is_positive: bool    # true = bonus, false = penalty

class DigestRecommendationReason(BaseModel):
    """Complete reasoning for digest article selection."""
    label: str                          # Top-level summary
    score_total: float                  # Sum of all contributions
    breakdown: List[DigestScoreBreakdown]  # Detailed contributions

class DigestItemResponse(BaseModel):
    # ... existing fields ...
    reason: Optional[str] = None  # Backward compatibility
    recommendation_reason: Optional[DigestRecommendationReason] = None
```

**2. Capture Scoring Layer Contributions** (`packages/api/app/services/digest_selector.py`):

Modify `_score_candidates()` to capture each layer:

```python
scored = []
for content in candidates:
    score = 0.0
    breakdown = []
    
    # CoreLayer - Theme Match
    if content.source.theme in context.user_interests:
        points = ScoringWeights.THEME_MATCH
        score += points
        breakdown.append(DigestScoreBreakdown(
            label=f"Thème matché : {content.source.theme}",
            points=points,
            is_positive=True
        ))
    
    # CoreLayer - Source Affinity
    if content.source_id in context.followed_source_ids:
        points = ScoringWeights.TRUSTED_SOURCE
        score += points
        breakdown.append(DigestScoreBreakdown(
            label="Source de confiance",
            points=points,
            is_positive=True
        ))
        
        if content.source_id in context.custom_source_ids:
            points = ScoringWeights.CUSTOM_SOURCE_BONUS
            score += points
            breakdown.append(DigestScoreBreakdown(
                label="Ta source personnalisée",
                points=points,
                is_positive=True
            ))
    
    # Recency Bonus (from Task 1)
    recency_points = self._calculate_recency_bonus(content)
    if recency_points > 0:
        score += recency_points
        breakdown.append(DigestScoreBreakdown(
            label=self._get_recency_label(content),
            points=recency_points,
            is_positive=True
        ))
    
    # ArticleTopicLayer - Topic Matches
    if content.topics:
        matches = set(content.topics) & context.user_subtopics
        for topic in list(matches)[:2]:  # Max 2 matches
            points = ScoringWeights.TOPIC_MATCH
            score += points
            breakdown.append(DigestScoreBreakdown(
                label=f"Sous-thème : {topic}",
                points=points,
                is_positive=True
            ))
        
        # Subtopic precision bonus
        if len(matches) > 0 and content.source.theme in context.user_interests:
            points = ScoringWeights.SUBTOPIC_PRECISION_BONUS
            score += points
            breakdown.append(DigestScoreBreakdown(
                label="Précision thématique",
                points=points,
                is_positive=True
            ))
    
    # StaticPreferenceLayer - Format preferences
    format_pref = context.user_prefs.get('preferred_format')
    if format_pref and content.content_type.value == format_pref:
        points = 15.0  # From StaticPreferenceLayer
        score += points
        breakdown.append(DigestScoreBreakdown(
            label=f"Format préféré : {format_pref}",
            points=points,
            is_positive=True
        ))
    
    # QualityLayer - Source quality
    if content.source and content.source.is_curated:
        points = ScoringWeights.CURATED_SOURCE
        score += points
        breakdown.append(DigestScoreBreakdown(
            label="Source qualitative",
            points=points,
            is_positive=True
        ))
    
    # QualityLayer - Reliability penalty
    if content.source and content.source.reliability_score < 0.5:
        points = ScoringWeights.FQS_LOW_MALUS
        score += points
        breakdown.append(DigestScoreBreakdown(
            label="Fiabilité source faible",
            points=points,
            is_positive=False
        ))
    
    scored.append((content, score, breakdown))
```

**3. Update API Response** (`packages/api/app/api/routes/digest.py`):

```python
def _determine_top_reason(breakdown: List[DigestScoreBreakdown]) -> str:
    """Extract the most significant positive reason for the label."""
    positive_breakdown = [b for b in breakdown if b.is_positive]
    if not positive_breakdown:
        return "Sélectionné pour vous"
    
    # Sort by points descending
    positive_breakdown.sort(key=lambda x: x.points, reverse=True)
    top = positive_breakdown[0]
    
    # Format the label based on the top reason
    if "Thème" in top.label:
        return f"Vos intérêts : {top.label.split(': ')[1]}"
    elif "Source de confiance" in top.label:
        return "Source suivie"
    elif "Source personnalisée" in top.label:
        return "Ta source personnalisée"
    elif "Sous-thème" in top.label:
        topics = [b.label.split(': ')[1] for b in positive_breakdown 
                  if "Sous-thème" in b.label][:2]
        return f"Vos centres d'intérêt : {', '.join(topics)}"
    else:
        return top.label

# In digest response construction:
digest_items = [
    DigestItemResponse(
        # ... existing fields ...
        reason=item.reason,  # Simple string (backward compatible)
        recommendation_reason=DigestRecommendationReason(
            label=_determine_top_reason(item.breakdown),
            score_total=sum(b.points for b in item.breakdown),
            breakdown=[
                DigestScoreBreakdown(
                    label=b.label,
                    points=b.points,
                    is_positive=b.is_positive
                ) for b in item.breakdown
            ]
        ) if item.breakdown else None
    )
    for item in digest_items
]
```

#### Frontend Changes

**1. Extend Models** (`apps/mobile/lib/features/digest/models/digest_models.dart`):

```dart
@freezed
class DigestScoreBreakdown with _$DigestScoreBreakdown {
  const factory DigestScoreBreakdown({
    required String label,
    required double points,
    required bool isPositive,
  }) = _DigestScoreBreakdown;

  factory DigestScoreBreakdown.fromJson(Map<String, dynamic> json) =>
      _$DigestScoreBreakdownFromJson(json);
}

@freezed
class DigestRecommendationReason with _$DigestRecommendationReason {
  const factory DigestRecommendationReason({
    required String label,
    required double scoreTotal,
    required List<DigestScoreBreakdown> breakdown,
  }) = _DigestRecommendationReason;

  factory DigestRecommendationReason.fromJson(Map<String, dynamic> json) =>
      _$DigestRecommendationReasonFromJson(json);
}

@freezed
class DigestItem with _$DigestItem {
  const factory DigestItem({
    // ... existing fields ...
    String? reason,  // Keep for backward compatibility
    DigestRecommendationReason? recommendationReason,
  }) = _DigestItem;
  
  factory DigestItem.fromJson(Map<String, dynamic> json) =>
      _$DigestItemFromJson(json);
}
```

**2. Run Code Generation**:

```bash
cd apps/mobile
flutter pub run build_runner build --delete-conflicting-outputs
```

**3. Update UI** (`apps/mobile/lib/features/digest/widgets/digest_briefing_section.dart`):

Add tap handler to show reasoning:

```dart
// In article card builder:
GestureDetector(
  onTap: () => _showArticleDetail(item),
  onLongPress: () => _showReasoningSheet(context, item),
  child: FeedCard(
    // ... existing props ...
  ),
)

void _showReasoningSheet(BuildContext context, DigestItem item) {
  if (item.recommendationReason == null) return;
  
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => DigestPersonalizationSheet(item: item),
  );
}
```

**4. Create DigestPersonalizationSheet** (`apps/mobile/lib/features/digest/widgets/digest_personalization_sheet.dart`):

Reuse the pattern from feed's PersonalizationSheet:

```dart
class DigestPersonalizationSheet extends StatelessWidget {
  final DigestItem item;
  
  const DigestPersonalizationSheet({super.key, required this.item});
  
  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final reason = item.recommendationReason!;
    
    return Container(
      padding: const EdgeInsets.only(top: 24, bottom: 40, left: 20, right: 20),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with title and total score
          Row(
            children: [
              Icon(PhosphorIcons.question(PhosphorIconsStyle.bold),
                  color: colors.primary, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Pourquoi cet article ?',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${reason.scoreTotal.toInt()} pts',
                  style: TextStyle(
                    color: colors.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          // Breakdown list
          ...reason.breakdown.map((contribution) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(
                  contribution.isPositive
                      ? PhosphorIcons.trendUp(PhosphorIconsStyle.bold)
                      : PhosphorIcons.trendDown(PhosphorIconsStyle.bold),
                  color: contribution.isPositive
                      ? colors.success
                      : colors.error,
                  size: 16,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    contribution.label,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 15,
                    ),
                  ),
                ),
                Text(
                  '${contribution.points > 0 ? '+' : ''}${contribution.points.toInt()}',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          )),
          
          const SizedBox(height: 16),
          Divider(color: colors.border),
          const SizedBox(height: 16),
          
          // Actions (mute source/theme/topic)
          // ... reuse logic from feed's PersonalizationSheet ...
        ],
      ),
    );
  }
}
```

### Scoring Layers Priority

Port these layers in order:

1. **CoreLayer** (Essential)
   - Theme match: +70 pts
   - Source followed: +40 pts
   - Custom source: +10 pts

2. **Recency** (from Task 1)
   - Very recent (< 6h): +30 pts
   - Recent (< 24h): +25 pts
   - Today: +15 pts
   - Yesterday: +8 pts

3. **ArticleTopicLayer** (High value)
   - Topic match: +60 pts each (max 2)
   - Subtopic precision: +20 pts

4. **StaticPreferenceLayer** (Nice-to-have)
   - Format match: +15 pts

5. **QualityLayer** (Important)
   - Curated source: +10 pts
   - Low reliability: -30 pts

### Side Effects & Considerations

**Performance Impact:**
- Capturing breakdown adds ~10-20ms per article
- For 5 articles: <100ms additional latency
- Acceptable for async batch job

**API Payload:**
- Adds ~500 bytes per article
- Total: ~2.5KB extra for full digest
- Acceptable overhead

**Backward Compatibility:**
- Old `reason` string field preserved
- New `recommendation_reason` is optional
- Old app versions ignore new field gracefully

### Success Criteria

- [ ] Backend returns full `DigestRecommendationReason` with breakdown array
- [ ] Frontend displays "Pourquoi cet article?" with detailed breakdown
- [ ] Shows: Theme match (+70), Source (+40), Topics (+60), etc.
- [ ] Each reason shows points with +/- indicators
- [ ] Total score displayed prominently
- [ ] Same visual format as feed cards
- [ ] Backward compatible (old `reason` field still works)

### Time Estimate

**12-16 hours** (BIG TASK)

---

## Task 3: Phase 2 - Bookmarked Articles in Settings (Quick Win)

### Current Situation

- `SavedScreen` exists at `/saved` route
- `savedFeedProvider` already implemented
- **Missing:** Navigation to access saved articles

### Solution: Settings Integration

Add "Articles sauvegardés" tile in Settings under **CONTENU** section, right after "Sources de confiance".

### Implementation

**1. Update SettingsScreen** (`apps/mobile/lib/features/settings/screens/settings_screen.dart`):

Add tile in "CONTENU" section (after line ~76):

```dart
// CONTENU Section
_buildSection(
  context,
  title: 'CONTENU',
  children: [
    _buildTile(
      context,
      icon: Icons.star_outline,
      title: 'Sources de confiance',
      subtitle: 'Gérer vos préférences',
      onTap: () => context.pushNamed(RouteNames.sources),
    ),
    // NEW: Bookmarked articles tile
    _buildTile(
      context,
      icon: Icons.bookmark_outline,
      title: 'Articles sauvegardés',
      subtitle: 'Consulter vos articles enregistrés',
      onTap: () => context.pushNamed(RouteNames.saved),
    ),
  ],
),
```

**2. Verify Route Configuration** (`apps/mobile/lib/config/routes.dart`):

Already configured:
- `RouteNames.saved = 'saved'`
- `RoutePaths.saved = '/saved'`
- Route exists in GoRouter (outside ShellRoute)

**3. SavedScreen Verification** (`apps/mobile/lib/features/saved/screens/saved_screen.dart`):

Already fully functional:
- Uses `savedFeedProvider`
- Pagination implemented
- Empty state handled
- Can unsave articles
- Pull-to-refresh

### Visual Design

```
┌──────────────────────────────────────────┐
│  CONTENU                                 │
├──────────────────────────────────────────┤
│  ⭐ Sources de confiance          >      │
│     Gérer vos préférences                │
├──────────────────────────────────────────┤
│  🔖 Articles sauvegardés          >      │  ← NEW
│     Consulter vos articles enregistrés   │
└──────────────────────────────────────────┘
```

### Navigation Flow

1. User in Settings → taps "Articles sauvegardés"
2. Navigate to `/saved` (full screen, no bottom nav)
3. SavedScreen displays list of bookmarked articles
4. User can:
   - Scroll through saved articles
   - Tap to open article
   - Unsave (remove bookmark)
   - Pull-to-refresh
5. Back button returns to Settings

### Side Effects

**None.** This purely adds navigation to existing functionality.

### Success Criteria

- [ ] Tile appears in CONTENU section
- [ ] Tapping navigates to SavedScreen
- [ ] Shows bookmark icon (consistent with save action)
- [ ] Empty state displays correctly when no saved articles
- [ ] Can unsave articles from the list
- [ ] Returns to settings on back button

### Time Estimate

**1-2 hours** (Quick Win)

---

## Execution Order Recommendation

| Priority | Task | Phase | Complexity | Time | Critical |
|----------|------|-------|------------|------|----------|
| 1 | Task 1: Digest Source Fix | Phase 1 | Medium | 3-4h | **YES** |
| 2 | Task 3: Bookmarked Nav | Phase 2 | Low | 1-2h | No |
| 3 | Task 2: Full Reasoning | Phase 2 | High | 12-16h | No |

**Rationale:**
1. **Task 1 first** - Fixes core functionality bug (users getting wrong articles)
2. **Task 3 second** - Quick UX improvement, minimal risk
3. **Task 2 last** - Big enhancement, can be deferred if needed

---

## Dependencies

- Task 2 (Reasoning) can use recency bonuses from Task 1
- Task 3 is completely independent
- All tasks can be developed in parallel if resources allow

---

## Notes

- Task 1 requires careful alignment with existing `ScoringWeights`
- Task 2 requires backend + frontend coordination (BIG TASK)
- Task 3 is pure frontend, minimal risk
- All changes maintain backward compatibility

---

**Plan Status:** ✅ Ready for Implementation  
**Last Updated:** 2026-02-06
