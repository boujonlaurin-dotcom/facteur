import os
from dotenv import load_dotenv
from pathlib import Path
from urllib.parse import urlparse

env_path = Path("packages/api/.env")
load_dotenv(env_path)

db_url = os.getenv("DATABASE_URL")
if db_url:
    parsed = urlparse(db_url)
    print(f"DB Host: {parsed.hostname}")
    print(f"DB Port: {parsed.port}")
    print(f"DB Name: {parsed.path}")
else:
    print("DATABASE_URL not found")
