"""Routes d'authentification."""

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, EmailStr

from app.dependencies import get_current_user_id

router = APIRouter()


class LoginRequest(BaseModel):
    """Requête de connexion."""

    email: EmailStr
    password: str


class SignupRequest(BaseModel):
    """Requête d'inscription."""

    email: EmailStr
    password: str


class TokenResponse(BaseModel):
    """Réponse avec token."""

    access_token: str
    token_type: str = "bearer"
    expires_in: int


@router.post("/signup", response_model=TokenResponse)
async def signup(request: SignupRequest) -> TokenResponse:
    """
    Créer un nouveau compte.

    Note: L'authentification est gérée côté client via Supabase.
    Ce endpoint est un placeholder pour une éventuelle logique serveur.
    """
    # L'auth est gérée par Supabase côté client
    # Ce endpoint peut être utilisé pour de la logique additionnelle
    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail="Auth is handled by Supabase client SDK",
    )


@router.post("/login", response_model=TokenResponse)
async def login(request: LoginRequest) -> TokenResponse:
    """
    Se connecter avec email/password.

    Note: L'authentification est gérée côté client via Supabase.
    """
    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail="Auth is handled by Supabase client SDK",
    )


@router.post("/logout")
async def logout(user_id: str = Depends(get_current_user_id)) -> dict[str, str]:
    """
    Se déconnecter.

    Note: La déconnexion est gérée côté client via Supabase.
    """
    return {"message": "Logout handled by client"}


@router.post("/refresh", response_model=TokenResponse)
async def refresh_token() -> TokenResponse:
    """
    Rafraîchir le token.

    Note: Le refresh est géré côté client via Supabase.
    """
    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail="Token refresh is handled by Supabase client SDK",
    )
