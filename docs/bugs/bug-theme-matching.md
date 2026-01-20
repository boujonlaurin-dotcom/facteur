# Bug: Theme Matching Always Fails in CoreLayer

## Symptom
The theme matching logic in the recommendation algorithm (`CoreLayer`) never correctly identifies a match between a content's source theme and the user's interests. This results in the +70 match bonus never being applied, leading to recommendations that do not respect user topic preferences.

## Root Cause
The code compares two incompatible string formats:
- `content.source.theme`: Human-readable labels (e.g., "Tech & Futur", "Société & Climat").
- `context.user_interests`: Normalized slugs (e.g., "tech", "society").

**Code Location:** `packages/api/app/services/recommendation/layers/core.py` (Line 25)
```python
if content.source and content.source.theme in context.user_interests:
    # Always False because "Tech & Futur" != "tech"
```

## Impact
- **User Relevance**: Users see random content instead of what they signed up for ("Quasi-aléatoire").
- **Scoring**: The strongest signal (+70 points) is ignored. Source affinity (+30) and recency become the only differentiation factors.
- **Product Promise**: The core value proposition of a personalized feed is broken.

## Proposed Fix
1. Create a `ThemeMapper` module to map human-readable themes to corresponding slugs.
2. Update `CoreLayer` to use this mapper for comparison.

### Mapping Table
| Source Theme | User Interest Slugs |
|--------------|---------------------|
| Tech & Futur | tech, science |
| Société & Climat | society, environment |
| Économie | economy, business |
| Géopolitique | politics, international |
| Culture & Idées | culture |
