from unittest.mock import MagicMock
from app.services.recommendation.layers.visual import VisualLayer
from app.services.recommendation.scoring_engine import ScoringContext
from app.models.content import Content
from app.services.recommendation.scoring_config import ScoringWeights
import uuid

def test_visual_layer_boost():
    print("Testing VisualLayer boost...")
    
    layer = VisualLayer()
    context = ScoringContext(
        user_profile=None,
        user_interests=set(),
        user_interest_weights={},
        followed_source_ids=set(),
        user_prefs={},
        now=None
    )
    context.reasons = {}
    
    # 1. Content without thumbnail
    content_no_img = Content(
        id=uuid.uuid4(),
        thumbnail_url=None
    )
    score_no_img = layer.score(content_no_img, context)
    print(f"Score for content without image: {score_no_img}")
    assert score_no_img == 0.0
    
    # 2. Content with empty thumbnail
    content_empty_img = Content(
        id=uuid.uuid4(),
        thumbnail_url="  "
    )
    score_empty_img = layer.score(content_empty_img, context)
    print(f"Score for content with empty image: {score_empty_img}")
    assert score_empty_img == 0.0
    
    # 3. Content with thumbnail
    content_with_img = Content(
        id=uuid.uuid4(),
        thumbnail_url="https://example.com/image.jpg"
    )
    score_with_img = layer.score(content_with_img, context)
    print(f"Score for content with image: {score_with_img}")
    assert score_with_img == ScoringWeights.IMAGE_BOOST
    assert content_with_img.id in context.reasons
    assert context.reasons[content_with_img.id][0]['layer'] == 'visual'
    
    print("✅ VisualLayer verification PASSED!")

if __name__ == "__main__":
    # Setup PYTHONPATH if needed or mock imports
    # For this demonstration, we assume the environment is set up.
    try:
        test_visual_layer_boost()
    except Exception as e:
        print(f"❌ Verification FAILED: {e}")
        import traceback
        traceback.print_exc()
