"""Service d'extraction de contenu d'articles via trafilatura.

Enrichit les articles dont le RSS ne fournit pas de html_content complet.
Utilisé en batch (sync RSS) et on-demand (ouverture article).
"""

import re
from dataclasses import dataclass

import structlog
import trafilatura
from readability import Document as ReadabilityDocument
from trafilatura.settings import use_config

from app.utils.duration_estimator import estimate_reading_time

logger = structlog.get_logger()

# Seuils de qualité contenu (en caractères de texte brut)
CONTENT_QUALITY_FULL = 500
CONTENT_QUALITY_PARTIAL = 100


@dataclass
class ExtractedContent:
    """Résultat d'une extraction de contenu."""

    html_content: str | None = None
    text_content: str | None = None
    reading_time_seconds: int | None = None
    content_quality: str = "none"  # 'full', 'partial', 'none'


def compute_content_quality(text: str | None) -> str:
    """Calcule la qualité du contenu à partir du texte brut.

    Args:
        text: Texte brut (HTML déjà strippé) ou None.

    Returns:
        'full' si > 500 chars, 'partial' si 100-500, 'none' sinon.
    """
    if not text:
        return "none"
    length = len(text.strip())
    if length >= CONTENT_QUALITY_FULL:
        return "full"
    if length >= CONTENT_QUALITY_PARTIAL:
        return "partial"
    return "none"


def _strip_html(html_text: str) -> str:
    """Strip HTML tags et collapse whitespace."""
    text = re.sub(r"<[^>]+>", " ", html_text)
    return re.sub(r"\s+", " ", text).strip()


class ContentExtractor:
    """Extracteur de contenu d'articles web via trafilatura."""

    def __init__(self, download_timeout: int = 15):
        self._config = use_config()
        self._config.set("DEFAULT", "DOWNLOAD_TIMEOUT", str(download_timeout))

    def extract(self, url: str) -> ExtractedContent:
        """Extrait le contenu lisible d'une URL.

        Args:
            url: URL de l'article à extraire.

        Returns:
            ExtractedContent avec html, texte, durée et qualité.
        """
        try:
            downloaded = trafilatura.fetch_url(url, config=self._config)
            if not downloaded:
                logger.warning("content_extractor_fetch_failed", url=url)
                return ExtractedContent()

            # Extraction HTML (favor_recall for aggressive extraction on sparse sites)
            html_content = trafilatura.extract(
                downloaded,
                output_format="html",
                include_images=True,
                include_links=True,
                favor_recall=True,
                config=self._config,
            )

            # Extraction texte brut
            text_content = trafilatura.extract(
                downloaded,
                output_format="text",
                include_images=False,
                include_links=False,
                favor_recall=True,
                config=self._config,
            )

            quality = compute_content_quality(text_content)

            # Fallback: try readability-lxml if trafilatura quality is not 'full'
            if quality != "full":
                try:
                    rb_result = self._extract_with_readability(downloaded)
                    if rb_result:
                        rb_html, rb_text = rb_result
                        rb_quality = compute_content_quality(rb_text)
                        rb_len = len(rb_text.strip()) if rb_text else 0
                        traf_len = len(text_content.strip()) if text_content else 0
                        if rb_len > traf_len:
                            html_content = rb_html
                            text_content = rb_text
                            quality = rb_quality
                            logger.info(
                                "content_extractor_readability_upgrade",
                                url=url,
                                traf_len=traf_len,
                                rb_len=rb_len,
                                quality=quality,
                            )
                except Exception:
                    logger.warning(
                        "content_extractor_readability_failed", url=url
                    )

            reading_time = None
            if text_content:
                reading_time = estimate_reading_time(text_content)

            logger.info(
                "content_extractor_success",
                url=url,
                quality=quality,
                text_length=len(text_content) if text_content else 0,
            )

            return ExtractedContent(
                html_content=html_content,
                text_content=text_content,
                reading_time_seconds=reading_time,
                content_quality=quality,
            )

        except Exception:
            logger.exception("content_extractor_error", url=url)
            return ExtractedContent()

    def _extract_with_readability(
        self, html_source: str
    ) -> tuple[str, str] | None:
        """Fallback extraction using readability-lxml.

        Args:
            html_source: Raw HTML source of the page.

        Returns:
            Tuple of (html_content, text_content) or None if extraction fails.
        """
        if not html_source:
            return None
        try:
            doc = ReadabilityDocument(html_source)
            rb_html = doc.summary()
            if not rb_html:
                return None
            rb_text = _strip_html(rb_html)
            if not rb_text or len(rb_text.strip()) < CONTENT_QUALITY_PARTIAL:
                return None
            return (rb_html, rb_text)
        except Exception:
            return None

    def compute_quality_for_existing(
        self,
        html_content: str | None,
        description: str | None,
    ) -> str:
        """Calcule la qualité pour du contenu déjà en base.

        Priorité au html_content, fallback sur description.
        """
        if html_content:
            plain = _strip_html(html_content)
            return compute_content_quality(plain)
        if description:
            plain = _strip_html(description)
            return compute_content_quality(plain)
        return "none"
