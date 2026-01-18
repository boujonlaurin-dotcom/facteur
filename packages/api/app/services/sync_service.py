import asyncio
import datetime
import re
import html
from typing import List, Optional
from uuid import uuid4

import feedparser
import httpx
import certifi
import structlog
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.content import Content, UserContentStatus
from app.models.enums import ContentStatus, ContentType, SourceType
from app.models.source import Source

logger = structlog.get_logger()

class SyncService:
    def __init__(self, session: AsyncSession, session_maker=None):
        self.session = session
        self.session_maker = session_maker
        self.client = httpx.AsyncClient(
            timeout=30.0, 
            follow_redirects=True,
            verify=certifi.where(),
            headers={"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"}
        )


    async def close(self):
        await self.client.aclose()

    async def sync_all_sources(self):
        """Synchronise toutes les sources actives avec une limite de concomitance."""
        logger.info("Starting sync of all sources")
        
        # Récupérer les sources actives
        result = await self.session.execute(
            select(Source).where(Source.is_active == True)
        )
        sources = result.scalars().all()
        
        logger.info(f"Found {len(sources)} active sources to sync")
        
        results = {"success": 0, "failed": 0, "total_new": 0}
        
        # Concurrency control
        semaphore = asyncio.Semaphore(5)  # 5 sources à la fois max
        
        async def sync_with_semaphore(source: Source):
            async with semaphore:
                # Si on a un session_maker, on crée une session dédiée pour la tâche
                if self.session_maker:
                    async with self.session_maker() as session:
                        # On ré-associe l'objet source à la nouvelle session si nécessaire
                        # Mais plus simple : on repasse par l'ID
                        stmt = select(Source).where(Source.id == source.id)
                        res = await session.execute(stmt)
                        source_obj = res.scalar_one()
                        
                        # Temporairement on "patche" self.session pour process_source
                        # Hackish mais évite de refactorer tout process_source(session, source)
                        old_session = self.session
                        self.session = session
                        try:
                            return await self.process_source(source_obj)
                        finally:
                            self.session = old_session
                else:
                    # Fallback séquentiel sécurisé si pas de session_maker
                    return await self.process_source(source)

        tasks = [sync_with_semaphore(s) for s in sources]
        
        # Exécution et collecte des résultats
        sync_results = await asyncio.gather(*tasks, return_exceptions=True)
        
        for res in sync_results:
            if isinstance(res, Exception):
                logger.error("Source sync task failed", error=str(res))
                results["failed"] += 1
            elif isinstance(res, int):
                results["success"] += 1
                results["total_new"] += res
                
        logger.info("Sync completed", results=results)
        return results

    async def process_source(self, source: Source) -> int:
        """Synchronise une source spécifique."""
        logger.info("Syncing source", source_name=source.name, feed_url=source.feed_url)
        
        try:
            # 1. Fetch feed content asynchronously
            response = await self.client.get(source.feed_url)
            response.raise_for_status()
            content = response.text
            
            # 2. Parse feed
            feed = feedparser.parse(content)
            
            if feed.bozo:
                logger.warning("Feed parsing warning", source=source.name, error=feed.bozo_exception)
            
            if not feed.entries:
                logger.warning("No entries found in feed", source=source.name)
                return 0
                
            new_contents_count = 0
            
            # 3. Process entries
            # On prend les 20 plus récents pour éviter de tout reparser à chaque fois
            # si le flux est énorme
            for entry in feed.entries[:50]: 
                content_data = self._parse_entry(entry, source)
                if content_data:
                    is_new = await self._save_content(content_data)
                    if is_new:
                        new_contents_count += 1
            
            # Update last_synced_at
            source.last_synced_at = datetime.datetime.utcnow()
            await self.session.commit()
            
            return new_contents_count
            
        except Exception as e:
            logger.error("Error processing source", source=source.name, error=str(e))
            raise e

    def _parse_entry(self, entry, source: Source) -> Optional[dict]:
        """Extrait les données pertinentes selon le type de source."""
        try:
            # Common fields
            title = entry.get("title", "No Title")
            link = entry.get("link", "")
            guid = entry.get("id", link) # Fallback to link if no ID
            
            if not link:
                return None

            # Date handling
            published_at = datetime.datetime.utcnow()
            if hasattr(entry, "published_parsed") and entry.published_parsed:
                published_at = datetime.datetime(*entry.published_parsed[:6])
            elif hasattr(entry, "updated_parsed") and entry.updated_parsed:
                published_at = datetime.datetime(*entry.updated_parsed[:6])
                
            # Base content data
            content_data = {
                "source_id": source.id,
                "title": title,
                "url": link,
                "guid": guid,
                "published_at": published_at,
                "content_type": ContentType.ARTICLE, # Default
                "description": None,
                "thumbnail_url": None,
                "duration_seconds": None,
                "html_content": None,  # Story 5.2: In-App Reading
                "audio_url": None,     # Story 5.2: In-App Reading
            }
            
            # Type specific parsing
            if source.type == SourceType.YOUTUBE:
                content_data["content_type"] = ContentType.YOUTUBE
                
                # YouTube specific details
                if "media_group" in entry:
                    group = entry.media_group
                    if "media_thumbnail" in group:
                        # Taken the largest thumbnail usually usually the first one or we can verify
                        thumbnails = group.media_thumbnail
                        if isinstance(thumbnails, list) and thumbnails:
                            content_data["thumbnail_url"] = thumbnails[0]["url"]
                    if "media_description" in group:
                         content_data["description"] = group.media_description
                
                if not content_data["description"] and "summary" in entry:
                    content_data["description"] = entry.summary
                
                if content_data["thumbnail_url"]:
                    content_data["thumbnail_url"] = self._optimize_thumbnail_url(content_data["thumbnail_url"])

            elif source.type == SourceType.PODCAST:
                content_data["content_type"] = ContentType.PODCAST
                
                # Podcast duration
                if "itunes_duration" in entry:
                    duration_str = entry.itunes_duration
                    content_data["duration_seconds"] = self._parse_duration(duration_str)
                
                # Story 5.2: Extract audio URL from enclosure
                if "enclosures" in entry:
                    for enclosure in entry.enclosures:
                        if enclosure.get("type", "").startswith("audio"):
                            content_data["audio_url"] = enclosure.get("href") or enclosure.get("url")
                            break
                
                # Thumbnail extraction
                if "image" in entry and "href" in entry.image:
                     content_data["thumbnail_url"] = entry.image.href
                elif "itunes_image" in entry and "href" in entry.itunes_image:
                     content_data["thumbnail_url"] = entry.itunes_image.href
                     
                content_data["description"] = entry.get("summary", "")
                
                if content_data["thumbnail_url"]:
                    content_data["thumbnail_url"] = self._optimize_thumbnail_url(content_data["thumbnail_url"])

            else: # ARTICLE
                content_data["content_type"] = ContentType.ARTICLE
                # Try to find an image in standard enclosures
                if "media_content" in entry:
                     for media in entry.media_content:
                         if media.get("medium") == "image" and "url" in media:
                             content_data["thumbnail_url"] = media["url"]
                             break
                
                # Fallback to enclosures
                if not content_data["thumbnail_url"] and "enclosures" in entry:
                    for enclosure in entry.enclosures:
                        if enclosure.get("type", "").startswith("image/"):
                            content_data["thumbnail_url"] = enclosure.get("href")
                            break
                            
                content_data["description"] = entry.get("summary", "")

                # Fallback: Try to find image in description/content using regex
                if not content_data["thumbnail_url"]:
                    html_content = ""
                    if "content" in entry:
                         # Atom/RSS content usually in list of dicts
                         for c in entry.content:
                             html_content += c.get("value", "")
                    
                    if not html_content:
                        html_content = content_data["description"] or ""
                    
                    # Unescape HTML (fixes Socialter and others)
                    html_content = html.unescape(html_content)

                    # Broad regex for img src
                    # Loop through all matches to find a valid one
                    img_matches = re.finditer(r'<img[^>]+src=["\'](http[^"\']+)["\']', html_content)
                    for match in img_matches:
                        url = match.group(1)
                        if self._is_valid_thumbnail(url):
                             content_data["thumbnail_url"] = url
                             break
                
                if content_data["thumbnail_url"]:
                    content_data["thumbnail_url"] = self._optimize_thumbnail_url(content_data["thumbnail_url"])
                
                # Story 5.2: Extract content:encoded for in-app reading
                if "content" in entry:
                    for c in entry.content:
                        content_type = c.get("type", "")
                        if content_type in ("text/html", "html") or "html" in content_type:
                            content_data["html_content"] = c.get("value")
                            break
                    # Fallback to first content if no HTML found
                    if not content_data["html_content"] and entry.content:
                        content_data["html_content"] = entry.content[0].get("value")

            return content_data

        except Exception as e:
            logger.warning("Error parsing entry", entry_title=entry.get("title", "Unknown"), error=str(e))
            return None

    def _optimize_thumbnail_url(self, url: str) -> str:
        """Tente d'obtenir une version haute résolution de l'image."""
        if not url:
            return url
            
        # 1. Courrier International: /644/ -> /original/ or /1200/
        if "focus.courrierinternational.com" in url:
            # Pattern: .../644/0/60/0/...
            url = url.replace("/644/", "/1200/")
            
        # 2. WordPress resizing: thumb-150x150.jpg -> thumb.jpg
        # Pattern match for -WxH before extension
        wordpress_pattern = re.compile(r'-\d+x\d+(\.[a-z]{3,4})$', re.IGNORECASE)
        url = wordpress_pattern.sub(r'\1', url)
        
        return url

    def _is_valid_thumbnail(self, url: str) -> bool:
        """Vérifie si une URL d'image est pertinente comme thumbnail."""
        if not url:
            return False
            
        url_lower = url.lower()
        
        # 1. Exclure les emojis Wordpress et autres trackers connus
        if "s.w.org/images/core/emoji" in url_lower:
            return False
        if "doubleclick.net" in url_lower:
            return False
        if "googlesyndication" in url_lower:
            return False
            
        # 2. Exclure par mots-clés dans le nom de fichier
        # On essaie de ne pas être trop agressif sur le domaine, mais sur le path
        bad_keywords = [
            "logo", "icon", "button", "pixel", "tracker", "avatar", "smiley", "emoji", 
            "facebook", "twitter", "linkedin", "share",
            "counter", "count.gif", "ad.", "doubleclick"
        ]
        
        # Check if any bad keyword is in the URL filename part roughly
        # Clean query params?
        base_url = url_lower.split("?")[0]
        if any(keyword in base_url for keyword in bad_keywords):
            return False
            
        return True

    def _parse_duration(self, duration_str: str) -> Optional[int]:
        """Convertit une durée itunes (HH:MM:SS ou MM:SS ou secondes) en entier."""
        try:
            if ":" in duration_str:
                parts = duration_str.split(":")
                if len(parts) == 3:
                    return int(parts[0]) * 3600 + int(parts[1]) * 60 + int(parts[2])
                elif len(parts) == 2:
                    return int(parts[0]) * 60 + int(parts[1])
            else:
                return int(duration_str)
        except:
            return None
        return None

    async def _save_content(self, data: dict) -> bool:
        """Sauvegarde le contenu en base (Upsert/Ignore). Retourne True si nouveau."""
        
        # Check if exists by guid
        stmt = select(Content).where(Content.guid == data["guid"])
        result = await self.session.execute(stmt)
        existing = result.scalars().first()
        
        if existing:
            # Backfill thumbnail if missing
            if not existing.thumbnail_url and data.get("thumbnail_url"):
                existing.thumbnail_url = data["thumbnail_url"]
            
            # Also update description if missing
            if not existing.description and data.get("description"):
                existing.description = data["description"]
            
            # Story 5.2: Backfill html_content and audio_url if missing
            if not existing.html_content and data.get("html_content"):
                existing.html_content = data["html_content"]
            if not existing.audio_url and data.get("audio_url"):
                existing.audio_url = data["audio_url"]
            
            return False
            
        # Create new content
        new_content = Content(
            id=uuid4(),
            source_id=data["source_id"],
            title=data["title"][:500], # Trucate to fit DB
            url=data["url"],
            guid=data["guid"][:500],
            published_at=data["published_at"],
            content_type=data["content_type"],
            description=data["description"],
            thumbnail_url=data["thumbnail_url"],
            duration_seconds=data["duration_seconds"],
            html_content=data.get("html_content"),  # Story 5.2
            audio_url=data.get("audio_url"),        # Story 5.2
            created_at=datetime.datetime.utcnow()
        )
        
        self.session.add(new_content)
        # Flush to get the ID but don't commit transaction yet (handled by caller or auto-flush)
        # But here we are in a loop, so let's allow session to handle it.
        # However, to avoid integrity errors on GUID if we process duplicates in same batch,
        # we should flush.
        await self.session.flush()
        
        return True
