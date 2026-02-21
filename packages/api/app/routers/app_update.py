"""Router pour les mises à jour de l'application mobile.

Interroge GitHub Releases API pour détecter les nouvelles versions
et fournir une URL de téléchargement temporaire pour l'APK.
"""

import time

import httpx
import structlog
from fastapi import APIRouter, HTTPException

from app.config import get_settings

logger = structlog.get_logger()
router = APIRouter()

# Simple in-memory cache with TTL
_cache: dict[str, tuple[float, dict]] = {}
_CACHE_TTL = 300  # 5 minutes


async def _fetch_latest_release() -> dict:
    """Fetch latest release info from GitHub API, with 5-min cache."""
    now = time.monotonic()
    cached = _cache.get("latest")
    if cached and now < cached[0]:
        return cached[1]

    settings = get_settings()
    if not settings.github_token:
        raise HTTPException(
            status_code=503,
            detail="App update feature not configured (GITHUB_TOKEN missing)",
        )

    headers = {
        "Authorization": f"Bearer {settings.github_token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }

    async with httpx.AsyncClient(timeout=10) as client:
        resp = await client.get(
            f"https://api.github.com/repos/{settings.github_repo}/releases/latest",
            headers=headers,
        )

    if resp.status_code == 404:
        raise HTTPException(status_code=404, detail="No releases found")
    if resp.status_code != 200:
        logger.error(
            "github_api_error",
            status=resp.status_code,
            body=resp.text[:200],
        )
        raise HTTPException(status_code=502, detail="Failed to fetch release info")

    data = resp.json()

    # Find the first .apk asset
    apk_asset = next(
        (a for a in data.get("assets", []) if a["name"].endswith(".apk")),
        None,
    )

    result = {
        "tag": data["tag_name"],
        "name": data.get("name", ""),
        "notes": data.get("body", ""),
        "published_at": data.get("published_at", ""),
        "apk_asset_id": apk_asset["id"] if apk_asset else None,
        "apk_size": apk_asset["size"] if apk_asset else None,
    }

    _cache["latest"] = (now + _CACHE_TTL, result)
    logger.info("github_release_fetched", tag=result["tag"])
    return result


@router.get("/update")
async def check_for_update() -> dict:
    """Retourne les infos de la dernière release GitHub."""
    return await _fetch_latest_release()


@router.get("/update/download-url")
async def get_download_url() -> dict[str, str]:
    """Retourne une URL de téléchargement temporaire pour l'APK.

    GitHub redirige (302) vers une URL S3 pré-signée quand on requête
    un asset avec Accept: application/octet-stream. On capture cette URL
    et la retourne au client (~10 min de validité).
    """
    release = await _fetch_latest_release()
    asset_id = release.get("apk_asset_id")
    if not asset_id:
        raise HTTPException(status_code=404, detail="No APK found in latest release")

    settings = get_settings()
    headers = {
        "Authorization": f"Bearer {settings.github_token}",
        "Accept": "application/octet-stream",
        "X-GitHub-Api-Version": "2022-11-28",
    }

    async with httpx.AsyncClient(follow_redirects=False, timeout=10) as client:
        resp = await client.get(
            f"https://api.github.com/repos/{settings.github_repo}/releases/assets/{asset_id}",
            headers=headers,
        )

    if resp.status_code in (301, 302) and "location" in resp.headers:
        return {"url": resp.headers["location"]}

    logger.error(
        "github_download_redirect_failed",
        status=resp.status_code,
        headers=dict(resp.headers),
    )
    raise HTTPException(status_code=502, detail="Failed to get download URL")
