
import sys
import os
from pathlib import Path
from dotenv import load_dotenv

print(f"1. Initial (Shell) DATABASE_URL: {os.environ.get('DATABASE_URL', 'Not Set')}")

env_path = Path(__file__).parent.parent / ".env"
print(f"2. Loading .env from: {env_path}")
if env_path.exists():
    print("   .env file exists.")
else:
    print("   .env file DOES NOT exist.")

# Mimic app/config.py behavior
load_dotenv(env_path, override=True)

print(f"3. After load_dotenv(override=True) DATABASE_URL: {os.environ.get('DATABASE_URL', 'Not Set')}")

# Check mismatch
shell_url = sys.argv[1] if len(sys.argv) > 1 else ""
current_url = os.environ.get('DATABASE_URL', '')

if shell_url and shell_url != current_url:
    print("⚠️  MISMATCH DETECTED: Shell URL was overwritten by .env!")
    
# Try listing tables with current URL
if current_url:
    if "+asyncpg" in current_url:
        current_url = current_url.replace("+asyncpg", "+psycopg")
    elif "postgres://" in current_url:
        current_url = current_url.replace("postgres://", "postgresql+psycopg://")
    if "?" not in current_url:
        current_url += "?sslmode=require"
    
    print(f"4. Connecting to: {current_url.split('@')[-1]}") # Hide credentials
    try:
        from sqlalchemy import create_engine, inspect
        engine = create_engine(current_url)
        print(f"   Tables: {inspect(engine).get_table_names()}")
    except Exception as e:
        print(f"   Connection failed: {e}")
