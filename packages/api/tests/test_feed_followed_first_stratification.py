"""Unit tests for the followed-source stratification used by get_feed when
filtering by theme or topic. Verifies that articles from sources the user
follows are lifted above the rest while preserving in-group score order.
"""

from unittest.mock import Mock
from uuid import uuid4

from app.services.recommendation_service import stratify_followed_first


def _item(source_id, score):
    c = Mock()
    c.source_id = source_id
    return (c, score)


def test_empty_followed_returns_input_unchanged():
    followed = set()
    items = [_item(uuid4(), 90.0), _item(uuid4(), 80.0)]
    assert stratify_followed_first(items, followed) is items


def test_followed_lifted_to_front_preserves_inner_order():
    sid_followed = uuid4()
    sid_other_a = uuid4()
    sid_other_b = uuid4()
    items = [
        _item(sid_other_a, 95.0),  # non-followed but top score
        _item(sid_followed, 60.0),  # followed but lower score
        _item(sid_other_b, 80.0),
        _item(sid_followed, 50.0),  # second followed even lower
    ]
    result = stratify_followed_first(items, {sid_followed})
    assert [it[0].source_id for it in result] == [
        sid_followed,
        sid_followed,
        sid_other_a,
        sid_other_b,
    ]
    # Score order is preserved within each group (came in sorted by score).
    assert [it[1] for it in result] == [60.0, 50.0, 95.0, 80.0]


def test_all_followed_returns_input_order():
    sid_a = uuid4()
    sid_b = uuid4()
    items = [_item(sid_a, 70.0), _item(sid_b, 60.0)]
    result = stratify_followed_first(items, {sid_a, sid_b})
    assert result == items


def test_no_followed_present_returns_input_order():
    sid_followed = uuid4()
    sid_other = uuid4()
    items = [_item(sid_other, 70.0), _item(sid_other, 60.0)]
    result = stratify_followed_first(items, {sid_followed})
    assert result == items
