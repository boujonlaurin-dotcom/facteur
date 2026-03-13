"""Tests for editorial pipeline configuration loader."""

from unittest.mock import patch

import pytest

from app.services.editorial.config import (
    EditorialConfig,
    FeatureFlags,
    PipelineConfig,
    PromptConfig,
    load_editorial_config,
)


@pytest.fixture(autouse=True)
def clear_config_cache():
    """Clear lru_cache between tests."""
    load_editorial_config.cache_clear()
    yield
    load_editorial_config.cache_clear()


class TestPipelineConfig:
    def test_defaults(self):
        cfg = PipelineConfig()
        assert cfg.subjects_count == 3
        assert cfg.cluster_input_limit == 15
        assert cfg.deep_candidates_prefilter == 10
        assert cfg.deep_required is False
        assert cfg.actu_max_age_hours == 24
        assert cfg.deep_jaccard_threshold == 0.10


class TestFeatureFlags:
    def test_defaults(self):
        ff = FeatureFlags()
        assert ff.editorial_enabled is False
        assert ff.editorial_user_ids == []


class TestPromptConfig:
    def test_defaults(self):
        pc = PromptConfig(system="You are an editor.")
        assert pc.model == "mistral-large-latest"
        assert pc.temperature == 0.3
        assert pc.max_tokens == 1000


class TestEditorialConfig:
    def test_is_enabled_disabled(self):
        cfg = EditorialConfig()
        assert cfg.is_enabled_for_user("any-user") is False

    def test_is_enabled_empty_whitelist(self):
        cfg = EditorialConfig(
            feature_flags=FeatureFlags(editorial_enabled=True, editorial_user_ids=[])
        )
        assert cfg.is_enabled_for_user("any-user") is True

    def test_is_enabled_whitelist_match(self):
        cfg = EditorialConfig(
            feature_flags=FeatureFlags(
                editorial_enabled=True, editorial_user_ids=["user-123"]
            )
        )
        assert cfg.is_enabled_for_user("user-123") is True

    def test_is_enabled_whitelist_miss(self):
        cfg = EditorialConfig(
            feature_flags=FeatureFlags(
                editorial_enabled=True, editorial_user_ids=["user-123"]
            )
        )
        assert cfg.is_enabled_for_user("user-999") is False


class TestLoadEditorialConfig:
    def test_returns_defaults_when_files_missing(self):
        with patch("app.services.editorial.config.CONFIG_DIR") as mock_dir:
            mock_config_path = mock_dir / "editorial_config.yaml"
            mock_prompts_path = mock_dir / "editorial_prompts.yaml"
            mock_config_path.exists.return_value = False
            mock_prompts_path.exists.return_value = False

            cfg = load_editorial_config()

        assert cfg.pipeline.subjects_count == 3
        assert cfg.feature_flags.editorial_enabled is False

    def test_loads_from_yaml(self):
        yaml_config = """
pipeline:
  subjects_count: 5
  cluster_input_limit: 20
feature_flags:
  editorial_enabled: true
  editorial_user_ids:
    - "user-a"
"""
        yaml_prompts = """
curation:
  system: "You are an editor"
  model: "mistral-large-latest"
  temperature: 0.3
  max_tokens: 1000
deep_matching:
  system: "Find deep articles"
  model: "mistral-large-latest"
  temperature: 0.2
  max_tokens: 300
"""
        from pathlib import Path
        from unittest.mock import MagicMock

        mock_config_path = MagicMock(spec=Path)
        mock_config_path.exists.return_value = True
        mock_config_path.read_text.return_value = yaml_config

        mock_prompts_path = MagicMock(spec=Path)
        mock_prompts_path.exists.return_value = True
        mock_prompts_path.read_text.return_value = yaml_prompts

        class MockDir:
            def __truediv__(self, name):
                if "config" in name:
                    return mock_config_path
                return mock_prompts_path

        with patch("app.services.editorial.config.CONFIG_DIR", MockDir()):
            cfg = load_editorial_config()

        assert cfg.pipeline.subjects_count == 5
        assert cfg.feature_flags.editorial_enabled is True
        assert "user-a" in cfg.feature_flags.editorial_user_ids
