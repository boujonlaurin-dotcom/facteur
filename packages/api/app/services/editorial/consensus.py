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
