
import pytest
from app.models.source import Source, SourceType, BiasStance, ReliabilityScore
from sqlalchemy.ext.asyncio import AsyncSession

@pytest.mark.asyncio
async def test_source_lifecycle_states(db_session: AsyncSession):
    # Test INDEXED source
    indexed_source = Source(
        name="Indexed Source",
        url="https://example.com",
        feed_url="https://example.com/rss",
        type=SourceType.ARTICLE,
        is_curated=False,
        bias_stance=BiasStance.CENTER,
        reliability_score=ReliabilityScore.HIGH
    )
    db_session.add(indexed_source)
    await db_session.commit()
    
    # Test CURATED source
    curated_source = Source(
        name="Curated Source",
        url="https://trusted.com",
        feed_url="https://trusted.com/rss",
        type=SourceType.ARTICLE,
        is_curated=True,
        score_independence=0.9,
        score_rigor=0.9,
        score_ux=0.9,
        description="Rationale for curation"
    )
    db_session.add(curated_source)
    await db_session.commit()

    # Verify retrieval
    from sqlalchemy import select
    
    result = await db_session.execute(select(Source).where(Source.is_curated == True))
    curated = result.scalars().first()
    assert curated.name == "Curated Source"
    assert curated.score_independence == 0.9
    
    result = await db_session.execute(select(Source).where(Source.is_curated == False))
    indexed = result.scalars().first()
    assert indexed.name == "Indexed Source"
    assert indexed.score_independence is None

def test_source_model_defaults():
    source = Source(name="Test")
    assert source.is_curated is False
    assert source.is_active is True

def test_master_csv_quality():
    import csv
    import os
    
    # Path relative to project root
    root_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
    csv_path = os.path.join(root_dir, "sources", "sources_master.csv")
    
    assert os.path.exists(csv_path), f"CSV path {csv_path} does not exist"
    
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for i, row in enumerate(reader, 1):
            name = row.get("Name")
            status = row.get("Status")
            
            if not name or name.startswith("#"): continue
            
            # 1. Status must be valid
            assert status in ["ARCHIVED", "INDEXED", "CURATED"], f"Invalid status {status} for {name}"
            
            # 2. CURATED sources must have a Rationale and Scores
            if status == "CURATED":
                assert row.get("Rationale"), f"Missing Rationale for curated source: {name}"
                assert row.get("Score_Independence"), f"Missing Score_Independence for: {name}"
                assert row.get("Score_Rigor"), f"Missing Score_Rigor for: {name}"
                assert row.get("Score_UX"), f"Missing Score_UX for: {name}"
            
            # 3. INDEXED sources must have Bias and Reliability
            if status == "INDEXED":
                assert row.get("Bias"), f"Missing Bias for indexed source: {name}"
                assert row.get("Reliability"), f"Missing Reliability for: {name}"
