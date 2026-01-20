from app.schemas.content import ContentResponse
from app.models.enums import ContentType, ContentStatus
import uuid
from datetime import datetime

def test_schema_description():
    data = {
        "id": uuid.uuid4(),
        "title": "Test Title",
        "url": "https://example.com",
        "thumbnail_url": None,
        "content_type": ContentType.ARTICLE,
        "duration_seconds": None,
        "published_at": datetime.utcnow(),
        "source": {
            "id": uuid.uuid4(),
            "name": "Test Source",
            "logo_url": None,
            "type": "ARTICLE",
            "theme": None
        },
        "status": ContentStatus.UNSEEN,
        "is_saved": False,
        "is_hidden": False,
        "description": "This is a test description"
    }
    
    response = ContentResponse(**data)
    print(f"Schema validated with description: {response.description}")
    assert response.description == "This is a test description"

if __name__ == "__main__":
    test_schema_description()
