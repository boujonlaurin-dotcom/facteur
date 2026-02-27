import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from app.services.rss_parser import RSSParser, DetectedFeed


class AttrDict(dict):
    def __init__(self, *args, **kwargs):
        super(AttrDict, self).__init__(*args, **kwargs)
        self.__dict__ = self


class MockFeed:
    """A valid RSS feed mock."""

    def __init__(self, title="TechCrunch", version="rss20", entries=None):
        self.bozo = False
        self.feed = AttrDict(
            {
                "title": title,
                "description": "Feed description",
                "image": AttrDict({"href": "https://example.com/logo.png"}),
            }
        )
        self.entries = entries or [
            AttrDict({"title": "Article 1", "link": "http://example.com/1", "published": "now"})
        ]
        self.version = version


class BadFeed:
    """A feed that fails to parse (bozo, no entries)."""

    def __init__(self):
        self.bozo = True
        self.entries = []
        self.feed = {}
        self.version = ""


# ─── Existing Tests ───────────────────────────────────────────────


@pytest.mark.asyncio
async def test_parse_direct_rss_feed():
    """Test parsing a direct valid RSS feed URL."""
    parser = RSSParser()

    with patch("feedparser.parse", return_value=MockFeed()):
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

    mock_response = MagicMock()
    mock_response.text = html_content
    mock_response.status_code = 200

    with patch("httpx.AsyncClient.get", return_value=mock_response):
        with patch(
            "feedparser.parse",
            side_effect=[BadFeed(), MockFeed(title="Le Monde - Actualités")],
        ):
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


# ─── Reddit Tests ─────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_detect_reddit_subreddit_url():
    """Test Reddit subreddit URL is transformed to .rss and detected."""
    parser = RSSParser()

    reddit_feed = MockFeed(title="technology", version="atom10", entries=[
        AttrDict({"title": "Post 1", "link": "https://reddit.com/r/technology/1", "published": "now"}),
        AttrDict({"title": "Post 2", "link": "https://reddit.com/r/technology/2", "published": "now"}),
    ])

    mock_response = MagicMock()
    mock_response.text = "<atom feed content>"
    mock_response.status_code = 200
    mock_response.raise_for_status = MagicMock()

    with patch("httpx.AsyncClient.get", return_value=mock_response):
        with patch("feedparser.parse", return_value=reddit_feed):
            result = await parser.detect("https://www.reddit.com/r/technology")

    assert result.feed_url == "https://www.reddit.com/r/technology/.rss"
    assert result.feed_type == "reddit"
    assert len(result.entries) == 2


@pytest.mark.asyncio
async def test_detect_reddit_old_reddit_url():
    """Test old.reddit.com URL is also detected."""
    parser = RSSParser()

    reddit_feed = MockFeed(title="worldnews", version="atom10")

    mock_response = MagicMock()
    mock_response.text = "<atom>"
    mock_response.status_code = 200
    mock_response.raise_for_status = MagicMock()

    with patch("httpx.AsyncClient.get", return_value=mock_response):
        with patch("feedparser.parse", return_value=reddit_feed):
            result = await parser.detect("https://old.reddit.com/r/worldnews/")

    assert result.feed_url == "https://www.reddit.com/r/worldnews/.rss"
    assert result.feed_type == "reddit"


@pytest.mark.asyncio
async def test_reddit_feed_type_detection():
    """Verify _format_response sets feed_type='reddit' for Reddit feeds."""
    parser = RSSParser()

    feed = MockFeed(title="r/science", version="atom10")
    result = await parser._format_response(
        "https://www.reddit.com/r/science/.rss", feed
    )

    assert result.feed_type == "reddit"
    assert result.title == "r/science"


# ─── YouTube Tests ────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_detect_youtube_channel_id_direct():
    """Test YouTube URL with direct channel_id (UC...) goes straight to feed."""
    parser = RSSParser()

    yt_feed = MockFeed(title="Science Etonnante", version="atom10", entries=[
        AttrDict({"title": "Video 1", "link": "https://youtube.com/watch?v=abc", "published": "now"}),
    ])

    mock_response = MagicMock()
    mock_response.text = "<atom feed>"
    mock_response.status_code = 200
    mock_response.raise_for_status = MagicMock()

    with patch("httpx.AsyncClient.get", return_value=mock_response):
        with patch("feedparser.parse", return_value=yt_feed):
            result = await parser.detect(
                "https://www.youtube.com/channel/UCaNlbnghtwlsGF-KzAFThqA"
            )

    assert "channel_id=UCaNlbnghtwlsGF-KzAFThqA" in result.feed_url
    assert result.feed_type == "youtube"


@pytest.mark.asyncio
async def test_detect_youtube_handle_via_api():
    """Test YouTube @handle is resolved via API v3."""
    parser = RSSParser()

    # Mock settings to have API key
    mock_settings = MagicMock()
    mock_settings.youtube_api_key = "fake-api-key"

    yt_feed = MockFeed(title="Science Etonnante", version="atom10")

    # First call: API resolve (channels endpoint)
    api_response = MagicMock()
    api_response.status_code = 200
    api_response.json.return_value = {"items": [{"id": "UCaNlbnghtwlsGF-KzAFThqA"}]}
    api_response.raise_for_status = MagicMock()

    # Second call: feed fetch
    feed_response = MagicMock()
    feed_response.text = "<atom>"
    feed_response.status_code = 200
    feed_response.raise_for_status = MagicMock()

    with patch("app.services.rss_parser.get_settings", return_value=mock_settings):
        with patch(
            "httpx.AsyncClient.get", side_effect=[api_response, feed_response]
        ):
            with patch("feedparser.parse", return_value=yt_feed):
                result = await parser.detect("https://www.youtube.com/@ScienceEtonnante")

    assert "channel_id=UCaNlbnghtwlsGF-KzAFThqA" in result.feed_url
    assert result.feed_type == "youtube"
    assert result.title == "Science Etonnante"


@pytest.mark.asyncio
async def test_detect_youtube_video_url():
    """Test YouTube video URL extracts channel_id from watch page."""
    parser = RSSParser()

    # Video page HTML with embedded channelId
    video_html = '<html><script>{"channelId":"UCqA8H22FwgBVcF3GJpp0MQw"}</script></html>'

    video_response = MagicMock()
    video_response.text = video_html
    video_response.status_code = 200
    video_response.raise_for_status = MagicMock()

    yt_feed = MockFeed(title="Channel Name", version="atom10")

    feed_response = MagicMock()
    feed_response.text = "<atom>"
    feed_response.status_code = 200
    feed_response.raise_for_status = MagicMock()

    with patch(
        "httpx.AsyncClient.get", side_effect=[video_response, feed_response]
    ):
        with patch("feedparser.parse", return_value=yt_feed):
            result = await parser.detect(
                "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
            )

    assert "channel_id=UCqA8H22FwgBVcF3GJpp0MQw" in result.feed_url
    assert result.feed_type == "youtube"


@pytest.mark.asyncio
async def test_youtube_feed_type_detection():
    """Verify _format_response sets feed_type='youtube' for YouTube feeds."""
    parser = RSSParser()

    feed = MockFeed(title="Channel Name", version="atom10")
    result = await parser._format_response(
        "https://www.youtube.com/feeds/videos.xml?channel_id=UCxxx", feed
    )

    assert result.feed_type == "youtube"


@pytest.mark.asyncio
async def test_youtube_no_api_key_falls_back_to_html():
    """Test YouTube handle without API key falls back to HTML scraping."""
    parser = RSSParser()

    mock_settings = MagicMock()
    mock_settings.youtube_api_key = ""  # No API key

    # HTML page with channelId in JS (lucky case)
    html_with_id = '<html><script>var x = {"channelId":"UCtest123456789"}</script></html>'
    html_response = MagicMock()
    html_response.text = html_with_id
    html_response.status_code = 200
    html_response.raise_for_status = MagicMock()

    yt_feed = MockFeed(title="Test Channel", version="atom10")
    feed_response = MagicMock()
    feed_response.text = "<atom>"
    feed_response.status_code = 200
    feed_response.raise_for_status = MagicMock()

    with patch("app.services.rss_parser.get_settings", return_value=mock_settings):
        with patch(
            "httpx.AsyncClient.get", side_effect=[html_response, feed_response]
        ):
            with patch("feedparser.parse", return_value=yt_feed):
                result = await parser.detect("https://www.youtube.com/@TestChannel")

    assert "channel_id=UCtest123456789" in result.feed_url
    assert result.feed_type == "youtube"
