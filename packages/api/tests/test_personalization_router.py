import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4, UUID
from fastapi import HTTPException
from app.routers.personalization import mute_source, MuteSourceRequest, PersonalizationResponse, get_personalization
from app.models.user_personalization import UserPersonalization

@pytest.mark.asyncio
async def test_get_personalization_empty():
    mock_db = AsyncMock()
    mock_db.scalar = AsyncMock(return_value=None)
    user_id = str(uuid4())
    
    response = await get_personalization(db=mock_db, current_user_id=user_id)
    
    assert isinstance(response, PersonalizationResponse)
    assert response.muted_sources == []
    assert response.muted_themes == []
    assert response.muted_topics == []

@pytest.mark.asyncio
async def test_mute_source_logic():
    mock_db = AsyncMock()
    user_id = str(uuid4())
    source_id = uuid4()
    request = MuteSourceRequest(source_id=source_id)
    
    # Mock user_service and db methods
    with patch("app.routers.personalization.UserService") as mock_user_service_cls:
        mock_user_service = mock_user_service_cls.return_value
        mock_user_service.get_or_create_profile = AsyncMock()
        
        # Test the endpoint
        response = await mute_source(request=request, db=mock_db, current_user_id=user_id)
        
        assert response["message"] == "Source mutée avec succès"
        assert response["source_id"] == str(source_id)
        
        # Verify db.execute was called (the upsert stmt)
        assert mock_db.execute.called
        assert mock_db.commit.called

@pytest.mark.asyncio
async def test_mute_source_error_handling():
    mock_db = AsyncMock()
    mock_db.execute = AsyncMock(side_effect=Exception("DB Error"))
    user_id = str(uuid4())
    source_id = uuid4()
    request = MuteSourceRequest(source_id=source_id)
    
    with patch("app.routers.personalization.UserService") as mock_user_service_cls:
        mock_user_service = mock_user_service_cls.return_value
        mock_user_service.get_or_create_profile = AsyncMock()
        
        with pytest.raises(HTTPException) as excinfo:
            await mute_source(request=request, db=mock_db, current_user_id=user_id)
        
        assert excinfo.value.status_code == 500
        assert "Erreur lors du masquage de la source" in excinfo.value.detail
        assert mock_db.rollback.called
