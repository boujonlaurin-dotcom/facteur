"""Test script for hybrid clustering."""

import asyncio
import os
import sys
from dotenv import load_dotenv
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker, selectinload
from sqlalchemy import select, func

sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from app.services.story_service import StoryService
from app.models.content import Content

load_dotenv()
DATABASE_URL = os.getenv("DATABASE_URL")


async def test_hybrid_clustering():
    """Test the hybrid clustering algorithm."""
    engine = create_async_engine(DATABASE_URL)
    AsyncSessionLocal = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    
    async with AsyncSessionLocal() as session:
        service = StoryService(session)
        
        print("🔍 Hybrid Clustering Test")
        print("=" * 60)
        
        # Run hybrid clustering
        clustered, total, num_clusters = await service.cluster_hybrid(
            time_window_hours=168  # 7 days
        )
        
        rate = (clustered / total * 100) if total > 0 else 0
        
        print(f"\n📊 Results:")
        print(f"   Total articles: {total}")
        print(f"   Clustered: {clustered}")
        print(f"   Clustering rate: {rate:.1f}%")
        print(f"   Number of clusters: {num_clusters}")
        if num_clusters > 0:
            print(f"   Avg cluster size: {clustered / num_clusters:.1f}")
        
        # Show example clusters
        print("\n" + "=" * 60)
        print("\n📰 Example clusters (by size):")
        
        result = await session.execute(
            select(Content.cluster_id, func.count(Content.id).label('cnt'))
            .where(Content.cluster_id.isnot(None))
            .group_by(Content.cluster_id)
            .order_by(func.count(Content.id).desc())
            .limit(10)
        )
        
        clusters = result.all()
        
        for cluster_id, count in clusters:
            print(f"\n  📦 Cluster (size={count}):")
            
            result = await session.execute(
                select(Content).options(selectinload(Content.source))
                .where(Content.cluster_id == cluster_id)
                .order_by(Content.published_at.desc())
            )
            articles = result.scalars().all()
            
            # Extract common keywords
            all_keywords = [service._extract_topic_keywords(a.title) for a in articles]
            if all_keywords and len(all_keywords) > 1:
                common = set.intersection(*all_keywords)
                print(f"     Common keywords: {', '.join(common) if common else '(various)'}")
            
            for article in articles[:5]:
                src = article.source.name[:18] if article.source else "?"
                bias = article.source.bias_stance.value if article.source else "?"
                theme = article.source.theme[:8] if article.source else "?"
                print(f"    [{bias:^12}|{theme:^8}] {src:18} | {article.title[:40]}...")
    
    await engine.dispose()


if __name__ == "__main__":
    asyncio.run(test_hybrid_clustering())
