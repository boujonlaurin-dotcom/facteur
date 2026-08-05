"""Regression: pas de N+1 sur PerspectiveService.search_internal_perspectives /
build_cluster_perspectives — origine du ralentissement de la bottom-sheet
"Autres regards" remonté par le monitoring (13 utilisateurs touchés).

Avant fix : la boucle appelait `resolve_bias(domain)` par perspective →
2 requêtes ILIKE additionnelles sur `sources` par perspective.
Après fix : `Content.source` est eager-loadé (selectinload) et le bias est
lu directement sur la ligne `Source` déjà en mémoire.
"""

from __future__ import annotations

import json
from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
from uuid import uuid4

import pytest
from sqlalchemy import event
from sqlalchemy.orm import selectinload

from app.models.content import Content
from app.models.enums import BiasStance, ContentType, ReliabilityScore, SourceType
from app.models.source import Source
from app.services.perspective_service import PerspectiveService


class _QueryCounter:
    """Compteur de requêtes SQL émises via une connexion sync_engine."""

    def __init__(self) -> None:
        self.count = 0

    def _on_execute(self, conn, cursor, statement, parameters, context, executemany):
        # On ignore les SAVEPOINT / RELEASE / ROLLBACK posés par la fixture
        # db_session (transaction de test + savepoints).
        upper = statement.lstrip().upper()
        if upper.startswith(("SAVEPOINT", "RELEASE", "ROLLBACK")):
            return
        self.count += 1

    def attach(self, sync_conn):
        event.listen(sync_conn, "before_cursor_execute", self._on_execute)

    def detach(self, sync_conn):
        event.remove(sync_conn, "before_cursor_execute", self._on_execute)


async def _make_source(db_session, *, name: str, url: str, bias: BiasStance) -> Source:
    src = Source(
        id=uuid4(),
        name=name,
        url=url,
        feed_url=f"https://feed.example/{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_active=True,
        is_curated=False,
        bias_stance=bias,
    )
    db_session.add(src)
    await db_session.commit()
    return src


async def _make_source_full(
    db_session,
    *,
    name: str,
    url: str,
    bias: BiasStance,
    reliability: ReliabilityScore,
) -> Source:
    """Comme [_make_source] mais avec `reliability_score` explicite.

    `_parse_rss` résout biais ET fiabilité : laisser la fiabilité à "unknown"
    ferait retomber `resolve_reliability` sur une requête par domaine et
    masquerait l'effet du préchargement.
    """
    src = Source(
        id=uuid4(),
        name=name,
        url=url,
        feed_url=f"https://feed.example/{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_active=True,
        is_curated=False,
        bias_stance=bias,
        reliability_score=reliability,
    )
    db_session.add(src)
    await db_session.commit()
    return src


async def _make_content(
    db_session,
    source: Source,
    *,
    title: str,
    url: str,
    entity_name: str,
) -> Content:
    c = Content(
        id=uuid4(),
        source_id=source.id,
        title=title,
        url=url,
        published_at=datetime.now(UTC) - timedelta(hours=1),
        content_type=ContentType.ARTICLE,
        guid=str(uuid4()),
        entities=[json.dumps({"name": entity_name, "type": "PERSON"})],
        topics=["politics"],
    )
    db_session.add(c)
    await db_session.commit()
    return c


@pytest.mark.asyncio
async def test_search_internal_perspectives_no_n_plus_one(db_session, monkeypatch):
    """Le code path interne ne doit PAS émettre une requête par perspective.

    Avec 5 perspectives, l'ancien code émettait 1 + 5×2 = 11 requêtes
    (1 SELECT Content + 5 × 2 ILIKE sur Source). Après fix : 2 requêtes
    fixes (SELECT Content + selectinload Source), peu importe le nombre.
    """
    # Désactive le post-filtre de cohérence pour garder le titre & topics
    # simples — on cible le compteur de requêtes, pas la logique de filtre.
    monkeypatch.setattr(
        "app.services.perspective_service.PERSPECTIVE_FILTER_ENABLED", False
    )

    # Seed source (différente des candidates pour passer le filtre source_id != ...)
    seed_source = await _make_source(
        db_session, name="Seed", url="https://seed.example", bias=BiasStance.UNKNOWN
    )
    seed = SimpleNamespace(
        id=uuid4(),
        title="Affaire Dupont : nouvelle audition",
        url="https://seed.example/article",
        source_id=seed_source.id,
        entities=[json.dumps({"name": "Dupont", "type": "PERSON"})],
        topics=["politics"],
    )

    # 5 sources distinctes avec bias variés + 1 article chacune partageant
    # l'entité "Dupont"
    biases = [
        BiasStance.LEFT,
        BiasStance.CENTER_LEFT,
        BiasStance.CENTER,
        BiasStance.CENTER_RIGHT,
        BiasStance.RIGHT,
    ]
    for i, b in enumerate(biases):
        src = await _make_source(
            db_session,
            name=f"Outlet {i}",
            url=f"https://outlet{i}.example",
            bias=b,
        )
        await _make_content(
            db_session,
            src,
            title=f"Dupont {i}",
            url=f"https://outlet{i}.example/a{i}",
            entity_name="Dupont",
        )

    service = PerspectiveService(db=db_session)

    counter = _QueryCounter()
    sync_conn = await db_session.connection()
    raw_conn = sync_conn.sync_connection
    counter.attach(raw_conn)
    try:
        perspectives = await service.search_internal_perspectives(seed)
    finally:
        counter.detach(raw_conn)

    # 5 perspectives attendues, une par source/bias
    assert len(perspectives) == 5
    biases_returned = {p.bias_stance for p in perspectives}
    assert biases_returned == {"left", "center-left", "center", "center-right", "right"}

    # Garde-fou N+1 : on tolère ≤ 3 requêtes (SELECT Content + selectinload Source
    # + éventuelle requête de BEGIN du savepoint). L'ancien code en émettait ≥ 11.
    assert counter.count <= 3, (
        f"N+1 régression: {counter.count} requêtes émises pour 5 perspectives "
        "(attendu ≤ 3 — selectinload doit éviter les ILIKE par perspective)"
    )


@pytest.mark.asyncio
async def test_build_cluster_perspectives_no_db_hit_when_source_preloaded(
    db_session,
):
    """build_cluster_perspectives ne doit pas toucher la DB quand la source
    est déjà eager-loadée par l'appelant (cas réel : pipeline éditorial +
    _load_cluster_articles_for_representative)."""
    src_a = await _make_source(
        db_session,
        name="Le Monde",
        url="https://lemonde.fr",
        bias=BiasStance.CENTER_LEFT,
    )
    src_b = await _make_source(
        db_session,
        name="Le Figaro",
        url="https://lefigaro.fr",
        bias=BiasStance.CENTER_RIGHT,
    )
    c_a = await _make_content(
        db_session, src_a, title="Titre A", url="https://lemonde.fr/a", entity_name="X"
    )
    c_b = await _make_content(
        db_session, src_b, title="Titre B", url="https://lefigaro.fr/b", entity_name="X"
    )

    # Recharger avec selectinload, comme le fait l'appelant prod
    from sqlalchemy import select

    stmt = (
        select(Content)
        .options(selectinload(Content.source))
        .where(Content.id.in_([c_a.id, c_b.id]))
    )
    result = await db_session.execute(stmt)
    contents = list(result.scalars().all())
    assert len(contents) == 2

    service = PerspectiveService(db=db_session)

    counter = _QueryCounter()
    sync_conn = await db_session.connection()
    raw_conn = sync_conn.sync_connection
    counter.attach(raw_conn)
    try:
        perspectives = await service.build_cluster_perspectives(contents)
    finally:
        counter.detach(raw_conn)

    assert len(perspectives) == 2
    stances = {p.bias_stance for p in perspectives}
    assert stances == {"center-left", "center-right"}
    # 0 requête attendue : tout est déjà en mémoire.
    assert counter.count == 0, (
        f"N+1 régression: build_cluster_perspectives a émis {counter.count} requêtes "
        "alors que Content.source était pré-chargé."
    )


# --- PYTHON-50 : N+1 sur le parsing du flux RSS Google News --------------------
#
# Chemin DISTINCT de celui couvert plus haut (#806, perspectives internes) :
# `_parse_rss` résout le biais / la fiabilité par DOMAINE, pas via une relation
# `Content.source` eager-loadable. Sans préchargement, chaque item RSS émet 1-2
# SELECT ILIKE sur `sources`.

# Domaines volontairement absents de DOMAIN_BIAS_MAP : la map en dur court-circuite
# `resolve_bias` avant tout accès DB et masquerait le N+1 qu'on veut mesurer.
_RSS_DOMAINS = [
    "journal-alpha.example",
    "journal-bravo.example",
    "journal-charlie.example",
    "journal-delta.example",
    "journal-echo.example",
]


def _rss_with_sources(domains: list[str]) -> bytes:
    items = "".join(
        f"""
        <item>
          <title>Titre {i} - Journal {i}</title>
          <link>https://{d}/article-{i}</link>
          <source url="https://{d}/">Journal {i}</source>
          <pubDate>Tue, 04 Aug 2026 10:00:00 GMT</pubDate>
        </item>"""
        for i, d in enumerate(domains)
    )
    return f"<rss><channel>{items}</channel></rss>".encode()


@pytest.mark.asyncio
async def test_parse_rss_prefetches_source_attributes_in_one_query(db_session):
    """`_parse_rss` ne doit pas émettre 1-2 SELECT Source par item RSS.

    Avant fix : 5 items → jusqu'à 10 requêtes ILIKE (resolve_bias +
    resolve_reliability par domaine). Après : 1 requête de préchargement,
    puis tout est servi depuis `_bias_cache` / `_reliability_cache`.
    """
    for i, domain in enumerate(_RSS_DOMAINS):
        await _make_source_full(
            db_session,
            name=f"Journal {i}",
            url=f"https://{domain}/",
            bias=BiasStance.CENTER,
            reliability=ReliabilityScore.HIGH,
        )

    service = PerspectiveService(db=db_session)
    content = _rss_with_sources(_RSS_DOMAINS)

    counter = _QueryCounter()
    sync_conn = await db_session.connection()
    raw_conn = sync_conn.sync_connection
    counter.attach(raw_conn)
    try:
        perspectives = await service._parse_rss(content)
    finally:
        counter.detach(raw_conn)

    assert len(perspectives) == 5
    assert {p.bias_stance for p in perspectives} == {"center"}

    # 1 requête de préchargement attendue. On tolère 2 (BEGIN du savepoint) ;
    # l'ancien code en émettait jusqu'à 10.
    assert counter.count <= 2, (
        f"N+1 régression: _parse_rss a émis {counter.count} requêtes pour 5 items "
        "(attendu ≤ 2 — le préchargement doit éviter les ILIKE par item)"
    )


@pytest.mark.asyncio
async def test_prefetch_preserves_resolve_semantics(db_session):
    """Le préchargement doit donner EXACTEMENT ce que `resolve_*` aurait renvoyé.

    C'est l'invariant qui rend le fix sûr : il duplique la logique de
    `_resolve_source_column` (lookup par URL sur source active), donc on compare
    les deux chemins domaine par domaine sur les cas qui divergent le plus.
    """
    # 1 seule source active → le préchargement doit remplir le cache.
    await _make_source_full(
        db_session,
        name="Unique",
        url="https://unique-match.example/",
        bias=BiasStance.LEFT,
        reliability=ReliabilityScore.HIGH,
    )
    # 2 sources actives matchent le même domaine → `scalar_one_or_none` lèverait,
    # et `_resolve_source_column` retombe sur "unknown". Le préchargement doit
    # reproduire ce "unknown" (et NON piocher l'une des deux au hasard).
    for suffix in ("a", "b"):
        await _make_source_full(
            db_session,
            name=f"Double {suffix}",
            url=f"https://double-match.example/{suffix}",
            bias=BiasStance.RIGHT,
            reliability=ReliabilityScore.LOW,
        )

    cases = ["unique-match.example", "double-match.example", "absent.example"]

    # Chemin de référence : resolve_* sans préchargement, un service par cas
    # pour repartir d'un cache vide.
    expected = {}
    for domain in cases:
        ref = PerspectiveService(db=db_session)
        expected[domain] = (
            await ref.resolve_bias(domain),
            await ref.resolve_reliability(domain),
        )

    # Chemin préchargé.
    warmed = PerspectiveService(db=db_session)
    await warmed._prefetch_source_attributes(cases)
    actual = {
        domain: (
            await warmed.resolve_bias(domain),
            await warmed.resolve_reliability(domain),
        )
        for domain in cases
    }

    assert actual == expected, (
        f"Le préchargement diverge de resolve_* : attendu {expected}, obtenu {actual}"
    )
    # Garde-fou explicite sur les deux cas limites.
    assert expected["double-match.example"] == ("unknown", "unknown")
    assert expected["absent.example"] == ("unknown", "unknown")
