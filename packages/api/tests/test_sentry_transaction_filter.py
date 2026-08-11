"""Régression du filtre des spans de timeout de session dans Sentry."""

from app.sentry_filters import before_send_transaction


def test_sentry_transaction_keeps_business_spans_and_drops_session_timeout_spans():
    event = {
        "transaction": "app.routers.feed.get_personalized_feed",
        "spans": [
            {
                "op": "db.sql.query",
                "description": "SET LOCAL statement_timeout = 30000",
            },
            {
                "op": "db.sql.query",
                "description": "SET LOCAL idle_in_transaction_session_timeout = 10000",
            },
            {
                "op": "db.sql.query",
                "description": "SET LOCAL statement_timeout = 8000",
            },
            {"op": "db.sql.query", "description": "SELECT contents.* FROM contents"},
        ],
    }

    filtered = before_send_transaction(event, {})

    assert filtered["transaction"] == "app.routers.feed.get_personalized_feed"
    assert filtered["spans"] == [
        {"op": "db.sql.query", "description": "SELECT contents.* FROM contents"}
    ]


def test_sentry_transaction_keeps_non_timeout_set_local_span():
    event = {
        "spans": [
            {"op": "db.sql.query", "description": "SET LOCAL search_path = public"}
        ]
    }

    assert before_send_transaction(event, {})["spans"] == event["spans"]
