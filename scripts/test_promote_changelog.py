"""Tests pour scripts/promote_changelog.py."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from promote_changelog import promote


def _write(path: Path, payload: dict) -> None:
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def _read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def test_promote_moves_unreleased_to_released(tmp_path: Path) -> None:
    target = tmp_path / "changelog.json"
    _write(
        target,
        {
            "unreleased": [
                {"tag": "Perspectives", "summary": "Clustering plus pertinent."}
            ],
            "released": [
                {
                    "version": "1.0.0",
                    "date": "2026-04-01",
                    "entries": [{"tag": "Quoi de neuf", "summary": "Découvrez."}],
                }
            ],
        },
    )

    exit_code = promote(
        version="1.1.0", release_date="2026-06-09", changelog_path=target
    )

    assert exit_code == 0
    data = _read(target)
    assert data["unreleased"] == []
    assert data["released"][0] == {
        "version": "1.1.0",
        "date": "2026-06-09",
        "entries": [
            {"tag": "Perspectives", "summary": "Clustering plus pertinent."}
        ],
    }
    # Released ordering : nouveau en tête, anciens conservés.
    assert data["released"][1]["version"] == "1.0.0"


def test_promote_is_noop_when_unreleased_empty(tmp_path: Path) -> None:
    target = tmp_path / "changelog.json"
    payload = {
        "unreleased": [],
        "released": [
            {
                "version": "1.0.0",
                "date": "2026-04-01",
                "entries": [{"tag": "X", "summary": "Y"}],
            }
        ],
    }
    _write(target, payload)

    exit_code = promote(
        version="1.1.0", release_date="2026-06-09", changelog_path=target
    )

    assert exit_code == 0
    assert _read(target) == payload  # inchangé


def test_promote_refuses_duplicate_version(tmp_path: Path) -> None:
    target = tmp_path / "changelog.json"
    _write(
        target,
        {
            "unreleased": [{"tag": "X", "summary": "Y"}],
            "released": [
                {
                    "version": "1.1.0",
                    "date": "2026-05-01",
                    "entries": [{"tag": "Z", "summary": "W"}],
                }
            ],
        },
    )

    exit_code = promote(
        version="1.1.0", release_date="2026-06-09", changelog_path=target
    )

    assert exit_code == 1
    data = _read(target)
    assert data["unreleased"] == [{"tag": "X", "summary": "Y"}]  # pas touché


def test_promote_outputs_trailing_newline(tmp_path: Path) -> None:
    target = tmp_path / "changelog.json"
    _write(
        target,
        {
            "unreleased": [{"tag": "X", "summary": "Y"}],
            "released": [],
        },
    )

    promote(version="1.0.0", release_date="2026-06-09", changelog_path=target)

    raw = target.read_text(encoding="utf-8")
    assert raw.endswith("\n")
    assert "  " in raw  # indent 2


def test_promote_errors_when_file_missing(tmp_path: Path) -> None:
    missing = tmp_path / "absent.json"
    exit_code = promote(
        version="1.0.0", release_date="2026-06-09", changelog_path=missing
    )
    assert exit_code == 2
