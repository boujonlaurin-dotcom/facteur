import sys
import os

# Add the current directory to sys.path to ensure we can import the app
sys.path.append(os.getcwd())

from app.main import app

print("\n--- Registered Routes ---")
for route in app.routes:
    if hasattr(route, "path"):
        methods = ", ".join(route.methods) if hasattr(route, "methods") else "None"
        print(f"{methods} {route.path}")
print("-------------------------\n")
