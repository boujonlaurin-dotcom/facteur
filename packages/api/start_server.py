import uvicorn
import sys
import os

# Set working directory to this file's directory
os.chdir(os.path.dirname(os.path.abspath(__file__)))

# Redirect output
sys.stdout = open('server_stdout.log', 'w')
sys.stderr = open('server_stderr.log', 'w')

print("Starting server...")

if __name__ == "__main__":
    try:
        uvicorn.run("app.main:app", host="0.0.0.0", port=8000)
    except Exception as e:
        print(f"Error: {e}")
