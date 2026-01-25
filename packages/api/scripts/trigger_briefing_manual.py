import asyncio
import sys
import os
import structlog

# Adjust path to find app module
sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

from app.workers.top3_job import generate_daily_top3_job

# Configure basic logging
structlog.configure(
    processors=[structlog.processors.JSONRenderer()],
    logger_factory=structlog.PrintLoggerFactory(),
)

async def trigger_manual():
    print("🚀 Triggering Daily Briefing manually...")
    try:
        await generate_daily_top3_job(trigger_manual=True)
        print("✅ Daily Briefing generated.")
    except Exception as e:
        print(f"❌ Error: {e}")

if __name__ == "__main__":
    asyncio.run(trigger_manual())
