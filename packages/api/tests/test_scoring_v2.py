import pytest
from datetime import datetime, timedelta
from uuid import uuid4

from app.models.content import Content
from app.models.source import Source
from app.models.enums import ContentType, ContentStatus
from app.services.recommendation.scoring_engine import ScoringEngine, ScoringContext
from app.services.recommendation.layers import (
    CoreLayer, StaticPreferenceLayer, BehavioralLayer, 
    ArticleTopicLayer, PersonalizationLayer
)

# --- Fixtures ---

@pytest.fixture
def mock_now():
    return datetime.utcnow()

@pytest.fixture
def mock_content():
    source = Source(id=uuid4(), name="TechSource", theme="tech")
    return Content(
        id=uuid4(),
        title="Test Content",
        url="http://example.com",
        source_id=source.id,
        source=source,
        published_at=datetime.utcnow() - timedelta(hours=2), # 2 hours old
        content_type=ContentType.ARTICLE,
        duration_seconds=300 # 5 min
    )

@pytest.fixture
def base_context(mock_now):
    return ScoringContext(
        user_profile=None,
        user_interests={"tech"},
        user_interest_weights={"tech": 1.0},
        followed_source_ids=set(),
        muted_sources=set(),
        muted_themes=set(),
        muted_topics=set(),
        user_prefs={},
        now=mock_now
    )

# --- CoreLayer Tests ---

def test_core_layer_theme_match(mock_content, base_context):
    layer = CoreLayer()
    score = layer.score(mock_content, base_context)
    # Theme Match (50) + Recency (~27) + Source Standard (10)
    assert score > 80.0
    assert "Theme match: tech" in [r['details'] for r in base_context.reasons[mock_content.id]]

def test_core_layer_theme_match_single_taxonomy(base_context):
    """Verify that a source with a Slug theme matches a user with a Slug interest."""
    source = Source(id=uuid4(), name="TechSource", theme="tech") # Slug
    content = Content(
        id=uuid4(),
        title="Test Content",
        url="http://example.com",
        source_id=source.id,
        source=source,
        published_at=datetime.utcnow(),
        content_type=ContentType.ARTICLE
    )
    
    layer = CoreLayer()
    score = layer.score(content, base_context)
    
    # Needs to be > 70 (Theme Match 70 + Source Standard 10 + Recency ~30)
    assert score > 100.0 
    assert "Theme match: tech" in [r['details'] for r in base_context.reasons[content.id]]

def test_core_layer_source_affinity(mock_content, base_context):
    base_context.followed_source_ids.add(mock_content.source_id)
    layer = CoreLayer()
    score = layer.score(mock_content, base_context)
    # +30 compared to standard (40 vs 10)
    assert score > 100.0 # 70 + 40 + ~27 = 137

# --- StaticPreferenceLayer Tests ---

def test_static_prefs_recency_boost(mock_content, base_context):
    base_context.user_prefs["content_recency"] = "recent"
    layer = StaticPreferenceLayer()
    score = layer.score(mock_content, base_context)
    assert score == 15.0 

def test_static_prefs_format_short(mock_content, base_context):
    base_context.user_prefs["format_preference"] = "short"
    mock_content.duration_seconds = 200 # < 300
    layer = StaticPreferenceLayer()
    score = layer.score(mock_content, base_context)
    assert score == 15.0

def test_static_prefs_format_audio(mock_content, base_context):
    base_context.user_prefs["format_preference"] = "audio"
    mock_content.content_type = ContentType.PODCAST
    layer = StaticPreferenceLayer()
    score = layer.score(mock_content, base_context)
    assert score == 20.0

# --- BehavioralLayer Tests ---

def test_behavioral_layer_bonus(mock_content, base_context):
    base_context.user_interest_weights["tech"] = 1.5
    layer = BehavioralLayer()
    score = layer.score(mock_content, base_context)
    assert score == 25.0

def test_behavioral_layer_malus(mock_content, base_context):
    base_context.user_interest_weights["tech"] = 0.5
    layer = BehavioralLayer()
    score = layer.score(mock_content, base_context)
    assert score == -25.0

# --- Engine Test ---

def test_scoring_engine_integration(mock_content, base_context):
    base_context.user_prefs["format_preference"] = "short" # +15
    base_context.user_interest_weights["tech"] = 1.2 # +10 bonus
    
    engine = ScoringEngine([CoreLayer(), StaticPreferenceLayer(), BehavioralLayer()])
    total_score = engine.compute_score(mock_content, base_context)
    
    assert total_score > 110.0


# --- ArticleTopicLayer Tests (Story 4.1d) ---

def test_article_topic_layer_no_match(base_context):
    source = Source(id=uuid4(), name="TechSource", theme="tech")
    content = Content(
        id=uuid4(),
        title="Test Content",
        url="http://example.com",
        source_id=source.id,
        source=source,
        published_at=datetime.utcnow(),
        content_type=ContentType.ARTICLE,
        topics=["ai", "crypto"] 
    )
    base_context.user_subtopics = set()
    layer = ArticleTopicLayer()
    score = layer.score(content, base_context)
    assert score == 0.0

def test_article_topic_layer_single_match(base_context):
    source = Source(id=uuid4(), name="TechSource", theme="tech")
    content = Content(
        id=uuid4(),
        title="AI News",
        url="http://example.com",
        source_id=source.id,
        source=source,
        published_at=datetime.utcnow(),
        content_type=ContentType.ARTICLE,
        topics=["ai", "space"]
    )
    base_context.user_subtopics = {"ai", "climate"}
    layer = ArticleTopicLayer()
    score = layer.score(content, base_context)
    assert score == 80.0

# --- PersonalizationLayer Tests (Story 4.7) ---

def test_personalization_layer_muted_source(mock_content, base_context):
    base_context.muted_sources.add(mock_content.source_id)
    layer = PersonalizationLayer()
    score = layer.score(mock_content, base_context)
    assert score == -80.0
    assert "Tu vois moins de cette source" in [r['details'] for r in base_context.reasons[mock_content.id]]

def test_personalization_layer_muted_theme(mock_content, base_context):
    base_context.muted_themes.add("tech")
    layer = PersonalizationLayer()
    score = layer.score(mock_content, base_context)
    assert score == -40.0
    assert "Tu vois moins de tech" in [r['details'] for r in base_context.reasons[mock_content.id]]

def test_personalization_layer_muted_topic(mock_content, base_context):
    mock_content.topics = ["ai"]
    base_context.muted_topics.add("ai")
    layer = PersonalizationLayer()
    score = layer.score(mock_content, base_context)
    assert score == -30.0
    assert "Tu vois moins de ai" in [r['details'] for r in base_context.reasons[mock_content.id]]
