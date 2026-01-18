import asyncio
from app.database import async_session_maker
from app.models.source import Source
from sqlalchemy import select, func

async def count():
    async with async_session_maker() as s:
        res = await s.execute(select(func.count(Source.id)))
        total = res.scalar()
    
    async with async_session_maker() as s:
        res = await s.execute(select(func.count(Source.id)).where(Source.is_curated == True))
        curated = res.scalar()
        
    with open("count_result.txt", "w") as f:
        f.write(f"Total: {total}\nCurated: {curated}\n")

if __name__ == "__main__":
    asyncio.run(count())
