"""Proxy d'images pour la version Web (Safari/CanvasKit).

Sous CanvasKit, Flutter dessine les images dans un <canvas>. Toute image
cross-origin sans en-tête `Access-Control-Allow-Origin` produit un canvas
taint → l'`Image.network` tombe en `errorBuilder` et la vignette se
collapse pour le reste de la session (cf. facteur_thumbnail.dart). Ce
proxy re-sert l'image avec les en-têtes CORS et un cache CDN agressif.

Mobile (Android/iOS natifs) ne passe PAS par ce chemin — voir
`apps/mobile/lib/widgets/design/facteur_image.dart` qui ne réécrit l'URL
que si `kIsWeb`.
"""

from urllib.parse import urlparse

import httpx
import structlog
from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import Response

router = APIRouter()
logger = structlog.get_logger()

_TIMEOUT_S = 5.0
_MAX_BYTES = 5 * 1024 * 1024  # 5 MB
_CACHE_HEADERS = {
    "Cache-Control": "public, max-age=604800, immutable",
    "Access-Control-Allow-Origin": "*",
}


@router.get("/proxy")
async def proxy_image(url: str = Query(..., min_length=8, max_length=2048)) -> Response:
    """Fetch an external image and re-serve it with CORS + cache headers.

    Returns 404 on any upstream failure so the Flutter `errorBuilder`
    collapses the thumbnail cleanly (same UX as a real broken image).
    """
    parsed = urlparse(url)
    if parsed.scheme != "https" or not parsed.netloc:
        raise HTTPException(status_code=400, detail="invalid_url")

    try:
        async with httpx.AsyncClient(
            timeout=_TIMEOUT_S,
            follow_redirects=True,
            max_redirects=3,
        ) as client:
            resp = await client.get(url)
    except (httpx.HTTPError, httpx.InvalidURL):
        raise HTTPException(status_code=404, detail="upstream_unreachable") from None

    if resp.status_code != 200:
        raise HTTPException(status_code=404, detail="upstream_status")

    content_type = resp.headers.get("content-type", "").split(";")[0].strip().lower()
    if not content_type.startswith("image/"):
        raise HTTPException(status_code=415, detail="not_an_image")

    body = resp.content
    if len(body) > _MAX_BYTES:
        raise HTTPException(status_code=413, detail="image_too_large")

    return Response(
        content=body,
        media_type=content_type,
        headers=_CACHE_HEADERS,
    )
