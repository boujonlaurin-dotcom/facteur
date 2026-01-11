import asyncio
import os
import sys
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine
from dotenv import load_dotenv

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL")

async def apply_sql(file_path):
    if not DATABASE_URL:
        return
    engine = create_async_engine(DATABASE_URL)
    try:
        with open(file_path, 'r') as f:
            sql = f.read()
        raw_statements = sql.split(';')
        statements = []
        for raw in raw_statements:
            lines = [line for line in raw.split('\n') if not line.strip().startswith('--')]
            stmt = ' '.join(lines).strip()
            if stmt:
                statements.append(stmt)
        async with engine.begin() as conn:
            for statement in statements:
                await conn.execute(text(statement))
            print(f"✅ Applied {len(statements)} statements from {file_path}")
    finally:
        await engine.dispose()

if __name__ == "__main__":
    if len(sys.argv) > 1:
        asyncio.run(apply_sql(sys.argv[1]))
