"""Perspectives service - MVP live search via Google News RSS."""

import asyncio
from dataclasses import dataclass
from typing import List, Optional
from urllib.parse import quote
import xml.etree.ElementTree as ET

import httpx
import structlog

logger = structlog.get_logger(__name__)

# User-Agent to avoid being blocked by Google News
USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# Bias mapping for major French news sources
DOMAIN_BIAS_MAP = {
    # LEFT
    "liberation.fr": "left",
    "mediapart.fr": "left",
    "humanite.fr": "left",
    "politis.fr": "left",
    "lobs.com": "left",
    "lesinrocks.com": "left",
    "bonpote.com": "left",
    "reporterre.net": "left",
    "lareleve.fr": "left",
    # CENTER-LEFT
    "lemonde.fr": "center-left",
    "francetvinfo.fr": "center-left",
    "franceinter.fr": "center-left",
    "telerama.fr": "center-left",
    "slate.fr": "center-left",
    "france24.com": "center-left",
    "rfi.fr": "center-left",
    "nouvelobs.com": "center-left",
    "marianne.net": "center-left",  # Sovereignist but left-leaning on social issues
    # CENTER
    "20minutes.fr": "center",
    "ouest-france.fr": "center",
    "sudouest.fr": "center",
    "lavoixdunord.fr": "center",
    "leparisien.fr": "center",
    "huffingtonpost.fr": "center",
    "rtl.fr": "center",
    "courrierinternational.com": "center",
    "legrandcontinent.eu": "center",
    "theconversation.com": "center",
    # CENTER-RIGHT
    "lesechos.fr": "center-right",
    "latribune.fr": "center-right",
    "lopinion.fr": "center-right",
    "lexpress.fr": "center-right",
    "lepoint.fr": "center-right",
    "lejdd.fr": "center-right",
    "challenges.fr": "center-right",
    # RIGHT
    "lefigaro.fr": "right",
    "valeursactuelles.com": "right",
    "atlantico.fr": "right",
    "contrepoints.org": "right",
    "bfmtv.com": "right",  # Pro-business, liberal economics
    "europe1.fr": "center-right",
    # FAR-RIGHT
    "cnews.fr": "far-right",  # Bolloré-owned, very conservative
}


@dataclass
class Perspective:
    """A perspective from an external source."""
    title: str
    url: str
    source_name: str
    source_domain: str
    bias_stance: str  # left, center-left, center, center-right, right, unknown
    published_at: Optional[str] = None


import certifi

class PerspectiveService:
    """Service for fetching perspectives via Google News RSS."""

    def __init__(self, timeout: float = 10.0, max_results: int = 10):
        self.timeout = timeout
        self.max_results = max_results

    async def search_perspectives(
        self, 
        keywords: List[str], 
        exclude_url: Optional[str] = None,
        exclude_title: Optional[str] = None
    ) -> List[Perspective]:
        """
        Search for perspectives using Google News RSS.
        
        Args:
            keywords: List of 4-5 keywords from article title for precision
            exclude_url: Optional URL to exclude from results (the source article)
            exclude_title: Optional title to exclude (if similarity is too high)
            
        Returns:
            List of Perspective objects, max 10
        """
        query = " ".join(keywords)
        encoded_query = quote(query)
        url = f"https://news.google.com/rss/search?q={encoded_query}&hl=fr&gl=FR&ceid=FR:fr"
        
        logger.info(
            "perspectives_search_start",
            keywords=keywords,
            query=query,
        )
        
        try:
            headers = {"User-Agent": USER_AGENT}
            async with httpx.AsyncClient(
                timeout=self.timeout, 
                verify=certifi.where(),
                headers=headers,
                follow_redirects=True,
            ) as client:
                response = await client.get(url)
                
                if response.status_code != 200:
                    logger.warning(
                        "perspectives_search_http_error",
                        status_code=response.status_code,
                        keywords=keywords,
                    )
                    return []
                
                perspectives = self._parse_rss(response.content, exclude_url, exclude_title)
                logger.info(
                    "perspectives_search_success",
                    keywords=keywords,
                    count=len(perspectives),
                )
                return perspectives

        except httpx.TimeoutException as e:
            logger.error(
                "perspectives_search_timeout",
                keywords=keywords,
                timeout=self.timeout,
                error=str(e),
            )
            return []
        except httpx.RequestError as e:
            logger.error(
                "perspectives_search_request_error",
                keywords=keywords,
                error=str(e),
                error_type=type(e).__name__,
            )
            return []
        except Exception as e:
            logger.error(
                "perspectives_search_unexpected_error",
                keywords=keywords,
                error=str(e),
                error_type=type(e).__name__,
            )
            return []

    def _parse_rss(
        self, 
        content: bytes, 
        exclude_url: Optional[str] = None,
        exclude_title: Optional[str] = None
    ) -> List[Perspective]:
        """Parse Google News RSS feed."""
        try:
            root = ET.fromstring(content)
            items = root.findall(".//item")
            
            logger.debug(
                "perspectives_parse_rss",
                total_items=len(items),
            )
            
            perspectives = []
            seen_domains = set()
            
            for item in items:
                if len(perspectives) >= self.max_results:
                    break
                
                title_el = item.find("title")
                link_el = item.find("link")
                source_el = item.find("source")
                pub_date_el = item.find("pubDate")
                
                if title_el is None or link_el is None:
                    continue
                
                title = title_el.text or ""
                link = link_el.text or ""

                # 1. Filter out exact URL match
                if exclude_url and link == exclude_url:
                    continue
                
                # 2. Filter out very similar titles (simple exact match or contains for now)
                # Google News titles often include " - Source Name" at the end
                if exclude_title:
                    clean_title = title.split(" - ")[0].strip().lower()
                    clean_exclude = exclude_title.strip().lower()
                    if clean_title == clean_exclude or clean_exclude in clean_title:
                        continue
                
                source_name = source_el.text if source_el is not None else "Unknown"
                source_url = source_el.get("url", "") if source_el is not None else ""
                
                # Extract domain from source URL
                domain = self._extract_domain(source_url)
                
                # Skip duplicates from same domain
                if domain in seen_domains:
                    continue
                seen_domains.add(domain)
                
                # Get bias
                bias = DOMAIN_BIAS_MAP.get(domain, "unknown")
                
                perspectives.append(Perspective(
                    title=title_el.text or "",
                    url=link_el.text or "",
                    source_name=source_name,
                    source_domain=domain,
                    bias_stance=bias,
                    published_at=pub_date_el.text if pub_date_el is not None else None
                ))
            
            return perspectives
            
        except ET.ParseError as e:
            logger.error(
                "perspectives_parse_xml_error",
                error=str(e),
                content_preview=content[:200].decode('utf-8', errors='ignore'),
            )
            return []
        except Exception as e:
            logger.error(
                "perspectives_parse_unexpected_error",
                error=str(e),
                error_type=type(e).__name__,
            )
            return []

    def _extract_domain(self, url: str) -> str:
        """Extract domain from URL."""
        try:
            from urllib.parse import urlparse
            parsed = urlparse(url)
            domain = parsed.netloc
            # Remove www. prefix
            if domain.startswith("www."):
                domain = domain[4:]
            return domain
        except Exception:
            return ""

    def extract_keywords(self, title: str, max_keywords: int = 5) -> List[str]:
        """
        Extract significant keywords from a title.
        
        Prioritizes:
        1. Capitalized words (proper nouns like "Trump", "Powell", "Macron")
        2. Acronyms (all caps like "IA", "UE", "ONU")
        3. Long words that aren't stopwords
        """
        import re
        
        # French stopwords (lowercase only for comparison)
        stopwords = {
            "le", "la", "les", "un", "une", "des", "de", "du", "d", "l", "et", "en", "à", "au", "aux",
            "ce", "cette", "qui", "que", "quoi", "dont", "où", "se", "ne", "pas", "plus", "moins",
            "il", "elle", "on", "nous", "vous", "ils", "elles", "avec", "pour", "par", "sur", "sous",
            "dans", "entre", "vers", "chez", "sans", "est", "sont", "être", "avoir", "fait", "faire",
            "mais", "ou", "donc", "car", "si", "alors", "quand", "comme", "après", "avant",
            "pourquoi", "comment", "face", "contre", "entre", "tout", "tous", "toute", "toutes",
            "cet", "cette", "ces", "son", "sa", "ses", "leur", "leurs", "notre", "nos", "votre", "vos",
            "public", "doit", "peut", "veut", "sera", "été", "aussi", "très", "bien", "mal",
            "nouveau", "nouvelle", "nouveaux", "nouvelles", "grand", "grande", "petit", "petite",
            "premier", "première", "dernier", "dernière", "autre", "autres", "même", "mêmes",
        }
        
        # Common title filler words to ignore (even if capitalized at start)
        title_fillers = {
            "Le", "La", "Les", "Un", "Une", "Des", "Ce", "Cette", "Ces", "Son", "Sa", "Ses",
            "Comment", "Pourquoi", "Quand", "Qui", "Que", "Où", "Voici", "Voilà",
        }
        
        # Split on punctuation but preserve words
        words = re.findall(r'\b[\wÀ-ÿ]+\b', title)
        
        proper_nouns = []  # Capitalized words (likely names/places)
        acronyms = []      # All caps words (like IA, UE, ONU)
        regular_words = [] # Other significant words
        
        for i, word in enumerate(words):
            # Skip very short words
            if len(word) <= 2:
                continue
                
            # Skip stopwords
            if word.lower() in stopwords:
                continue
                
            # Skip title fillers
            if word in title_fillers:
                continue
            
            # Check for acronyms (all uppercase, 2-5 chars)
            if word.isupper() and 2 <= len(word) <= 5:
                acronyms.append(word)
            # Check for proper nouns (starts with capital, not at sentence start or after colon)
            elif word[0].isupper() and len(word) > 2:
                # If it's the first word, check if it looks like a proper noun
                # (not a common word that just happens to be at start)
                if i == 0:
                    # Only keep if it really looks like a name (not a common word)
                    if word.lower() not in stopwords and word not in title_fillers:
                        proper_nouns.append(word)
                else:
                    # Mid-sentence capitalization = definitely important
                    proper_nouns.append(word)
            # Regular significant words
            elif len(word) > 4 and word.lower() not in stopwords:
                regular_words.append(word.lower())
        
        # Combine: prioritize proper nouns and acronyms, then regular words
        keywords = []
        
        # First add proper nouns (most important for news)
        for pn in proper_nouns:
            if pn not in keywords:
                keywords.append(pn)
            if len(keywords) >= max_keywords:
                break
        
        # Add acronyms
        if len(keywords) < max_keywords:
            for acr in acronyms:
                if acr not in keywords:
                    keywords.append(acr)
                if len(keywords) >= max_keywords:
                    break
        
        # Fill with regular words if needed (targeting 4-5 keywords)
        if len(keywords) < max_keywords:
            for rw in regular_words:
                if rw not in keywords:
                    keywords.append(rw)
                if len(keywords) >= max_keywords:
                    break
        
        return keywords
