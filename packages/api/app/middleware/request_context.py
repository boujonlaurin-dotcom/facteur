"""Expose métadonnées de la requête courante aux listeners (checkin pool, etc.)."""

from contextvars import ContextVar

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

current_request_path: ContextVar[str] = ContextVar("current_request_path")
current_request_method: ContextVar[str] = ContextVar("current_request_method")


class RequestContextMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next) -> Response:
        path_token = current_request_path.set(request.url.path)
        method_token = current_request_method.set(request.method)
        try:
            return await call_next(request)
        finally:
            current_request_path.reset(path_token)
            current_request_method.reset(method_token)
