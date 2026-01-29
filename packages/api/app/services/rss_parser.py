import structlog
import feedparser
import httpx
from bs4 import BeautifulSoup
from typing import Optional, List
from pydantic import BaseModel

logger = structlog.get_logger()

class DetectedFeed(BaseModel):
    feed_url: str
    title: str = "Unknown Feed"
    description: Optional[str] = None
    feed_type: str = "rss" # rss, atom, youtube, podcast
    logo_url: Optional[str] = None
    entries: List[dict] = []

class RSSParser:
    """Service to parse and detect RSS feeds."""
    
    def __init__(self):
        self.client = httpx.AsyncClient(
            timeout=10.0,
            follow_redirects=True,
            headers={
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36",
                "Accept-Language": "en-US,en;q=0.9",
            },
            cookies={"CONSENT": "YES+cb.20210328-17-p0.en+FX+430"}
        )

    async def close(self):
        await self.client.aclose()

    async def parse(self, url: str) -> dict:
        """
        Parses a direct RSS/Atom feed URL using feedparser.
        Returns the raw dict from feedparser.
        This is a low-level method.
        """
        # feedparser is synchronous and blocking, so run in executor
        import asyncio
        loop = asyncio.get_event_loop()
        
        # We fetch potential content first to avoid blocking IO in feedparser's internal fetcher
        # But for 'parse', we might accept just the URL if we trust feedparser? 
        # Better to fetch with httpx for consistent timeout/headers control.
        try:
            response = await self.client.get(url)
            response.raise_for_status()
            content = response.text
        except Exception as e:
            # If fetch fails, maybe it's not a URL but raw content? No, type hint says url.
            # Reraise or return empty?
            raise ValueError(f"Failed to fetch RSS URI: {str(e)}")

        feed = await loop.run_in_executor(None, feedparser.parse, content)
        
        if feed.bozo:
             # feedparser.bozo means malformed XML, but often it still parses something usable.
             # We log it but proceed if entries exist.
             logger.warning("Feedparser reported bozo", url=url, error=feed.bozo_exception)
             
        return feed

    async def detect(self, url: str) -> DetectedFeed:
        """
        Smart detection of a feed from a URL.
        1. Tries to parse directly as RSS.
        2. If fails, treats as HTML and looks for <link rel="alternate">.
        3. If found, tries to parse the found link.
        """
        logger.info("Detecting feed", url=url)
        
        # 1. Try fetching and parsing
        try:
            response = await self.client.get(url)
            logger.info("Fetched URL", url=url, status_code=response.status_code)
            response.raise_for_status()
            content = response.text
        except Exception as e:
             raise ValueError(f"Could not access URL: {str(e)}")

        import asyncio
        loop = asyncio.get_event_loop()
        feed_data = await loop.run_in_executor(None, feedparser.parse, content)
        
        # Check if direct parse worked
        if not feed_data.bozo and len(feed_data.entries) > 0:
            return await self._format_response(url, feed_data)
        
        # If bozo (malformed) but has entries, we might accept it?
        # But often HTML pages return non-empty 'entries' because feedparser is too lenient.
        # Strict check: Feed title must exist.
        if len(feed_data.entries) > 0 and 'title' in feed_data.feed:
             return await self._format_response(url, feed_data)

        # 2. HTML Auto-Discovery
        soup = BeautifulSoup(content, 'html.parser')
        
        # SPECIAL: YouTube Handle Resolution
        if "youtube.com" in url or "youtu.be" in url:
            logger.info("YouTube URL detected, looking for channel ID", url=url)
            channel_id = None
            
            # 1. Try meta tag (channelId or identifier)
            channel_id_meta = soup.find("meta", itemprop="channelId")
            if channel_id_meta and channel_id_meta.get("content"):
                channel_id = channel_id_meta["content"]
            
            if not channel_id:
                identifier_meta = soup.find("meta", itemprop="identifier")
                if identifier_meta and identifier_meta.get("content"):
                    channel_id = identifier_meta["content"]
            
            # 2. Schema.org fallback
            if not channel_id:
                 # <meta property="og:url" content="https://www.youtube.com/channel/UC...">
                 og_url = soup.find("meta", property="og:url")
                 if og_url and "channel/" in (og_url.get("content") or ""):
                     channel_id = og_url["content"].split("channel/")[-1]

            # 3. Regex fallback (Robust for "Consent" pages or JS renders)
            if not channel_id:
                import re
                # Look for "channelId":"UC..." in JSON blobs
                match = re.search(r'"channelId":"(UC[\w-]+)"', content)
                if match:
                    channel_id = match.group(1)
            
            # 4. Canonical link check (Wait, often points to /channel/UC...)
            if not channel_id:
                canonical = soup.find("link", rel="canonical")
                if canonical and "channel/" in (canonical.get("href") or ""):
                    channel_id = canonical["href"].split("channel/")[-1]
                elif canonical and "@" in (canonical.get("href") or ""):
                    # Still a handle, we might need to retry with a better cookie
                    logger.info("Canonical is still a handle, trying with alternative CONSENT cookie", url=url)

            # 5. Redirection URL extraction (Look for 'continue' param)
            if not channel_id:
                # Often present in consent pages: <a href="...continue=https%3A%2F%2Fwww.youtube.com%2Fchannel%2FUC...">
                all_links = soup.find_all("a", href=True)
                for link in all_links:
                    href = link["href"]
                    if "continue=" in href and "channel%2FUC" in href:
                        import urllib.parse
                        parsed_href = urllib.parse.urlparse(href)
                        query_params = urllib.parse.parse_qs(parsed_href.query)
                        cont_url = query_params.get("continue", [None])[0]
                        if cont_url and "channel/" in cont_url:
                           channel_id = cont_url.split("channel/")[-1].split("?")[0]
                           logger.info("Extracted channel ID from continue param", channel_id=channel_id)
                           break

            # 6. Retry with /about suffix if still nothing
            if not channel_id and "/@" in url:
                about_url = url.rstrip("/") + "/about"
                logger.info("Retrying YouTube detection with /about suffix", about_url=about_url)
                try:
                    about_resp = await self.client.get(about_url)
                    if about_resp.status_code == 200:
                        about_content = about_resp.text
                        match = re.search(r'"channelId":"(UC[\w-]+)"', about_content)
                        if match:
                            channel_id = match.group(1)
                            logger.info("Resolved YouTube Channel ID from /about page", channel_id=channel_id)
                except Exception as e:
                    logger.warning("Retry with /about failed", error=str(e))

            # 7. Regex fallback for identifier meta (if soup failed)
            if not channel_id:
                import re
                match = re.search(r'itemprop="identifier" content="([\w-]+)"', content)
                if match:
                    channel_id = match.group(1)
                    
            # 8. Retry with a known robust CONSENT cookie if still nothing
            if not channel_id and ("consent.youtube.com" in content or "canonical" in str(soup.find("link", rel="canonical"))):
                 logger.info("Detected consent wall or missing ID, retrying with robust cookie", url=url)
                 try:
                     retry_resp = await self.client.get(url, cookies={"CONSENT": "YES+cb.20230531-17-p0.en+FX+908"})
                     if retry_resp.status_code == 200:
                         retry_content = retry_resp.text
                         match = re.search(r'"channelId":"(UC[\w-]+)"', retry_content)
                         if match:
                             channel_id = match.group(1)
                             logger.info("Resolved YouTube Channel ID after retry with cookie", channel_id=channel_id)
                 except Exception as e:
                     logger.warning("Retry with robust cookie failed", error=str(e))

            # 9. Ultimate Fallback: YouTube Search discovery (Bypasses most consent walls)
            if not channel_id and "/@" in url:
                handle = url.split("@")[-1].split("/")[0].split("?")[0]
                search_url = f"https://www.youtube.com/results?search_query=@{handle}&sp=EgIQAg%253D%253D"
                logger.info("Trying YouTube Search discovery for ID", search_url=search_url)
                try:
                    search_resp = await self.client.get(search_url)
                    if search_resp.status_code == 200:
                        search_content = search_resp.text
                        # Look for channelId in the search results JS
                        match = re.search(r'"channelId":"(UC[\w-]+)"', search_content)
                        if match:
                            channel_id = match.group(1)
                            logger.info("Resolved YouTube Channel ID via search discovery", channel_id=channel_id)
                except Exception as e:
                    logger.warning("Search discovery failed", error=str(e))
             
            if not channel_id:
                logger.warning("Failed to resolve YouTube Channel ID", url=url)
                # print(f"DEBUG YOUTUBE CONTENT: {content[:2000]}") 
                with open("debug_youtube.html", "w") as f:
                    f.write(content)
                logger.info("Dumped YouTube HTML to debug_youtube.html")
            
            if channel_id:
                logger.info("Resolved YouTube Channel ID", handle=url, channel_id=channel_id)
                rss_url = f"https://www.youtube.com/feeds/videos.xml?channel_id={channel_id}"
                
                # Fetch and parse the resolved Feed
                try:
                    feed_resp = await self.client.get(rss_url)
                    feed_resp.raise_for_status()
                    # Feedparser inside executor
                    yt_feed = await loop.run_in_executor(None, feedparser.parse, feed_resp.text)
                    if len(yt_feed.entries) > 0:
                        return await self._format_response(rss_url, yt_feed)
                except Exception as e:
                    logger.warning("Failed to parse resolved YouTube feed", rss_url=rss_url, error=str(e))

        rss_links = soup.find_all('link', rel='alternate')
        
        found_url = None
        
        for link in rss_links:
            type_attr = link.get('type', '').lower()
            href = link.get('href')
            
            # Filter out unwanted types
            if 'oembed' in type_attr:
                continue
            if 'comments' in type_attr or 'comments' in (href or '').lower():
                continue
                
            if 'rss' in type_attr or 'atom' in type_attr or 'xml' in type_attr:
                if href:
                    # Handle relative URLs
                    if href.startswith('/'):
                        from urllib.parse import urljoin
                        found_url = urljoin(url, href)
                    else:
                        found_url = href
                    break # Take the first one for now
        
        if found_url:
            logger.info("Found RSS link in HTML", page_url=url, rss_url=found_url)
            # Recursively parse the found feed (but avoid infinite loops if it points to self)
            if found_url != url:
                # Fetch the found feed
                try:
                    feed_resp = await self.client.get(found_url)
                    feed_resp.raise_for_status()
                    found_feed_data = await loop.run_in_executor(None, feedparser.parse, feed_resp.text)
                    if len(found_feed_data.entries) > 0:
                         return await self._format_response(found_url, found_feed_data)
                except Exception as e:
                    logger.warning("Failed to parse discovered feed", rss_url=found_url, error=str(e))
        
        # 3. Common Suffix Fallback (WordPress, Ghost, etc.)
        # Only if strict URL was passed (not a search query)
        if not found_url:
            from urllib.parse import urljoin
            common_suffixes = ["/feed", "/rss", "/rss.xml", "/feed.xml"]
            for suffix in common_suffixes:
                 try_url = url.rstrip("/") + suffix
                 logger.info("Trying common RSS suffix", try_url=try_url)
                 try:
                     resp = await self.client.get(try_url)
                     if resp.status_code == 200:
                         # Check if it parses
                         suffix_feed = await loop.run_in_executor(None, feedparser.parse, resp.text)
                         if not suffix_feed.bozo and len(suffix_feed.entries) > 0:
                              logger.info("Found valid feed via suffix", url=try_url)
                              return await self._format_response(try_url, suffix_feed)
                 except Exception:
                     continue

        # If we reach here, nothing found
        raise ValueError("No RSS feed found on this page.")

    async def _format_response(self, url: str, feed_data) -> DetectedFeed:
        feed = feed_data.feed
        
        # Detect type
        feed_type = "rss"
        if "atom" in feed_data.version:
            feed_type = "atom"
            
        # SPECIAL: Check if it's a YouTube feed
        if "youtube.com/feeds/videos.xml" in url:
            feed_type = "youtube"
            
        # Image
        logo = None
        if "image" in feed and "href" in feed.image:
            logo = feed.image.href
            
        entries = []
        for e in feed_data.entries[:3]: # Preview first 3
            entries.append({
                "title": e.get("title", "No Title"),
                "link": e.get("link", ""),
                "published_at": e.get("published", "")
            })

        return DetectedFeed(
            feed_url=url,
            title=feed.get("title", "Unknown Feed"),
            description=feed.get("description", "")[:200] if "description" in feed else None,
            feed_type=feed_type,
            logo_url=logo,
            entries=entries
        )
