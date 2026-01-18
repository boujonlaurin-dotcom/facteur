import os
import sys
import asyncio
from pathlib import Path

# Set up paths
project_root = "/Users/laurinboujon/Desktop/Projects/Work Projects/Facteur"
os.chdir(project_root)
sys.path.append(os.path.join(project_root, "packages/api"))

from scripts.import_sources import main as import_main

async def run():
    print("Starting import...")
    # Mock sys.argv to pass arguments to import_sources.main
    sys.argv = ["import_sources.py", "--start-at", "11", "--limit", "36"]
    
    try:
        await import_main()
        with open("sync_success.txt", "w") as f:
            f.write("Import completed successfully at 12:10")
    except Exception as e:
        with open("sync_error.txt", "w") as f:
            f.write(f"Import failed: {str(e)}")

if __name__ == "__main__":
    asyncio.run(run())
