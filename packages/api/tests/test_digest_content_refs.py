"""Tests for digest_content_refs.extract_content_ids.

These are the guardrail: cleanup workers and diag tools rely on this
extractor to know which Content rows are still referenced by live
digests. Any change to the persisted JSONB layouts must be reflected
here or the RSS cleanup will start deleting referenced articles again.
"""

from uuid import uuid4

from app.services.digest_content_refs import extract_content_ids


def test_flat_v1_list_layout():
    a, b = uuid4(), uuid4()
    items = [
        {"content_id": str(a), "rank": 1},
        {"content_id": str(b), "rank": 2},
    ]
    assert extract_content_ids(items, "flat_v1") == {a, b}


def test_flat_v1_is_default_when_format_version_none():
    a = uuid4()
    assert extract_content_ids([{"content_id": str(a)}], None) == {a}


def test_topics_v1_walks_nested_articles():
    a, b, c = uuid4(), uuid4(), uuid4()
    items = {
        "format": "topics_v1",
        "topics": [
            {"topic_id": "t1", "articles": [{"content_id": str(a)}]},
            {
                "topic_id": "t2",
                "articles": [{"content_id": str(b)}, {"content_id": str(c)}],
            },
        ],
    }
    assert extract_content_ids(items, "topics_v1") == {a, b, c}


def test_editorial_v1_walks_all_slots():
    actu, extra, deep, pep, cdc, decalee = (
        uuid4(),
        uuid4(),
        uuid4(),
        uuid4(),
        uuid4(),
        uuid4(),
    )
    items = {
        "format_version": "editorial_v1",
        "subjects": [
            {
                "actu_article": {"content_id": str(actu)},
                "extra_actu_articles": [{"content_id": str(extra)}],
                "deep_article": {"content_id": str(deep)},
            }
        ],
        "pepite": {"content_id": str(pep)},
        "coup_de_coeur": {"content_id": str(cdc)},
        "actu_decalee": {"content_id": str(decalee)},
    }
    assert extract_content_ids(items, "editorial_v1") == {
        actu,
        extra,
        deep,
        pep,
        cdc,
        decalee,
    }


def test_editorial_v1_tolerates_missing_subjects():
    pep = uuid4()
    items = {"pepite": {"content_id": str(pep)}}
    assert extract_content_ids(items, "editorial_v1") == {pep}


def test_editorial_v1_tolerates_null_slots():
    """Pydantic serialization can produce explicit nulls for absent slots."""
    items = {
        "subjects": [
            {
                "actu_article": None,
                "extra_actu_articles": [],
                "deep_article": None,
            }
        ],
        "pepite": None,
        "coup_de_coeur": None,
        "actu_decalee": None,
    }
    assert extract_content_ids(items, "editorial_v1") == set()


def test_malformed_uuid_is_skipped_not_raised():
    good = uuid4()
    items = [{"content_id": "not-a-uuid"}, {"content_id": str(good)}]
    assert extract_content_ids(items, "flat_v1") == {good}


def test_missing_content_id_key_is_skipped():
    items = [{"rank": 1}, {"content_id": str(uuid4())}]
    assert len(extract_content_ids(items, "flat_v1")) == 1


def test_none_items_returns_empty_set():
    assert extract_content_ids(None, "flat_v1") == set()
    assert extract_content_ids(None, "editorial_v1") == set()


def test_wrong_layout_for_format_falls_back_to_flat_walker():
    """editorial_v1 metadata + list items: graceful degradation to flat walk.

    If the persisted layout ever disagrees with the declared format, we'd
    rather still collect whatever ids we can find than silently return
    nothing and then delete the referenced Content rows.
    """
    cid = uuid4()
    assert extract_content_ids([{"content_id": str(cid)}], "editorial_v1") == {cid}
