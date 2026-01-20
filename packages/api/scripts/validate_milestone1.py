#!/usr/bin/env python3
"""Script de validation Milestone 1 - DailyTop3 Model."""
import sys
sys.path.insert(0, '.')

def main():
    from app.models.daily_top3 import DailyTop3
    from app.models.source import Source
    import uuid
    
    results = []
    
    # Test 1: DailyTop3 creation
    try:
        item = DailyTop3(
            user_id=uuid.uuid4(),
            content_id=uuid.uuid4(),
            rank=1,
            top3_reason='À la Une'
        )
        assert item.rank == 1
        assert item.top3_reason == 'À la Une'
        results.append(("DailyTop3 creation", "PASS"))
    except Exception as e:
        results.append(("DailyTop3 creation", f"FAIL: {e}"))

    # Test 2: Tablename
    try:
        assert DailyTop3.__tablename__ == 'daily_top3'
        results.append(("Tablename check", "PASS"))
    except Exception as e:
        results.append(("Tablename check", f"FAIL: {e}"))

    # Test 3: Source.une_feed_url
    try:
        assert hasattr(Source, 'une_feed_url')
        results.append(("Source.une_feed_url exists", "PASS"))
    except Exception as e:
        results.append(("Source.une_feed_url exists", f"FAIL: {e}"))

    # Test 4: Rank constraint
    try:
        constraint_names = [arg.name for arg in DailyTop3.__table_args__ if hasattr(arg, 'name') and arg.name]
        assert 'ck_daily_top3_rank_range' in constraint_names
        results.append(("Rank constraint", "PASS"))
    except Exception as e:
        results.append(("Rank constraint", f"FAIL: {e}"))

    # Test 5: User date index
    try:
        constraint_names = [arg.name for arg in DailyTop3.__table_args__ if hasattr(arg, 'name') and arg.name]
        assert 'ix_daily_top3_user_date' in constraint_names
        results.append(("User date index", "PASS"))
    except Exception as e:
        results.append(("User date index", f"FAIL: {e}"))

    # Print results
    print("=" * 50)
    print("MILESTONE 1 VALIDATION - DailyTop3 Model")
    print("=" * 50)
    
    all_pass = True
    for name, status in results:
        icon = "✓" if status == "PASS" else "✗"
        print(f"  {icon} {name}: {status}")
        if status != "PASS":
            all_pass = False
    
    print("=" * 50)
    if all_pass:
        print("✅ MILESTONE 1 VALIDATED - All tests passed!")
        return 0
    else:
        print("❌ MILESTONE 1 FAILED - Some tests failed")
        return 1

if __name__ == "__main__":
    sys.exit(main())
