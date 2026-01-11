import pytest
from unittest.mock import MagicMock, AsyncMock
from datetime import datetime
from uuid import uuid4

from app.services.sync_service import SyncService
from app.models.source import Source
from app.models.enums import SourceType, ContentType
from app.models.content import Content

# Mock data
MOCK_RSS_ENTRY = {
    "title": "Test Article",
    "link": "https://example.com/article",
    "id": "guid:123",
    "published_parsed": (2024, 1, 1, 12, 0, 0, 0, 0, 0),
    "summary": "Description of article"
}

MOCK_YOUTUBE_ENTRY = {
    "title": "Test Video",
    "link": "https://youtube.com/watch?v=123",
    "id": "yt:video:123",
    "published_parsed": (2024, 1, 1, 12, 0, 0, 0, 0, 0),
    "summary": "Video description"
}

@pytest.fixture
def mock_session():
    session = AsyncMock()
    # Mock result object
    mock_result = MagicMock()
    mock_scalars = MagicMock()
    mock_first = MagicMock()
    
    mock_result.scalars.return_value = mock_scalars
    mock_scalars.first.return_value = None # Default no existing
    
    session.execute.return_value = mock_result
    return session

@pytest.fixture
def sync_service(mock_session):
    service = SyncService(mock_session)
    return service

@pytest.mark.asyncio
async def test_parse_entry_article(sync_service):
    source = Source(id=uuid4(), type=SourceType.ARTICLE)
    entry = MagicMock()
    # Configure dictionary access
    def get_side_effect(key, default=None):
        return MOCK_RSS_ENTRY.get(key, default)
    
    entry.get.side_effect = get_side_effect
    entry.__contains__.side_effect = lambda k: k in MOCK_RSS_ENTRY
    entry.published_parsed = MOCK_RSS_ENTRY["published_parsed"]
    
    result = sync_service._parse_entry(entry, source)
    
    assert result["title"] == "Test Article"
    assert result["content_type"] == ContentType.ARTICLE
    assert result["guid"] == "guid:123"

@pytest.mark.asyncio
async def test_parse_entry_youtube(sync_service):
    source = Source(id=uuid4(), type=SourceType.YOUTUBE)
    entry = MagicMock()
    
    # Configure dictionary access including media_group
    def get_side_effect(key, default=None):
        return MOCK_YOUTUBE_ENTRY.get(key, default)
    
    entry.get.side_effect = get_side_effect
    
    # Configure 'in' operator to return True for media_group
    entry.__contains__.side_effect = lambda k: k in MOCK_YOUTUBE_ENTRY or k == "media_group"
    
    entry.published_parsed = MOCK_YOUTUBE_ENTRY["published_parsed"]
    entry.summary = MOCK_YOUTUBE_ENTRY["summary"]
    
    # Mock media_group object structure
    media_group = MagicMock()
    media_group.__contains__.side_effect = lambda k: k in ["media_thumbnail", "media_description"]
    media_group.media_thumbnail = [{"url": "https://img.youtube.com/vi/123/hqdefault.jpg"}]
    media_group.media_description = "Full media description"
    
    entry.media_group = media_group
    
    result = sync_service._parse_entry(entry, source)
    
    assert result["title"] == "Test Video"
    assert result["content_type"] == ContentType.YOUTUBE
    assert result["thumbnail_url"] == "https://img.youtube.com/vi/123/hqdefault.jpg"
    assert result["description"] == "Full media description"

@pytest.mark.asyncio
async def test_save_content_deduplication(sync_service, mock_session):
    # Setup: content already exists
    mock_existing = Content(id=uuid4(), guid="guid:123")
    
    # Setup the return chain properly
    mock_result = MagicMock()
    mock_session.execute.return_value = mock_result
    mock_result.scalars.return_value.first.return_value = mock_existing
    
    data = {
        "source_id": uuid4(),
        "title": "New Title",
        "url": "http://url",
        "guid": "guid:123", # Same GUID
        "published_at": datetime.now(),
        "content_type": ContentType.ARTICLE,
        "description": "desc",
        "thumbnail_url": "thumb",
        "duration_seconds": None
    }
    
    is_new = await sync_service._save_content(data)
    
    assert is_new is False
    # Check if we updated the existing content
    assert mock_existing.thumbnail_url == "thumb"
    
@pytest.mark.asyncio
async def test_thumbnail_optimization(sync_service):
    # Courrier International
    url = "https://focus.courrierinternational.com/644/0/60/0/img.jpg"
    optimized = sync_service._optimize_thumbnail_url(url)
    assert "/1200/" in optimized
    
    # Wordpress
    url = "https://site.com/uploads/image-150x150.jpg"
    optimized = sync_service._optimize_thumbnail_url(url)
    assert optimized == "https://site.com/uploads/image.jpg"
