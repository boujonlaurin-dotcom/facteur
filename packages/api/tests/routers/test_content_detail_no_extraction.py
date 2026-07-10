from uuid import uuid4

import pytest

from app.routers import contents as contents_router


@pytest.mark.asyncio
async def test_content_detail_returns_stored_rss_content_without_db_mutation(
    monkeypatch,
):
    content_id = uuid4()
    user_id = uuid4()
    stored = {
        "id": content_id,
        "content_type": "article",
        "html_content": "<p>Contenu RSS</p>",
        "content_quality": "partial",
    }

    class FakeService:
        def __init__(self, db):
            self.db = db

        async def get_content_detail(self, requested_id, requested_user_id):
            assert requested_id == content_id
            assert requested_user_id == user_id
            return stored

    class FakeDb:
        def __getattr__(self, name):
            raise AssertionError(f"unexpected database mutation: {name}")

    monkeypatch.setattr(contents_router, "ContentService", FakeService)

    result = await contents_router.get_content_detail(
        content_id=content_id,
        db=FakeDb(),
        current_user_id=str(user_id),
    )

    assert result is stored
