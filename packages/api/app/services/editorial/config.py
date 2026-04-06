"""YAML configuration loader for the editorial pipeline."""

from dataclasses import dataclass, field
from functools import lru_cache
from pathlib import Path

import structlog
import yaml

logger = structlog.get_logger()

CONFIG_DIR = Path(__file__).parent.parent.parent.parent / "config"


@dataclass(frozen=True)
class PipelineConfig:
    """Pipeline parameters."""

    subjects_count: int = 5
    cluster_input_limit: int = 15
    deep_candidates_prefilter: int = 10
    deep_required: bool = False
    actu_max_age_hours: int = 24
    deep_jaccard_threshold: float = 0.10


@dataclass(frozen=True)
class FeatureFlags:
    """Feature flags for progressive rollout."""

    editorial_enabled: bool = False
    editorial_user_ids: list[str] = field(default_factory=list)


@dataclass(frozen=True)
class PromptConfig:
    """LLM prompt template."""

    system: str
    model: str = "mistral-large-latest"
    temperature: float = 0.3
    max_tokens: int = 1000


@dataclass(frozen=True)
class EditorialConfig:
    """Full editorial pipeline configuration."""

    pipeline: PipelineConfig = field(default_factory=PipelineConfig)
    feature_flags: FeatureFlags = field(default_factory=FeatureFlags)
    curation_prompt: PromptConfig = field(
        default_factory=lambda: PromptConfig(system="")
    )
    deep_matching_prompt: PromptConfig = field(
        default_factory=lambda: PromptConfig(system="", temperature=0.2, max_tokens=300)
    )
    query_expansion_prompt: PromptConfig = field(
        default_factory=lambda: PromptConfig(
            system="", model="mistral-small-latest", temperature=0.3, max_tokens=150
        )
    )
    writing_prompt: PromptConfig = field(
        default_factory=lambda: PromptConfig(system="", max_tokens=2000)
    )
    writing_serene_prompt: PromptConfig = field(
        default_factory=lambda: PromptConfig(system="", max_tokens=2000)
    )
    pepite_prompt: PromptConfig = field(
        default_factory=lambda: PromptConfig(system="", temperature=0.3, max_tokens=500)
    )
    a_la_une_prompt: PromptConfig = field(
        default_factory=lambda: PromptConfig(
            system="", model="mistral-small-latest", temperature=0.1, max_tokens=200
        )
    )

    def is_enabled_for_user(self, user_id: str) -> bool:
        """Check if editorial pipeline is enabled for a specific user."""
        if not self.feature_flags.editorial_enabled:
            return False
        # Empty whitelist = enabled for all (when master switch is on)
        if not self.feature_flags.editorial_user_ids:
            return True
        return user_id in self.feature_flags.editorial_user_ids


@lru_cache(maxsize=1)
def load_editorial_config() -> EditorialConfig:
    """Load editorial config from YAML files. Cached."""
    config_path = CONFIG_DIR / "editorial_config.yaml"
    prompts_path = CONFIG_DIR / "editorial_prompts.yaml"

    pipeline_cfg = PipelineConfig()
    feature_flags = FeatureFlags()
    curation_prompt = PromptConfig(system="")
    deep_matching_prompt = PromptConfig(system="", temperature=0.2, max_tokens=300)
    query_expansion_prompt = PromptConfig(
        system="", model="mistral-small-latest", temperature=0.3, max_tokens=150
    )
    writing_prompt = PromptConfig(system="", max_tokens=2000)
    writing_serene_prompt = PromptConfig(system="", max_tokens=2000)
    pepite_prompt = PromptConfig(system="", temperature=0.3, max_tokens=500)
    a_la_une_prompt = PromptConfig(
        system="", model="mistral-small-latest", temperature=0.1, max_tokens=200
    )

    # Load pipeline config
    if not config_path.exists():
        logger.error(
            "editorial_config_yaml_missing",
            path=str(config_path),
            message="editorial_config.yaml not found — using defaults (editorial DISABLED)",
        )
    else:
        try:
            raw = yaml.safe_load(config_path.read_text())
            if raw and "pipeline" in raw:
                pipeline_cfg = PipelineConfig(**raw["pipeline"])
            if raw and "feature_flags" in raw:
                feature_flags = FeatureFlags(**raw["feature_flags"])
        except Exception:
            logger.exception("editorial_config_load_failed", path=str(config_path))

    # Load prompts
    if not prompts_path.exists():
        logger.error(
            "editorial_prompts_yaml_missing",
            path=str(prompts_path),
            message="editorial_prompts.yaml not found — writing/pepite prompts empty",
        )
    else:
        try:
            raw = yaml.safe_load(prompts_path.read_text())
            if raw and "curation" in raw:
                curation_prompt = PromptConfig(**raw["curation"])
            if raw and "deep_matching" in raw:
                deep_matching_prompt = PromptConfig(**raw["deep_matching"])
            if raw and "query_expansion" in raw:
                query_expansion_prompt = PromptConfig(**raw["query_expansion"])
            if raw and "writing" in raw:
                writing_prompt = PromptConfig(**raw["writing"])
            if raw and "writing_serene" in raw:
                writing_serene_prompt = PromptConfig(**raw["writing_serene"])
            if raw and "pepite" in raw:
                pepite_prompt = PromptConfig(**raw["pepite"])
            if raw and "a_la_une" in raw:
                a_la_une_prompt = PromptConfig(**raw["a_la_une"])
        except Exception:
            logger.exception("editorial_prompts_load_failed", path=str(prompts_path))

    cfg = EditorialConfig(
        pipeline=pipeline_cfg,
        feature_flags=feature_flags,
        curation_prompt=curation_prompt,
        deep_matching_prompt=deep_matching_prompt,
        query_expansion_prompt=query_expansion_prompt,
        writing_prompt=writing_prompt,
        writing_serene_prompt=writing_serene_prompt,
        pepite_prompt=pepite_prompt,
        a_la_une_prompt=a_la_une_prompt,
    )

    logger.info(
        "editorial_config_loaded",
        editorial_enabled=cfg.feature_flags.editorial_enabled,
        whitelist_count=len(cfg.feature_flags.editorial_user_ids),
        has_curation_prompt=bool(cfg.curation_prompt.system),
        has_writing_prompt=bool(cfg.writing_prompt.system),
        has_pepite_prompt=bool(cfg.pepite_prompt.system),
        config_path=str(config_path),
        prompts_path=str(prompts_path),
    )

    return cfg
