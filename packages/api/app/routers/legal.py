"""Router légal — sert les pages Privacy Policy et CGU statiques.

Routes exposées au root (pas sous /api/) pour permettre des liens propres
depuis App Store Connect, Play Console et le mobile.
"""

from pathlib import Path

from fastapi import APIRouter
from fastapi.responses import FileResponse

router = APIRouter()

_STATIC_DIR = Path(__file__).resolve().parent.parent / "static" / "legal"
_CACHE_HEADERS = {"Cache-Control": "public, max-age=3600"}


@router.get("/privacy", response_class=FileResponse)
async def privacy_policy() -> FileResponse:
    """Politique de confidentialité (HTML statique)."""
    return FileResponse(
        _STATIC_DIR / "privacy.html",
        media_type="text/html",
        headers=_CACHE_HEADERS,
    )


@router.get("/terms", response_class=FileResponse)
async def terms_of_service() -> FileResponse:
    """Conditions Générales d'Utilisation (HTML statique)."""
    return FileResponse(
        _STATIC_DIR / "terms.html",
        media_type="text/html",
        headers=_CACHE_HEADERS,
    )
