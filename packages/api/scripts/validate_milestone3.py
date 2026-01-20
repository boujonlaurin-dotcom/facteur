#!/usr/bin/env python3
"""Script de validation Milestone 3 - Top3Selector.

Execute les tests unitaires du Top3Selector.
"""
import sys
import uuid
from unittest.mock import MagicMock

sys.path.insert(0, '.')

def create_mock_content(title: str = "Test", source_id: uuid.UUID = None) -> MagicMock:
    """Helper pour créer un mock Content."""
    mock = MagicMock()
    mock.id = uuid.uuid4()
    mock.source_id = source_id or uuid.uuid4()
    mock.title = title
    mock.guid = str(uuid.uuid4())
    return mock

def main():
    from app.services.briefing.top3_selector import Top3Selector
    
    results = []
    
    # Test 1: Une boost
    try:
        selector = Top3Selector()
        content = create_mock_content("Article Une")
        scored_contents = [(content, 50.0)]
        result = selector.select_top3(
            scored_contents=scored_contents,
            user_followed_sources=set(),
            une_content_ids={content.id},
            trending_content_ids=set()
        )
        assert len(result) == 1
        assert result[0].score == 80.0  # 50 + 30
        assert result[0].top3_reason == "À la Une"
        results.append(("Une boost (+30)", "PASS"))
    except Exception as e:
        results.append(("Une boost (+30)", f"FAIL: {e}"))

    # Test 2: Trending boost
    try:
        selector = Top3Selector()
        content = create_mock_content("Article Trending")
        scored_contents = [(content, 50.0)]
        result = selector.select_top3(
            scored_contents=scored_contents,
            user_followed_sources=set(),
            une_content_ids=set(),
            trending_content_ids={content.id}
        )
        assert len(result) == 1
        assert result[0].score == 90.0  # 50 + 40
        assert result[0].top3_reason == "Sujet tendance"
        results.append(("Trending boost (+40)", "PASS"))
    except Exception as e:
        results.append(("Trending boost (+40)", f"FAIL: {e}"))

    # Test 3: Cumulative boosts
    try:
        selector = Top3Selector()
        content = create_mock_content("Both")
        scored_contents = [(content, 50.0)]
        result = selector.select_top3(
            scored_contents=scored_contents,
            user_followed_sources=set(),
            une_content_ids={content.id},
            trending_content_ids={content.id}
        )
        assert len(result) == 1
        assert result[0].score == 120.0  # 50 + 30 + 40
        results.append(("Cumulative boosts (+70)", "PASS"))
    except Exception as e:
        results.append(("Cumulative boosts (+70)", f"FAIL: {e}"))

    # Test 4: Max 1 per source
    try:
        selector = Top3Selector()
        source_a = uuid.uuid4()
        source_b = uuid.uuid4()
        contents = [
            (create_mock_content("A1", source_a), 100.0),
            (create_mock_content("A2", source_a), 90.0),
            (create_mock_content("B1", source_b), 80.0),
        ]
        result = selector.select_top3(
            scored_contents=contents,
            user_followed_sources=set(),
            une_content_ids=set(),
            trending_content_ids=set()
        )
        # Should select A1 (100) and B1 (80), not A2
        source_ids = {item.content.source_id for item in result}
        assert len(source_ids) == 2  # 2 sources distinctes
        results.append(("Max 1 per source", "PASS"))
    except Exception as e:
        results.append(("Max 1 per source", f"FAIL: {e}"))

    # Test 5: Slot #3 followed source
    try:
        selector = Top3Selector()
        source_a = uuid.uuid4()
        source_b = uuid.uuid4()
        source_followed = uuid.uuid4()
        content_followed = create_mock_content("Followed", source_followed)
        contents = [
            (create_mock_content("Top 1", source_a), 100.0),
            (create_mock_content("Top 2", source_b), 90.0),
            (create_mock_content("Higher but not followed", uuid.uuid4()), 85.0),
            (content_followed, 50.0),
        ]
        result = selector.select_top3(
            scored_contents=contents,
            user_followed_sources={source_followed},
            une_content_ids=set(),
            trending_content_ids=set()
        )
        assert len(result) == 3
        assert result[2].content.source_id == source_followed
        assert result[2].top3_reason == "Source suivie"
        results.append(("Slot #3 followed source", "PASS"))
    except Exception as e:
        results.append(("Slot #3 followed source", f"FAIL: {e}"))

    # Test 6: Empty input
    try:
        selector = Top3Selector()
        result = selector.select_top3(
            scored_contents=[],
            user_followed_sources=set(),
            une_content_ids=set(),
            trending_content_ids=set()
        )
        assert result == []
        results.append(("Empty input handling", "PASS"))
    except Exception as e:
        results.append(("Empty input handling", f"FAIL: {e}"))

    # Test 7: Sorting by score
    try:
        selector = Top3Selector()
        source_a = uuid.uuid4()
        source_b = uuid.uuid4()
        source_c = uuid.uuid4()
        content_high = create_mock_content("High", source_c)
        contents = [
            (create_mock_content("Low", source_a), 30.0),
            (create_mock_content("Mid", source_b), 60.0),
            (content_high, 90.0),
        ]
        result = selector.select_top3(
            scored_contents=contents,
            user_followed_sources=set(),
            une_content_ids=set(),
            trending_content_ids=set()
        )
        assert result[0].content.id == content_high.id
        results.append(("Sorting by score", "PASS"))
    except Exception as e:
        results.append(("Sorting by score", f"FAIL: {e}"))

    # Print results
    print("=" * 55)
    print("MILESTONE 3 VALIDATION - Top3Selector")
    print("=" * 55)
    
    all_pass = True
    for name, status in results:
        icon = "✓" if status == "PASS" else "✗"
        print(f"  {icon} {name}: {status}")
        if status != "PASS":
            all_pass = False
    
    print("=" * 55)
    if all_pass:
        print(f"✅ MILESTONE 3 VALIDATED - {len(results)}/{len(results)} tests passed!")
        return 0
    else:
        failed = sum(1 for _, s in results if s != "PASS")
        print(f"❌ MILESTONE 3 FAILED - {len(results) - failed}/{len(results)} tests passed")
        return 1

if __name__ == "__main__":
    sys.exit(main())
