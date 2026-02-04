"""Dépendances FastAPI (injection)."""

import asyncio
import httpx
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt

from app.config import get_settings

settings = get_settings()
security = HTTPBearer()

# Cache pour les clés JWKS
_jwks_cache = None

# Cache pour le statut email confirmé (user_id -> (confirmed, timestamp))
# Simple TTL cache pour réduire les requêtes DB pendant les pics de trafic
_email_confirmed_cache = {}
_EMAIL_CACHE_TTL_SECONDS = 300  # 5 minutes

import certifi
import time


async def _check_email_confirmed_with_retry(user_id: str, max_retries: int = 3, timeout: float = 5.0) -> bool:
    """
    Check if user email is confirmed in database with retry logic and caching.
    
    Handles connection pool timeouts and stale connections gracefully.
    Uses in-memory TTL cache to reduce database load during traffic spikes.
    
    Args:
        user_id: The Supabase user ID
        max_retries: Maximum number of retry attempts
        timeout: Timeout per attempt in seconds
        
    Returns:
        True if email is confirmed, False otherwise
    """
    from app.database import async_session_maker
    from sqlalchemy import text
    from sqlalchemy.exc import OperationalError, TimeoutError as SQLAlchemyTimeoutError
    
    global _email_confirmed_cache
    
    # Check cache first
    current_time = time.time()
    if user_id in _email_confirmed_cache:
        cached_result, timestamp = _email_confirmed_cache[user_id]
        if current_time - timestamp < _EMAIL_CACHE_TTL_SECONDS:
            return cached_result
        # Cache expired, remove it
        del _email_confirmed_cache[user_id]
    
    # Query database with retries
    for attempt in range(max_retries):
        try:
            # Use asyncio.wait_for to add timeout to the entire session operation
            async with async_session_maker() as session:
                # Execute query with shorter timeout to avoid holding connections
                result = await asyncio.wait_for(
                    session.execute(
                        text("SELECT email_confirmed_at FROM auth.users WHERE id = :uid"),
                        {"uid": user_id}
                    ),
                    timeout=timeout
                )
                row = result.fetchone()
                is_confirmed = row is not None and row[0] is not None
                
                # Cache the result
                _email_confirmed_cache[user_id] = (is_confirmed, current_time)
                
                return is_confirmed
                
        except (asyncio.TimeoutError, SQLAlchemyTimeoutError) as timeout_err:
            # Connection pool timeout - retry with backoff
            if attempt < max_retries - 1:
                wait_time = 0.5 * (2 ** attempt)  # Exponential backoff: 0.5s, 1s, 2s
                print(f"⚠️ Auth: DB timeout on attempt {attempt + 1}, retrying in {wait_time}s...", flush=True)
                await asyncio.sleep(wait_time)
            else:
                print(f"❌ Auth: DB check failed after {max_retries} attempts (timeout)", flush=True)
                return False
                
        except OperationalError as op_err:
            # Connection/SSL errors - retry with backoff
            if attempt < max_retries - 1:
                wait_time = 0.5 * (2 ** attempt)
                print(f"⚠️ Auth: DB connection error on attempt {attempt + 1}: {op_err}, retrying in {wait_time}s...", flush=True)
                await asyncio.sleep(wait_time)
            else:
                print(f"❌ Auth: DB check failed after {max_retries} attempts (operational error)", flush=True)
                return False
                
        except Exception as e:
            # Unexpected error - don't retry
            print(f"❌ Auth: Unexpected DB error: {e}", flush=True)
            return False
    
    return False


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

        # Vérifier si l'email est confirmé
        # Supabase inclut email_confirmed_at dans le payload si l'email est validé
        email_confirmed_at = payload.get("email_confirmed_at")
        if not email_confirmed_at:
            # On vérifie le provider pour ne pas bloquer les logins sociaux qui pourraient 
            # avoir une structure différente ou être confirmés d'office
            app_metadata = payload.get("app_metadata", {})
            provider = app_metadata.get("provider")
            
            if provider == "email":
                # Fallback: Check DB directly (JWT might be stale after manual confirmation)
                # Uses retry logic to handle connection pool timeouts gracefully
                is_confirmed = await _check_email_confirmed_with_retry(user_id)
                
                if is_confirmed:
                    print(f"✅ Auth: User {user_id} confirmed in DB (stale JWT)", flush=True)
                    return user_id
                else:
                    print(f"🚫 Auth: User {user_id} blocked (email not confirmed)", flush=True)
                print(f"🔍 DEBUG JWT PAYLOAD: {payload}", flush=True)
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Email not confirmed",
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

