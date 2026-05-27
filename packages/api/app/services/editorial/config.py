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
    # Minimum age (hours) for an article to be eligible as a "Pas de recul"
    # candidate. Enforces that a deep-tier article published on the same
    # morning as the hot news is excluded — "prendre du recul" should mean
    # stepping back, not another same-day dispatch from a deep source.
    # See docs/bugs/bug-digest-pas-de-recul-same-event.md.
    deep_min_age_hours: int = 24


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
    curation_prompt: PromptConfig = field(
        default_factory=lambda: PromptConfig(system="")
    )
    # TODO: réactiver pour la prochaine itération Pas de recul
    deep_matching_prompt: PromptConfig = field(
        default_factory=lambda: PromptConfig(system="", temperature=0.2, max_tokens=300)
    )
    query_expansion_prompt: PromptConfig = field(
        default_factory=lambda: PromptConfig(
            system="", model="mistral-small-latest", temperature=0.3, max_tokens=150
        )
    )
    a_la_une_prompt: PromptConfig = field(
        default_factory=lambda: PromptConfig(
            system="", model="mistral-small-latest", temperature=0.1, max_tokens=200
        )
    )
    bonne_nouvelle_prompt: PromptConfig = field(
        default_factory=lambda: PromptConfig(
            system="", model="mistral-small-latest", temperature=0.1, max_tokens=200
        )
    )


@lru_cache(maxsize=1)
def load_editorial_config() -> EditorialConfig:
    """Load editorial config from YAML files. Cached."""
    config_path = CONFIG_DIR / "editorial_config.yaml"
    prompts_path = CONFIG_DIR / "editorial_prompts.yaml"

    pipeline_cfg = PipelineConfig()
    curation_prompt = PromptConfig(system="")
    deep_matching_prompt = PromptConfig(system="", temperature=0.2, max_tokens=300)
    query_expansion_prompt = PromptConfig(
        system="", model="mistral-small-latest", temperature=0.3, max_tokens=150
    )
    a_la_une_prompt = PromptConfig(
        system="", model="mistral-small-latest", temperature=0.1, max_tokens=200
    )
    bonne_nouvelle_prompt = PromptConfig(
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
        except Exception:
            logger.exception("editorial_config_load_failed", path=str(config_path))

    # Load prompts
    if not prompts_path.exists():
        logger.error(
            "editorial_prompts_yaml_missing",
            path=str(prompts_path),
            message="editorial_prompts.yaml not found — curation/a_la_une prompts empty",
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
            if raw and "a_la_une" in raw:
                a_la_une_prompt = PromptConfig(**raw["a_la_une"])
            if raw and "bonne_nouvelle" in raw:
                bonne_nouvelle_prompt = PromptConfig(**raw["bonne_nouvelle"])
        except Exception:
            logger.exception("editorial_prompts_load_failed", path=str(prompts_path))

    cfg = EditorialConfig(
        pipeline=pipeline_cfg,
        curation_prompt=curation_prompt,
        deep_matching_prompt=deep_matching_prompt,
        query_expansion_prompt=query_expansion_prompt,
        a_la_une_prompt=a_la_une_prompt,
        bonne_nouvelle_prompt=bonne_nouvelle_prompt,
    )

    logger.info(
        "editorial_config_loaded",
        has_curation_prompt=bool(cfg.curation_prompt.system),
        config_path=str(config_path),
        prompts_path=str(prompts_path),
    )

    return cfg
