"""Analyse des angles 6C — contrat servi au Reader + post-traitement (Story 35.1).

Ce module porte tout ce qui transforme une sortie LLM brute en données
affichables : jusqu'à 3 accords + 2 désaccords **attribués**, plus deux
variantes courtes pour le CTA en haut d'article.

Tout ce qui suit est déterministe : la sortie du modèle n'est **jamais**
persistée telle quelle. Le modèle propose des constats et des domaines, Python
recalcule `support_count`, tronque, rejette et qualifie. Cf.
`PerspectiveService.analyze_consensus` pour la génération.

Séparé de `schemas.py` (qui ne porte que les DTO du digest) pour deux raisons :
ce sont des règles métier, pas un contrat de sérialisation, et l'arête d'import
vers `perspective_service` ne concerne que le chemin consensus — pas les dix
modules éditoriaux qui importent `schemas`.
"""

import json
import re
from collections.abc import Mapping

from pydantic import BaseModel

from app.models.coverage_analysis import (
    CONSENSUS_STATE_AVAILABLE,
    CONSENSUS_STATE_UNAVAILABLE,
)
from app.services.perspective_service import (
    CONSENSUS_CTA_PROMPT_CHARS,
    CONSENSUS_STATEMENT_PROMPT_CHARS,
    normalize_domain,
)

# Plafonds d'affichage du design 6C.
CONSENSUS_MAX_AGREEMENTS = 3
CONSENSUS_MAX_DISAGREEMENTS = 2

# Budget « 2 lignes » du hand-off : on coupe côté génération, pas côté CSS.
# Ces plafonds sont **dérivés** du budget annoncé au modèle dans le prompt
# (~65 caractères par ligne sur la largeur du Reader ; le CTA est plus court
# parce qu'il partage sa ligne avec la pile de logos). La troncature Python est
# un filet, pas la règle : un plafond passé sous le budget du prompt couperait
# *tous* les constats, d'où la dérivation plutôt que deux nombres libres.
CONSENSUS_TRUNCATION_SLACK = 10
CONSENSUS_STATEMENT_MAX_CHARS = (
    CONSENSUS_STATEMENT_PROMPT_CHARS + CONSENSUS_TRUNCATION_SLACK
)
CONSENSUS_CTA_MAX_CHARS = CONSENSUS_CTA_PROMPT_CHARS + CONSENSUS_TRUNCATION_SLACK
# En deçà, ce n'est pas une phrase : on écarte (« Oui. », « Débat »).
CONSENSUS_STATEMENT_MIN_CHARS = 12

ANGLE_QUALIFIER_POLARIZED = "polarized"
ANGLE_QUALIFIER_VARIED = "varied"
ANGLE_QUALIFIER_CONVERGENT = "convergent"

_LEFT_STANCES = frozenset({"left", "center-left"})
_RIGHT_STANCES = frozenset({"right", "center-right"})

# Fin de phrase = ponctuation forte suivie d'une espace. Le lookbehind garde la
# ponctuation sur la phrase qui la porte.
_SENTENCE_SPLIT_RE = re.compile(r"(?<=[.!?…])\s+")
_MARKDOWN_EMPHASIS_RE = re.compile(r"[*_`]{1,3}")
_WHITESPACE_RE = re.compile(r"\s+")


class ConsensusStatement(BaseModel):
    """Un constat attribué : le texte, les médias qui le portent, leur nombre.

    ``source_domains`` est **exhaustif** (tous les domaines du corpus qui portent
    le constat) : le choix des 2 logos affichés est une décision par utilisateur,
    prise au moment de servir (PR 2), pas au moment de générer.
    """

    text: str
    source_domains: list[str] = []
    support_count: int = 0


class ConsensusCta(BaseModel):
    """Variantes courtes pour le CTA en haut d'article : 1 accord + 1 désaccord."""

    agreement: ConsensusStatement | None = None
    disagreement: ConsensusStatement | None = None


class ConsensusPayload(BaseModel):
    """Bloc ``consensus`` persisté dans `coverage_analyses.consensus`."""

    state: str = CONSENSUS_STATE_AVAILABLE
    qualifier: str | None = None
    agreements: list[ConsensusStatement] = []
    disagreements: list[ConsensusStatement] = []
    cta: ConsensusCta = ConsensusCta()


def _field(item: object, name: str) -> object:
    """Lit un champ sur un objet `Perspective` **ou** sur son dict équivalent.

    Le pipeline manipule des `Perspective`, le dry-run relit le snapshot JSONB
    du digest : même donnée, deux formes, une seule règle d'attribution.
    """
    if isinstance(item, Mapping):
        return item.get(name)
    return getattr(item, name, None)


def build_corpus_index(perspectives) -> tuple[list[str], dict[str, str]]:
    """Domaines du corpus (ordre de couverture, dédupliqués) et leur biais.

    C'est la référence d'attribution de l'analyse : `support_count` est
    l'intersection avec ces domaines, et le qualificatif se décide sur ces
    biais. Jamais sur ce que le modèle affirme.
    """
    domains: list[str] = []
    bias_by_domain: dict[str, str] = {}
    for perspective in perspectives:
        domain = normalize_domain(_field(perspective, "source_domain"))
        if domain and domain not in bias_by_domain:
            domains.append(domain)
            bias_by_domain[domain] = _field(perspective, "bias_stance") or "unknown"
    return domains, bias_by_domain


def truncate_to_sentence(text: str, max_chars: int) -> str:
    """Ramène ``text`` sous ``max_chars`` en coupant **à la phrase**.

    Garde le plus grand nombre de phrases entières qui tiennent dans le budget.
    Quand la première phrase dépasse déjà à elle seule, on se rabat sur une
    coupe au mot suivie d'une ellipse — un constat tronqué en plein mot est pire
    qu'un constat visiblement écourté.
    """
    text = (text or "").strip()
    if len(text) <= max_chars:
        return text

    kept = ""
    for sentence in _SENTENCE_SPLIT_RE.split(text):
        candidate = f"{kept} {sentence}".strip() if kept else sentence.strip()
        if len(candidate) > max_chars:
            break
        kept = candidate
    if kept:
        return kept

    cut = text[: max_chars - 1].rstrip()
    if " " in cut:
        cut = cut[: cut.rfind(" ")]
    return f"{cut.rstrip(' ,;:')}…"


def _clean_statement_text(raw: object) -> str:
    """Texte plat : pas de markdown résiduel, espaces normalisées."""
    if not isinstance(raw, str):
        return ""
    return _WHITESPACE_RE.sub(" ", _MARKDOWN_EMPHASIS_RE.sub("", raw)).strip()


def _keep_corpus_domains(raw_domains: object, corpus: set[str]) -> list[str]:
    """Intersection avec le corpus, dédupliquée, ordre d'origine préservé.

    C'est ici que meurent les domaines hallucinés : le modèle ne peut pas
    inventer un « +10 » puisque `support_count` est la taille de cette liste.
    """
    if not isinstance(raw_domains, list):
        return []
    kept: list[str] = []
    for raw in raw_domains:
        if not isinstance(raw, str):
            continue
        domain = normalize_domain(raw)
        if domain and domain in corpus and domain not in kept:
            kept.append(domain)
    return kept


def _normalize_statement(raw: object, corpus: set[str]) -> ConsensusStatement | None:
    """Un constat du modèle → un constat servable, ou None s'il est irrecevable.

    Un constat est toujours un objet `{text, source_domains}` : sans domaine qui
    recoupe le corpus, il n'y a pas d'attribution, donc pas de constat.
    """
    if not isinstance(raw, dict):
        return None
    text = _clean_statement_text(raw.get("text"))
    if len(text) < CONSENSUS_STATEMENT_MIN_CHARS:
        return None
    domains = _keep_corpus_domains(raw.get("source_domains"), corpus)
    if not domains:
        return None
    return ConsensusStatement(
        text=truncate_to_sentence(text, CONSENSUS_STATEMENT_MAX_CHARS),
        source_domains=domains,
        support_count=len(domains),
    )


def _normalize_statements(
    raw_items: object, corpus: set[str], limit: int
) -> list[ConsensusStatement]:
    """Normalise, déduplique, trie par appui décroissant, plafonne."""
    if not isinstance(raw_items, list):
        return []

    statements: list[ConsensusStatement] = []
    seen: set[str] = set()
    for raw in raw_items:
        statement = _normalize_statement(raw, corpus)
        if statement is None:
            continue
        key = statement.text.casefold().rstrip(" .")
        if key in seen:
            continue
        seen.add(key)
        statements.append(statement)

    # `sorted` est stable : à appui égal, l'ordre du modèle est conservé.
    statements.sort(key=lambda s: -s.support_count)
    return statements[:limit]


def _resolve_cta(
    raw_variant: object, statements: list[ConsensusStatement]
) -> ConsensusStatement | None:
    """Variante courte du CTA, avec l'attribution du constat complet.

    Le CTA est le **même** constat dit plus court : son « +N » doit compter les
    mêmes médias. On ne retient donc du LLM que le texte, et on hérite de
    l'attribution du premier constat de la section — sans constat de section, il
    n'y a rien à teaser, donc pas de CTA. Si le modèle n'a pas rendu de variante
    recevable, on retombe sur le constat lui-même, retronqué au budget du CTA.
    """
    if not statements:
        return None
    anchor = statements[0]

    raw_text = raw_variant.get("text") if isinstance(raw_variant, dict) else raw_variant
    text = _clean_statement_text(raw_text)
    if len(text) < CONSENSUS_STATEMENT_MIN_CHARS:
        text = anchor.text
    return ConsensusStatement(
        text=truncate_to_sentence(text, CONSENSUS_CTA_MAX_CHARS),
        source_domains=list(anchor.source_domains),
        support_count=anchor.support_count,
    )


def _has_opposing_bias(
    statement: ConsensusStatement, bias_by_domain: dict[str, str]
) -> bool:
    """Vrai si le constat est porté des deux côtés du spectre."""
    stances = {bias_by_domain.get(d, "unknown") for d in statement.source_domains}
    return bool(stances & _LEFT_STANCES) and bool(stances & _RIGHT_STANCES)


def compute_angle_qualifier(
    disagreements: list[ConsensusStatement],
    bias_by_domain: dict[str, str] | None = None,
    *,
    state: str = CONSENSUS_STATE_AVAILABLE,
) -> str | None:
    """Qualificatif 6C : il décrit l'écart entre les **angles**, pas le corpus.

    Distinct de `compute_divergence_level`, qui dérive du biais du corpus et
    reste le signal de ranking. Ici :
    0 désaccord → convergent ; ≥ 2 désaccords dont au moins un porté par des
    biais opposés → polarized ; sinon varied. Hors état `available`, on ne
    qualifie pas : on n'affiche pas de parenthèse sur un débat qu'on n'a pas lu.
    """
    if state != CONSENSUS_STATE_AVAILABLE:
        return None
    if not disagreements:
        return ANGLE_QUALIFIER_CONVERGENT

    # Les domaines viennent d'un appelant qui les a déjà canonicalisés, mais
    # cette fonction est aussi le point d'entrée du dry-run et de la PR 2 : on
    # re-normalise à la frontière plutôt que de faire confiance.
    normalized_bias = {
        normalize_domain(domain): stance
        for domain, stance in (bias_by_domain or {}).items()
    }
    if len(disagreements) >= 2 and any(
        _has_opposing_bias(statement, normalized_bias) for statement in disagreements
    ):
        return ANGLE_QUALIFIER_POLARIZED
    return ANGLE_QUALIFIER_VARIED


def normalize_consensus(
    raw: object,
    corpus_domains: list[str] | set[str] | None,
    bias_by_domain: dict[str, str] | None = None,
) -> ConsensusPayload:
    """Transforme la sortie LLM brute en contrat `consensus` servable.

    Renvoie toujours un payload : `state="unavailable"` quand rien n'est
    exploitable (appel raté, constats tous hors corpus). L'appelant persiste
    alors un échec **définitif** plutôt que de laisser le Reader afficher
    « analyse en cours » indéfiniment.
    """
    corpus = {
        domain
        for domain in (normalize_domain(d) for d in (corpus_domains or []))
        if domain
    }
    payload = raw if isinstance(raw, dict) else {}

    agreements = _normalize_statements(
        payload.get("agreements"), corpus, CONSENSUS_MAX_AGREEMENTS
    )
    disagreements = _normalize_statements(
        payload.get("disagreements"), corpus, CONSENSUS_MAX_DISAGREEMENTS
    )
    state = (
        CONSENSUS_STATE_AVAILABLE
        if (agreements or disagreements)
        else CONSENSUS_STATE_UNAVAILABLE
    )

    return ConsensusPayload(
        state=state,
        qualifier=compute_angle_qualifier(disagreements, bias_by_domain, state=state),
        agreements=agreements,
        disagreements=disagreements,
        cta=ConsensusCta(
            agreement=_resolve_cta(payload.get("cta_agreement"), agreements),
            disagreement=_resolve_cta(payload.get("cta_disagreement"), disagreements),
        ),
    )


def coerce_analysis_text(raw: object) -> str | None:
    """Ramène le champ `analysis` du LLM à une string plate.

    Round 3 fix (Sentry PYTHON-R) : le modèle peut renvoyer un dict imbriqué
    (ex: {"contexte": "...", "liens": [...]}) au lieu d'une string. Pydantic
    rejette → 500 sur /digest/both.
    """
    if raw is None or isinstance(raw, str):
        return raw
    if isinstance(raw, dict):
        return json.dumps(raw, ensure_ascii=False)
    return str(raw)


# --------------------------------------------------------------------------- #
# Service au Reader (Story 35.2) — tout ce qui suit décide de ce que VOIT un  #
# utilisateur donné : gates d'affichage dérivées du corpus servi, et choix    #
# des ≤ 2 logos par constat (suivies > notoriété, biais opposés sur un        #
# désaccord). Rien ici n'est persisté : `source_domains` reste exhaustif en   #
# base, la sélection se rejoue à chaque requête.                              #
# --------------------------------------------------------------------------- #

# 2 logos max par constat (hand-off 6C) ; « +N » au-delà.
CONSENSUS_DISPLAY_DOMAINS_MAX = 2


def compute_display_gates(coverage_count: int) -> dict:
    """Gates d'affichage 6C, dérivées du `coverage_count` **servi** (D5).

    Le front applique, ne dérive pas — c'est le même `coverage_count` que
    « Comparer les N angles » et « N médias en parlent ». Seuils du hand-off :
    1 média → ni CTA ni barre ni carrousel ; 2 → CTA + carrousel sans carte
    IA ; 3+ → rendu complet. Volontairement indépendantes de l'analyse : une
    analyse absente ne fait jamais disparaître le carrousel.
    """
    count = max(0, int(coverage_count or 0))
    return {
        "is_solo": count <= 1,
        "has_cta": count >= 2,
        "has_cards": count >= 2,
        "has_ai_card": count >= 3,
        "has_bar": count >= 3,
    }


def _domain_side(stance: str | None) -> str | None:
    if stance in _LEFT_STANCES:
        return "left"
    if stance in _RIGHT_STANCES:
        return "right"
    return None


def pick_display_domains(
    source_domains: list[str],
    *,
    followed: frozenset[str] | set[str] = frozenset(),
    notoriety: Mapping[str, tuple[int, bool]] | None = None,
    bias_by_domain: Mapping[str, str] | None = None,
    opposing: bool = False,
) -> list[str]:
    """Les ≤ 2 domaines affichés pour ce constat, pour cet utilisateur (D3).

    Ordre : sources suivies d'abord, puis notoriété — nombre de followers
    (`count(user_sources)`) puis `is_curated`, puis ordre du constat (stable).
    `source_tier` est explicitement écarté (E8 : faux signal).

    Sur un **désaccord** (`opposing=True`), si les domaines candidats couvrent
    les deux côtés du spectre, on force un domaine de chaque côté (le
    meilleur-classé de chacun) : montrer le désaccord porté par deux médias du
    même bord raconterait une fausse symétrie.
    """
    notoriety = notoriety or {}
    bias_by_domain = bias_by_domain or {}

    def rank(item: tuple[int, str]) -> tuple:
        index, domain = item
        followers, is_curated = notoriety.get(domain, (0, False))
        return (domain not in followed, -followers, not is_curated, index)

    ordered = [d for _, d in sorted(enumerate(source_domains), key=rank)]
    if len(ordered) <= CONSENSUS_DISPLAY_DOMAINS_MAX:
        return ordered

    if opposing:
        by_side: dict[str, str] = {}
        for domain in ordered:
            side = _domain_side(bias_by_domain.get(domain))
            if side and side not in by_side:
                by_side[side] = domain
        if len(by_side) == 2:
            picked = [d for d in ordered if d in by_side.values()]
            return picked[:CONSENSUS_DISPLAY_DOMAINS_MAX]

    return ordered[:CONSENSUS_DISPLAY_DOMAINS_MAX]


def _serve_statement(
    statement: Mapping,
    *,
    followed: frozenset[str] | set[str],
    notoriety: Mapping[str, tuple[int, bool]] | None,
    bias_by_domain: Mapping[str, str] | None,
    opposing: bool,
) -> dict | None:
    text = statement.get("text")
    if not isinstance(text, str) or not text:
        return None
    domains = [
        d for d in (statement.get("source_domains") or []) if isinstance(d, str) and d
    ]
    # `support_count` a été recalculé à l'écriture (= |domaines ∩ corpus|) ;
    # on le resserre sur la liste réellement portée par la ligne, jamais plus.
    support_count = min(
        int(statement.get("support_count") or len(domains)), len(domains)
    )
    return {
        "text": text,
        "support_count": support_count,
        "display_domains": pick_display_domains(
            domains,
            followed=followed,
            notoriety=notoriety,
            bias_by_domain=bias_by_domain,
            opposing=opposing,
        ),
        # « +N » seulement au-delà de 2 sources (hand-off) — jamais négatif.
        "plus_count": max(0, support_count - CONSENSUS_DISPLAY_DOMAINS_MAX),
    }


def empty_consensus_block(state: str) -> dict:
    """Bloc `consensus` servi quand il n'y a rien à montrer (pending/unavailable).

    Toujours la même forme que le cas nominal : le front 6C ne doit jamais
    avoir à distinguer « clé absente » de « liste vide ». Pas de qualificatif
    hors `available` — on ne qualifie pas un débat qu'on n'a pas lu.
    """
    return {
        "state": state,
        "qualifier": None,
        "agreements": [],
        "disagreements": [],
        "cta": {"agreement": None, "disagreement": None},
        "generated_at": None,
    }


def serve_consensus_block(
    stored: Mapping,
    *,
    generated_at: str | None,
    followed: frozenset[str] | set[str] = frozenset(),
    notoriety: Mapping[str, tuple[int, bool]] | None = None,
    bias_by_domain: Mapping[str, str] | None = None,
) -> dict:
    """Le JSONB `coverage_analyses.consensus` → le bloc servi à CET utilisateur.

    La partie invariante (textes, `support_count`, plafonds) vient de la ligne ;
    la partie par-user (`display_domains`, donc l'ordre des logos) est résolue
    ici et n'est **jamais** mise en cache partagé ni persistée.
    """

    def _serve_list(raw: object, *, limit: int, opposing: bool) -> list[dict]:
        served = []
        for item in raw if isinstance(raw, list) else []:
            if not isinstance(item, Mapping):
                continue
            statement = _serve_statement(
                item,
                followed=followed,
                notoriety=notoriety,
                bias_by_domain=bias_by_domain,
                opposing=opposing,
            )
            if statement is not None:
                served.append(statement)
        return served[:limit]

    def _serve_cta(raw: object, *, opposing: bool) -> dict | None:
        if not isinstance(raw, Mapping):
            return None
        return _serve_statement(
            raw,
            followed=followed,
            notoriety=notoriety,
            bias_by_domain=bias_by_domain,
            opposing=opposing,
        )

    cta = stored.get("cta") if isinstance(stored.get("cta"), Mapping) else {}
    qualifier = stored.get("qualifier")
    return {
        "state": CONSENSUS_STATE_AVAILABLE,
        "qualifier": qualifier if isinstance(qualifier, str) else None,
        "agreements": _serve_list(
            stored.get("agreements"), limit=CONSENSUS_MAX_AGREEMENTS, opposing=False
        ),
        "disagreements": _serve_list(
            stored.get("disagreements"),
            limit=CONSENSUS_MAX_DISAGREEMENTS,
            opposing=True,
        ),
        "cta": {
            "agreement": _serve_cta(cta.get("agreement"), opposing=False),
            "disagreement": _serve_cta(cta.get("disagreement"), opposing=True),
        },
        "generated_at": generated_at,
    }
