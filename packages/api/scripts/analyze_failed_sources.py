"""
Mission 2 — Analyse des failed RSS adds
Queries the failed_source_attempts table and categorizes URLs.

Usage:
  # Via Supabase PostgREST API (recommended):
  SUPABASE_URL=https://xxx.supabase.co SUPABASE_SERVICE_ROLE_KEY=xxx python analyze_failed_sources.py

  # Via direct DATABASE_URL:
  DATABASE_URL=postgresql://... python analyze_failed_sources.py
"""

import asyncio
import json
import os
import re
import sys
from collections import Counter
from datetime import datetime

import httpx


# ─── Platform Detection ───────────────────────────────────────

def classify_url(input_text: str) -> str:
    """Categorize a URL/input by platform."""
    text = input_text.lower().strip()

    if "youtube.com" in text or "youtu.be" in text:
        if "/watch?" in text:
            return "YouTube (video)"
        elif "/@" in text or "/c/" in text or "/channel/" in text:
            return "YouTube (channel)"
        elif "/playlist" in text:
            return "YouTube (playlist)"
        return "YouTube (other)"

    if "reddit.com" in text or "old.reddit.com" in text:
        if "/r/" in text:
            return "Reddit (subreddit)"
        elif "/user/" in text or "/u/" in text:
            return "Reddit (user)"
        return "Reddit (other)"

    if "substack.com" in text or ".substack." in text:
        return "Substack"

    if "medium.com" in text:
        return "Medium"

    if "twitter.com" in text or "x.com" in text:
        return "Twitter/X"

    if "instagram.com" in text:
        return "Instagram"

    if "tiktok.com" in text:
        return "TikTok"

    if "facebook.com" in text or "fb.com" in text:
        return "Facebook"

    if "linkedin.com" in text:
        return "LinkedIn"

    if "spotify.com" in text:
        return "Spotify"

    if "apple.com/podcast" in text or "podcasts.apple.com" in text:
        return "Apple Podcasts"

    if "soundcloud.com" in text:
        return "SoundCloud"

    if "twitch.tv" in text:
        return "Twitch"

    if "github.com" in text:
        return "GitHub"

    if "threads.net" in text:
        return "Threads"

    if "mastodon" in text or "fosstodon" in text:
        return "Mastodon"

    if "bluesky" in text or "bsky.app" in text:
        return "Bluesky"

    if "lemonde.fr" in text or "lefigaro.fr" in text or "liberation.fr" in text:
        return "French Press"

    # Check if it looks like a URL at all
    if re.match(r"^https?://", text) or re.match(r"^[\w\.-]+\.[a-z]{2,6}", text):
        return "Website (other)"

    return "Keyword/Malformed"


# ─── Supabase PostgREST Client ────────────────────────────────

async def query_supabase(supabase_url: str, service_key: str) -> list[dict]:
    """Fetch all failed_source_attempts via Supabase REST API."""
    url = f"{supabase_url}/rest/v1/failed_source_attempts"
    headers = {
        "apikey": service_key,
        "Authorization": f"Bearer {service_key}",
        "Content-Type": "application/json",
        "Prefer": "count=exact",
    }
    params = {
        "select": "id,user_id,input_text,input_type,endpoint,error_message,created_at",
        "order": "created_at.desc",
        "limit": "1000",
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.get(url, headers=headers, params=params)
        resp.raise_for_status()
        total = resp.headers.get("content-range", "unknown")
        data = resp.json()
        print(f"  Fetched {len(data)} records (total range: {total})")
        return data


# ─── Analysis ──────────────────────────────────────────────────

def analyze(records: list[dict]) -> str:
    """Analyze and produce the report."""
    if not records:
        return "No records found in failed_source_attempts table."

    lines = []
    lines.append(f"# Analyse des failed RSS adds — Mission 2\n")
    lines.append(f"**Date**: {datetime.now().strftime('%Y-%m-%d')}")
    lines.append(f"**Auteur**: Agent @dev (workspace Conductor)")
    lines.append(f"**Source**: Table `failed_source_attempts` (production Supabase)\n")
    lines.append("---\n")

    # 1. Overview
    lines.append("## 1. Vue d'ensemble\n")
    dates = [r["created_at"] for r in records if r.get("created_at")]
    if dates:
        lines.append(f"- **Total records**: {len(records)}")
        lines.append(f"- **Premiere entree**: {min(dates)[:10]}")
        lines.append(f"- **Derniere entree**: {max(dates)[:10]}")
    unique_users = len(set(r["user_id"] for r in records if r.get("user_id")))
    lines.append(f"- **Users uniques**: {unique_users}\n")

    # 2. Breakdown by input_type and endpoint
    lines.append("## 2. Breakdown par type et endpoint\n")
    lines.append("| input_type | endpoint | count |")
    lines.append("|------------|----------|-------|")
    type_endpoint = Counter((r.get("input_type", "?"), r.get("endpoint", "?")) for r in records)
    for (itype, endpoint), count in type_endpoint.most_common():
        lines.append(f"| {itype} | {endpoint} | {count} |")
    lines.append("")

    # 3. Platform categorization
    lines.append("## 3. Categorisation par plateforme\n")
    url_records = [r for r in records if r.get("input_type") == "url" or re.match(r"^https?://", r.get("input_text", ""))]
    platform_counter = Counter()
    platform_users = {}
    platform_examples = {}

    for r in records:
        platform = classify_url(r.get("input_text", ""))
        platform_counter[platform] += 1
        uid = r.get("user_id", "")
        if platform not in platform_users:
            platform_users[platform] = set()
        platform_users[platform].add(uid)
        if platform not in platform_examples:
            platform_examples[platform] = []
        if len(platform_examples[platform]) < 3:
            platform_examples[platform].append(r.get("input_text", "")[:80])

    total = sum(platform_counter.values())
    lines.append("| Plateforme | Count | % | Users uniques | Faisabilite | Exemples |")
    lines.append("|------------|-------|---|---------------|-------------|----------|")

    feasibility_map = {
        "YouTube (channel)": "Facile (API v3)",
        "YouTube (video)": "Facile (API v3)",
        "YouTube (playlist)": "Facile (API v3)",
        "YouTube (other)": "Moyen",
        "Reddit (subreddit)": "Facile (.rss suffix)",
        "Reddit (user)": "Facile (.rss suffix)",
        "Reddit (other)": "Moyen",
        "Substack": "Facile (/feed suffix)",
        "Medium": "Moyen (RSS parfois dispo)",
        "Twitter/X": "Difficile (API payante)",
        "Instagram": "Difficile (pas de RSS)",
        "TikTok": "Difficile (pas de RSS)",
        "Facebook": "Difficile (pas de RSS)",
        "LinkedIn": "Difficile (pas de RSS)",
        "Spotify": "Moyen (podcast RSS resolve)",
        "Apple Podcasts": "Facile (feed URL in page)",
        "SoundCloud": "Moyen",
        "Twitch": "Moyen (RSS dispo)",
        "GitHub": "Facile (releases/commits RSS)",
        "Threads": "Difficile (pas de RSS)",
        "Mastodon": "Facile (RSS natif)",
        "Bluesky": "Moyen",
        "French Press": "Facile (RSS natif)",
        "Website (other)": "Variable",
        "Keyword/Malformed": "N/A",
    }

    for platform, count in platform_counter.most_common():
        pct = f"{count/total*100:.1f}%"
        users = len(platform_users.get(platform, set()))
        feasibility = feasibility_map.get(platform, "Variable")
        examples = " / ".join(platform_examples.get(platform, [])[:2])
        lines.append(f"| {platform} | {count} | {pct} | {users} | {feasibility} | `{examples}` |")
    lines.append("")

    # 4. Top 20 failed URLs
    lines.append("## 4. Top 20 URLs echouees\n")
    url_counter = Counter(r.get("input_text", "") for r in records)
    lines.append("| # | URL | Tentatives | Plateforme |")
    lines.append("|---|-----|-----------|-----------|")
    for i, (url, count) in enumerate(url_counter.most_common(20), 1):
        platform = classify_url(url)
        lines.append(f"| {i} | `{url[:80]}` | {count} | {platform} |")
    lines.append("")

    # 5. Error patterns
    lines.append("## 5. Patterns d'erreur\n")
    error_counter = Counter()
    for r in records:
        msg = r.get("error_message", "") or ""
        # Normalize error messages
        if "YouTube handles are currently disabled" in msg:
            error_counter["YouTube explicitly disabled"] += 1
        elif "No RSS feed found" in msg:
            error_counter["No RSS feed found on page"] += 1
        elif "Could not access URL" in msg:
            error_counter["Could not access URL (network error)"] += 1
        elif "Unable to parse URL as RSS feed" in msg:
            error_counter["Unable to parse as RSS feed"] += 1
        elif msg:
            error_counter[msg[:100]] += 1
        else:
            error_counter["(no error message)"] += 1

    lines.append("| Erreur | Count | % |")
    lines.append("|--------|-------|---|")
    for error, count in error_counter.most_common():
        pct = f"{count/total*100:.1f}%"
        lines.append(f"| {error} | {count} | {pct} |")
    lines.append("")

    # 6. Recommendations
    lines.append("## 6. Recommandations\n")
    lines.append("### Par priorite (basee sur volume + faisabilite)\n")

    # Sort platforms by count, exclude keyword/malformed
    actionable = [(p, c) for p, c in platform_counter.most_common() if p != "Keyword/Malformed"]
    priority_map = {
        "Facile": "P0",
        "Moyen": "P1",
        "Difficile": "P2",
        "Variable": "P1",
        "N/A": "P3",
    }

    lines.append("| Priorite | Plateforme | Volume | Fix |")
    lines.append("|----------|-----------|--------|-----|")
    for platform, count in actionable:
        feasibility = feasibility_map.get(platform, "Variable")
        priority_key = feasibility.split(" ")[0] if feasibility else "Variable"
        priority = priority_map.get(priority_key, "P2")
        lines.append(f"| {priority} | {platform} | {count} | {feasibility} |")
    lines.append("")

    lines.append("---\n")
    lines.append("*Genere par Agent @dev — Mission 2 du brief \"Diagnostic RSS Sources\"*")

    return "\n".join(lines)


async def main():
    print("=" * 60)
    print("  Mission 2 — Analyse des failed RSS adds")
    print("=" * 60)

    supabase_url = os.environ.get("SUPABASE_URL")
    service_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    database_url = os.environ.get("DATABASE_URL")

    if supabase_url and service_key:
        print(f"\n  Mode: Supabase PostgREST API")
        print(f"  URL: {supabase_url[:40]}...")
        records = await query_supabase(supabase_url, service_key)
    elif database_url:
        print(f"\n  Mode: Direct DATABASE_URL")
        print("  ERROR: Direct DB mode requires sqlalchemy+psycopg. Use Supabase REST API instead.")
        print("  Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY environment variables.")
        sys.exit(1)
    else:
        print("\n  ERROR: No credentials found.")
        print("  Set either:")
        print("    SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY (recommended)")
        print("    or DATABASE_URL")
        sys.exit(1)

    # Analyze
    report = analyze(records)

    # Write report
    output_path = os.path.join(
        os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))),
        "docs", "maintenance", "diag-failed-source-analysis.md"
    )
    with open(output_path, "w") as f:
        f.write(report)
    print(f"\n  Report written to: {output_path}")

    # Also print to stdout
    print("\n" + "=" * 60)
    print(report)


if __name__ == "__main__":
    asyncio.run(main())
