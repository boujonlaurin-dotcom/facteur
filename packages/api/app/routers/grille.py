"""Routes de « La Grille du jour » (Story 24.1).

3 endpoints, auth requise. Monté sous `/api/grille` dans `main.py` :
- GET  /api/grille/today
- POST /api/grille/today/guess
- GET  /api/grille/today/leaderboard
"""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user_id
from app.schemas.grille import (
    GrilleGuessRequest,
    GrilleGuessResponse,
    GrilleLeaderboardResponse,
    GrilleTodayResponse,
)
from app.services.grille_service import (
    GameAlreadyFinished,
    GameNotFinished,
    GrilleService,
    PuzzleNotFound,
)

router = APIRouter()


@router.get("/today", response_model=GrilleTodayResponse)
async def get_today(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> GrilleTodayResponse:
    """Charge/auto-crée la partie du jour et restaure les essais joués."""
    service = GrilleService(db)
    try:
        return await service.get_today(user_id)
    except PuzzleNotFound:
        raise HTTPException(status_code=404, detail="Aucun mot du jour disponible")


@router.post("/today/guess", response_model=GrilleGuessResponse)
async def submit_guess(
    payload: GrilleGuessRequest,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> GrilleGuessResponse:
    """Soumet une proposition ; validation et états calculés côté serveur."""
    service = GrilleService(db)
    try:
        return await service.submit_guess(user_id, payload.mot)
    except PuzzleNotFound:
        raise HTTPException(status_code=404, detail="Aucun mot du jour disponible")
    except GameAlreadyFinished:
        raise HTTPException(status_code=409, detail="deja_termine")


@router.get("/today/leaderboard", response_model=GrilleLeaderboardResponse)
async def get_leaderboard(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> GrilleLeaderboardResponse:
    """Classement « tournée de quartier » (partie terminée requise)."""
    service = GrilleService(db)
    try:
        return await service.get_leaderboard(user_id)
    except PuzzleNotFound:
        raise HTTPException(status_code=404, detail="Aucun mot du jour disponible")
    except GameNotFinished:
        raise HTTPException(status_code=409, detail="partie_en_cours")
