"""Utilitaires YouTube."""

import re
from typing import Optional


def extract_youtube_channel_id(url: str) -> Optional[str]:
    """
    Extrait l'ID de chaîne YouTube depuis une URL.
    
    Supporte les formats:
    - https://youtube.com/channel/UC...
    - https://youtube.com/c/ChannelName
    - https://youtube.com/@handle
    - https://www.youtube.com/user/username
    """
    # Pattern pour /channel/UC...
    channel_match = re.search(r"youtube\.com/channel/(UC[\w-]+)", url)
    if channel_match:
        return channel_match.group(1)

    # Pattern pour /@handle - nécessite une requête HTTP pour résoudre
    handle_match = re.search(r"youtube\.com/@([\w-]+)", url)
    if handle_match:
        # TODO: Résoudre le handle vers l'ID de chaîne via l'API YouTube
        # Pour l'instant, on utilise le handle comme identifiant
        return f"@{handle_match.group(1)}"

    # Pattern pour /c/ChannelName
    c_match = re.search(r"youtube\.com/c/([\w-]+)", url)
    if c_match:
        return f"c/{c_match.group(1)}"

    # Pattern pour /user/username
    user_match = re.search(r"youtube\.com/user/([\w-]+)", url)
    if user_match:
        return f"user/{user_match.group(1)}"

    return None


def get_youtube_rss_url(channel_id: str) -> str:
    """
    Retourne l'URL du flux RSS YouTube pour une chaîne.
    
    Note: Seuls les IDs au format UC... fonctionnent directement.
    Les handles et noms personnalisés nécessitent une résolution préalable.
    """
    if channel_id.startswith("UC"):
        return f"https://www.youtube.com/feeds/videos.xml?channel_id={channel_id}"

    # Pour les handles et autres formats, on essaie quand même
    # (YouTube peut rediriger)
    if channel_id.startswith("@"):
        # Les handles ne fonctionnent pas directement avec le RSS
        # Il faudrait résoudre vers l'ID UC... via l'API
        raise ValueError(
            f"YouTube handle '{channel_id}' must be resolved to channel ID first"
        )

    if channel_id.startswith("c/") or channel_id.startswith("user/"):
        raise ValueError(
            f"Custom channel URL '{channel_id}' must be resolved to channel ID first"
        )

    return f"https://www.youtube.com/feeds/videos.xml?channel_id={channel_id}"


def get_youtube_thumbnail(video_id: str, quality: str = "mqdefault") -> str:
    """
    Retourne l'URL de la thumbnail d'une vidéo YouTube.
    
    Qualités disponibles:
    - default (120x90)
    - mqdefault (320x180)
    - hqdefault (480x360)
    - sddefault (640x480)
    - maxresdefault (1280x720)
    """
    return f"https://img.youtube.com/vi/{video_id}/{quality}.jpg"


def extract_video_id(url: str) -> Optional[str]:
    """Extrait l'ID de vidéo depuis une URL YouTube."""
    patterns = [
        r"youtube\.com/watch\?v=([\w-]+)",
        r"youtu\.be/([\w-]+)",
        r"youtube\.com/embed/([\w-]+)",
    ]

    for pattern in patterns:
        match = re.search(pattern, url)
        if match:
            return match.group(1)

    return None

