"""
MCP Server Sentry — Accès read-only aux erreurs Sentry pour le diagnostic production.

Outils exposés :
- list_issues : Issues non résolues avec filtres
- get_issue_events : Events/stacktraces d'une issue
- get_event_context : Tags, breadcrumbs, request data d'un event

Nécessite les variables d'environnement :
- SENTRY_AUTH_TOKEN : Token API Sentry (scope: project:read, event:read)
- SENTRY_ORG : Slug de l'organisation Sentry
- SENTRY_PROJECT : Slug du projet Sentry
"""

import os
import httpx
from mcp.server.fastmcp import FastMCP

SENTRY_BASE_URL = "https://sentry.io/api/0"
SENTRY_AUTH_TOKEN = os.environ.get("SENTRY_AUTH_TOKEN", "")
SENTRY_ORG = os.environ.get("SENTRY_ORG", "")
SENTRY_PROJECT = os.environ.get("SENTRY_PROJECT", "")

mcp = FastMCP(
    "sentry-observability",
    description="Read-only access to Sentry errors for production diagnostics",
)


def _headers() -> dict[str, str]:
    return {
        "Authorization": f"Bearer {SENTRY_AUTH_TOKEN}",
        "Content-Type": "application/json",
    }


def _check_config() -> str | None:
    """Retourne un message d'erreur si la configuration est incomplète."""
    missing = []
    if not SENTRY_AUTH_TOKEN:
        missing.append("SENTRY_AUTH_TOKEN")
    if not SENTRY_ORG:
        missing.append("SENTRY_ORG")
    if not SENTRY_PROJECT:
        missing.append("SENTRY_PROJECT")
    if missing:
        return f"Missing environment variables: {', '.join(missing)}"
    return None


@mcp.tool()
async def list_issues(
    query: str = "is:unresolved",
    time_range: str = "24h",
    limit: int = 10,
) -> str:
    """
    Liste les issues Sentry du projet Facteur.

    Args:
        query: Requête Sentry (ex: "is:unresolved", "is:unresolved level:error",
               "UndefinedColumn", "is:unresolved !logger:httpx"). Par défaut: "is:unresolved"
        time_range: Période relative (ex: "1h", "24h", "7d", "14d", "30d"). Par défaut: "24h"
        limit: Nombre max d'issues à retourner (1-100). Par défaut: 10

    Returns:
        Liste formatée des issues avec ID, titre, niveau, nombre d'events, et dernière occurrence.
    """
    err = _check_config()
    if err:
        return f"Configuration error: {err}"

    # Conversion time_range en paramètre statsPeriod Sentry
    stats_period = time_range if time_range else "24h"

    url = f"{SENTRY_BASE_URL}/projects/{SENTRY_ORG}/{SENTRY_PROJECT}/issues/"
    params = {
        "query": query,
        "statsPeriod": stats_period,
        "limit": min(limit, 100),
        "sort": "date",
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.get(url, headers=_headers(), params=params)
        if resp.status_code != 200:
            return f"Sentry API error {resp.status_code}: {resp.text}"

        issues = resp.json()

    if not issues:
        return f"No issues found for query '{query}' in the last {time_range}."

    lines = [f"Found {len(issues)} issue(s) for query '{query}' (last {time_range}):\n"]
    for issue in issues:
        lines.append(
            f"- [{issue.get('shortId', 'N/A')}] {issue.get('title', 'No title')}\n"
            f"  ID: {issue.get('id')} | Level: {issue.get('level', '?')} | "
            f"Events: {issue.get('count', '?')} | Users: {issue.get('userCount', '?')}\n"
            f"  First seen: {issue.get('firstSeen', '?')} | Last seen: {issue.get('lastSeen', '?')}\n"
            f"  Link: {issue.get('permalink', 'N/A')}"
        )
    return "\n".join(lines)


@mcp.tool()
async def get_issue_events(
    issue_id: str,
    limit: int = 5,
) -> str:
    """
    Récupère les events (stacktraces) d'une issue Sentry.

    Args:
        issue_id: L'ID numérique de l'issue Sentry (obtenu via list_issues).
        limit: Nombre d'events à retourner (1-50). Par défaut: 5

    Returns:
        Events formatés avec stacktrace, message, tags et timestamp.
    """
    err = _check_config()
    if err:
        return f"Configuration error: {err}"

    url = f"{SENTRY_BASE_URL}/issues/{issue_id}/events/"
    params = {"limit": min(limit, 50)}

    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.get(url, headers=_headers(), params=params)
        if resp.status_code != 200:
            return f"Sentry API error {resp.status_code}: {resp.text}"

        events = resp.json()

    if not events:
        return f"No events found for issue {issue_id}."

    lines = [f"Found {len(events)} event(s) for issue {issue_id}:\n"]
    for i, event in enumerate(events, 1):
        event_id = event.get("eventID", event.get("id", "?"))
        lines.append(f"--- Event {i} (ID: {event_id}) ---")
        lines.append(f"Timestamp: {event.get('dateCreated', '?')}")
        lines.append(f"Message: {event.get('message', event.get('title', 'N/A'))}")

        # Tags
        tags = event.get("tags", [])
        if tags:
            tag_str = ", ".join(f"{t.get('key')}={t.get('value')}" for t in tags[:15])
            lines.append(f"Tags: {tag_str}")

        # Stacktrace (from exception entries)
        entries = event.get("entries", [])
        for entry in entries:
            if entry.get("type") == "exception":
                for exc_val in entry.get("data", {}).get("values", []):
                    exc_type = exc_val.get("type", "Exception")
                    exc_value = exc_val.get("value", "")
                    lines.append(f"\nException: {exc_type}: {exc_value}")

                    stacktrace = exc_val.get("stacktrace", {})
                    frames = stacktrace.get("frames", [])
                    if frames:
                        lines.append("Stacktrace (most recent last):")
                        # Show last 10 frames
                        for frame in frames[-10:]:
                            filename = frame.get("filename", "?")
                            lineno = frame.get("lineNo", "?")
                            func = frame.get("function", "?")
                            context_line = frame.get("context_line", "").strip()
                            in_app = " [app]" if frame.get("inApp") else ""
                            lines.append(f"  {filename}:{lineno} in {func}{in_app}")
                            if context_line:
                                lines.append(f"    > {context_line}")

        lines.append("")

    return "\n".join(lines)


@mcp.tool()
async def get_event_context(
    event_id: str,
) -> str:
    """
    Récupère le contexte complet d'un event Sentry (tags, breadcrumbs, request data).

    Args:
        event_id: L'ID de l'event Sentry (obtenu via get_issue_events).

    Returns:
        Contexte détaillé : tags, breadcrumbs, données de requête HTTP, user info.
    """
    err = _check_config()
    if err:
        return f"Configuration error: {err}"

    url = f"{SENTRY_BASE_URL}/projects/{SENTRY_ORG}/{SENTRY_PROJECT}/events/{event_id}/"

    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.get(url, headers=_headers())
        if resp.status_code != 200:
            return f"Sentry API error {resp.status_code}: {resp.text}"

        event = resp.json()

    lines = [f"Event context for {event_id}:\n"]

    # User
    user = event.get("user")
    if user:
        lines.append(f"User: id={user.get('id', '?')}, ip={user.get('ip_address', '?')}")

    # Tags
    tags = event.get("tags", [])
    if tags:
        lines.append("\nTags:")
        for tag in tags:
            lines.append(f"  {tag.get('key')}: {tag.get('value')}")

    # Contexts (device, os, runtime, etc.)
    contexts = event.get("contexts", {})
    if contexts:
        lines.append("\nContexts:")
        for ctx_name, ctx_data in contexts.items():
            if isinstance(ctx_data, dict):
                ctx_summary = ", ".join(f"{k}={v}" for k, v in ctx_data.items() if k != "type")
                lines.append(f"  {ctx_name}: {ctx_summary}")

    # Request data
    entries = event.get("entries", [])
    for entry in entries:
        if entry.get("type") == "request":
            req = entry.get("data", {})
            lines.append(f"\nHTTP Request:")
            lines.append(f"  Method: {req.get('method', '?')}")
            lines.append(f"  URL: {req.get('url', '?')}")
            headers = req.get("headers", [])
            if headers:
                # Filter sensitive headers
                safe_headers = [
                    h for h in headers
                    if h[0].lower() not in ("authorization", "cookie", "set-cookie")
                ]
                for h in safe_headers[:10]:
                    lines.append(f"  {h[0]}: {h[1]}")
            query = req.get("query", "")
            if query:
                lines.append(f"  Query: {query}")

        # Breadcrumbs
        if entry.get("type") == "breadcrumbs":
            crumbs = entry.get("data", {}).get("values", [])
            if crumbs:
                lines.append(f"\nBreadcrumbs ({len(crumbs)} total, showing last 20):")
                for crumb in crumbs[-20:]:
                    ts = crumb.get("timestamp", "?")
                    cat = crumb.get("category", "?")
                    msg = crumb.get("message", "")
                    level = crumb.get("level", "info")
                    data = crumb.get("data", {})
                    data_str = f" | {data}" if data else ""
                    lines.append(f"  [{ts}] [{level}] {cat}: {msg}{data_str}")

    # SDK info
    sdk = event.get("sdk", {})
    if sdk:
        lines.append(f"\nSDK: {sdk.get('name', '?')} {sdk.get('version', '?')}")

    return "\n".join(lines)


@mcp.tool()
async def search_errors(
    search_term: str,
    time_range: str = "7d",
    limit: int = 10,
) -> str:
    """
    Recherche des erreurs par mot-clé dans Sentry (stacktrace, message, etc.).

    Args:
        search_term: Terme de recherche (ex: "UndefinedColumn", "KeyError",
                     "digest_service", "alembic"). Recherche dans les titres et messages.
        time_range: Période relative (ex: "24h", "7d", "30d"). Par défaut: "7d"
        limit: Nombre max de résultats (1-100). Par défaut: 10

    Returns:
        Issues correspondantes avec contexte.
    """
    return await list_issues(
        query=f"is:unresolved {search_term}",
        time_range=time_range,
        limit=limit,
    )


if __name__ == "__main__":
    mcp.run()
