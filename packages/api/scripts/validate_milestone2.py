#!/usr/bin/env python3
"""Script de validation Milestone 2 - ImportanceDetector.

Execute les tests unitaires de ImportanceDetector.
"""
import sys
import uuid
from unittest.mock import MagicMock

sys.path.insert(0, '.')

def create_mock_content(title: str, source_id: uuid.UUID = None) -> MagicMock:
    """Helper pour créer un mock Content."""
    mock = MagicMock()
    mock.id = uuid.uuid4()
    mock.source_id = source_id or uuid.uuid4()
    mock.title = title
    mock.guid = str(uuid.uuid4())
    return mock

def main():
    from app.services.briefing.importance_detector import ImportanceDetector
    
    results = []
    
    # Test 1: Normalize title
    try:
        detector = ImportanceDetector()
        tokens = detector.normalize_title("Macron annonce des réformes économiques")
        assert "macron" in tokens
        assert "reformes" in tokens
        results.append(("normalize_title basic", "PASS"))
    except Exception as e:
        results.append(("normalize_title basic", f"FAIL: {e}"))

    # Test 2: Stop words removal
    try:
        detector = ImportanceDetector()
        tokens = detector.normalize_title("Le président de la France")
        assert "le" not in tokens
        assert "de" not in tokens
        assert "president" in tokens
        results.append(("stop words removal", "PASS"))
    except Exception as e:
        results.append(("stop words removal", f"FAIL: {e}"))

    # Test 3: Jaccard identical
    try:
        detector = ImportanceDetector()
        tokens = {"macron", "reforme", "economie"}
        sim = detector.jaccard_similarity(tokens, tokens)
        assert sim == 1.0
        results.append(("jaccard identical", "PASS"))
    except Exception as e:
        results.append(("jaccard identical", f"FAIL: {e}"))

    # Test 4: Jaccard different
    try:
        detector = ImportanceDetector()
        tokens_a = {"macron", "reforme"}
        tokens_b = {"guerre", "ukraine"}
        sim = detector.jaccard_similarity(tokens_a, tokens_b)
        assert sim == 0.0
        results.append(("jaccard different", "PASS"))
    except Exception as e:
        results.append(("jaccard different", f"FAIL: {e}"))

    # Test 5: Trending with 3 sources
    try:
        detector = ImportanceDetector(similarity_threshold=0.4, min_sources_for_trending=3)
        source_a, source_b, source_c = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
        contents = [
            create_mock_content("Macron annonce une grande réforme", source_a),
            create_mock_content("Macron présente sa réforme majeure", source_b),
            create_mock_content("La réforme de Macron enfin dévoilée", source_c),
        ]
        trending = detector.detect_trending_clusters(contents)
        assert len(trending) == 3
        results.append(("trending 3 sources", "PASS"))
    except Exception as e:
        results.append(("trending 3 sources", f"FAIL: {e}"))

    # Test 6: Not trending with 2 sources
    try:
        detector = ImportanceDetector(similarity_threshold=0.4, min_sources_for_trending=3)
        source_a, source_b = uuid.uuid4(), uuid.uuid4()
        contents = [
            create_mock_content("Macron annonce une grande réforme", source_a),
            create_mock_content("Macron présente sa réforme majeure", source_b),
        ]
        trending = detector.detect_trending_clusters(contents)
        assert len(trending) == 0
        results.append(("not trending 2 sources", "PASS"))
    except Exception as e:
        results.append(("not trending 2 sources", f"FAIL: {e}"))

    # Test 7: Identify Une contents
    try:
        detector = ImportanceDetector()
        content1 = create_mock_content("Title 1")
        content1.guid = "guid-1"
        content2 = create_mock_content("Title 2")
        content2.guid = "guid-2"
        contents = [content1, content2]
        une_guids = {"guid-1"}
        une_ids = detector.identify_une_contents(contents, une_guids)
        assert content1.id in une_ids
        assert content2.id not in une_ids
        results.append(("identify une contents", "PASS"))
    except Exception as e:
        results.append(("identify une contents", f"FAIL: {e}"))

    # Test 8: Invalid init
    try:
        try:
            ImportanceDetector(similarity_threshold=1.5)
            results.append(("invalid threshold validation", "FAIL: should raise"))
        except ValueError:
            results.append(("invalid threshold validation", "PASS"))
    except Exception as e:
        results.append(("invalid threshold validation", f"FAIL: {e}"))

    # Print results
    print("=" * 55)
    print("MILESTONE 2 VALIDATION - ImportanceDetector")
    print("=" * 55)
    
    all_pass = True
    for name, status in results:
        icon = "✓" if status == "PASS" else "✗"
        print(f"  {icon} {name}: {status}")
        if status != "PASS":
            all_pass = False
    
    print("=" * 55)
    if all_pass:
        print(f"✅ MILESTONE 2 VALIDATED - {len(results)}/{len(results)} tests passed!")
        return 0
    else:
        failed = sum(1 for _, s in results if s != "PASS")
        print(f"❌ MILESTONE 2 FAILED - {len(results) - failed}/{len(results)} tests passed")
        return 1

if __name__ == "__main__":
    sys.exit(main())
