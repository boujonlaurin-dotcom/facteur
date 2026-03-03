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


# ─── Platform Transform Tests ────────────────────────────────────


def test_platform_transform_substack():
    """Substack URL transforms to /feed suffix."""
    result = RSSParser._try_platform_transform("https://example.substack.com")
    assert result == "https://example.substack.com/feed"

    result = RSSParser._try_platform_transform("https://my-newsletter.substack.com/")
    assert result == "https://my-newsletter.substack.com/feed"


def test_platform_transform_github():
    """GitHub repo URL transforms to /releases.atom."""
    result = RSSParser._try_platform_transform("https://github.com/anthropics/claude-code")
    assert result == "https://github.com/anthropics/claude-code/releases.atom"


def test_platform_transform_github_commits():
    """GitHub commits URL transforms to /commits.atom."""
    result = RSSParser._try_platform_transform(
        "https://github.com/anthropics/claude-code/commits/main"
    )
    assert result == "https://github.com/anthropics/claude-code/commits.atom"


def test_platform_transform_mastodon():
    """Mastodon profile URL transforms to .rss suffix."""
    result = RSSParser._try_platform_transform("https://mastodon.social/@user")
    assert result == "https://mastodon.social/@user.rss"


def test_platform_transform_medium():
    """Medium publication URL transforms to /feed/ prefix."""
    result = RSSParser._try_platform_transform("https://medium.com/towards-data-science")
    assert result == "https://medium.com/feed/towards-data-science"


def test_platform_transform_no_match():
    """Non-platform URL returns None."""
    assert RSSParser._try_platform_transform("https://www.grimper.com") is None


# ─── Content-Type Helper Tests ───────────────────────────────────


def test_is_feed_content_type():
    """Content-type validation correctly filters HTML from XML feeds."""
    resp = MagicMock()

    resp.headers = {"content-type": "text/html; charset=utf-8"}
    assert RSSParser._is_feed_content_type(resp) is False

    resp.headers = {"content-type": "application/rss+xml"}
    assert RSSParser._is_feed_content_type(resp) is True

    resp.headers = {"content-type": "application/atom+xml"}
    assert RSSParser._is_feed_content_type(resp) is True

    resp.headers = {"content-type": "text/xml"}
    assert RSSParser._is_feed_content_type(resp) is True

    # Unknown type — allow feedparser to decide
    resp.headers = {"content-type": "text/plain"}
    assert RSSParser._is_feed_content_type(resp) is True

    resp.headers = {}
    assert RSSParser._is_feed_content_type(resp) is True


def test_is_antibot_response():
    """Anti-bot detection correctly identifies CAPTCHA/challenge responses."""
    assert RSSParser._is_antibot_response(403, "") is True
    assert RSSParser._is_antibot_response(200, "normal page content") is False
    assert RSSParser._is_antibot_response(200, '<script src="captcha-delivery.com">') is True
    assert RSSParser._is_antibot_response(200, "datadome challenge") is True


# ─── <a href> Deep Scan Tests ────────────────────────────────────


@pytest.mark.asyncio
async def test_a_tag_feed_scanning():
    """Feed discovered via <a href> when no <link rel='alternate'> exists."""
    parser = RSSParser()

    html_content = """
    <html>
        <head><title>Grimper</title></head>
        <body>
            <a href="https://www.grimper.com/feed/all">
                <img src="rss-icon.png"/>
            </a>
        </body>
    </html>
    """

    main_response = MagicMock()
    main_response.text = html_content
    main_response.status_code = 200
    main_response.raise_for_status = MagicMock()

    feed_response = MagicMock()
    feed_response.text = "<rss>valid</rss>"
    feed_response.status_code = 200
    feed_response.headers = {"content-type": "application/rss+xml"}

    async def mock_get(url, **kwargs):
        if "feed/all" in url:
            return feed_response
        return main_response

    with patch("httpx.AsyncClient.get", side_effect=mock_get):
        with patch(
            "feedparser.parse",
            side_effect=lambda c: MockFeed(title="Grimper RSS")
            if "valid" in c
            else BadFeed(),
        ):
            result = await parser.detect("https://www.grimper.com")

    assert result.feed_url == "https://www.grimper.com/feed/all"
    assert result.title == "Grimper RSS"


@pytest.mark.asyncio
async def test_a_tag_feed_scanning_by_text():
    """Feed discovered via <a> with RSS-related text content."""
    parser = RSSParser()

    html_content = """
    <html>
        <body>
            <a href="/custom-rss-path">Flux RSS</a>
        </body>
    </html>
    """

    main_response = MagicMock()
    main_response.text = html_content
    main_response.status_code = 200
    main_response.raise_for_status = MagicMock()

    feed_response = MagicMock()
    feed_response.text = "<rss>valid</rss>"
    feed_response.status_code = 200
    feed_response.headers = {"content-type": "application/rss+xml"}

    not_found = MagicMock()
    not_found.status_code = 404
    not_found.text = "Not found"
    not_found.headers = {"content-type": "text/html"}

    async def mock_get(url, **kwargs):
        if "custom-rss-path" in url:
            return feed_response
        if any(s in url for s in ["/feed", "/rss", "/atom", "/index", "/blog", "/.rss"]):
            return not_found
        return main_response

    with patch("httpx.AsyncClient.get", side_effect=mock_get):
        with patch(
            "feedparser.parse",
            side_effect=lambda c: MockFeed(title="Custom Feed")
            if "valid" in c
            else BadFeed(),
        ):
            result = await parser.detect("https://example.com")

    assert "custom-rss-path" in result.feed_url


# ─── curl-cffi Fallback Tests ────────────────────────────────────


@pytest.mark.asyncio
async def test_curl_cffi_fallback_on_403():
    """When httpx gets 403/anti-bot, curl-cffi should be tried as fallback."""
    parser = RSSParser()

    blocked_response = MagicMock()
    blocked_response.status_code = 403
    blocked_response.text = '<html><script src="https://ct.captcha-delivery.com/i.js"></script></html>'
    blocked_response.headers = {"content-type": "text/html"}

    valid_html = """
    <html><head>
        <link rel="alternate" type="application/rss+xml" href="/rss.xml" />
    </head><body>Content</body></html>
    """

    feed_response = MagicMock()
    feed_response.text = "<rss>valid</rss>"
    feed_response.status_code = 200
    feed_response.headers = {"content-type": "application/rss+xml"}
    feed_response.raise_for_status = MagicMock()

    call_count = 0

    async def mock_httpx_get(url, **kwargs):
        nonlocal call_count
        call_count += 1
        if call_count == 1:
            return blocked_response
        return feed_response

    with patch("httpx.AsyncClient.get", side_effect=mock_httpx_get):
        with patch.object(parser, "_fetch_with_impersonation", return_value=valid_html):
            with patch(
                "feedparser.parse",
                side_effect=lambda c: MockFeed(title="Recovered Feed")
                if "valid" in c
                else BadFeed(),
            ):
                result = await parser.detect("https://www.usine-digitale.fr")

    assert result.feed_url == "https://www.usine-digitale.fr/rss.xml"


@pytest.mark.asyncio
async def test_curl_cffi_fallback_both_fail():
    """When both httpx and curl-cffi fail, raise clear error."""
    parser = RSSParser()

    blocked_response = MagicMock()
    blocked_response.status_code = 403
    blocked_response.text = '<script src="captcha-delivery.com"></script>'
    blocked_response.headers = {"content-type": "text/html"}

    with patch("httpx.AsyncClient.get", return_value=blocked_response):
        with patch.object(parser, "_fetch_with_impersonation", return_value=None):
            with pytest.raises(ValueError, match="blocked automated access"):
                await parser.detect("https://blocked-site.com")


# ─── Expanded Suffix + Content-Type Tests ────────────────────────


@pytest.mark.asyncio
async def test_content_type_validation_skips_html_suffix():
    """Suffix returning text/html should be skipped via Content-Type check."""
    parser = RSSParser()

    main_html = "<html><body>Site with no link tags</body></html>"
    main_response = MagicMock()
    main_response.text = main_html
    main_response.status_code = 200
    main_response.raise_for_status = MagicMock()
    main_response.headers = {"content-type": "text/html"}

    html_suffix_response = MagicMock()
    html_suffix_response.text = "<html>Not a feed</html>"
    html_suffix_response.status_code = 200
    html_suffix_response.headers = {"content-type": "text/html; charset=UTF-8"}

    rss_response = MagicMock()
    rss_response.text = "<rss>valid</rss>"
    rss_response.status_code = 200
    rss_response.headers = {"content-type": "application/rss+xml"}

    async def mock_get(url, **kwargs):
        if url.endswith("/feed/all"):
            return rss_response
        if any(url.endswith(s) for s in ["/feed", "/rss", "/feed.xml", "/rss.xml",
                                          "/atom.xml", "/index.xml", "/feed/rss",
                                          "/blog/feed", "/.rss"]):
            return html_suffix_response
        return main_response

    with patch("httpx.AsyncClient.get", side_effect=mock_get):
        with patch(
            "feedparser.parse",
            side_effect=lambda c: MockFeed(title="Grimper Feed")
            if "valid" in c
            else BadFeed(),
        ):
            result = await parser.detect("https://www.grimper.com")

    assert result.feed_url == "https://www.grimper.com/feed/all"


# ─── Error Diagnostics Test ──────────────────────────────────────


@pytest.mark.asyncio
async def test_error_diagnostics_include_detection_log():
    """Error message should include detection log details."""
    parser = RSSParser()

    html_content = "<html><body>No feeds here</body></html>"
    mock_response = MagicMock()
    mock_response.text = html_content
    mock_response.status_code = 200
    mock_response.raise_for_status = MagicMock()
    mock_response.headers = {"content-type": "text/html"}

    not_found = MagicMock()
    not_found.status_code = 404
    not_found.text = "Not Found"
    not_found.headers = {"content-type": "text/html"}

    async def mock_get(url, **kwargs):
        if url == "https://nofeed.example.com":
            return mock_response
        return not_found

    with patch("httpx.AsyncClient.get", side_effect=mock_get):
        with patch("feedparser.parse", return_value=BadFeed()):
            with pytest.raises(ValueError) as exc_info:
                await parser.detect("https://nofeed.example.com")

    error_msg = str(exc_info.value)
    assert "No RSS feed found" in error_msg
    assert "Tried:" in error_msg
    assert "direct_parse=fail" in error_msg
