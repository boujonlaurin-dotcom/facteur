"""Service « lettre du jour » de l'Essentiel (Story 9.6).

Génère un digest rédigé concis où les références sont la navigation :
- Le serveur construit un **plan déterministe** (quels picks dans le chapô,
  quelles rubriques par thème) ; le LLM ne rédige que la prose avec des
  marqueurs ``[[n]]`` (n = rang du pick).
- Parsing + validation serveur : la règle « chaque pick référencé exactement
  une fois » devient un simple comptage de marqueurs.
- 1 retry max avec bloc « CORRECTIONS OBLIGATOIRES », sinon échec loggé →
  pas de stockage (le mobile retombe sur la carte 5 articles).

Contrainte pool (leçons PYTHON-5M/5G) : aucune fonction de ce module ne garde
de session DB ouverte pendant un appel LLM — la génération est pure
(`generate_letter`), le stockage et la lecture sont des helpers séparés.
"""

import re
from dataclasses import dataclass, field
from datetime import UTC, date, datetime, timedelta
from uuid import UUID

import structlog
from sqlalchemy import delete, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.essentiel_letter import EssentielLetterRow
from app.schemas.essentiel import EssentielArticle
from app.schemas.essentiel_letter import (
    LETTER_FORMAT_VERSION,
    EssentielLetter,
    LetterRubrique,
    LetterSegment,
    LetterSegmentType,
)
from app.services.digest_service import get_batch_action_states
from app.services.editorial.config import load_editorial_config
from app.services.editorial.llm_client import EditorialLLMClient
from app.utils.time import today_paris

logger = structlog.get_logger()

# Caps de longueur (prose sans marqueurs) — au-delà, la lettre perd sa raison
# d'être (un digest concis) ; en-deçà, elle n'apporte rien.
CHAPO_MIN_CHARS = 120
CHAPO_MAX_CHARS = 360
RUBRIQUE_MIN_CHARS = 60
RUBRIQUE_MAX_CHARS = 200
TOTAL_MAX_CHARS = 1000

# Structure du plan : chapô 1-2 sujets forts, max 3 rubriques de 1-2 picks,
# pied « autres thèmes » cap 4.
MAX_RUBRIQUES = 3
MAX_PICKS_PER_RUBRIQUE = 2
MAX_FOOTER_THEMES = 4

_MARKER_RE = re.compile(r"\[\[(\d+)\]\]")
# 1re personne : la lettre a une voix éditoriale neutre, le Facteur héberge
# mais ne narre pas.
_FIRST_PERSON_RE = re.compile(
    r"(?i)(?<![a-zà-ÿ])j['']|\bje\b|\bmoi\b|\bmon\b|\bma\b|\bmes\b"
    r"|\bnous\b|\bnotre\b|\bnos\b"
)
_FORBIDDEN_SUBSTRINGS = ("**", "](", "http://", "https://", "www.", "`")

_SEREIN_TONE_NOTE = (
    "VARIANTE SEREINE : le lecteur a active le mode apaise. Ton encore plus "
    "calme et factuel, aucun vocabulaire anxiogene ou dramatisant, pas "
    "d'urgence artificielle."
)


@dataclass(frozen=True)
class LetterPlan:
    """Plan déterministe de la lettre, construit avant l'appel LLM.

    Invariant structurel : l'union de `chapo_ranks` et des ranks des
    `rubriques` couvre tous les picks, sans doublon.
    """

    chapo_ranks: list[int] = field(default_factory=list)
    rubriques: list[tuple[str, list[int]]] = field(default_factory=list)
    footer_themes: list[str] = field(default_factory=list)


def build_letter_plan(
    articles: list[EssentielArticle],
    followed_themes: list[str] | None = None,
) -> LetterPlan:
    """Répartit les picks entre chapô et rubriques, déterministe.

    - Chapô : pick rank 1, + rank 2 dès que le digest a ≥4 picks, + tout pick
      sans thème (une rubrique sans pill n'a pas de sens).
    - Rubriques : picks restants groupés par thème (ordre d'apparition), max
      `MAX_RUBRIQUES` de `MAX_PICKS_PER_RUBRIQUE` picks ; un seul thème →
      une rubrique multi-picks. L'excédent remonte au chapô (jamais de pick
      orphelin).
    - Footer : thèmes suivis non couverts par les picks, cap 4.
    """
    ordered = sorted(articles, key=lambda a: a.rank)
    if not ordered:
        return LetterPlan()

    chapo_ranks: list[int] = []
    remaining: list[EssentielArticle] = []
    for article in ordered:
        if (
            article.rank == 1
            or article.rank == 2
            and len(ordered) >= 4
            or article.theme is None
        ):
            chapo_ranks.append(article.rank)
        else:
            remaining.append(article)

    # Groupes par thème, ordre d'apparition (donc ordre de rank).
    groups: dict[str, list[int]] = {}
    for article in remaining:
        groups.setdefault(article.theme or "", []).append(article.rank)

    rubriques: list[tuple[str, list[int]]] = []
    overflow: list[int] = []
    single_theme = len(groups) == 1
    for theme, ranks in groups.items():
        if len(rubriques) >= MAX_RUBRIQUES:
            overflow.extend(ranks)
            continue
        if single_theme:
            # Cas 1 seul thème : une rubrique multi-picks, rien ne déborde.
            rubriques.append((theme, ranks))
            continue
        rubriques.append((theme, ranks[:MAX_PICKS_PER_RUBRIQUE]))
        overflow.extend(ranks[MAX_PICKS_PER_RUBRIQUE:])
    chapo_ranks.extend(overflow)
    chapo_ranks.sort()

    covered_themes = {a.theme for a in ordered if a.theme}
    footer_themes = [
        theme for theme in (followed_themes or []) if theme not in covered_themes
    ][:MAX_FOOTER_THEMES]

    return LetterPlan(
        chapo_ranks=chapo_ranks,
        rubriques=rubriques,
        footer_themes=footer_themes,
    )


def _plan_covers_all_picks(plan: LetterPlan, articles: list[EssentielArticle]) -> bool:
    planned = list(plan.chapo_ranks) + [
        rank for _, ranks in plan.rubriques for rank in ranks
    ]
    return sorted(planned) == sorted(a.rank for a in articles)


def _article_brief(article: EssentielArticle) -> str:
    desc = (article.description or "").strip().replace("\n", " ")
    if len(desc) > 220:
        desc = desc[:220] + "…"
    parts = [f"[[{article.rank}]] {article.title.strip()}"]
    if desc:
        parts.append(desc)
    return " : ".join(parts)


def _build_user_message(
    plan: LetterPlan,
    articles: list[EssentielArticle],
    corrections: list[str] | None = None,
) -> str:
    """Sérialise le plan + les articles en message user pour le LLM."""
    by_rank = {a.rank: a for a in articles}
    lines: list[str] = ["PLAN IMPOSE", "", "CHAPO (2-4 phrases) :"]
    for rank in plan.chapo_ranks:
        lines.append(f"- {_article_brief(by_rank[rank])}")
    for theme, ranks in plan.rubriques:
        lines.append("")
        lines.append(f"RUBRIQUE theme={theme} (1 phrase) :")
        for rank in ranks:
            lines.append(f"- {_article_brief(by_rank[rank])}")
    if corrections:
        lines.append("")
        lines.append("CORRECTIONS OBLIGATOIRES (ta precedente reponse a ete rejetee) :")
        for violation in corrections:
            lines.append(f"- {violation}")
    return "\n".join(lines)


def _repair_dashes(text: str) -> str:
    """Auto-repair silencieux des cadratins (règle projet : jamais d'em-dash)."""
    text = text.replace(" — ", " : ").replace(" – ", " : ")
    text = text.replace("—", ", ").replace("–", ", ")
    return re.sub(r" {2,}", " ", text)


def _prose_len(text: str) -> int:
    return len(_MARKER_RE.sub("", text).strip())


def _has_emoji(text: str) -> bool:
    return any(
        ord(ch) >= 0x1F000 or 0x2600 <= ord(ch) <= 0x27BF or 0x2190 <= ord(ch) <= 0x21FF
        for ch in text
    )


def _check_prose(
    label: str,
    text: str,
    expected_ranks: list[int],
    min_chars: int,
    max_chars: int,
    source_names: list[str],
) -> list[str]:
    """Violations d'un bloc de prose (chapô ou rubrique)."""
    violations: list[str] = []

    found = [int(n) for n in _MARKER_RE.findall(text)]
    if sorted(found) != sorted(expected_ranks):
        violations.append(
            f"{label} : les marqueurs doivent etre exactement "
            f"{sorted(set(expected_ranks))} chacun une seule fois "
            f"(trouves : {found or 'aucun'})"
        )

    if _FIRST_PERSON_RE.search(text):
        violations.append(f"{label} : premiere personne interdite (je, mon, nous...)")
    if "!" in text:
        violations.append(f"{label} : point d'exclamation interdit")
    for token in _FORBIDDEN_SUBSTRINGS:
        if token in text:
            violations.append(f"{label} : markdown ou URL interdits ({token})")
            break
    if _has_emoji(text):
        violations.append(f"{label} : emoji interdit")

    lowered = text.lower()
    for name in source_names:
        if name and name.lower() in lowered:
            violations.append(
                f"{label} : ne cite jamais le nom de la source « {name} » "
                "dans la prose (le bouton l'affiche deja)"
            )

    prose_len = _prose_len(text)
    if not min_chars <= prose_len <= max_chars:
        violations.append(
            f"{label} : longueur {prose_len} caracteres hors bornes "
            f"({min_chars}-{max_chars})"
        )
    return violations


def _parse_segments(text: str, rank_to_content: dict[int, UUID]) -> list[LetterSegment]:
    """Découpe une prose à marqueurs en segments text/source_ref."""
    segments: list[LetterSegment] = []
    cursor = 0
    for match in _MARKER_RE.finditer(text):
        before = text[cursor : match.start()]
        if before.strip():
            segments.append(LetterSegment(type=LetterSegmentType.TEXT, text=before))
        rank = int(match.group(1))
        content_id = rank_to_content.get(rank)
        if content_id is not None:
            segments.append(
                LetterSegment(type=LetterSegmentType.SOURCE_REF, content_id=content_id)
            )
        cursor = match.end()
    tail = text[cursor:]
    if tail.strip():
        segments.append(LetterSegment(type=LetterSegmentType.TEXT, text=tail))
    return segments


def validate_letter_output(
    raw: dict,
    plan: LetterPlan,
    articles: list[EssentielArticle],
) -> tuple[dict[str, str] | None, list[str]]:
    """Valide la sortie LLM contre le plan.

    Renvoie `(blocs {clé: prose réparée}, violations)`. Blocs = `chapo` +
    un bloc par thème de rubrique. Les cadratins sont auto-réparés en amont
    des autres checks (jamais une cause de retry).
    """
    violations: list[str] = []
    source_names = [a.source.name for a in articles]

    chapo_text = raw.get("chapo")
    if not isinstance(chapo_text, str) or not chapo_text.strip():
        return None, ["reponse : cle 'chapo' manquante ou vide"]
    chapo_text = _repair_dashes(chapo_text.strip())

    raw_rubriques = raw.get("rubriques")
    if not isinstance(raw_rubriques, list):
        return None, ["reponse : cle 'rubriques' manquante ou invalide"]
    rubrique_texts: dict[str, str] = {}
    for item in raw_rubriques:
        if not isinstance(item, dict):
            continue
        theme = item.get("theme")
        text = item.get("text")
        if isinstance(theme, str) and isinstance(text, str) and text.strip():
            rubrique_texts[theme] = _repair_dashes(text.strip())

    expected_themes = [theme for theme, _ in plan.rubriques]
    if sorted(rubrique_texts) != sorted(expected_themes):
        violations.append(
            "rubriques : reprends exactement les themes du plan "
            f"({expected_themes}), recus : {sorted(rubrique_texts)}"
        )
        return None, violations

    violations.extend(
        _check_prose(
            "chapo",
            chapo_text,
            plan.chapo_ranks,
            CHAPO_MIN_CHARS,
            CHAPO_MAX_CHARS,
            source_names,
        )
    )
    for theme, ranks in plan.rubriques:
        violations.extend(
            _check_prose(
                f"rubrique {theme}",
                rubrique_texts[theme],
                ranks,
                RUBRIQUE_MIN_CHARS,
                RUBRIQUE_MAX_CHARS,
                source_names,
            )
        )

    total = _prose_len(chapo_text) + sum(
        _prose_len(text) for text in rubrique_texts.values()
    )
    if total > TOTAL_MAX_CHARS:
        violations.append(
            f"total : {total} caracteres, maximum {TOTAL_MAX_CHARS} : raccourcis"
        )

    if violations:
        return None, violations
    return {"chapo": chapo_text, **rubrique_texts}, []


def _blocks_to_letter(
    blocks: dict[str, str],
    plan: LetterPlan,
    articles: list[EssentielArticle],
    model: str,
) -> EssentielLetter:
    rank_to_content = {a.rank: a.content_id for a in articles}
    return EssentielLetter(
        version=LETTER_FORMAT_VERSION,
        chapo=_parse_segments(blocks["chapo"], rank_to_content),
        rubriques=[
            LetterRubrique(
                theme=theme,
                segments=_parse_segments(blocks[theme], rank_to_content),
            )
            for theme, _ in plan.rubriques
        ],
        footer_themes=plan.footer_themes,
        generated_at=datetime.now(UTC),
        model=model,
    )


async def generate_letter(
    articles: list[EssentielArticle],
    *,
    followed_themes: list[str] | None = None,
    is_serene: bool = False,
    client: EditorialLLMClient | None = None,
) -> EssentielLetter | None:
    """Génère la lettre pour un jeu de picks. Pure de toute session DB.

    1 retry max avec bloc corrections ; None si le LLM échoue ou si la
    validation rejette les deux tentatives (le caller ne stocke rien).
    """
    if not articles:
        return None

    plan = build_letter_plan(articles, followed_themes)
    if not _plan_covers_all_picks(plan, articles):
        # Bug de plan, jamais attendu : mieux vaut pas de lettre qu'une lettre
        # aux références incomplètes.
        logger.error(
            "essentiel_letter.plan_invariant_broken",
            plan_chapo=plan.chapo_ranks,
            plan_rubriques=plan.rubriques,
            picks=[a.rank for a in articles],
        )
        return None

    prompt_cfg = load_editorial_config().essentiel_letter_prompt
    if not prompt_cfg.system:
        logger.error("essentiel_letter.prompt_missing")
        return None
    system = prompt_cfg.system.format(tone_note=_SEREIN_TONE_NOTE if is_serene else "")

    llm = client or EditorialLLMClient()
    owns_client = client is None
    try:
        corrections: list[str] | None = None
        for attempt in (1, 2):
            raw = await llm.chat_json(
                system=system,
                user_message=_build_user_message(plan, articles, corrections),
                model=prompt_cfg.model,
                temperature=prompt_cfg.temperature,
                max_tokens=prompt_cfg.max_tokens,
                call_site="essentiel_letter",
            )
            if not raw or not isinstance(raw, dict):
                logger.warning("essentiel_letter.llm_empty", attempt=attempt)
                return None
            blocks, violations = validate_letter_output(raw, plan, articles)
            if blocks is not None:
                return _blocks_to_letter(blocks, plan, articles, prompt_cfg.model)
            logger.warning(
                "essentiel_letter.validation_failed",
                attempt=attempt,
                violations=violations,
            )
            corrections = violations
        return None
    finally:
        if owns_client:
            await llm.close()


async def store_letter(
    db: AsyncSession,
    *,
    user_id: UUID,
    target_date: date,
    is_serene: bool,
    letter: EssentielLetter,
    articles: list[EssentielArticle],
) -> None:
    """INSERT idempotent (race on-demand/job → ON CONFLICT DO NOTHING)."""
    stmt = (
        pg_insert(EssentielLetterRow)
        .values(
            user_id=user_id,
            target_date=target_date,
            is_serene=is_serene,
            letter=letter.model_dump(mode="json"),
            articles=[a.model_dump(mode="json") for a in articles],
            model=letter.model,
            generated_at=letter.generated_at,
        )
        .on_conflict_do_nothing(constraint="uq_essentiel_letters_user_date_serene")
    )
    await db.execute(stmt)
    await db.commit()


async def load_letter_row(
    db: AsyncSession,
    user_id: UUID,
    target_date: date,
    is_serene: bool,
) -> EssentielLetterRow | None:
    stmt = select(EssentielLetterRow).where(
        EssentielLetterRow.user_id == user_id,
        EssentielLetterRow.target_date == target_date,
        EssentielLetterRow.is_serene == is_serene,
    )
    return (await db.execute(stmt)).scalar_one_or_none()


async def rehydrate_snapshot(
    db: AsyncSession,
    user_id: UUID,
    raw_articles: list[dict],
) -> list[EssentielArticle]:
    """Reparse le snapshot JSONB et réhydrate les flags de statut user.

    La lettre est figée pour la journée mais l'état lu/enregistré doit rester
    vivant : 1 SELECT sur `user_content_status` pour les ids du snapshot, via
    la projection canonique partagée avec le digest.
    """
    articles = [EssentielArticle.model_validate(item) for item in raw_articles]
    if not articles:
        return []
    states = await get_batch_action_states(
        db, user_id, [a.content_id for a in articles]
    )
    return [
        article.model_copy(update=states[article.content_id])
        if article.content_id in states
        else article
        for article in articles
    ]


async def purge_old_letters(db: AsyncSession, *, older_than_days: int = 30) -> int:
    """Purge les lettres > N jours (index `target_date`). Renvoie le count."""
    cutoff = today_paris() - timedelta(days=older_than_days)
    result = await db.execute(
        delete(EssentielLetterRow).where(EssentielLetterRow.target_date < cutoff)
    )
    await db.commit()
    return int(result.rowcount or 0)
