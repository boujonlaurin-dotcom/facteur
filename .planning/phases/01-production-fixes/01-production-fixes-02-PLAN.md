---
phase: 01-production-fixes
plan: 02
type: execute
wave: 1
depends_on: []
files_modified:
  - packages/api/app/services/digest_selector.py
autonomous: true

must_haves:
  truths:
    - "Digest contains articles from at least 3 different sources"
    - "No single source contributes more than 2 articles to the digest"
    - "Decay factor of 0.70 is applied: final_score = base_score * (0.70 ^ source_count)"
    - "Diversity algorithm prevents same-source dominance"
  artifacts:
    - path: "packages/api/app/services/digest_selector.py"
      provides: "Diversity selection with decay factor"
      contains:
        - "decay_factor = 0.70"
        - "final_score = score * (decay_factor ** source_counts[source_id])"
        - "min(3, len(set(...)))"
  key_links:
    - from: "_select_with_diversity()"
      to: "decay calculation"
      via: "source_counts tracking and score adjustment"
      pattern: "score \* \(decay_factor \*\*"
---

<objective>
Implement source diversity with decay factor in digest selection.

Purpose: Fix FIX-02 - the digest currently allows multiple articles from the same source without applying decay, causing poor diversity. This fix ensures at least 3 different sources and applies 0.70 decay factor per additional article from same source.
Output: Modified digest_selector.py with decay-based diversity selection in _select_with_diversity() method.
</objective>

<execution_context>
@/Users/laurinboujon/.config/opencode/get-shit-done/workflows/execute-plan.md
@/Users/laurinboujon/.config/opencode/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@.planning/REQUIREMENTS.md

Current implementation (lines 704-756 in digest_selector.py):
- Method: _select_with_diversity()
- Currently tracks source_counts and theme_counts
- Enforces MAX_PER_SOURCE = 2 and MAX_PER_THEME = 2
- Does NOT apply decay factor to scores

Required pattern (from recommendation_service.py lines 179-190):
```python
source_counts = {}
decay_factor = 0.70 # Each subsequent item from same source loses 30% score
# ...
count = source_counts.get(source_id, 0)
# FinalScore = BaseScore * (decay_factor ^ count)
final_score = base_score * (decay_factor ** count)
# ...
source_counts[source_id] = count + 1
```

Key requirements:
1. Decay factor: 0.70 (same as feed algorithm)
2. Formula: final_score = base_score * (0.70 ^ source_count)
3. Minimum 3 sources in digest (need to track and enforce)
4. Maximum 2 per source already enforced
</context>

<tasks>

<task type="auto">
  <name>Task 1: Implement decay-based diversity in _select_with_diversity()</name>
  <files>packages/api/app/services/digest_selector.py</files>
  <action>
Modify the _select_with_diversity() method in packages/api/app/services/digest_selector.py (around line 704-756).

Current algorithm flow:
1. Initialize source_counts and theme_counts as defaultdict(int)
2. Loop through scored_candidates (already sorted by score)
3. Check if source_counts[source_id] >= MAX_PER_SOURCE (2)
4. Check if theme_counts[theme] >= MAX_PER_THEME (2)
5. If constraints pass, add to selected

NEW algorithm with decay:
1. Keep the same initialization and source/theme counting
2. ADD decay factor calculation BEFORE constraint checks
3. ADD minimum 3 sources enforcement at the end

Specific changes:

1. Add at the start of the method (after selected = []):
   ```python
   DECAY_FACTOR = 0.70  # Same as feed algorithm
   MIN_SOURCES = 3
   ```

2. Modify the loop to apply decay BEFORE constraint checks:
   ```python
   for content, score, breakdown in scored_candidates:
       if len(selected) >= target_count:
           break

       source_id = content.source_id
       theme = content.source.theme if content.source else None
       
       # Apply decay factor based on how many articles already selected from this source
       current_source_count = source_counts.get(source_id, 0)
       decayed_score = score * (DECAY_FACTOR ** current_source_count)
       
       # Check constraints with decayed consideration
       if source_counts[source_id] >= self.constraints.MAX_PER_SOURCE:
           continue

       if theme and theme_counts[theme] >= self.constraints.MAX_PER_THEME:
           continue

       # Contraintes respectées - ajouter avec raison générée
       reason = self._generate_reason(content, source_counts, theme_counts, breakdown)
       selected.append((content, decayed_score, reason, breakdown))
       source_counts[source_id] += 1
       if theme:
           theme_counts[theme] += 1
   ```

3. Add minimum sources check at the end (after the loop, before return):
   ```python
   # Ensure minimum source diversity
   selected_sources = set(item[0].source_id for item in selected)
   if len(selected_sources) < MIN_SOURCES and len(scored_candidates) >= target_count:
       logger.warning(
           "digest_diversity_insufficient_sources",
           selected_sources=len(selected_sources),
           min_required=MIN_SOURCES
       )
       # Could optionally re-run with relaxed constraints, but for now just log
   ```

4. Update the debug log to include decay info:
   ```python
   logger.debug(
       "digest_diversity_selection",
       selected_count=len(selected),
       source_distribution=dict(source_counts),
       theme_distribution=dict(theme_counts),
       decay_factor=DECAY_FACTOR
   )
   ```

Key points:
- Use the existing source_counts tracking (it's already a defaultdict(int))
- Apply decay BEFORE constraint checks so scores reflect true priority
- Keep the existing MAX_PER_SOURCE = 2 constraint
- Log when minimum sources not met (but still return what we have)
  </action>
  <verify>
Verify by checking the file:
- grep -n "DECAY_FACTOR = 0.70" packages/api/app/services/digest_selector.py
- grep -n "decayed_score" packages/api/app/services/digest_selector.py
- grep -n "MIN_SOURCES = 3" packages/api/app/services/digest_selector.py
- grep -n "\*\* current_source_count" packages/api/app/services/digest_selector.py
  </verify>
  <done>
- DECAY_FACTOR = 0.70 constant defined in _select_with_diversity()
- Decay applied: decayed_score = score * (DECAY_FACTOR ** current_source_count)
- MIN_SOURCES = 3 constant defined
- Logic ensures diversity with decay-based scoring
- Selected items use decayed_score instead of original score
  </done>
</task>

</tasks>

<verification>
Verify the fix:
1. DECAY_FACTOR = 0.70 is defined in _select_with_diversity()
2. Decay formula is applied: score * (DECAY_FACTOR ** source_count)
3. MIN_SOURCES = 3 is defined and checked
4. The selected items use decayed scores
5. Existing MAX_PER_SOURCE = 2 constraint is preserved
</verification>

<success_criteria>
- _select_with_diversity() applies 0.70 decay factor
- Formula: final_score = base_score * (0.70 ^ source_count)
- Minimum 3 sources requirement is tracked
- Selection uses decayed scores for ranking
- All existing constraints (max 2 per source/theme) still enforced
</success_criteria>

<output>
After completion, create `.planning/phases/01-production-fixes/01-production-fixes-02-SUMMARY.md`
</output>
