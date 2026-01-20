#!/usr/bin/env python3
"""Terminate blocking database connections to resolve deadlock."""
import asyncio
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from sqlalchemy import text
from app.database import engine

async def terminate_locks():
    """Find and terminate blocking connections on sources table."""
    async with engine.connect() as conn:
        # Find blocking queries
        result = await conn.execute(text("""
            SELECT pid, state, query, query_start, wait_event_type, wait_event
            FROM pg_stat_activity 
            WHERE pid != pg_backend_pid()
            AND (
                state = 'active' 
                OR state = 'idle in transaction'
            )
            AND (query LIKE '%sources%' OR query LIKE '%contents%' OR query LIKE '%alembic%' OR query LIKE '%ALTER%')
            ORDER BY query_start
        """))
        rows = result.fetchall()
        
        if not rows:
            print("✓ No blocking queries found")
        else:
            print(f"Found {len(rows)} active queries:")
            for row in rows:
                print(f"  PID: {row[0]}, State: {row[1]}, Query: {row[2][:80]}...")
            
            print("\nTerminating these connections...")
            for row in rows:
                await conn.execute(text(f"SELECT pg_terminate_backend({row[0]})"))
                print(f"  ✓ Terminated PID {row[0]}")
        
        await conn.commit()
        print("\n✅ Done. Please retry the migration.")

if __name__ == "__main__":
    asyncio.run(terminate_locks())
