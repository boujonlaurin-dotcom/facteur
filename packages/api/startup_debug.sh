#!/bin/bash
# startup_debug.sh
cd "$(dirname "$0")"
echo "Current directory: $(pwd)" > debug_startup.log
source venv/bin/activate
echo "Venv activated. Python: $(which python)" >> debug_startup.log

# Check if port 8000 is free
lsof -i :8000 >> debug_startup.log 2>&1 || echo "Port 8000 free" >> debug_startup.log

echo "Starting uvicorn..." >> debug_startup.log
nohup uvicorn app.main:app --host 0.0.0.0 --port 8000 >> backend_output.log 2>&1 &
PID=$!
echo "Uvicorn started in background with PID $PID" >> debug_startup.log
