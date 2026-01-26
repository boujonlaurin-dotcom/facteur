import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from app.services.rss_parser import RSSParser, DetectedFeed

@pytest.mark.asyncio
async def test_parse_direct_rss_feed():
    """Test parsing a direct valid RSS feed URL."""
    parser = RSSParser()
    
    # Mock feedparser.parse return value using a dict-like object
    class AttrDict(dict):
        def __init__(self, *args, **kwargs):
            super(AttrDict, self).__init__(*args, **kwargs)
            self.__dict__ = self

    class MockFeed:
        def __init__(self):
            self.bozo = False
            self.feed = AttrDict({"title": "TechCrunch", "description": "Startup and Technology News", "image": AttrDict({"href": "https://techcrunch.com/logo.png"})})
            self.entries = [AttrDict({"title": "Article 1", "link": "http://tc.com/1", "published": "now"})]
            self.version = "rss20"
            
    mock_result = MockFeed()
    
    with patch("feedparser.parse", return_value=mock_result):
        with patch("httpx.AsyncClient.get") as mock_get:
            mock_get.return_value.status_code = 200
            mock_get.return_value.text = "content"
            result = await parser.detect("https://techcrunch.com/feed")
        
    assert result.title == "TechCrunch"
    assert result.feed_url == "https://techcrunch.com/feed"
    assert result.feed_type == "rss"

@pytest.mark.asyncio
async def test_find_feed_in_html():
    """Test finding an RSS link in a standard HTML page."""
    parser = RSSParser()
    
    html_content = """
    <html>
        <head>
            <title>Le Monde</title>
            <link rel="alternate" type="application/rss+xml" title="Le Monde - Actualités" href="https://www.lemonde.fr/rss/une.xml" />
        </head>
        <body>...</body>
    </html>
    """
    
    class AttrDict(dict):
        def __init__(self, *args, **kwargs):
            super(AttrDict, self).__init__(*args, **kwargs)
            self.__dict__ = self
    
    # Mock httpx response
    mock_response = MagicMock()
    mock_response.text = html_content
    mock_response.status_code = 200
    
    class BadFeed:
        def __init__(self):
            self.bozo = True
            self.entries = []
            self.feed = {}
            self.version = ""

    class GoodFeed:
         def __init__(self):
            self.bozo = False
            self.feed = AttrDict({"title": "Le Monde - Actualités"})
            self.entries = [AttrDict({"title": "News 1", "published": "now"})]
            self.version = "rss20"

    with patch("httpx.AsyncClient.get", return_value=mock_response) as mock_get:
        with patch("feedparser.parse", side_effect=[BadFeed(), GoodFeed()]):
             result = await parser.detect("https://www.lemonde.fr")
             
    assert result.feed_url == "https://www.lemonde.fr/rss/une.xml"
    assert result.title == "Le Monde - Actualités"

@pytest.mark.asyncio
async def test_no_feed_found():
    """Test handling a page with no RSS feed."""
    parser = RSSParser()
    
    html_content = "<html><body>No feeds here</body></html>"
    
    mock_response = MagicMock()
    mock_response.text = html_content
    mock_response.status_code = 200
    
    bad_feed = MagicMock()
    bad_feed.entries = []
    
    with patch("httpx.AsyncClient.get", return_value=mock_response):
        with patch("feedparser.parse", return_value=bad_feed):
            with pytest.raises(ValueError, match="No RSS feed found"):
                await parser.detect("https://example.com/nofeed")
