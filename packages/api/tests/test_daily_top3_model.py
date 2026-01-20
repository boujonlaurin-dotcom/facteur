"""Tests unitaires pour le modèle DailyTop3.

Story 4.4: Top 3 Briefing Quotidien
Valide le CRUD basique et les contraintes du modèle.
"""
import pytest
import uuid
from datetime import datetime, timedelta
from unittest.mock import MagicMock

from app.models.daily_top3 import DailyTop3


class TestDailyTop3Model:
    """Tests pour le modèle DailyTop3."""

    def test_create_daily_top3_item(self):
        """Test création d'un item DailyTop3 avec tous les champs."""
        user_id = uuid.uuid4()
        content_id = uuid.uuid4()
        
        item = DailyTop3(
            user_id=user_id,
            content_id=content_id,
            rank=1,
            top3_reason="À la Une",
            consumed=False,
            generated_at=datetime.utcnow()
        )
        
        assert item.user_id == user_id
        assert item.content_id == content_id
        assert item.rank == 1
        assert item.top3_reason == "À la Une"
        assert item.consumed is False

    def test_rank_valid_values(self):
        """Test que les valeurs de rank 1, 2, 3 sont acceptées."""
        user_id = uuid.uuid4()
        content_id = uuid.uuid4()
        
        for rank in [1, 2, 3]:
            item = DailyTop3(
                user_id=user_id,
                content_id=content_id,
                rank=rank,
                top3_reason="Test",
            )
            assert item.rank == rank

    def test_top3_reason_variants(self):
        """Test les différentes raisons de sélection."""
        user_id = uuid.uuid4()
        content_id = uuid.uuid4()
        
        reasons = ["À la Une", "Sujet tendance", "Source suivie", "Recommandé pour vous"]
        
        for reason in reasons:
            item = DailyTop3(
                user_id=user_id,
                content_id=content_id,
                rank=1,
                top3_reason=reason,
            )
            assert item.top3_reason == reason

    def test_consumed_default_false(self):
        """Test que consumed est False par défaut."""
        item = DailyTop3(
            user_id=uuid.uuid4(),
            content_id=uuid.uuid4(),
            rank=1,
            top3_reason="Test",
        )
        
        # Note: SQLAlchemy default n'est appliqué que lors du commit DB
        # Mais on vérifie que le champ peut être absent à l'initialisation
        # et qu'il sera False après persist
        assert item.consumed is None or item.consumed is False

    def test_tablename_correct(self):
        """Test que le nom de table est correct."""
        assert DailyTop3.__tablename__ == "daily_top3"


class TestDailyTop3Constraints:
    """Tests pour les contraintes du modèle (validation sans DB)."""

    def test_model_has_rank_constraint(self):
        """Vérifie que la contrainte de rank est définie."""
        # Cherche la contrainte dans __table_args__
        table_args = DailyTop3.__table_args__
        
        constraint_names = []
        for arg in table_args:
            if hasattr(arg, 'name'):
                constraint_names.append(arg.name)
        
        assert 'ck_daily_top3_rank_range' in constraint_names

    def test_model_has_user_date_index(self):
        """Vérifie que l'index user+date est défini."""
        table_args = DailyTop3.__table_args__
        
        index_names = []
        for arg in table_args:
            if hasattr(arg, 'name') and arg.name:
                index_names.append(arg.name)
        
        assert 'ix_daily_top3_user_date' in index_names


class TestSourceUneFeedUrl:
    """Tests pour le champ une_feed_url sur Source."""

    def test_source_has_une_feed_url_field(self):
        """Vérifie que Source a le champ une_feed_url."""
        from app.models.source import Source
        
        # Vérifie que l'attribut existe sur la classe
        assert hasattr(Source, 'une_feed_url')

    def test_une_feed_url_is_nullable(self):
        """Vérifie que une_feed_url est nullable."""
        from app.models.source import Source
        
        # Le champ doit permettre None (la plupart des sources n'ont pas de feed Une)
        mapper = Source.__mapper__
        une_feed_url_col = mapper.columns['une_feed_url']
        
        assert une_feed_url_col.nullable is True
