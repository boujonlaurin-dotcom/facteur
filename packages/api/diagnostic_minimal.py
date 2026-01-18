
import sys
import asyncio
from fastapi import FastAPI
import uvicorn
import time

# Minimal app - No DB, No Scheduler, No Middlewares
app = FastAPI()

@app.get("/health")
async def health():
    return {"status": "ok", "time": time.time()}

if __name__ == "__main__":
    print("🚀 Starting MINIMAL diagnostic server on port 8081...", flush=True)
    try:
        uvicorn.run(app, host="0.0.0.0", port=8081)
    except KeyboardInterrupt:
        print("Stopping.")
