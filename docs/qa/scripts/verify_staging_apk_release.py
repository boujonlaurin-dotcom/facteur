#!/usr/bin/env python3
"""Pre-production check for the staging Android APK.

This script verifies the release gate described in
``docs/maintenance/maintenance-restore-staging-env.md``:

* the latest/main APK build is compiled against the staging backend;
* staging and production health endpoints report the expected environment;
* the perspectives endpoint used by "Couverture médiatique" and "Pas de recul"
  behaves consistently between staging and production for representative
  content IDs;
* the precomputed ``content_deep_recommendations`` rows explain empty
  "Pas de recul" cards when database access is available.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
from dataclasses import dataclass
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


DEFAULT_STAGING_API = "https://api-staging-40d3.up.railway.app/api"
DEFAULT_PROD_API = "https://facteur-production.up.railway.app/api"
EXPECTED_STAGING_HOST = "api-staging-40d3.up.railway.app"
EXPECTED_PROD_HOST = "facteur-production.up.railway.app"


@dataclass
class Check:
    ok: bool
    label: str
    detail: str = ""
    warning: bool = False


def emit(check: Check) -> None:
    if check.ok:
        prefix = "WARN" if check.warning else "PASS"
    else:
        prefix = "FAIL"
    suffix = f" - {check.detail}" if check.detail else ""
    print(f"[{prefix}] {check.label}{suffix}")


def normalize_api_base(value: str) -> str:
    return value.rstrip("/")


def auth_header(token: str | None) -> dict[str, str]:
    if not token:
        return {}
    token = token.strip()
    if not token:
        return {}
    if not token.lower().startswith("bearer "):
        token = f"Bearer {token}"
    return {"Authorization": token}


def http_json(
    url: str,
    *,
    headers: dict[str, str] | None = None,
    timeout: int = 30,
) -> tuple[int, dict[str, Any] | list[Any] | None, str]:
    req = Request(url, headers={"Accept": "application/json", **(headers or {})})
    try:
        with urlopen(req, timeout=timeout) as response:
            raw = response.read().decode("utf-8", errors="replace")
            data = json.loads(raw) if raw else None
            return response.status, data, raw
    except HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        try:
            data = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            data = None
        return exc.code, data, raw
    except (TimeoutError, URLError) as exc:
        return 0, None, str(exc)


def run_cmd(args: list[str], timeout: int = 30) -> tuple[int, str, str]:
    try:
        proc = subprocess.run(
            args,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return proc.returncode, proc.stdout, proc.stderr
    except (FileNotFoundError, subprocess.TimeoutExpired) as exc:
        return 127, "", str(exc)


def check_health(api_base: str, expected_env: str) -> list[Check]:
    checks: list[Check] = []
    for path, expected_status in (("/health", "ok"), ("/health/ready", "ready")):
        status, data, raw = http_json(f"{api_base}{path}", timeout=15)
        label = f"{api_base}{path}"
        if status != 200 or not isinstance(data, dict):
            checks.append(Check(False, label, f"HTTP {status}: {raw[:160]}"))
            continue
        got_env = data.get("environment")
        got_status = data.get("status")
        checks.append(
            Check(
                status == 200
                and got_env == expected_env
                and got_status == expected_status,
                label,
                f"status={got_status}, environment={got_env}",
            )
        )
    return checks


def latest_build_apk_run(repo: str, branch: str) -> dict[str, Any] | None:
    code, out, err = run_cmd(
        [
            "gh",
            "run",
            "list",
            "--workflow=build-apk.yml",
            "--branch",
            branch,
            "--limit",
            "1",
            "--json",
            "databaseId,headSha,displayTitle,status,conclusion,createdAt,url",
            "--repo",
            repo,
        ],
        timeout=30,
    )
    if code != 0:
        print(f"[WARN] GitHub run lookup skipped - {err.strip() or out.strip()}")
        return None
    runs = json.loads(out or "[]")
    return runs[0] if runs else None


def check_github_build(
    *,
    repo: str,
    branch: str,
    expected_tag: str | None,
    expected_sha: str | None,
) -> list[Check]:
    run = latest_build_apk_run(repo, branch)
    if not run:
        return [Check(True, "GitHub APK build lookup", "not available", warning=True)]

    run_id = str(run["databaseId"])
    checks = [
        Check(
            run.get("status") == "completed" and run.get("conclusion") == "success",
            "Latest build-apk.yml run",
            f"id={run_id}, sha={run.get('headSha', '')[:8]}, conclusion={run.get('conclusion')}",
        )
    ]
    if expected_sha:
        checks.append(
            Check(
                str(run.get("headSha", "")).startswith(expected_sha),
                "APK build commit matches expected SHA",
                f"expected={expected_sha}, actual={run.get('headSha')}",
            )
        )

    code, log, err = run_cmd(
        ["gh", "run", "view", run_id, "--log", "--repo", repo],
        timeout=60,
    )
    if code != 0:
        checks.append(
            Check(True, "GitHub APK build log", err.strip() or "not available", warning=True)
        )
        return checks

    required_patterns = {
        "APK build uses staging API": rf"API_BASE_URL=https://{re.escape(EXPECTED_STAGING_HOST)}/api",
        "APK build does not use production API": rf"API_BASE_URL=https://{re.escape(EXPECTED_PROD_HOST)}/api",
        "APK build uses staging Sentry environment": r"SENTRY_ENVIRONMENT=staging",
        "APK build uses beta update channel": r"UPDATE_CHANNEL=beta",
    }
    for label, pattern in required_patterns.items():
        found = re.search(pattern, log) is not None
        if "does not use" in label:
            checks.append(Check(not found, label))
        else:
            checks.append(Check(found, label))

    if expected_tag:
        checks.append(
            Check(
                f"APP_RELEASE_TAG={expected_tag}" in log,
                "APK build release tag matches expected tag",
                f"expected={expected_tag}",
            )
        )

    return checks


def collect_content_ids_from_digest(
    api_base: str,
    token: str,
    limit: int,
) -> list[str]:
    status, data, raw = http_json(
        f"{api_base}/digest",
        headers=auth_header(token),
        timeout=30,
    )
    if status != 200 or data is None:
        print(f"[WARN] Digest discovery skipped - HTTP {status}: {raw[:180]}")
        return []

    ids: list[str] = []
    seen: set[str] = set()
    uuid_re = re.compile(
        r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
    )

    content_markers = {
        "title",
        "url",
        "source",
        "source_name",
        "content_type",
        "published_at",
        "representative_id",
        "content_id",
    }

    def add_id(value: Any) -> None:
        if isinstance(value, str) and uuid_re.match(value) and value not in seen:
            seen.add(value)
            ids.append(value)

    def visit(node: Any, key: str | None = None) -> None:
        if len(ids) >= limit:
            return
        if isinstance(node, dict):
            keys = {str(k).lower() for k in node}
            if "content_id" in keys:
                add_id(node.get("content_id"))
            if "representative_id" in keys:
                add_id(node.get("representative_id"))
            if "id" in keys and keys.intersection(content_markers):
                add_id(node.get("id"))
            for k, v in node.items():
                visit(v, str(k))
        elif isinstance(node, list):
            for item in node:
                visit(item, key)
        elif isinstance(node, str):
            key_l = (key or "").lower()
            if key_l in {"content_id", "representative_id"}:
                add_id(node)

    visit(data)
    return ids[:limit]


def perspective_summary(body: dict[str, Any] | None) -> dict[str, Any]:
    if not isinstance(body, dict):
        return {
            "perspectives_count": None,
            "should_display": None,
            "partial": None,
            "deep_recommendation": None,
            "deep_pending": None,
            "timings_ms": None,
        }
    perspectives = body.get("perspectives")
    return {
        "perspectives_count": len(perspectives) if isinstance(perspectives, list) else None,
        "should_display": body.get("should_display"),
        "partial": body.get("partial"),
        "deep_recommendation": body.get("deep_recommendation") is not None,
        "deep_pending": body.get("deep_pending"),
        "timings_ms": body.get("timings_ms"),
    }


def compare_perspectives(
    *,
    staging_api: str,
    prod_api: str,
    token: str,
    content_ids: list[str],
) -> tuple[list[Check], dict[str, dict[str, Any]]]:
    checks: list[Check] = []
    summaries: dict[str, dict[str, Any]] = {}
    headers = auth_header(token)

    for content_id in content_ids:
        row: dict[str, Any] = {}
        for name, api in (("staging", staging_api), ("production", prod_api)):
            status, data, raw = http_json(
                f"{api}/contents/{content_id}/perspectives",
                headers=headers,
                timeout=45,
            )
            summary = perspective_summary(data if isinstance(data, dict) else None)
            summary["http_status"] = status
            if status != 200:
                summary["error"] = raw[:220]
            row[name] = summary
        summaries[content_id] = row

        st = row["staging"]
        pr = row["production"]
        st_count = st["perspectives_count"]
        pr_count = pr["perspectives_count"]

        checks.append(
            Check(
                st["http_status"] == 200,
                f"Staging perspectives {content_id}",
                json.dumps(st, ensure_ascii=False, default=str),
            )
        )
        checks.append(
            Check(
                pr["http_status"] == 200,
                f"Production perspectives {content_id}",
                json.dumps(pr, ensure_ascii=False, default=str),
            )
        )
        if st["http_status"] == 200 and pr["http_status"] == 200:
            checks.append(
                Check(
                    not (st_count == 0 and isinstance(pr_count, int) and pr_count > 0),
                    f"Staging/prod perspectives parity {content_id}",
                    f"staging={st_count}, production={pr_count}",
                )
            )
            checks.append(
                Check(
                    st["partial"] is not True,
                    f"Staging response is not stuck partial {content_id}",
                    f"partial={st['partial']}",
                    warning=st["partial"] is True,
                )
            )

    return checks, summaries


def db_deep_reco_checks(content_ids: list[str]) -> list[Check]:
    database_url = os.environ.get("DATABASE_URL", "").strip()
    if not database_url:
        return [
            Check(
                True,
                "DB deep recommendation lookup",
                "DATABASE_URL not set; skipped",
                warning=True,
            )
        ]

    try:
        import psycopg
    except ImportError:
        return [
            Check(
                True,
                "DB deep recommendation lookup",
                "psycopg not importable; skipped",
                warning=True,
            )
        ]

    sync_url = (
        database_url.replace("+psycopg", "")
        .replace("+asyncpg", "")
        .replace("postgresql://", "postgres://", 1)
    )
    placeholders = ",".join(["%s"] * len(content_ids))
    sql = f"""
        SELECT
            content_id::text,
            matched_content_id::text,
            computed_at
        FROM content_deep_recommendations
        WHERE content_id::text IN ({placeholders})
    """
    try:
        with psycopg.connect(sync_url) as conn:
            with conn.cursor() as cur:
                cur.execute(sql, content_ids)
                rows = {r[0]: {"matched_content_id": r[1], "computed_at": r[2]} for r in cur.fetchall()}
    except Exception as exc:
        return [Check(False, "DB deep recommendation lookup", str(exc))]

    checks: list[Check] = []
    for content_id in content_ids:
        row = rows.get(content_id)
        if row is None:
            checks.append(
                Check(
                    False,
                    f"Deep recommendation precompute row {content_id}",
                    "missing row",
                )
            )
        elif row["matched_content_id"] is None:
            checks.append(
                Check(
                    True,
                    f"Deep recommendation precompute row {content_id}",
                    "sentinel row: computed with no relevant match",
                    warning=True,
                )
            )
        else:
            checks.append(
                Check(
                    True,
                    f"Deep recommendation precompute row {content_id}",
                    f"matched_content_id={row['matched_content_id']}",
                )
            )
    return checks


def parse_content_ids(raw_values: list[str]) -> list[str]:
    ids: list[str] = []
    for raw in raw_values:
        for part in re.split(r"[\s,]+", raw.strip()):
            if part and part not in ids:
                ids.append(part)
    return ids


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", "boujonlaurin-dotcom/facteur"))
    parser.add_argument("--branch", default=os.environ.get("APK_BRANCH", "main"))
    parser.add_argument("--expected-tag", default=os.environ.get("EXPECTED_APK_TAG", "beta-20260618-0932"))
    parser.add_argument("--expected-sha", default=os.environ.get("EXPECTED_APK_SHA", "e9c56703"))
    parser.add_argument("--staging-api", default=os.environ.get("STAGING_API_BASE_URL", DEFAULT_STAGING_API))
    parser.add_argument("--prod-api", default=os.environ.get("PROD_API_BASE_URL", DEFAULT_PROD_API))
    parser.add_argument("--token", default=os.environ.get("FACTEUR_AUTH_TOKEN") or os.environ.get("FACTEUR_TEST_TOKEN"))
    parser.add_argument("--content-id", action="append", default=[])
    parser.add_argument("--content-ids", default=os.environ.get("CONTENT_IDS", ""))
    parser.add_argument("--limit", type=int, default=int(os.environ.get("CONTENT_LIMIT", "10")))
    parser.add_argument(
        "--skip-github",
        action="store_true",
        default=os.environ.get("SKIP_GITHUB_CHECK", "0") == "1",
    )
    args = parser.parse_args()

    staging_api = normalize_api_base(args.staging_api)
    prod_api = normalize_api_base(args.prod_api)
    checks: list[Check] = []

    print("== Facteur staging APK pre-production verification ==")
    print(f"staging_api={staging_api}")
    print(f"prod_api={prod_api}")
    print(f"expected_tag={args.expected_tag}")
    print(f"expected_sha={args.expected_sha}")
    print("")

    if not args.skip_github:
        checks.extend(
            check_github_build(
                repo=args.repo,
                branch=args.branch,
                expected_tag=args.expected_tag,
                expected_sha=args.expected_sha,
            )
        )

    checks.extend(check_health(staging_api, "staging"))
    checks.extend(check_health(prod_api, "production"))

    content_ids = parse_content_ids(args.content_id + [args.content_ids])
    if not content_ids and args.token:
        content_ids = collect_content_ids_from_digest(staging_api, args.token, args.limit)
        if content_ids:
            checks.append(
                Check(True, "Content IDs discovered from staging digest", ", ".join(content_ids))
            )

    if not args.token:
        checks.append(
            Check(
                False,
                "Perspectives comparison",
                "FACTEUR_AUTH_TOKEN or FACTEUR_TEST_TOKEN is required",
            )
        )
    elif not content_ids:
        checks.append(
            Check(
                False,
                "Perspectives comparison",
                "provide CONTENT_IDS or use a token that can read /api/digest",
            )
        )
    else:
        perspective_checks, summaries = compare_perspectives(
            staging_api=staging_api,
            prod_api=prod_api,
            token=args.token,
            content_ids=content_ids[: args.limit],
        )
        checks.extend(perspective_checks)
        checks.extend(db_deep_reco_checks(content_ids[: args.limit]))
        print("")
        print("Perspective summary:")
        print(json.dumps(summaries, ensure_ascii=False, indent=2, default=str))

    print("")
    print("Checks:")
    for check in checks:
        emit(check)

    hard_failures = [c for c in checks if not c.ok]
    warnings = [c for c in checks if c.ok and c.warning]
    print("")
    print(f"Result: {len(checks) - len(hard_failures)} pass/warn, {len(hard_failures)} fail")
    if warnings:
        print(f"Warnings: {len(warnings)}")

    if hard_failures:
        print("NO-GO: staging APK release verification failed.")
        return 1
    print("GO: staging APK release verification passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
