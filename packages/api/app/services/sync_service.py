import asyncio
import copy
import datetime
import html
import re
from contextlib import asynccontextmanager
from uuid import UUID, uuid4

import certifi
import feedparser
import httpx
import structlog
from sqlalchemy import select, update
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.content import Content
from app.models.enums import ContentType, SourceType
from app.models.source import Source, UserSource
from app.services.content_extractor import ContentExtractor
from app.services.paywall_detector import detect_paywall

logger = structlog.get_logger()


class SyncService:
    def __init__(self, session: AsyncSession, session_maker=None):
        self.session = session
        self.session_maker = session_maker
        self.client = httpx.AsyncClient(
            timeout=30.0,
            follow_redirects=True,
            verify=certifi.where(),
            headers={
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            },
        )

    async def close(self):
        await self.client.aclose()

    @asynccontextmanager
    async def _short_session(self):
        """Yield a short-lived session for one DB operation.

        Cf. docs/bugs/bug-infinite-load-requests.md (P2). On NE TIENT JAMAIS
        de session ouverte pendant un await externe (httpx, trafilatura). Cette
        helper ouvre une session, commit en sortie nominale, rollback sur
        exception, et la ferme. Si `session_maker` n'est pas fourni
        (constructeur legacy / tests unitaires), on retombe sur `self.session`
        sans la fermer (compat ascendante).
        """
        if self.session_maker is None:
            yield self.session
            return
        async with self.session_maker() as session:
            try:
                yield session
                await session.commit()
            except Exception:
                await session.rollback()
                raise

    async def sync_all_sources(self):
        """Synchronise toutes les sources actives avec une limite de concomitance."""
        logger.info("Starting sync of all sources")

        # Sync curated sources + user custom sources only (not indexed candidates)
        custom_source_ids = (
            select(UserSource.source_id)
            .where(UserSource.is_custom)
            .distinct()
            .scalar_subquery()
        )
        result = await self.session.execute(
            select(Source).where(
                Source.is_active,
                (Source.is_curated) | (Source.id.in_(custom_source_ids)),
            )
        )
        sources = result.scalars().all()

        logger.info(f"Found {len(sources)} active sources to sync")

        results = {"success": 0, "failed": 0, "total_new": 0}

        # Concurrency control
        semaphore = asyncio.Semaphore(5)  # 5 sources à la fois max

        async def sync_with_semaphore(source: Source):
            async with semaphore:
                if self.session_maker:
                    async with self.session_maker() as session:
                        stmt = select(Source).where(Source.id == source.id)
                        res = await session.execute(stmt)
                        source_obj = res.scalar_one()

                        # Shallow copy isolates session state without creating a new httpx client
                        task_service = copy.copy(self)
                        task_service.session = session
                        return await task_service.process_source(source_obj)
                else:
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
        """Synchronise une source spécifique.

        Refactor P2 (cf. docs/bugs/bug-infinite-load-requests.md) : la session
        SQLAlchemy n'est PLUS tenue ouverte pendant la boucle de 50 entries. Les
        I/O externes (httpx, trafilatura, feedparser) s'exécutent hors session ;
        chaque INSERT/UPDATE ouvre une session courte via `_short_session()`.
        Avant ce fix, `self.session` restait checked-out pendant 4 à 20 minutes
        par source × 5 sources en parallèle → fuite massive du pool DB.
        """
        logger.info("Syncing source", source_name=source.name, feed_url=source.feed_url)

        # Capture les attributs de la source AVANT toute opération asynchrone :
        # cela évite que la source soit expirée entre temps si la session
        # appelante a été commit. Les copies sont pures données, donc utilisables
        # depuis n'importe quelle session.
        source_id = source.id
        source_name = source.name
        source_url = source.feed_url
        source_paywall_config = getattr(source, "paywall_config", None)

        try:
            # 1. Fetch feed content (HORS session DB)
            response = await self.client.get(source_url)
            response.raise_for_status()
            content = response.text

            # 2. Parse feed (HORS session DB ; offloaded to thread pool, CPU-bound)
            loop = asyncio.get_event_loop()
            feed = await loop.run_in_executor(None, feedparser.parse, content)

            if feed.bozo:
                logger.warning(
                    "Feed parsing warning",
                    source=source_name,
                    error=feed.bozo_exception,
                )

            if not feed.entries:
                logger.warning("No entries found in feed", source=source_name)
                # On met quand même à jour last_synced_at pour ne pas re-tenter
                # immédiatement.
                await self._update_source_last_synced(source_id)
                return 0

            new_contents_count = 0

            # 3. Process entries — chaque itération ouvre des sessions COURTES.
            # Aucun `await` externe (httpx, trafilatura) ne se produit dans un
            # `with session:` bloc.
            for entry in feed.entries[:50]:
                content_data = self._parse_entry(entry, source)
                if not content_data:
                    continue

                # 3a. HTML head fetch (HORS session DB) — paywall detection
                html_head = None
                if content_data.get("content_type") == ContentType.ARTICLE:
                    html_head = await self._fetch_html_head(content_data.get("url", ""))

                # 3b. Paywall detection (pure CPU, HORS session DB)
                content_data["is_paid"] = detect_paywall(
                    title=content_data.get("title", ""),
                    description=content_data.get("description"),
                    url=content_data.get("url", ""),
                    html_content=content_data.get("html_content"),
                    source_id=str(source_id),
                    paywall_config=source_paywall_config,
                    html_head=html_head,
                )

                # 3c. Upsert atomique (session COURTE) — retourne ce qu'il faut
                # pour décider de l'enrichissement trafilatura suivant.
                try:
                    (
                        is_new,
                        content_id,
                        needs_enrich,
                        content_url,
                    ) = await self._save_content(content_data)
                except SQLAlchemyError as save_err:
                    logger.warning(
                        "Failed to save content",
                        source=source_name,
                        guid=content_data.get("guid"),
                        error=str(save_err),
                    )
                    continue

                if is_new:
                    new_contents_count += 1

                # 3d. Trafilatura (HORS session DB, max 20s).
                if needs_enrich and content_id is not None and content_url:
                    extraction = await self._run_extraction_safely(content_url)
                    # 3e. Apply extraction result en session COURTE.
                    if extraction is not None:
                        try:
                            await self._apply_extraction(content_id, extraction)
                        except SQLAlchemyError as enrich_err:
                            logger.warning(
                                "Failed to apply extraction",
                                content_id=str(content_id),
                                error=str(enrich_err),
                            )

            # 4. Update source.last_synced_at en session COURTE.
            await self._update_source_last_synced(source_id)

            return new_contents_count

        except Exception as e:
            logger.error("Error processing source", source=source_name, error=str(e))
            raise e

    def _parse_entry(self, entry, source: Source) -> dict | None:
        """Extrait les données pertinentes selon le type de source."""
        try:
            # Common fields
            title = entry.get("title", "No Title")
            link = entry.get("link", "")
            guid = entry.get("id", link)  # Fallback to link if no ID

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
                "content_type": ContentType.ARTICLE,  # Default
                "description": None,
                "thumbnail_url": None,
                "duration_seconds": None,
                "html_content": None,  # Story 5.2: In-App Reading
                "audio_url": None,  # Story 5.2: In-App Reading
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
                        content_data["description"] = html.unescape(
                            group.media_description
                        )

                if not content_data["description"] and "summary" in entry:
                    content_data["description"] = html.unescape(entry.summary)

                # HD Thumbnail: extract video ID and use maxresdefault
                video_id = self._extract_youtube_video_id(link)
                if video_id:
                    content_data["thumbnail_url"] = (
                        f"https://img.youtube.com/vi/{video_id}/maxresdefault.jpg"
                    )
                elif content_data["thumbnail_url"]:
                    content_data["thumbnail_url"] = self._optimize_thumbnail_url(
                        content_data["thumbnail_url"]
                    )

                # Description -> html_content for in-app reading
                if content_data["description"]:
                    desc = content_data["description"]
                    html_lines = html.escape(desc).replace("\n", "<br>")
                    content_data["html_content"] = f"<p>{html_lines}</p>"
                    content_data["content_quality"] = (
                        "full" if len(desc) > 500 else "partial"
                    )

            elif source.type == SourceType.PODCAST:
                content_data["content_type"] = ContentType.PODCAST

                # Podcast duration
                if "itunes_duration" in entry:
                    duration_str = entry.itunes_duration
                    content_data["duration_seconds"] = self._parse_duration(
                        duration_str
                    )

                # Story 5.2: Extract audio URL from enclosure
                if "enclosures" in entry:
                    for enclosure in entry.enclosures:
                        if enclosure.get("type", "").startswith("audio"):
                            content_data["audio_url"] = enclosure.get(
                                "href"
                            ) or enclosure.get("url")
                            break

                # Thumbnail extraction
                if "image" in entry and "href" in entry.image:
                    content_data["thumbnail_url"] = entry.image.href
                elif "itunes_image" in entry and "href" in entry.itunes_image:
                    content_data["thumbnail_url"] = entry.itunes_image.href

                description = entry.get("summary", "")
                content_data["description"] = (
                    html.unescape(description) if description else ""
                )

                if content_data["thumbnail_url"]:
                    content_data["thumbnail_url"] = self._optimize_thumbnail_url(
                        content_data["thumbnail_url"]
                    )

            else:  # ARTICLE
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

                description = entry.get("summary", "")
                content_data["description"] = (
                    html.unescape(description) if description else ""
                )

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
                    img_matches = re.finditer(
                        r'<img[^>]+src=["\'](http[^"\']+)["\']', html_content
                    )
                    for match in img_matches:
                        url = match.group(1)
                        if self._is_valid_thumbnail(url):
                            content_data["thumbnail_url"] = url
                            break

                if content_data["thumbnail_url"]:
                    content_data["thumbnail_url"] = self._optimize_thumbnail_url(
                        content_data["thumbnail_url"]
                    )

                # Story 5.2: Extract content:encoded for in-app reading
                if "content" in entry:
                    for c in entry.content:
                        content_type = c.get("type", "")
                        if (
                            content_type in ("text/html", "html")
                            or "html" in content_type
                        ):
                            content_data["html_content"] = c.get("value")
                            break
                    # Fallback to first content if no HTML found
                    if not content_data["html_content"] and entry.content:
                        content_data["html_content"] = entry.content[0].get("value")

            return content_data

        except Exception as e:
            logger.warning(
                "Error parsing entry",
                entry_title=entry.get("title", "Unknown"),
                error=str(e),
            )
            return None

    @staticmethod
    def _extract_youtube_video_id(url: str) -> str | None:
        """Extract video ID from a YouTube URL.

        Supports patterns like:
        - https://www.youtube.com/watch?v=VIDEO_ID
        - https://img.youtube.com/vi/VIDEO_ID/...
        - https://youtu.be/VIDEO_ID
        """
        if not url:
            return None
        # watch?v=VIDEO_ID
        match = re.search(r"[?&]v=([\w-]+)", url)
        if match:
            return match.group(1)
        # /vi/VIDEO_ID or /embed/VIDEO_ID
        match = re.search(r"/(?:vi|embed)/([\w-]+)", url)
        if match:
            return match.group(1)
        # youtu.be/VIDEO_ID
        match = re.search(r"youtu\.be/([\w-]+)", url)
        if match:
            return match.group(1)
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
        wordpress_pattern = re.compile(r"-\d+x\d+(\.[a-z]{3,4})$", re.IGNORECASE)
        url = wordpress_pattern.sub(r"\1", url)

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
            "logo",
            "icon",
            "button",
            "pixel",
            "tracker",
            "avatar",
            "smiley",
            "emoji",
            "facebook",
            "twitter",
            "linkedin",
            "share",
            "counter",
            "count.gif",
            "ad.",
            "doubleclick",
        ]

        # Check if any bad keyword is in the URL filename part roughly
        # Clean query params?
        base_url = url_lower.split("?")[0]
        return not any(keyword in base_url for keyword in bad_keywords)

    async def _fetch_html_head(self, url: str) -> str | None:
        """Fetch first ~50KB of an article page for paywall detection.

        Uses Range header to avoid downloading the full page.
        Returns HTML head content or None on any error.
        """
        if not url:
            return None
        try:
            response = await self.client.get(
                url,
                headers={"Range": "bytes=0-50000"},
                timeout=5.0,
            )
            # Accept both 200 (full) and 206 (partial) responses
            if response.status_code in (200, 206):
                return response.text[:50000]
        except Exception:
            pass  # Fail silently — scoring fallback will handle detection
        return None

    def _parse_duration(self, duration_str: str) -> int | None:
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
        except (ValueError, IndexError):
            return None
        return None

    async def _save_content(
        self, data: dict
    ) -> tuple[bool, UUID | None, bool, str | None]:
        """Upsert the content row in a SHORT session and return enrichment hints.

        Returns (is_new, content_id, needs_enrich, content_url) :
        - is_new : True si une nouvelle ligne a été insérée
        - content_id : UUID de la ligne à enrichir (None si pas d'enrichissement)
        - needs_enrich : True si trafilatura doit tenter une extraction
        - content_url : URL à passer à trafilatura

        L'extraction trafilatura (await externe long) se fait HORS de cette
        session pour ne pas tenir le pool. `extraction_attempted_at` est écrit
        avant le retour pour garantir le cooldown même si l'extraction hang.
        """
        # Pre-flush priority computation (pure)
        priority = self._compute_classification_priority(data)

        async with self._short_session() as session:
            # Check if exists by guid
            stmt = select(Content).where(Content.guid == data["guid"])
            result = await session.execute(stmt)
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

                # Paywall: upgrade false→true only (never downgrade paid→free)
                if data.get("is_paid") and not existing.is_paid:
                    existing.is_paid = True

                # Compute current quality if not set
                if not existing.content_quality:
                    extractor = ContentExtractor()
                    if existing.html_content or existing.description:
                        existing.content_quality = (
                            extractor.compute_quality_for_existing(
                                existing.html_content, existing.description
                            )
                        )

                needs_enrich = (
                    existing.content_type == ContentType.ARTICLE
                    and existing.content_quality != "full"
                    and not existing.html_content
                )
                if needs_enrich:
                    # Marquer AVANT l'await externe pour garantir le cooldown
                    # même si trafilatura hang. Cf. bug-infinite-load-requests.md.
                    existing.extraction_attempted_at = datetime.datetime.now(
                        datetime.UTC
                    )

                await session.flush()
                return (
                    False,
                    existing.id if needs_enrich else None,
                    needs_enrich,
                    existing.url if needs_enrich else None,
                )

            # Create new content
            new_content = Content(
                id=uuid4(),
                source_id=data["source_id"],
                title=data["title"][:500],
                url=data["url"],
                guid=data["guid"][:500],
                published_at=data["published_at"],
                content_type=data["content_type"],
                description=data["description"],
                thumbnail_url=data["thumbnail_url"],
                duration_seconds=data["duration_seconds"],
                html_content=data.get("html_content"),
                audio_url=data.get("audio_url"),
                is_paid=data.get("is_paid", False),
                created_at=datetime.datetime.utcnow(),
            )

            session.add(new_content)
            await session.flush()

            content_id_for_enrich: UUID | None = None
            url_for_enrich: str | None = None
            needs_enrich = new_content.content_type == ContentType.ARTICLE
            if needs_enrich:
                new_content.extraction_attempted_at = datetime.datetime.now(
                    datetime.UTC
                )
                content_id_for_enrich = new_content.id
                url_for_enrich = new_content.url

            # US-2 : add to classification queue (same SHORT session for atomicity)
            await self._enqueue_for_classification_in_session(
                session, new_content.id, priority
            )

            return (True, content_id_for_enrich, needs_enrich, url_for_enrich)

    async def _run_extraction_safely(self, url: str):
        """Lance trafilatura en thread pool, borné à 20 s. JAMAIS dans une session.

        Retourne le résultat ContentExtractor ou None en cas d'échec / timeout.
        """
        extractor = ContentExtractor()
        try:
            return await asyncio.wait_for(
                asyncio.get_event_loop().run_in_executor(None, extractor.extract, url),
                timeout=20.0,
            )
        except Exception:
            logger.exception("content_enrichment_failed", url=url)
            return None

    async def _apply_extraction(self, content_id: UUID, result) -> None:
        """Applique le résultat trafilatura à la ligne en session COURTE."""
        async with self._short_session() as session:
            content = await session.get(Content, content_id)
            if content is None:
                return
            if result.html_content:
                content.html_content = result.html_content
            if result.reading_time_seconds and not content.duration_seconds:
                content.duration_seconds = result.reading_time_seconds
            # Always set quality (even if extraction returned 'none')
            content.content_quality = result.content_quality
            await session.flush()

    async def _update_source_last_synced(self, source_id: UUID) -> None:
        """Met à jour `sources.last_synced_at` en session COURTE."""
        async with self._short_session() as session:
            await session.execute(
                update(Source)
                .where(Source.id == source_id)
                .values(last_synced_at=datetime.datetime.utcnow())
            )

    @staticmethod
    def _compute_classification_priority(data: dict) -> int:
        """Compute classification priority based on article age."""
        priority = 0
        if data.get("published_at"):
            try:
                hours_old = (
                    datetime.datetime.utcnow() - data["published_at"]
                ).total_seconds() / 3600
                if hours_old < 24:
                    priority = 10  # Recent articles - high priority
                elif hours_old < 72:
                    priority = 5  # 1-3 days old - medium priority
            except (TypeError, AttributeError):
                pass
        return priority

    async def _enqueue_for_classification_in_session(
        self, session: AsyncSession, content_id: UUID, priority: int
    ) -> None:
        """Add content to classification queue inside the given session."""
        from app.services.classification_queue_service import (
            ClassificationQueueService,
        )

        queue_service = ClassificationQueueService(session)
        await queue_service.enqueue(content_id, priority=priority)
