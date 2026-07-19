"""Tests for the rescue classification core (Story 12.2, T2)."""

from datetime import UTC, datetime, timedelta

import pytest

from app.services.rescue import (
    FIXED_SINCE,
    FOUND_BUT_ABANDONED,
    INVALID,
    NO_FEED,
    RESOLVABLE_RSS,
    Signal,
    classify_all,
    classify_signal,
    infer_abandons,
    is_invalid_input,
    is_url_like,
    merge_signal,
    resolve_target,
    signal_key,
    summarize,
)


def _sig(text, kind, **kw):
    return Signal(key=signal_key(text), input_text=text, kind=kind, **kw)


def test_is_url_like():
    assert is_url_like("https://usine-digitale.fr/rss")
    assert is_url_like("monpetithoublon.com")
    assert is_url_like("autobrasseur.fr/feed")
    assert not is_url_like("mediapart")
    assert not is_url_like("r/ai")


def test_is_invalid_input_short_tokens():
    assert is_invalid_input("ai")
    assert is_invalid_input("vu")
    assert not is_invalid_input("esa")  # 3 chars → not invalid
    assert not is_invalid_input("mediapart")


def test_signal_key_strips_tracking_and_dedupes():
    # betterclinicianproject class: polluted URL collapses to the clean key.
    k1 = signal_key("https://betterclinicianproject.com/?utm_source=x&fbclid=y")
    k2 = signal_key("betterclinicianproject.com")
    assert k1 == k2 == "betterclinicianproject.com"


def test_url_resolvable_vs_no_feed():
    # monpetithoublon / autobrasseur → resolvable via T1a WP curl-cffi.
    assert classify_signal(_sig("monpetithoublon.com", "url"), True) == RESOLVABLE_RSS
    # usine-digitale (DataDome) stays no_feed.
    assert classify_signal(_sig("usine-digitale.fr", "url"), False) == NO_FEED


def test_youtube_keyword_is_fixed_since():
    # The #939 rafale: youtube-filtered zero-result searches.
    assert (
        classify_signal(_sig("micode", "keyword", content_type="youtube"), None)
        == FIXED_SINCE
    )


def test_reddit_keyword_resolution():
    assert classify_signal(_sig("r/ai", "keyword"), True) == RESOLVABLE_RSS
    assert classify_signal(_sig("r/deadsub", "keyword"), False) == NO_FEED


def test_found_but_abandoned_keyword():
    sig = _sig("liberation", "keyword", max_result_count=3, abandoned=True)
    assert classify_signal(sig, None) == FOUND_BUT_ABANDONED


def test_invalid_keyword():
    assert classify_signal(_sig("ai", "keyword"), None) == INVALID


def test_resolve_target_reddit_and_url():
    assert resolve_target(_sig("r/worldnews", "keyword")) == (
        "https://www.reddit.com/r/worldnews/.rss"
    )
    assert resolve_target(_sig("autobrasseur.fr", "url")) == "https://autobrasseur.fr"
    # A plain keyword is not resolvable offline.
    assert resolve_target(_sig("mediapart", "keyword")) is None


def test_merge_signal_folds_duplicates():
    signals: dict = {}
    merge_signal(signals, input_text="usine-digitale.fr", kind="url", user_id="u1")
    merge_signal(
        signals,
        input_text="https://usine-digitale.fr/",
        kind="url",
        result_count=0,
        user_id="u2",
    )
    assert len(signals) == 1
    sig = next(iter(signals.values()))
    assert sig.occurrences == 2
    assert sig.user_ids == {"u1", "u2"}


@pytest.mark.asyncio
async def test_classify_all_and_summarize():
    signals = [
        _sig("usine-digitale.fr", "url"),
        _sig("monpetithoublon.com", "url"),
        _sig("micode", "keyword", content_type="youtube"),
        _sig("ai", "keyword"),
    ]

    async def resolver(url: str) -> bool:
        return "monpetithoublon" in url  # only this one resolves

    classified = await classify_all(signals, resolver)
    cats = {row["input_text"]: row["category"] for row in classified}
    assert cats["usine-digitale.fr"] == NO_FEED
    assert cats["monpetithoublon.com"] == RESOLVABLE_RSS
    assert cats["micode"] == FIXED_SINCE
    assert cats["ai"] == INVALID

    summary = summarize(classified)
    assert summary["by_category"][NO_FEED] == 1
    assert summary["no_feed_hosts"] == ["usine-digitale.fr"]
    assert summary["no_feed_host_count"] == 1


def test_infer_abandons():
    now = datetime(2026, 7, 1, 12, 0, tzinfo=UTC)
    result_logs = [
        {"user_id": "u1", "created_at": now, "query_normalized": "mediapart"},
        {"user_id": "u2", "created_at": now, "query_normalized": "socialter"},
    ]
    # u1 added a source right after the search → not abandoned; u2 never added.
    adds = [{"user_id": "u1", "added_at": now + timedelta(minutes=5)}]
    inferred = infer_abandons(result_logs, adds)
    assert len(inferred) == 1
    assert inferred[0]["user_id"] == "u2"
