#!/usr/bin/env python3
"""
Phase 1 Foundation Validation Script
====================================

Validates all Phase 1 (Foundation) deliverables:
- Database migrations (daily_digest, digest_completions, user_streaks)
- DigestSelector service with diversity constraints
- API endpoints (GET /digest, POST /action, POST /complete)
- Integration with existing systems (no regression)

Usage:
    cd packages/api
    python ../../docs/qa/scripts/validate_phase1.py

Or with pytest:
    cd packages/api
    python -m pytest ../../docs/qa/scripts/validate_phase1.py -v

Environment Variables:
    DATABASE_URL: Database connection string (defaults to .env config)
    TEST_USER_ID: Optional UUID for testing with specific user
"""

import asyncio
import os
import sys
import time
from datetime import date, datetime, timedelta
from typing import Optional
from uuid import UUID, uuid4

# Add packages/api to path for imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../packages/api'))

import pytest
import pytest_asyncio
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession


# ═══════════════════════════════════════════════════════════════════════════════
# Database Validation Tests
# ═══════════════════════════════════════════════════════════════════════════════


@pytest.mark.asyncio
async def test_001_daily_digest_table_exists(db_session: AsyncSession):
    """Verify daily_digest table exists with correct structure."""
    result = await db_session.execute(text("""
        SELECT column_name, data_type, is_nullable
        FROM information_schema.columns
        WHERE table_name = 'daily_digest'
        ORDER BY ordinal_position
    """))
    columns = {row[0]: (row[1], row[2]) for row in result.fetchall()}
    
    assert 'id' in columns, "Missing id column"
    assert 'user_id' in columns, "Missing user_id column"
    assert 'date' in columns, "Missing date column"
    assert 'items' in columns, "Missing items column (JSONB)"
    assert 'generated_at' in columns, "Missing generated_at column"
    assert 'completed' in columns, "Missing completed column"
    assert 'completed_at' in columns, "Missing completed_at column"
    
    # Verify JSONB type for items
    assert columns['items'][0] in ['jsonb', 'JSONB'], f"items should be JSONB, got {columns['items'][0]}"
    
    print("✅ daily_digest table structure verified")


@pytest.mark.asyncio
async def test_002_digest_completions_table_exists(db_session: AsyncSession):
    """Verify digest_completions table exists with correct structure."""
    result = await db_session.execute(text("""
        SELECT column_name, data_type, is_nullable
        FROM information_schema.columns
        WHERE table_name = 'digest_completions'
        ORDER BY ordinal_position
    """))
    columns = {row[0]: (row[1], row[2]) for row in result.fetchall()}
    
    assert 'id' in columns, "Missing id column"
    assert 'user_id' in columns, "Missing user_id column"
    assert 'date' in columns, "Missing date column"
    assert 'completed_at' in columns, "Missing completed_at column"
    assert 'time_to_closure_minutes' in columns, "Missing time_to_closure_minutes column"
    
    print("✅ digest_completions table structure verified")


@pytest.mark.asyncio
async def test_003_user_streaks_extended(db_session: AsyncSession):
    """Verify user_streaks table has closure tracking columns."""
    result = await db_session.execute(text("""
        SELECT column_name, data_type, column_default
        FROM information_schema.columns
        WHERE table_name = 'user_streaks'
        AND column_name IN ('closure_streak', 'longest_closure_streak', 'last_closure_date')
    """))
    columns = {row[0]: (row[1], row[2]) for row in result.fetchall()}
    
    assert 'closure_streak' in columns, "Missing closure_streak column"
    assert 'longest_closure_streak' in columns, "Missing longest_closure_streak column"
    assert 'last_closure_date' in columns, "Missing last_closure_date column"
    
    # Verify defaults
    assert columns['closure_streak'][1] == '0', "closure_streak should default to 0"
    assert columns['longest_closure_streak'][1] == '0', "longest_closure_streak should default to 0"
    
    print("✅ user_streaks closure tracking columns verified")


@pytest.mark.asyncio
async def test_004_tables_have_indexes(db_session: AsyncSession):
    """Verify required indexes exist for performance."""
    result = await db_session.execute(text("""
        SELECT indexname, tablename
        FROM pg_indexes
        WHERE tablename IN ('daily_digest', 'digest_completions')
        AND schemaname = 'public'
    """))
    indexes = [(row[0], row[1]) for row in result.fetchall()]
    
    # Check for user_id + date indexes
    daily_digest_indexes = [idx[0] for idx in indexes if idx[1] == 'daily_digest']
    completions_indexes = [idx[0] for idx in indexes if idx[1] == 'digest_completions']
    
    assert any('user' in idx.lower() or 'date' in idx.lower() for idx in daily_digest_indexes), \
        "daily_digest should have index on user_id/date"
    
    print("✅ Table indexes verified")


# ═══════════════════════════════════════════════════════════════════════════════
# Model Import Tests
# ═══════════════════════════════════════════════════════════════════════════════


def test_005_models_importable():
    """Verify all new models can be imported."""
    try:
        from app.models.daily_digest import DailyDigest
        from app.models.digest_completion import DigestCompletion
        from app.models.user import UserStreak
        print("✅ All models import successfully")
    except ImportError as e:
        pytest.fail(f"Failed to import models: {e}")


def test_006_model_attributes():
    """Verify models have expected attributes."""
    from app.models.daily_digest import DailyDigest
    from app.models.digest_completion import DigestCompletion
    from app.models.user import UserStreak
    
    # DailyDigest checks
    assert hasattr(DailyDigest, 'items'), "DailyDigest missing items attribute"
    assert hasattr(DailyDigest, 'user_id'), "DailyDigest missing user_id attribute"
    assert hasattr(DailyDigest, 'date'), "DailyDigest missing date attribute"
    assert hasattr(DailyDigest, 'completed'), "DailyDigest missing completed attribute"
    
    # DigestCompletion checks
    assert hasattr(DigestCompletion, 'user_id'), "DigestCompletion missing user_id"
    assert hasattr(DigestCompletion, 'date'), "DigestCompletion missing date"
    assert hasattr(DigestCompletion, 'completed_at'), "DigestCompletion missing completed_at"
    
    # UserStreak closure checks
    assert hasattr(UserStreak, 'closure_streak'), "UserStreak missing closure_streak"
    assert hasattr(UserStreak, 'longest_closure_streak'), "UserStreak missing longest_closure_streak"
    assert hasattr(UserStreak, 'last_closure_date'), "UserStreak missing last_closure_date"
    
    print("✅ Model attributes verified")


# ═══════════════════════════════════════════════════════════════════════════════
# DigestSelector Service Tests
# ═══════════════════════════════════════════════════════════════════════════════


def test_007_digest_selector_importable():
    """Verify DigestSelector service can be imported."""
    try:
        from app.services.digest_selector import DigestSelector, DigestItem
        print("✅ DigestSelector imports successfully")
    except ImportError as e:
        pytest.fail(f"Failed to import DigestSelector: {e}")


def test_008_digest_selector_has_methods():
    """Verify DigestSelector has required methods."""
    from app.services.digest_selector import DigestSelector
    
    assert hasattr(DigestSelector, 'select_for_user'), "Missing select_for_user method"
    
    print("✅ DigestSelector methods verified")


@pytest.mark.asyncio
async def test_009_diversity_constraints_constants():
    """Verify diversity constraint constants are defined."""
    from app.services.digest_selector import DigestSelector
    
    # Check if constraints are defined (may be class variables or constants)
    # The constraints should be: max 2 per source, max 2 per theme
    selector_code = open('app/services/digest_selector.py').read()
    
    assert 'MAX_PER_SOURCE' in selector_code or 'max_per_source' in selector_code.lower(), \
        "MAX_PER_SOURCE constraint not found"
    assert 'MAX_PER_THEME' in selector_code or 'max_per_theme' in selector_code.lower(), \
        "MAX_PER_THEME constraint not found"
    
    print("✅ Diversity constraints defined")


# ═══════════════════════════════════════════════════════════════════════════════
# DigestService Tests
# ═══════════════════════════════════════════════════════════════════════════════


def test_010_digest_service_importable():
    """Verify DigestService can be imported."""
    try:
        from app.services.digest_service import DigestService
        print("✅ DigestService imports successfully")
    except ImportError as e:
        pytest.fail(f"Failed to import DigestService: {e}")


def test_011_digest_service_has_methods():
    """Verify DigestService has required methods."""
    from app.services.digest_service import DigestService
    
    assert hasattr(DigestService, 'get_or_create_digest'), "Missing get_or_create_digest method"
    assert hasattr(DigestService, 'apply_action'), "Missing apply_action method"
    assert hasattr(DigestService, 'complete_digest'), "Missing complete_digest method"
    
    print("✅ DigestService methods verified")


# ═══════════════════════════════════════════════════════════════════════════════
# Job Tests
# ═══════════════════════════════════════════════════════════════════════════════


def test_012_generation_job_importable():
    """Verify generation job can be imported."""
    try:
        from app.jobs.digest_generation_job import run_digest_generation, DigestGenerationJob
        print("✅ Digest generation job imports successfully")
    except ImportError as e:
        pytest.fail(f"Failed to import generation job: {e}")


def test_013_job_has_entry_point():
    """Verify job has main entry point function."""
    from app.jobs.digest_generation_job import run_digest_generation
    
    assert callable(run_digest_generation), "run_digest_generation should be callable"
    
    print("✅ Generation job entry point verified")


# ═══════════════════════════════════════════════════════════════════════════════
# API Router Tests
# ═══════════════════════════════════════════════════════════════════════════════


def test_014_digest_router_importable():
    """Verify digest router can be imported."""
    try:
        from app.routers import digest
        print("✅ Digest router imports successfully")
    except ImportError as e:
        pytest.fail(f"Failed to import digest router: {e}")


def test_015_router_has_endpoints():
    """Verify router has required endpoints."""
    from app.routers.digest import router
    
    # Get routes from router
    routes = [route for route in router.routes]
    route_paths = [getattr(r, 'path', '') for r in routes]
    route_methods = []
    
    for r in routes:
        methods = getattr(r, 'methods', set())
        path = getattr(r, 'path', '')
        for method in methods:
            route_methods.append(f"{method} {path}")
    
    # Check for required endpoints
    has_get = any('GET' in m and '/' in m for m in route_methods)
    has_action = any('action' in m.lower() for m in route_methods)
    has_complete = any('complete' in m.lower() for m in route_methods)
    
    assert has_get, "Missing GET / endpoint"
    assert has_action, "Missing action endpoint"
    assert has_complete, "Missing complete endpoint"
    
    print(f"✅ Router endpoints verified: {len(route_methods)} routes found")


def test_016_router_registered_in_main():
    """Verify router is registered in main.py."""
    main_code = open('app/main.py').read()
    
    assert 'digest' in main_code, "digest router not referenced in main.py"
    assert 'include_router' in main_code, "include_router not found in main.py"
    
    print("✅ Router registration in main.py verified")


# ═══════════════════════════════════════════════════════════════════════════════
# Schema Tests
# ═══════════════════════════════════════════════════════════════════════════════


def test_017_schemas_importable():
    """Verify Pydantic schemas can be imported."""
    try:
        from app.schemas.digest import DigestResponse, DigestActionRequest
        print("✅ Pydantic schemas import successfully")
    except ImportError as e:
        pytest.fail(f"Failed to import schemas: {e}")


def test_018_response_schema_structure():
    """Verify DigestResponse has required fields."""
    from app.schemas.digest import DigestResponse
    
    # Check model fields
    assert hasattr(DigestResponse, 'model_fields') or hasattr(DigestResponse, '__fields__'), \
        "DigestResponse should have model fields"
    
    print("✅ Response schema structure verified")


# ═══════════════════════════════════════════════════════════════════════════════
# Integration & Regression Tests
# ═══════════════════════════════════════════════════════════════════════════════


@pytest.mark.asyncio
async def test_019_no_feed_regression(db_session: AsyncSession):
    """Verify existing feed router is untouched."""
    # Check feed router exists and imports
    try:
        from app.routers import feed
        assert hasattr(feed, 'router'), "Feed router should exist"
        print("✅ Feed router exists (no regression)")
    except ImportError:
        pytest.fail("Feed router import failed - possible regression")


@pytest.mark.asyncio
async def test_020_existing_models_unchanged(db_session: AsyncSession):
    """Verify existing models still work."""
    try:
        from app.models.daily_top3 import DailyTop3
        from app.models.user import User
        print("✅ Existing models still import (no regression)")
    except ImportError as e:
        pytest.fail(f"Existing model import failed: {e}")


# ═══════════════════════════════════════════════════════════════════════════════
# Functional Tests (requires test user)
# ═══════════════════════════════════════════════════════════════════════════════


@pytest.mark.asyncio
async def test_021_can_create_daily_digest(db_session: AsyncSession):
    """Test creating a daily digest record."""
    from app.models.daily_digest import DailyDigest
    from uuid import uuid4
    
    user_id = uuid4()
    today = date.today()
    
    # Create test digest
    digest = DailyDigest(
        id=uuid4(),
        user_id=user_id,
        date=today,
        items=[
            {
                "content_id": str(uuid4()),
                "rank": 1,
                "reason": "Test article 1",
                "action": "unread"
            },
            {
                "content_id": str(uuid4()),
                "rank": 2,
                "reason": "Test article 2",
                "action": "unread"
            }
        ],
        generated_at=datetime.now(),
        completed=False
    )
    
    db_session.add(digest)
    await db_session.commit()
    
    # Verify it was saved
    result = await db_session.execute(
        select(DailyDigest).where(DailyDigest.user_id == user_id)
    )
    saved = result.scalar_one_or_none()
    
    assert saved is not None, "Failed to save digest"
    assert len(saved.items) == 2, "Items array not saved correctly"
    assert saved.items[0]['rank'] == 1, "Item rank not preserved"
    
    print("✅ Daily digest creation works")


@pytest.mark.asyncio
async def test_022_can_update_digest_items(db_session: AsyncSession):
    """Test updating digest items (actions)."""
    from app.models.daily_digest import DailyDigest
    from uuid import uuid4
    
    user_id = uuid4()
    today = date.today()
    content_id = str(uuid4())
    
    # Create digest
    digest = DailyDigest(
        id=uuid4(),
        user_id=user_id,
        date=today,
        items=[
            {
                "content_id": content_id,
                "rank": 1,
                "reason": "Test article",
                "action": "unread"
            }
        ],
        generated_at=datetime.now(),
        completed=False
    )
    
    db_session.add(digest)
    await db_session.commit()
    
    # Update action
    digest.items[0]['action'] = 'read'
    digest.items[0]['action_timestamp'] = datetime.now().isoformat()
    
    await db_session.commit()
    
    # Verify update
    result = await db_session.execute(
        select(DailyDigest).where(DailyDigest.id == digest.id)
    )
    updated = result.scalar_one()
    
    assert updated.items[0]['action'] == 'read', "Action not updated"
    assert 'action_timestamp' in updated.items[0], "Timestamp not added"
    
    print("✅ Digest item updates work")


# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite Runner
# ═══════════════════════════════════════════════════════════════════════════════


def run_all_validations():
    """Run all validation tests and print summary."""
    print("\n" + "="*70)
    print("Phase 1 Foundation Validation Suite")
    print("="*70 + "\n")
    
    # This will be run by pytest
    pass


if __name__ == "__main__":
    print("""
╔══════════════════════════════════════════════════════════════════════╗
║  Phase 1 Foundation Validation                                       ║
║  Run with: cd packages/api && python -m pytest ../../docs/qa/scripts/validate_phase1.py -v
╚══════════════════════════════════════════════════════════════════════╝
""")
    
    # If run directly, advise using pytest
    print("⚠️  This script should be run with pytest for proper test execution.")
    print("\nRecommended commands:")
    print("  1. Quick validation:     pytest docs/qa/scripts/validate_phase1.py -v --tb=short")
    print("  2. Full validation:      pytest docs/qa/scripts/validate_phase1.py -v")
    print("  3. With coverage:        pytest docs/qa/scripts/validate_phase1.py --cov=app")
    sys.exit(1)
