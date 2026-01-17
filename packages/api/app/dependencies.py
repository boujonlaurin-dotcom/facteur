"""Dépendances FastAPI (injection)."""

import httpx
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt

from app.config import get_settings

settings = get_settings()
security = HTTPBearer()

# Cache pour les clés JWKS
_jwks_cache = None

import certifi

async def fetch_jwks():
    global _jwks_cache
    if _jwks_cache:
        return _jwks_cache
    
    jwks_url = f"{settings.supabase_url}/auth/v1/.well-known/jwks.json"
    
    try:
        # Use certifi bundle for SSL verification (fix for macOS local issuer error)
        # Add timeout to prevent hanging indefinite requests
        async with httpx.AsyncClient(verify=certifi.where(), timeout=10.0) as client:
            print(f"🔐 Auth: Fetching JWKS from {jwks_url}...", flush=True)
            response = await client.get(jwks_url)
            response.raise_for_status()
            _jwks_cache = response.json()
            print("✅ Auth: JWKS fetched successfully.", flush=True)
            return _jwks_cache
    except Exception as e:
        print(f"❌ Auth: Failed to fetch JWKS: {str(e)}", flush=True)
        # Log response content if available (for 4xx/5xx errors)
        if 'response' in locals():
            print(f"   Response: {response.text}", flush=True)
        # Rethrow as 500 (will be caught by main.py logger) but with clear message
        raise HTTPException(
            status_code=status.HTTP_501_NOT_IMPLEMENTED, # 501 or 503 might be more appropriate, but keeping it simple
            detail=f"Auth configuration error: Could not fetch JWKS. {str(e)}"
        )


async def get_current_user_id(
    credentials: HTTPAuthorizationCredentials = Depends(security),
) -> str:
    """
    Extrait et vérifie le user_id depuis le JWT Supabase.
    """
    token = credentials.credentials

    try:
        # 1. Obtenir le header pour connaître l'algorithme
        header = jwt.get_unverified_header(token)
        alg = header.get("alg", "HS256")

        if alg == "ES256":
            # 2. Utiliser JWKS pour l'algorithme asymétrique ES256
            jwks = await fetch_jwks()
            payload = jwt.decode(
                token,
                jwks,
                algorithms=["ES256"],
                audience="authenticated",
            )
        else:
            # 3. Utiliser le secret symétrique pour HS256
            payload = jwt.decode(
                token,
                settings.supabase_jwt_secret,
                algorithms=["HS256"],
                audience="authenticated",
            )

        user_id = payload.get("sub")

        if not user_id:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid token: missing user_id",
            )

        return user_id

    except JWTError as e:
        # En cas d'échec ES256 (clé expirée ?), on vide le cache pour la prochaine fois
        global _jwks_cache
        _jwks_cache = None
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid token: {str(e)}",
        )


async def get_optional_user_id(
    credentials: HTTPAuthorizationCredentials | None = Depends(
        HTTPBearer(auto_error=False)
    ),
) -> str | None:
    """
    Version optionnelle - retourne None si pas de token.
    
    Utile pour les endpoints qui fonctionnent avec ou sans auth.
    """
    if not credentials:
        return None

    try:
        return await get_current_user_id(credentials)
    except HTTPException:
        return None

