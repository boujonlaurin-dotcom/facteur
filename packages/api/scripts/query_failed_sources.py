"""Lightweight script to query failed_source_attempts via DATABASE_URL."""
import json
import os
import re
import sys
from collections import Counter

import psycopg


def classify_url(text: str) -> str:
    text = text.lower().strip()
    if "youtube.com" in text or "youtu.be" in text:
        if "/watch?" in text: return "YouTube (video)"
        elif "/@" in text or "/c/" in text or "/channel/" in text: return "YouTube (channel)"
        elif "/playlist" in text: return "YouTube (playlist)"
        return "YouTube (other)"
    if "reddit.com" in text:
        if "/r/" in text: return "Reddit (subreddit)"
        elif "/user/" in text or "/u/" in text: return "Reddit (user)"
        return "Reddit (other)"
    if "substack.com" in text or ".substack." in text: return "Substack"
    if "medium.com" in text: return "Medium"
    if "twitter.com" in text or "x.com" in text: return "Twitter/X"
    if "instagram.com" in text: return "Instagram"
    if "tiktok.com" in text: return "TikTok"
    if "facebook.com" in text or "fb.com" in text: return "Facebook"
    if "linkedin.com" in text: return "LinkedIn"
    if "spotify.com" in text: return "Spotify"
    if "podcasts.apple.com" in text: return "Apple Podcasts"
    if "soundcloud.com" in text: return "SoundCloud"
    if "twitch.tv" in text: return "Twitch"
    if "github.com" in text: return "GitHub"
    if "threads.net" in text: return "Threads"
    if "mastodon" in text or "fosstodon" in text: return "Mastodon"
    if "bluesky" in text or "bsky.app" in text: return "Bluesky"
    if re.match(r"^https?://", text) or re.match(r"^[\w\.-]+\.[a-z]{2,6}", text):
        return "Website (other)"
    return "Keyword/Malformed"


def main():
    db_url = os.environ.get("DATABASE_URL")
    if not db_url:
        print("ERROR: DATABASE_URL not set")
        sys.exit(1)

    # Fix driver prefix for psycopg
    if db_url.startswith("postgres://"):
        db_url = db_url.replace("postgres://", "postgresql://", 1)

    print(f"Connecting to database...")
    conn = psycopg.connect(db_url)
    cur = conn.cursor()

    # Query all records
    cur.execute("""
        SELECT id, user_id, input_text, input_type, endpoint, error_message, created_at
        FROM failed_source_attempts
        ORDER BY created_at DESC
    """)
    columns = [desc[0] for desc in cur.description]
    rows = [dict(zip(columns, row)) for row in cur.fetchall()]
    print(f"Fetched {len(rows)} records\n")

    if not rows:
        print("No records found.")
        conn.close()
        return

    # Convert to JSON-serializable
    for r in rows:
        for k, v in r.items():
            if hasattr(v, 'isoformat'):
                r[k] = v.isoformat()
            elif hasattr(v, 'hex'):  # UUID
                r[k] = str(v)

    # Quick summary
    print(f"{'='*60}")
    print(f"  OVERVIEW")
    print(f"{'='*60}")
    print(f"  Total records: {len(rows)}")
    print(f"  Earliest: {min(r['created_at'] for r in rows)[:10]}")
    print(f"  Latest: {max(r['created_at'] for r in rows)[:10]}")
    print(f"  Unique users: {len(set(r['user_id'] for r in rows))}")

    # Type/endpoint breakdown
    print(f"\n  BY TYPE/ENDPOINT:")
    te = Counter((r["input_type"], r["endpoint"]) for r in rows)
    for (t, e), c in te.most_common():
        print(f"    {t}/{e}: {c}")

    # Platform categorization
    print(f"\n  BY PLATFORM:")
    pc = Counter(classify_url(r.get("input_text", "")) for r in rows)
    platform_users = {}
    for r in rows:
        p = classify_url(r.get("input_text", ""))
        if p not in platform_users:
            platform_users[p] = set()
        platform_users[p].add(r["user_id"])

    for p, c in pc.most_common():
        pct = c / len(rows) * 100
        users = len(platform_users.get(p, set()))
        print(f"    {p}: {c} ({pct:.1f}%) [{users} users]")

    # Top URLs
    print(f"\n  TOP 20 URLS:")
    uc = Counter(r.get("input_text", "") for r in rows)
    for i, (url, c) in enumerate(uc.most_common(20), 1):
        platform = classify_url(url)
        print(f"    {i:2}. [{c}x] {url[:70]} ({platform})")

    # Error patterns
    print(f"\n  ERROR PATTERNS:")
    ec = Counter()
    for r in rows:
        msg = r.get("error_message", "") or ""
        if "YouTube handles are currently disabled" in msg:
            ec["YouTube explicitly disabled"] += 1
        elif "No RSS feed found" in msg:
            ec["No RSS feed found"] += 1
        elif "Could not access URL" in msg:
            ec["Could not access URL"] += 1
        elif "Unable to parse URL" in msg:
            ec["Unable to parse as RSS"] += 1
        elif msg:
            ec[msg[:80]] += 1
        else:
            ec["(no error message)"] += 1
    for err, c in ec.most_common():
        print(f"    {c:3}x  {err}")

    # Save raw JSON for report generation
    output = {"total": len(rows), "records": rows}
    raw_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "failed_sources_raw.json")
    with open(raw_path, "w") as f:
        json.dump(output, f, indent=2, default=str)
    print(f"\n  Raw data saved to: {raw_path}")

    conn.close()
    print(f"\nDone.")


if __name__ == "__main__":
    main()
