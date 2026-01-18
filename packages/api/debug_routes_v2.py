import sys
import os

sys.path.append(os.getcwd())

try:
    from app.main import app
    
    with open("debug_routes_output.txt", "w") as f:
        f.write("--- Registered Routes ---\n")
        for route in app.routes:
            if hasattr(route, "path"):
                methods = ", ".join(route.methods) if hasattr(route, "methods") else "None"
                f.write(f"{methods} {route.path}\n")
        f.write("-------------------------\n")
        
    print("Routes written to debug_routes_output.txt")
except Exception as e:
    with open("debug_routes_error.txt", "w") as f:
        f.write(str(e))
    print(f"Error: {e}")
