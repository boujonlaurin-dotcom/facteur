#!/usr/bin/env python3
"""
Independent validation script to prove Story 4.1c Part 1/3 completion.
This script strictly queries the database schema to show current state.
"""
import asyncio
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from sqlalchemy import text
from app.database import engine

async def prove_schema_state():
    print("\n🔍 VERIFICATION INDÉPENDANTE DU SCHÉMA\n")
    
    async with engine.connect() as conn:
        # 1. Vérification Contrainte Source.theme
        result = await conn.execute(text("""
            SELECT constraint_name, check_clause 
            FROM information_schema.check_constraints 
            WHERE constraint_name = 'ck_source_theme_valid'
        """))
        constraint = result.fetchone()
        
        print("1️⃣ Contrainte Source.theme :")
        if constraint:
            print(f"   ✅ PRÉSENTE. Clause: {constraint.check_clause}")
        else:
            print("   ❌ ABSENTE")

        # 2. Vérification Colonne Content.topics + Index
        result = await conn.execute(text("""
            SELECT column_name, data_type 
            FROM information_schema.columns 
            WHERE table_name = 'contents' AND column_name = 'topics'
        """))
        col = result.fetchone()
        
        print("\n2️⃣ Colonne Content.topics :")
        if col:
            print(f"   ✅ PRÉSENTE. Type: {col.data_type}")
            # Verif Index
            idx_res = await conn.execute(text("""
                SELECT indexname, indexdef FROM pg_indexes 
                WHERE tablename = 'contents' AND indexname = 'ix_contents_topics'
            """))
            idx = idx_res.fetchone()
            if idx:
                print(f"   ✅ INDEX GIN PRÉSENT: {idx.indexdef}")
            else:
                print("   ❌ INDEX MANQUANT")
        else:
            print("   ❌ ABSENTE")

        # 3. Vérification Table user_subtopics
        result = await conn.execute(text("""
            SELECT column_name, data_type 
            FROM information_schema.columns 
            WHERE table_name = 'user_subtopics'
        """))
        cols = result.fetchall()
        
        print("\n3️⃣ Table user_subtopics :")
        if cols:
            print(f"   ✅ PRÉSENTE ({len(cols)} colonnes)")
            for c in cols:
                print(f"      - {c.column_name}: {c.data_type}")
        else:
            print("   ❌ ABSENTE")
            
    print("\n---------------------------------------------------")

if __name__ == "__main__":
    asyncio.run(prove_schema_state())
