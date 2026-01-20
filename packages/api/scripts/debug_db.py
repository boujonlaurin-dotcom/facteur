
import sys
import os
from sqlalchemy import create_engine, inspect
from dotenv import load_dotenv

# Load env same as app
load_dotenv(os.path.join(os.path.dirname(__file__), "../.env"))

db_url = os.environ.get("DATABASE_URL")
print(f"Raw DATABASE_URL: {db_url}")

if db_url:
    # Adapt for sync engine
    if "+asyncpg" in db_url:
        db_url = db_url.replace("+asyncpg", "+psycopg")
    elif "postgres://" in db_url:
        db_url = db_url.replace("postgres://", "postgresql+psycopg://")
    
    if "?" not in db_url:
        db_url += "?sslmode=require"
        
    print(f"Adapted DATABASE_URL: {db_url}")
    
    try:
        engine = create_engine(db_url)
        inspector = inspect(engine)
        tables = inspector.get_table_names()
        print(f"Tables found: {tables}")
        print(f"daily_top3 exists: {'daily_top3' in tables}")
    except Exception as e:
        print(f"Error connecting: {e}")
else:
    print("DATABASE_URL not found in env")
