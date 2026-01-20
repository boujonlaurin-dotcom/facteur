"""Parser RSS/Atom."""

from typing import Any
import httpx
import feedparser
import asyncio
import sys
import os
import structlog

logger = structlog.get_logger()

class RSSParser:
    """Parser de flux RSS/Atom."""

    def __init__(self, timeout: int = 30):
        self.timeout = timeout

    async def parse(self, url: str) -> dict[str, Any]:
        """
        Parse un flux RSS/Atom depuis une URL.
        Essaie avec httpx (standard), et fallback sur un subprocess curl_cffi si bloqué (403/401).
        """
        headers = {
            "User-Agent": "Mozilla/5.0 (compatible; Facteur/1.0; +http://facteur.app)"
        }
        
        text_content = ""
        
        try:
            # 1. Tentative standard (rapide, sans overhead)
            async with httpx.AsyncClient(timeout=self.timeout, follow_redirects=True) as client:
                response = await client.get(url, headers=headers)
                response.raise_for_status()
                text_content = response.text
                
        except httpx.HTTPStatusError as e:
            if e.response.status_code in (403, 401, 429):
                logger.warning("rss_fetch_blocked_fallback", url=url, status=e.response.status_code)
                # 2. Fallback: Subprocess (Safe Sandbox)
                text_content = await self._fetch_via_subprocess(url)
            else:
                raise e
        except Exception as e:
            # Pour les autres erreurs (timeout, connection), on peut aussi tenter le fallback ?
            # Pour l'instant on re-raise, sauf si on est sûr que curl ferait mieux
            raise e

        # 3. Parsing du contenu XML/Atom récupéré
        return self._parse_feed_xml(text_content)

    async def _fetch_via_subprocess(self, url: str) -> str:
        """Exécute le script fetch_rss.py dans un processus séparé pour contourner le WAF sans bloquer la loop."""
        
        # Chemin absolu vers le script
        current_dir = os.path.dirname(os.path.abspath(__file__)) # packages/api/app/utils
        script_path = os.path.join(current_dir, "../../scripts/fetch_rss.py")
        script_path = os.path.abspath(script_path)
        
        if not os.path.exists(script_path):
             raise FileNotFoundError(f"RSS Script not found at {script_path}")
        
        # Lancement du subprocess
        cmd = [sys.executable, script_path, url]
        
        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            
            # Wait with timeout slightly larger than the script's internal timeout
            stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=self.timeout + 5)
            
            if proc.returncode != 0:
                error_msg = stderr.decode().strip()
                logger.error("rss_subprocess_failed", url=url, error=error_msg)
                raise RuntimeError(f"RSS Subprocess fetch failed: {error_msg}")
                
            return stdout.decode()
            
        except asyncio.TimeoutError:
            if 'proc' in locals():
                try:
                    proc.kill()
                except:
                    pass
            raise TimeoutError(f"RSS Subprocess timed out for {url}")

    def _parse_feed_xml(self, text_content: str) -> dict[str, Any]:
        """Parse le contenu brut RSS/Atom."""
        feed = feedparser.parse(text_content)

        if feed.bozo and not feed.entries:
            # feedparser est très permissif, mais si bozo=1 et 0 entries, c'est souvent un échec
            raise ValueError(f"Invalid RSS feed data: {feed.bozo_exception}")

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
            for content_item in entry.content:
                if content_item.get("type") in ("text/html", "html"):
                    html_content = content_item.get("value")
                    break
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
