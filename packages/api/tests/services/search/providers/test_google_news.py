"""Tests for GoogleNewsProvider — focus on the entry.source.href parsing.

Google News RSS now wraps article links in opaque redirects
(`news.google.com/rss/articles/CB...`). The real publisher is exposed
via the <source url="..."> child element. We must read that, not <link>.
"""

from unittest.mock import AsyncMock, patch

import pytest

from app.services.search.providers.google_news import GoogleNewsProvider


def _build_rss(items: list[dict]) -> bytes:
    body = []
    for it in items:
        link = it.get("link", "")
        src = it.get("source", "")
        src_title = it.get("source_title", "Publisher")
        body.append(
            f"<item><title>x</title><link>{link}</link>"
            f'<source url="{src}">{src_title}</source></item>'
        )
    return (
        '<?xml version="1.0"?><rss version="2.0"><channel>'
        f'<title>q</title><link>https://news.google.com/</link>{"".join(body)}'
        "</channel></rss>"
    ).encode()


@pytest.mark.asyncio
async def test_extracts_publisher_from_source_href():
    rss = _build_rss(
        [
            {
                "link": "https://news.google.com/rss/articles/CBMiOPAQUERESQ?oc=5",
                "source": "https://www.politis.fr",
            },
            {
                "link": "https://news.google.com/rss/articles/CBMiOTHEROPAQ?oc=5",
                "source": "https://www.lemonde.fr",
            },
        ]
    )

    class _Resp:
        status_code = 200
        content = rss

    with patch("app.services.search.providers.google_news.httpx.AsyncClient") as cli:
        cli.return_value.__aenter__.return_value.get = AsyncMock(return_value=_Resp())
        urls = await GoogleNewsProvider().search("politis")

    assert urls == ["https://www.politis.fr", "https://www.lemonde.fr"]


@pytest.mark.asyncio
async def test_falls_back_to_link_when_source_missing():
    body = (
        '<?xml version="1.0"?><rss version="2.0"><channel>'
        "<title>x</title><link>https://news.google.com/</link>"
        "<item><title>x</title><link>https://www.lemonde.fr/article.html</link>"
        "</item></channel></rss>"
    ).encode()

    class _Resp:
        status_code = 200
        content = body

    with patch("app.services.search.providers.google_news.httpx.AsyncClient") as cli:
        cli.return_value.__aenter__.return_value.get = AsyncMock(return_value=_Resp())
        urls = await GoogleNewsProvider().search("lemonde")

    assert urls == ["https://www.lemonde.fr"]


@pytest.mark.asyncio
async def test_skips_google_redirects_with_no_source():
    rss = _build_rss(
        [
            {
                "link": "https://news.google.com/rss/articles/CBMiOPAQUE?oc=5",
                "source": "",
            },
            {
                "link": "https://news.google.com/foo",
                "source": "",
            },
        ]
    )

    class _Resp:
        status_code = 200
        content = rss

    with patch("app.services.search.providers.google_news.httpx.AsyncClient") as cli:
        cli.return_value.__aenter__.return_value.get = AsyncMock(return_value=_Resp())
        urls = await GoogleNewsProvider().search("anything")

    assert urls == []
