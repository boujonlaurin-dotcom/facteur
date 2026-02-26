import pytest
from unittest.mock import MagicMock, AsyncMock, patch
from uuid import uuid4
from datetime import datetime

from app.services.content_service import ContentService
from app.models.content import UserContentStatus

@pytest.mark.asyncio
async def test_set_save_status():
    session = AsyncMock()
    service = ContentService(session)
    
    user_id = uuid4()
    content_id = uuid4()
    
    # Mock result
    mock_status = UserContentStatus(user_id=user_id, content_id=content_id, is_saved=True)
    
    # We need to mock session.scalars(stmt).one()
    # scalars return a Result object
    mock_result = MagicMock()
    mock_result.one.return_value = mock_status
    session.scalars.return_value = mock_result
    
    with patch.object(service, "_adjust_subtopic_weights", new_callable=AsyncMock):
        result = await service.set_save_status(user_id, content_id, True)

    assert result.is_saved == True
