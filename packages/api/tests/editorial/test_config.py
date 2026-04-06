"""Tests for editorial pipeline configuration loader."""

from unittest.mock import patch

import pytest

from app.services.editorial.config import (
    EditorialConfig,
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
        assert cfg.subjects_count == 5
        assert cfg.cluster_input_limit == 15
        assert cfg.deep_candidates_prefilter == 10
        assert cfg.deep_required is False
        assert cfg.actu_max_age_hours == 24
        assert cfg.deep_jaccard_threshold == 0.10


class TestPromptConfig:
    def test_defaults(self):
        pc = PromptConfig(system="You are an editor.")
        assert pc.model == "mistral-large-latest"
        assert pc.temperature == 0.3
        assert pc.max_tokens == 1000


class TestLoadEditorialConfig:
    def test_returns_defaults_when_files_missing(self):
        with patch("app.services.editorial.config.CONFIG_DIR") as mock_dir:
            mock_config_path = mock_dir / "editorial_config.yaml"
            mock_prompts_path = mock_dir / "editorial_prompts.yaml"
            mock_config_path.exists.return_value = False
            mock_prompts_path.exists.return_value = False

            cfg = load_editorial_config()

        assert cfg.pipeline.subjects_count == 5

    def test_loads_from_yaml(self):
        yaml_config = """
pipeline:
  subjects_count: 5
  cluster_input_limit: 20
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
