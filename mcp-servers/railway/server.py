"""
MCP Server Railway — Accès read-only aux logs de déploiement Railway.

Outils exposés :
- get_latest_deployments : Derniers déploiements du service
- get_deployment_logs : Logs d'un déploiement spécifique
- get_build_logs : Logs de build d'un déploiement

Nécessite les variables d'environnement :
- RAILWAY_API_TOKEN : Token API Railway (scope read-only)
- RAILWAY_PROJECT_ID : ID du projet Railway
- RAILWAY_SERVICE_ID : ID du service Railway (optionnel, pour filtrer)
"""

import os
import httpx
from mcp.server.fastmcp import FastMCP

RAILWAY_API_URL = "https://backboard.railway.app/graphql/v2"
RAILWAY_API_TOKEN = os.environ.get("RAILWAY_API_TOKEN", "")
RAILWAY_PROJECT_ID = os.environ.get("RAILWAY_PROJECT_ID", "")
RAILWAY_SERVICE_ID = os.environ.get("RAILWAY_SERVICE_ID", "")

mcp = FastMCP(
    "railway-observability",
    description="Read-only access to Railway deployment logs for production diagnostics",
)


def _headers() -> dict[str, str]:
    return {
        "Authorization": f"Bearer {RAILWAY_API_TOKEN}",
        "Content-Type": "application/json",
    }


def _check_config() -> str | None:
    """Retourne un message d'erreur si la configuration est incomplète."""
    missing = []
    if not RAILWAY_API_TOKEN:
        missing.append("RAILWAY_API_TOKEN")
    if not RAILWAY_PROJECT_ID:
        missing.append("RAILWAY_PROJECT_ID")
    if missing:
        return f"Missing environment variables: {', '.join(missing)}"
    return None


async def _graphql_query(query: str, variables: dict | None = None) -> dict:
    """Exécute une requête GraphQL Railway."""
    payload = {"query": query}
    if variables:
        payload["variables"] = variables

    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.post(
            RAILWAY_API_URL,
            headers=_headers(),
            json=payload,
        )
        if resp.status_code != 200:
            raise RuntimeError(f"Railway API error {resp.status_code}: {resp.text}")

        data = resp.json()
        if "errors" in data:
            error_msgs = "; ".join(e.get("message", "?") for e in data["errors"])
            raise RuntimeError(f"Railway GraphQL errors: {error_msgs}")

        return data.get("data", {})


@mcp.tool()
async def get_latest_deployments(
    limit: int = 5,
    service_id: str = "",
) -> str:
    """
    Récupère les derniers déploiements Railway du projet Facteur.

    Args:
        limit: Nombre de déploiements à retourner (1-20). Par défaut: 5
        service_id: ID du service Railway (optionnel, utilise RAILWAY_SERVICE_ID par défaut).

    Returns:
        Liste des déploiements avec statut, timestamp, commit SHA et durée.
    """
    err = _check_config()
    if err:
        return f"Configuration error: {err}"

    sid = service_id or RAILWAY_SERVICE_ID

    query = """
    query($projectId: String!, $limit: Int!) {
        deployments(
            input: {
                projectId: $projectId
            }
            first: $limit
        ) {
            edges {
                node {
                    id
                    status
                    createdAt
                    updatedAt
                    staticUrl
                    meta {
                        ... on DeploymentMeta {
                            commitHash
                            commitMessage
                            branch
                        }
                    }
                    service {
                        id
                        name
                    }
                }
            }
        }
    }
    """

    try:
        data = await _graphql_query(query, {
            "projectId": RAILWAY_PROJECT_ID,
            "limit": min(limit, 20),
        })
    except RuntimeError as e:
        return str(e)

    edges = data.get("deployments", {}).get("edges", [])
    if not edges:
        return "No deployments found."

    # Filter by service if specified
    if sid:
        edges = [
            e for e in edges
            if e.get("node", {}).get("service", {}).get("id") == sid
        ]

    if not edges:
        return f"No deployments found for service {sid}."

    lines = [f"Latest {len(edges)} deployment(s):\n"]
    for edge in edges:
        d = edge.get("node", {})
        meta = d.get("meta", {})
        service = d.get("service", {})
        status = d.get("status", "?")
        status_icon = {
            "SUCCESS": "OK",
            "FAILED": "FAILED",
            "BUILDING": "BUILDING",
            "DEPLOYING": "DEPLOYING",
            "CRASHED": "CRASHED",
            "REMOVED": "REMOVED",
        }.get(status, status)

        commit_hash = meta.get("commitHash", "?")[:7] if meta.get("commitHash") else "?"
        commit_msg = meta.get("commitMessage", "N/A")
        branch = meta.get("branch", "?")

        lines.append(
            f"- [{status_icon}] {service.get('name', '?')} — {d.get('createdAt', '?')}\n"
            f"  ID: {d.get('id', '?')}\n"
            f"  Branch: {branch} | Commit: {commit_hash}\n"
            f"  Message: {commit_msg}"
        )
    return "\n".join(lines)


@mcp.tool()
async def get_deployment_logs(
    deployment_id: str,
    limit: int = 100,
) -> str:
    """
    Récupère les logs applicatifs (runtime) d'un déploiement Railway.

    Args:
        deployment_id: L'ID du déploiement (obtenu via get_latest_deployments).
        limit: Nombre max de lignes de log (1-500). Par défaut: 100

    Returns:
        Logs applicatifs du déploiement (stdout/stderr), les plus récents en dernier.
    """
    err = _check_config()
    if err:
        return f"Configuration error: {err}"

    query = """
    query($deploymentId: String!, $limit: Int!) {
        deploymentLogs(deploymentId: $deploymentId, limit: $limit) {
            ... on Log {
                message
                timestamp
                severity
            }
        }
    }
    """

    try:
        data = await _graphql_query(query, {
            "deploymentId": deployment_id,
            "limit": min(limit, 500),
        })
    except RuntimeError as e:
        return str(e)

    logs = data.get("deploymentLogs", [])
    if not logs:
        return f"No logs found for deployment {deployment_id}."

    lines = [f"Deployment logs ({len(logs)} entries) for {deployment_id}:\n"]
    for log_entry in logs:
        ts = log_entry.get("timestamp", "")
        severity = log_entry.get("severity", "info")
        msg = log_entry.get("message", "")
        lines.append(f"[{ts}] [{severity}] {msg}")

    return "\n".join(lines)


@mcp.tool()
async def get_build_logs(
    deployment_id: str,
    limit: int = 200,
) -> str:
    """
    Récupère les logs de build (Docker build) d'un déploiement Railway.

    Args:
        deployment_id: L'ID du déploiement (obtenu via get_latest_deployments).
        limit: Nombre max de lignes de log (1-500). Par défaut: 200

    Returns:
        Logs de build du déploiement, utiles pour diagnostiquer les erreurs de build Docker.
    """
    err = _check_config()
    if err:
        return f"Configuration error: {err}"

    query = """
    query($deploymentId: String!, $limit: Int!) {
        buildLogs(deploymentId: $deploymentId, limit: $limit) {
            ... on Log {
                message
                timestamp
                severity
            }
        }
    }
    """

    try:
        data = await _graphql_query(query, {
            "deploymentId": deployment_id,
            "limit": min(limit, 500),
        })
    except RuntimeError as e:
        return str(e)

    logs = data.get("buildLogs", [])
    if not logs:
        return f"No build logs found for deployment {deployment_id}."

    lines = [f"Build logs ({len(logs)} entries) for {deployment_id}:\n"]
    for log_entry in logs:
        ts = log_entry.get("timestamp", "")
        msg = log_entry.get("message", "")
        lines.append(f"[{ts}] {msg}")

    return "\n".join(lines)


@mcp.tool()
async def get_service_status() -> str:
    """
    Récupère le statut actuel du service Facteur sur Railway.

    Returns:
        Informations sur le service : dernier déploiement, statut, URL.
    """
    # Delegate to get_latest_deployments with limit=1
    return await get_latest_deployments(limit=3)


if __name__ == "__main__":
    mcp.run()
