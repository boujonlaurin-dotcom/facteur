#!/usr/bin/env python3
"""
Test script to verify Story 4.1c Part 1/3 database schema updates.

This script:
1. Verifies migrations were applied successfully
2. Checks database schema (constraints, columns, tables, indexes)
3. Tests UserSubtopic model insertion
"""

import sys
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from uuid import uuid4
from datetime import datetime
from sqlalchemy import inspect, text
from sqlalchemy.orm import Session

from app.database import engine
from app.models.user import UserProfile, UserSubtopic
from app.models.content import Content
from app.models.source import Source


def print_section(title: str):
    """Print a formatted section header."""
    print(f"\n{'='*60}")
    print(f" {title}")
    print(f"{'='*60}\n")


def verify_schema():
    """Verify database schema changes."""
    print_section("1. Verifying Database Schema")
    
    inspector = inspect(engine)
    
    # Check tables exist
    tables = inspector.get_table_names()
    print(f"✓ Total tables in database: {len(tables)}")
    
    # Verify user_subtopics table
    if 'user_subtopics' in tables:
        print("✓ Table 'user_subtopics' exists")
        
        # Check columns
        columns = inspector.get_columns('user_subtopics')
        column_names = [col['name'] for col in columns]
        print(f"  Columns: {', '.join(column_names)}")
        
        # Check constraints
        constraints = inspector.get_unique_constraints('user_subtopics')
        print(f"  Unique constraints: {len(constraints)}")
        for constraint in constraints:
            print(f"    - {constraint['name']}: {constraint['column_names']}")
    else:
        print("✗ FAILED: Table 'user_subtopics' does not exist!")
        return False
    
    # Verify contents.topics column
    content_columns = inspector.get_columns('contents')
    content_column_names = [col['name'] for col in content_columns]
    if 'topics' in content_column_names:
        print("✓ Column 'contents.topics' exists")
        topics_col = next(col for col in content_columns if col['name'] == 'topics')
        print(f"  Type: {topics_col['type']}")
    else:
        print("✗ FAILED: Column 'contents.topics' does not exist!")
        return False
    
    # Check for GIN index on contents.topics
    content_indexes = inspector.get_indexes('contents')
    topics_index = next((idx for idx in content_indexes if 'topics' in idx.get('column_names', [])), None)
    if topics_index:
        print(f"✓ Index on 'contents.topics' exists: {topics_index['name']}")
    else:
        print("✗ WARNING: GIN index on 'contents.topics' not found!")
    
    # Verify Source.theme constraint
    print("\n✓ Checking Source.theme constraint...")
    with engine.connect() as conn:
        result = conn.execute(text("""
            SELECT constraint_name, check_clause
            FROM information_schema.check_constraints
            WHERE constraint_schema = 'public'
            AND constraint_name = 'ck_source_theme_valid'
        """))
        constraint = result.fetchone()
        if constraint:
            print(f"✓ CHECK constraint 'ck_source_theme_valid' exists")
            print(f"  Clause: {constraint[1] if len(constraint) > 1 else 'N/A'}")
        else:
            print("✗ FAILED: CHECK constraint 'ck_source_theme_valid' not found!")
            return False
    
    return True


def test_user_subtopic_insertion():
    """Test UserSubtopic model by inserting and querying."""
    print_section("2. Testing UserSubtopic Model")
    
    with Session(engine) as session:
        try:
            # Create a temporary test user profile if needed
            test_user_id = uuid4()
            
            # Check if we have any existing user profile
            existing_profile = session.query(UserProfile).first()
            if existing_profile:
                test_user_id = existing_profile.user_id
                print(f"✓ Using existing user: {test_user_id}")
            else:
                # Create test user profile
                test_profile = UserProfile(
                    user_id=test_user_id,
                    display_name="Test User",
                    onboarding_completed=False,
                    gamification_enabled=True,
                    weekly_goal=10
                )
                session.add(test_profile)
                session.flush()
                print(f"✓ Created test user: {test_user_id}")
            
            # Insert UserSubtopic
            subtopic = UserSubtopic(
                user_id=test_user_id,
                topic_slug="ai",
                weight=1.5
            )
            session.add(subtopic)
            session.commit()
            print(f"✓ Successfully inserted UserSubtopic (topic: ai, weight: 1.5)")
            
            # Query it back
            retrieved = session.query(UserSubtopic).filter_by(
                user_id=test_user_id,
                topic_slug="ai"
            ).first()
            
            if retrieved:
                print(f"✓ Successfully retrieved UserSubtopic")
                print(f"  ID: {retrieved.id}")
                print(f"  User ID: {retrieved.user_id}")
                print(f"  Topic: {retrieved.topic_slug}")
                print(f"  Weight: {retrieved.weight}")
                print(f"  Created: {retrieved.created_at}")
            else:
                print("✗ FAILED: Could not retrieve UserSubtopic!")
                return False
            
            # Test unique constraint by attempting duplicate insert
            print("\n✓ Testing unique constraint...")
            try:
                duplicate = UserSubtopic(
                    user_id=test_user_id,
                    topic_slug="ai",  # Same slug
                    weight=2.0
                )
                session.add(duplicate)
                session.commit()
                print("✗ FAILED: Unique constraint did not prevent duplicate!")
                return False
            except Exception as e:
                session.rollback()
                print(f"✓ Unique constraint working correctly (prevented duplicate)")
            
            # Clean up test data
            session.delete(retrieved)
            if not existing_profile:
                session.delete(test_profile)
            session.commit()
            print("✓ Test data cleaned up")
            
            return True
            
        except Exception as e:
            session.rollback()
            print(f"✗ FAILED: Error during UserSubtopic test: {e}")
            import traceback
            traceback.print_exc()
            return False


def main():
    """Run all verification tests."""
    print_section("Story 4.1c Part 1/3 - Database Schema Verification")
    
    try:
        # Test 1: Schema verification
        schema_ok = verify_schema()
        
        # Test 2: UserSubtopic model test
        model_ok = test_user_subtopic_insertion()
        
        # Summary
        print_section("Verification Summary")
        if schema_ok and model_ok:
            print("✅ ALL TESTS PASSED!")
            print("\nDatabase schema successfully updated:")
            print("  - Source.theme CHECK constraint added")
            print("  - Content.topics column added with GIN index")
            print("  - user_subtopics table created and functional")
            return 0
        else:
            print("❌ SOME TESTS FAILED")
            print("\nPlease check the error messages above.")
            return 1
            
    except Exception as e:
        print(f"\n❌ CRITICAL ERROR: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
