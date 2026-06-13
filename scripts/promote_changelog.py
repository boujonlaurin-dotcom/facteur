#!/usr/bin/env python3
"""Déplace `unreleased` → `released[0]` dans apps/mobile/assets/changelog.json.

Usage :
    python scripts/promote_changelog.py --version 1.2.0 [--date 2026-06-09]

À appeler au moment du bump de version (manuel ou via futur weekly-release.yml).
Stdlib uniquement — pas de dépendance externe.
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import date as _date
from pathlib import Path

DEFAULT_CHANGELOG_PATH = (
    Path(__file__).resolve().parent.parent
    / "apps"
    / "mobile"
    / "assets"
    / "changelog.json"
)


def promote(
    *,
    version: str,
    release_date: str,
    changelog_path: Path = DEFAULT_CHANGELOG_PATH,
) -> int:
    if not changelog_path.is_file():
        print(f"ERROR: changelog introuvable : {changelog_path}", file=sys.stderr)
        return 2

    data = json.loads(changelog_path.read_text(encoding="utf-8"))
    unreleased: list[dict] = data.get("unreleased", [])
    released: list[dict] = data.get("released", [])

    if not unreleased:
        print(f"unreleased vide — no-op (version {version}).")
        return 0

    if any(r.get("version") == version for r in released):
        print(
            f"ERROR: version {version} déjà présente dans `released`. "
            "Utilise une version différente ou retire l'entrée existante.",
            file=sys.stderr,
        )
        return 1

    new_release = {
        "version": version,
        "date": release_date,
        "entries": unreleased,
    }
    data["released"] = [new_release, *released]
    data["unreleased"] = []

    changelog_path.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"OK: {len(unreleased)} entrée(s) promue(s) vers {version}.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True, help="ex: 1.2.0")
    parser.add_argument(
        "--date",
        default=_date.today().isoformat(),
        help="ex: 2026-06-09 (défaut: today)",
    )
    parser.add_argument(
        "--path",
        type=Path,
        default=DEFAULT_CHANGELOG_PATH,
        help="chemin vers changelog.json (défaut: apps/mobile/assets/changelog.json)",
    )
    args = parser.parse_args()
    return promote(
        version=args.version, release_date=args.date, changelog_path=args.path
    )


if __name__ == "__main__":
    sys.exit(main())
