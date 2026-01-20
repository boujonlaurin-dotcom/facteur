"""Parser RSS/Atom."""

from typing import Any

import feedparser
import feedparser
from curl_cffi.requests import AsyncSession

class RSSParser:
    """Parser de flux RSS/Atom."""

    def __init__(self, timeout: int = 30):
        self.timeout = timeout

    async def parse(self, url: str) -> dict[str, Any]:
        """
        Parse un flux RSS/Atom depuis une URL.
        Use curl_cffi to impersonate a real browser (Chrome) and bypass TLS fingerprinting/WAFs.
        """
        async with AsyncSession(timeout=self.timeout, impersonate="chrome") as client:
            try:
                response = await client.get(url)
                response.raise_for_status()
            except Exception as e:
                # Log context but re-raise transparently
                # print(f"RSS Fetch Error for {url}: {e}")
                raise e


        feed = feedparser.parse(response.text)

        if feed.bozo and not feed.entries:
            raise ValueError(f"Invalid RSS feed: {feed.bozo_exception}")

        return {
            "title": feed.feed.get("title", ""),
            "description": feed.feed.get("description", ""),
            "link": feed.feed.get("link", ""),
            "image": {
                "href": feed.feed.get("image", {}).get("href"),
                "title": feed.feed.get("image", {}).get("title"),
            }
            if feed.feed.get("image")
            else None,
            "entries": [self._parse_entry(entry) for entry in feed.entries],
        }

    def _parse_entry(self, entry: Any) -> dict[str, Any]:
        """Parse une entrée du flux."""
        # Extraire la thumbnail
        thumbnail = None
        if hasattr(entry, "media_thumbnail") and entry.media_thumbnail:
            thumbnail = entry.media_thumbnail[0].get("url")
        elif hasattr(entry, "media_content") and entry.media_content:
            for media in entry.media_content:
                if media.get("type", "").startswith("image"):
                    thumbnail = media.get("url")
                    break

        # Extraire l'enclosure (pour podcasts)
        enclosure = None
        audio_url = None
        if hasattr(entry, "enclosures") and entry.enclosures:
            for enc in entry.enclosures:
                if enc.get("type", "").startswith("audio"):
                    audio_url = enc.get("href") or enc.get("url")
                    enclosure = {
                        "url": audio_url,
                        "type": enc.get("type"),
                        "length": enc.get("length"),
                    }
                    break

        # Extraire le contenu HTML (content:encoded ou content)
        html_content = None
        if hasattr(entry, "content") and entry.content:
            # content:encoded est souvent dans entry.content[0].value
            for content_item in entry.content:
                if content_item.get("type") in ("text/html", "html"):
                    html_content = content_item.get("value")
                    break
            # Fallback: premier content disponible
            if not html_content and entry.content:
                html_content = entry.content[0].get("value")

        # Durée (pour podcasts/vidéos)
        duration = None
        if hasattr(entry, "itunes_duration"):
            duration = self._parse_duration(entry.itunes_duration)

        return {
            "title": entry.get("title", ""),
            "link": entry.get("link", ""),
            "description": entry.get("summary", entry.get("description", "")),
            "published": entry.get("published_parsed") or entry.get("updated_parsed"),
            "guid": entry.get("id") or entry.get("link"),
            "thumbnail": thumbnail,
            "enclosure": enclosure,
            "audio_url": audio_url,
            "html_content": html_content,
            "duration_seconds": duration,
        }

    def _parse_duration(self, duration_str: str) -> int:
        """Parse une durée au format HH:MM:SS ou MM:SS."""
        if not duration_str:
            return 0

        try:
            parts = duration_str.split(":")
            if len(parts) == 3:
                hours, minutes, seconds = map(int, parts)
                return hours * 3600 + minutes * 60 + seconds
            elif len(parts) == 2:
                minutes, seconds = map(int, parts)
                return minutes * 60 + seconds
            else:
                return int(duration_str)
        except (ValueError, AttributeError):
            return 0

