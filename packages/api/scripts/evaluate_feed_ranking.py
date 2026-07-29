"""Jauge CTR hors-ligne du ranking digest / feed.

Le script lit les `daily_digest.items` persistés et les joint à
`user_content_status` + `contents`. Il rapporte le CTR par rang, sujet, entité,
slot et bande de score.

Deux choses le distinguent de sa version initiale, et ce sont les deux raisons
pour lesquelles il ne produisait rien :

1. **Le format de prod est lu.** 97 % des digests des 60 derniers jours sont en
   `editorial_v3` (`items.subjects[]`), format que l'ancienne requête ignorait —
   elle ne connaissait que `flat_v1` (`items` = tableau) et `topics_v1`
   (`items.topics[]`). Les trois formats sont désormais unis, avec le rang de
   sujet, le libellé de sujet et le **slot** (`actu` vs `extra`).

2. **Le dénominateur ne dépend plus de `last_impressed_at`.** Cette colonne
   n'est écrite qu'au pull-to-refresh et au « déjà vu » manuel : ce n'est ni une
   impression ni une position. Le dénominateur est maintenant explicite
   (`--denominator`) et les **trois valeurs sont publiées côte à côte** pour que
   la dilution soit visible au lieu d'être masquée :

   - `all` — tout slot livré compte. Mesure la distribution, pas la pertinence :
     94 % des digests générés n'ont jamais eu un seul article consommé.
   - `engaged` — ne compte que les slots des digests avec ≥ 1 article consommé.
     Circulaire : l'article consommé se conditionne lui-même.
   - `engaged-loo` (**défaut**) — compte l'article *i* seulement si son digest a
     ≥ 1 consommé **autre que *i***. Dé-circularise le conditionnement.

`digest_completions` est **explicitement rejeté** comme conditionneur : 0 ligne
sur 60 j (58 all-time, dernière le 2026-05-10) **et** circulaire par
construction (inséré à `consumed/total >= 0,8` ⇒ CTR ≈ 100 % garanti).
`morning_ritual_opened` ne couvre que 2,5 % des digests ⇒ tranche de robustesse,
pas filtre.

Biais connus, écrits dans l'en-tête du rapport plutôt que maquillés :

- les `extra_actu_articles` **ne sont jamais scorés** (tri `(thumbnail,
  published_at)` dans `actu_matcher`) ⇒ leur `score` restera `null` ;
- la persistance des scores est **forward-only** ⇒ les bandes de score sont
  vides avant la date de merge. CTR par sujet / entité / rang de sujet est en
  revanche rétroactif sur tout l'historique `editorial_v3`.

Usage :
    cd packages/api
    PYTHONPATH=. python scripts/evaluate_feed_ranking.py --days 30
    PYTHONPATH=. python scripts/evaluate_feed_ranking.py --days 30 --tag pr1-before
    PYTHONPATH=. python scripts/evaluate_feed_ranking.py --compare \\
        ../../.context/feed-ranking-pr1-before-2026-07-29.json \\
        ../../.context/feed-ranking-pr1-after-2026-08-05.json

Sorties :
    .context/feed-ranking-<tag>-<date>.json  (machine, consommé par --compare)
    .context/feed-ranking-<tag>-<date>.md    (lisible humain)
"""

from __future__ import annotations

import argparse
import asyncio
import datetime as dt
import json
import os
import sys
from collections import defaultdict
from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

REPO_ROOT = Path(__file__).resolve().parents[3]
CONTEXT_DIR = REPO_ROOT / ".context"

PILLARS = ("pertinence", "source", "fraicheur", "qualite")

DENOMINATORS = ("all", "engaged", "engaged-loo")
DEFAULT_DENOMINATOR = "engaged-loo"

DENOMINATOR_HELP = {
    "all": "tout slot livré (mesure la distribution, pas la pertinence)",
    "engaged": "slots des digests avec >= 1 consommé (circulaire)",
    "engaged-loo": "slots des digests avec >= 1 consommé AUTRE que l'article mesuré",
}


@dataclass
class CtrBucket:
    shown: int = 0
    consumed: int = 0

    def add(self, *, consumed: bool) -> None:
        self.shown += 1
        if consumed:
            self.consumed += 1

    @property
    def ctr(self) -> float:
        if self.shown == 0:
            return 0.0
        return self.consumed / self.shown

    def as_dict(self, key: Any) -> dict[str, Any]:
        return {
            "key": key,
            "shown": self.shown,
            "consumed": self.consumed,
            "ctr": self.ctr,
        }


def _load_env_file(path: Path) -> None:
    if not path.exists():
        return
    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        if key and key not in os.environ:
            os.environ[key] = value.strip().strip('"').strip("'")


def _database_url() -> str:
    _load_env_file(REPO_ROOT / "packages" / "api" / ".env")
    _load_env_file(REPO_ROOT / ".env")

    url = os.environ.get("DATABASE_URL")
    if not url:
        raise SystemExit("DATABASE_URL is required")
    if url.startswith("postgres://"):
        return "postgresql+psycopg://" + url.removeprefix("postgres://")
    if url.startswith("postgresql://"):
        return "postgresql+psycopg://" + url.removeprefix("postgresql://")
    return url


def _parse_date(value: str | None) -> dt.datetime | None:
    if not value:
        return None
    parsed = dt.datetime.fromisoformat(value)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.UTC)
    return parsed.astimezone(dt.UTC)


def _coerce_json_object(value: Any) -> dict[str, Any]:
    if isinstance(value, dict):
        return value
    if isinstance(value, str) and value.strip():
        try:
            parsed = json.loads(value)
        except json.JSONDecodeError:
            return {}
        return parsed if isinstance(parsed, dict) else {}
    return {}


def _entity_name(raw: Any) -> str | None:
    value = raw
    if isinstance(raw, str):
        stripped = raw.strip()
        if not stripped:
            return None
        if stripped.startswith("{"):
            try:
                value = json.loads(stripped)
            except json.JSONDecodeError:
                value = stripped
        else:
            value = stripped

    if isinstance(value, dict):
        name = (
            value.get("canonical")
            or value.get("canonical_name")
            or value.get("name")
            or value.get("text")
        )
    else:
        name = value

    if not isinstance(name, str):
        return None
    normalized = " ".join(name.strip().split())
    return normalized or None


def _entity_names(raw_entities: Iterable[Any] | None) -> list[str]:
    seen: set[str] = set()
    names: list[str] = []
    for raw in raw_entities or []:
        name = _entity_name(raw)
        if not name:
            continue
        key = name.casefold()
        if key in seen:
            continue
        seen.add(key)
        names.append(name)
    return names


def _topic_slugs(raw_topics: Iterable[Any] | None) -> list[str]:
    seen: set[str] = set()
    topics: list[str] = []
    for raw in raw_topics or []:
        if not isinstance(raw, str):
            continue
        topic = raw.strip().lower()
        if not topic or topic in seen:
            continue
        seen.add(topic)
        topics.append(topic)
    return topics


def _score_band(score: Any, step: int = 20) -> str:
    if not isinstance(score, int | float):
        return "missing"
    if score < 0:
        return "<0"
    if score >= 100:
        return "100+"
    low = int(score // step) * step
    return f"{low:02d}-{low + step:02d}"


def _pct(value: float) -> str:
    return f"{value * 100:.1f}%"


# ---------------------------------------------------------------------------
# Dénominateur
# ---------------------------------------------------------------------------


def consumed_counts_by_digest(rows: Iterable[dict[str, Any]]) -> dict[str, int]:
    """Pré-passe : nombre d'articles consommés par digest.

    C'est la seule information nécessaire aux trois dénominateurs — le
    leave-one-out se déduit en retranchant l'article courant.
    """
    counts: defaultdict[str, int] = defaultdict(int)
    for row in rows:
        if _is_consumed(row):
            counts[str(row.get("digest_id"))] += 1
    return dict(counts)


def _is_consumed(row: dict[str, Any]) -> bool:
    return str(row.get("status") or "").lower() == "consumed"


def is_counted(
    row: dict[str, Any],
    *,
    denominator: str,
    consumed_by_digest: dict[str, int],
) -> bool:
    """Le slot entre-t-il au dénominateur ?

    - `all` : toujours.
    - `engaged` : son digest a >= 1 consommé.
    - `engaged-loo` : son digest a >= 1 consommé **autre que lui**. Un digest à
      un seul article consommé ne contribue donc rien (cas limite : l'article
      consommé lui-même est exclu).
    """
    if denominator == "all":
        return True
    total = consumed_by_digest.get(str(row.get("digest_id")), 0)
    if denominator == "engaged":
        return total >= 1
    if denominator == "engaged-loo":
        return total - (1 if _is_consumed(row) else 0) >= 1
    raise ValueError(f"unknown denominator: {denominator}")


# ---------------------------------------------------------------------------
# Métriques
# ---------------------------------------------------------------------------


def _by_shown_desc(item: tuple[Any, CtrBucket]) -> tuple[int, float, str]:
    return (-item[1].shown, -item[1].ctr, str(item[0]).casefold())


def _by_key_asc(item: tuple[Any, CtrBucket]) -> Any:
    return item[0]


def _by_band(item: tuple[Any, CtrBucket]) -> tuple[bool, str]:
    return (item[0] == "missing", str(item[0]))


def _bucket_rows(
    buckets: dict[Any, CtrBucket],
    *,
    min_shown: int,
    top: int | None,
    sort_key,
) -> list[dict[str, Any]]:
    ordered = sorted(buckets.items(), key=sort_key)
    kept = [bucket.as_dict(key) for key, bucket in ordered if bucket.shown >= min_shown]
    if top is not None:
        kept = kept[:top]
    return kept


def build_metrics(
    *,
    rows: list[dict[str, Any]],
    denominator: str = DEFAULT_DENOMINATOR,
    min_shown: int = 5,
    top: int = 25,
) -> dict[str, Any]:
    """Agrège les lignes en métriques CTR. Pur Python — ni DB ni réseau."""
    if denominator not in DENOMINATORS:
        raise ValueError(f"unknown denominator: {denominator}")

    consumed_by_digest = consumed_counts_by_digest(rows)

    # Les trois dénominateurs sont toujours calculés : publier le seul retenu
    # masquerait la dilution que ce script est censé rendre visible.
    all_denominators = {name: CtrBucket() for name in DENOMINATORS}

    global_bucket = CtrBucket()
    by_rank: defaultdict[int, CtrBucket] = defaultdict(CtrBucket)
    by_subject_rank: defaultdict[int, CtrBucket] = defaultdict(CtrBucket)
    by_slot: defaultdict[str, CtrBucket] = defaultdict(CtrBucket)
    by_subject: defaultdict[str, CtrBucket] = defaultdict(CtrBucket)
    by_topic: defaultdict[str, CtrBucket] = defaultdict(CtrBucket)
    by_entity: defaultdict[str, CtrBucket] = defaultdict(CtrBucket)
    by_score_band: defaultdict[str, CtrBucket] = defaultdict(CtrBucket)
    by_pillar_band: dict[str, defaultdict[str, CtrBucket]] = {
        pillar: defaultdict(CtrBucket) for pillar in PILLARS
    }

    formats: defaultdict[str, dict[str, Any]] = defaultdict(
        lambda: {"slots": 0, "digests": set()}
    )

    skipped = 0
    counted_digest_ids: set[str] = set()
    counted_user_ids: set[str] = set()

    for row in rows:
        consumed = _is_consumed(row)
        fmt = str(row.get("format_version") or "unknown")
        formats[fmt]["slots"] += 1
        formats[fmt]["digests"].add(str(row.get("digest_id")))

        for name, bucket in all_denominators.items():
            if is_counted(row, denominator=name, consumed_by_digest=consumed_by_digest):
                bucket.add(consumed=consumed)

        if not is_counted(
            row, denominator=denominator, consumed_by_digest=consumed_by_digest
        ):
            skipped += 1
            continue

        global_bucket.add(consumed=consumed)
        counted_digest_ids.add(str(row.get("digest_id")))
        counted_user_ids.add(str(row.get("user_id")))

        rank = row.get("rank")
        if isinstance(rank, int):
            by_rank[rank].add(consumed=consumed)

        subject_rank = row.get("topic_rank")
        if isinstance(subject_rank, int):
            by_subject_rank[subject_rank].add(consumed=consumed)

        by_slot[str(row.get("slot") or "unknown")].add(consumed=consumed)

        subject_label = row.get("subject_label")
        if isinstance(subject_label, str) and subject_label.strip():
            by_subject[subject_label.strip()].add(consumed=consumed)

        for topic in _topic_slugs(row.get("topics")):
            by_topic[topic].add(consumed=consumed)

        for entity in _entity_names(row.get("entities")):
            by_entity[entity].add(consumed=consumed)

        by_score_band[_score_band(row.get("final_score"))].add(consumed=consumed)

        pillar_scores = _coerce_json_object(row.get("pillar_scores"))
        for pillar in PILLARS:
            by_pillar_band[pillar][_score_band(pillar_scores.get(pillar))].add(
                consumed=consumed
            )

    return {
        "denominator": denominator,
        "denominators": {
            name: bucket.as_dict(name) for name, bucket in all_denominators.items()
        },
        "rows_fetched": len(rows),
        "rows_skipped": skipped,
        "digests_counted": len(counted_digest_ids),
        "users_counted": len(counted_user_ids),
        "global": global_bucket.as_dict("global"),
        "format_versions": [
            {
                "key": fmt,
                "slots": payload["slots"],
                "digests": len(payload["digests"]),
            }
            for fmt, payload in sorted(
                formats.items(), key=lambda item: -item[1]["slots"]
            )
        ],
        "by_rank": _bucket_rows(
            by_rank, min_shown=min_shown, top=None, sort_key=_by_key_asc
        ),
        "by_subject_rank": _bucket_rows(
            by_subject_rank, min_shown=min_shown, top=None, sort_key=_by_key_asc
        ),
        "by_slot": _bucket_rows(by_slot, min_shown=1, top=None, sort_key=_by_key_asc),
        "by_subject": _bucket_rows(
            by_subject, min_shown=min_shown, top=top, sort_key=_by_shown_desc
        ),
        "by_topic": _bucket_rows(
            by_topic, min_shown=min_shown, top=top, sort_key=_by_shown_desc
        ),
        "by_entity": _bucket_rows(
            by_entity, min_shown=min_shown, top=top, sort_key=_by_shown_desc
        ),
        "by_score_band": _bucket_rows(
            by_score_band, min_shown=1, top=None, sort_key=_by_band
        ),
        "by_pillar_band": {
            pillar: _bucket_rows(
                by_pillar_band[pillar], min_shown=1, top=None, sort_key=_by_band
            )
            for pillar in PILLARS
        },
    }


# ---------------------------------------------------------------------------
# Rendu
# ---------------------------------------------------------------------------


def _render_table(rows: list[dict[str, Any]], *, key_label: str) -> list[str]:
    if not rows:
        return ["_Aucune ligne au-dessus du seuil._"]
    lines = [
        f"| {key_label} | shown | consumed | CTR |",
        f"| {'-' * len(key_label)} | ---: | ---: | ---: |",
    ]
    for row in rows:
        lines.append(
            f"| {row['key']} | {row['shown']} | {row['consumed']} | "
            f"{_pct(row['ctr'])} |"
        )
    return lines


def render_report(
    metrics: dict[str, Any],
    *,
    since: dt.datetime,
    until: dt.datetime,
    mode: str | None,
    include_serene: bool,
    tag: str,
    row_limit_hit: bool,
) -> str:
    generated_at = dt.datetime.now(dt.UTC).strftime("%Y-%m-%d %H:%M:%SZ")
    denominator = metrics["denominator"]
    lines = [
        f"# Jauge CTR ranking feed / digest — {generated_at}",
        "",
        f"- Tag : `{tag}`",
        f"- Fenêtre : {since.isoformat()} -> {until.isoformat()}",
        f"- Mode : {mode or 'tous'}",
        f"- Digests sereins inclus : {'oui' if include_serene else 'non'}",
        f"- Slots lus : {metrics['rows_fetched']}",
        f"- **Dénominateur retenu : `{denominator}`** "
        f"({DENOMINATOR_HELP[denominator]})",
        f"- Slots écartés par ce dénominateur : {metrics['rows_skipped']}",
        f"- Digests comptés : {metrics['digests_counted']} · "
        f"users comptés : {metrics['users_counted']}",
        "",
    ]

    if row_limit_hit:
        lines.extend(
            [
                "> ⚠️ **`--row-limit` atteint** : la fenêtre est tronquée aux slots "
                "les plus récents. Les chiffres ci-dessous ne couvrent pas toute la "
                "période demandée — relancer avec un `--row-limit` plus haut.",
                "",
            ]
        )

    lines.extend(
        [
            "## Les 3 dénominateurs côte à côte",
            "",
            "Publiés ensemble volontairement : le CTR `all` mesure la "
            "distribution (la grande majorité des digests générés n'a jamais eu "
            "un seul article consommé), pas la pertinence du ranking.",
            "",
            "| dénominateur | slots | consommés | CTR | lecture |",
            "| --- | ---: | ---: | ---: | --- |",
        ]
    )
    for name in DENOMINATORS:
        bucket = metrics["denominators"][name]
        marker = " **(retenu)**" if name == denominator else ""
        lines.append(
            f"| `{name}`{marker} | {bucket['shown']} | {bucket['consumed']} | "
            f"{_pct(bucket['ctr'])} | {DENOMINATOR_HELP[name]} |"
        )

    lines.extend(
        [
            "",
            "`digest_completions` est rejeté comme conditionneur : 0 ligne sur "
            "60 j **et** circulaire par construction (inséré à "
            "`consumed/total >= 0,8`).",
            "",
            "## Formats de digest lus",
            "",
            "Un format absent de ce tableau n'est **pas** parsé par la requête : "
            "c'est le symptôme qui a rendu cette jauge muette pendant des mois.",
            "",
            "| format_version | slots | digests |",
            "| --- | ---: | ---: |",
        ]
    )
    for entry in metrics["format_versions"]:
        lines.append(f"| `{entry['key']}` | {entry['slots']} | {entry['digests']} |")

    global_bucket = metrics["global"]
    lines.extend(
        [
            "",
            f"## CTR global ({denominator})",
            "",
            f"{global_bucket['consumed']}/{global_bucket['shown']} = "
            f"**{_pct(global_bucket['ctr'])}**",
            "",
            "## CTR par rang de sujet (editorial_v3)",
            "",
        ]
    )
    lines.extend(_render_table(metrics["by_subject_rank"], key_label="rang de sujet"))

    lines.extend(["", "## CTR par slot", ""])
    lines.extend(
        [
            "`actu` = représentant scoré du sujet · `extra` = articles "
            "complémentaires, **jamais scorés** (tri thumbnail/date) · `flat` / "
            "`topic` = formats legacy.",
            "",
        ]
    )
    lines.extend(_render_table(metrics["by_slot"], key_label="slot"))

    lines.extend(["", "## CTR par rang d'article", ""])
    lines.extend(_render_table(metrics["by_rank"], key_label="rang"))

    lines.extend(["", "## CTR par sujet", ""])
    lines.extend(_render_table(metrics["by_subject"], key_label="sujet"))

    lines.extend(["", "## CTR par topic", ""])
    lines.extend(_render_table(metrics["by_topic"], key_label="topic"))

    lines.extend(["", "## CTR par entité", ""])
    lines.extend(_render_table(metrics["by_entity"], key_label="entité"))

    lines.extend(
        [
            "",
            "## CTR par bande de score",
            "",
            "**Forward-only** : `score` et `pillar_scores` ne sont persistés que "
            "depuis leur mise en production. Une bande `missing` massive sur une "
            "fenêtre ancienne est attendue, pas un bug. Les `extra_actu_articles` "
            "resteront `missing` pour toujours (jamais scorés).",
            "",
            "### Score final",
            "",
        ]
    )
    lines.extend(_render_table(metrics["by_score_band"], key_label="bande"))

    for pillar in PILLARS:
        lines.extend(["", f"### Pilier {pillar}", ""])
        lines.extend(
            _render_table(metrics["by_pillar_band"][pillar], key_label="bande")
        )

    return "\n".join(lines).rstrip() + "\n"


def _bucket_index(rows: list[dict[str, Any]]) -> dict[Any, dict[str, Any]]:
    return {row["key"]: row for row in rows}


def render_compare(baseline: dict[str, Any], after: dict[str, Any]) -> str:
    """Comparatif baseline ↔ after, en miroir des harnais frères."""
    lines = [
        "# Comparaison baseline ↔ after — jauge ranking",
        "",
        f"Dénominateur baseline = `{baseline['metrics']['denominator']}` · "
        f"after = `{after['metrics']['denominator']}`",
        "",
    ]
    if baseline["metrics"]["denominator"] != after["metrics"]["denominator"]:
        lines.extend(
            [
                "> ⚠️ Dénominateurs différents : les CTR ne sont pas comparables.",
                "",
            ]
        )

    b_global = baseline["metrics"]["global"]
    a_global = after["metrics"]["global"]
    lines.extend(
        [
            "| Métrique | baseline | after | Δ |",
            "| --- | ---: | ---: | ---: |",
            f"| slots | {b_global['shown']} | {a_global['shown']} | "
            f"{a_global['shown'] - b_global['shown']:+d} |",
            f"| consommés | {b_global['consumed']} | {a_global['consumed']} | "
            f"{a_global['consumed'] - b_global['consumed']:+d} |",
            f"| CTR global | {_pct(b_global['ctr'])} | {_pct(a_global['ctr'])} | "
            f"{(a_global['ctr'] - b_global['ctr']) * 100:+.1f} pp |",
            "",
            "## CTR par rang de sujet",
            "",
            "| rang | baseline | after | Δ | slots after |",
            "| ---: | ---: | ---: | ---: | ---: |",
        ]
    )
    b_ranks = _bucket_index(baseline["metrics"]["by_subject_rank"])
    a_ranks = _bucket_index(after["metrics"]["by_subject_rank"])
    for key in sorted(set(b_ranks) | set(a_ranks), key=lambda k: (k is None, k)):
        b = b_ranks.get(key)
        a = a_ranks.get(key)
        b_ctr = _pct(b["ctr"]) if b else "-"
        a_ctr = _pct(a["ctr"]) if a else "-"
        delta = f"{(a['ctr'] - b['ctr']) * 100:+.1f} pp" if b and a else "-"
        lines.append(
            f"| {key} | {b_ctr} | {a_ctr} | {delta} | {a['shown'] if a else 0} |"
        )

    lines.extend(
        [
            "",
            "## CTR par slot",
            "",
            "| slot | baseline | after | Δ | slots after |",
            "| --- | ---: | ---: | ---: | ---: |",
        ]
    )
    b_slots = _bucket_index(baseline["metrics"]["by_slot"])
    a_slots = _bucket_index(after["metrics"]["by_slot"])
    for key in sorted(set(b_slots) | set(a_slots)):
        b = b_slots.get(key)
        a = a_slots.get(key)
        b_ctr = _pct(b["ctr"]) if b else "-"
        a_ctr = _pct(a["ctr"]) if a else "-"
        delta = f"{(a['ctr'] - b['ctr']) * 100:+.1f} pp" if b and a else "-"
        lines.append(
            f"| {key} | {b_ctr} | {a_ctr} | {delta} | {a['shown'] if a else 0} |"
        )

    return "\n".join(lines).rstrip() + "\n"


# ---------------------------------------------------------------------------
# SQL
# ---------------------------------------------------------------------------

SQL = """
WITH digest_scope AS (
    SELECT
        dd.id,
        dd.user_id,
        dd.target_date,
        dd.generated_at,
        dd.mode,
        dd.is_serene,
        dd.format_version,
        dd.items
    FROM daily_digest dd
    WHERE dd.generated_at >= :since
      AND dd.generated_at < :until
      -- CAST explicite : sans lui `--mode` non fourni envoie un NULL non typé
      -- et Postgres refuse la requête (AmbiguousParameter). C'est la deuxième
      -- raison pour laquelle cette jauge ne tournait pas.
      AND (CAST(:mode AS text) IS NULL OR dd.mode = CAST(:mode AS text))
      AND (CAST(:include_serene AS boolean) OR dd.is_serene = false)
),
flat_items AS (
    SELECT
        d.id AS digest_id,
        d.user_id,
        d.target_date,
        d.generated_at,
        d.mode,
        d.is_serene,
        d.format_version,
        item AS item_json,
        NULL::integer AS topic_rank,
        NULL::text AS subject_label,
        'flat'::text AS slot
    FROM digest_scope d
    CROSS JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN jsonb_typeof(d.items) = 'array' THEN d.items
            ELSE '[]'::jsonb
        END
    ) AS item
),
topic_items AS (
    SELECT
        d.id AS digest_id,
        d.user_id,
        d.target_date,
        d.generated_at,
        d.mode,
        d.is_serene,
        d.format_version,
        article_item AS item_json,
        NULLIF(topic_item->>'rank', '')::integer AS topic_rank,
        NULLIF(topic_item->>'label', '') AS subject_label,
        'topic'::text AS slot
    FROM digest_scope d
    CROSS JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN jsonb_typeof(d.items) = 'object'
                THEN COALESCE(d.items->'topics', '[]'::jsonb)
            ELSE '[]'::jsonb
        END
    ) AS topic_item
    CROSS JOIN LATERAL jsonb_array_elements(
        COALESCE(topic_item->'articles', '[]'::jsonb)
    ) AS article_item
),
-- editorial_v1/v2/v3 : `items.subjects[]`, un représentant `actu_article`
-- (scoré) + N `extra_actu_articles` (jamais scorés). C'est 97 % de la prod.
editorial_items AS (
    SELECT
        d.id AS digest_id,
        d.user_id,
        d.target_date,
        d.generated_at,
        d.mode,
        d.is_serene,
        d.format_version,
        art.article_item AS item_json,
        NULLIF(subject_item->>'rank', '')::integer AS topic_rank,
        NULLIF(subject_item->>'label', '') AS subject_label,
        art.slot
    FROM digest_scope d
    CROSS JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN jsonb_typeof(d.items) = 'object'
                THEN COALESCE(d.items->'subjects', '[]'::jsonb)
            ELSE '[]'::jsonb
        END
    ) AS subject_item
    CROSS JOIN LATERAL (
        -- `actu_article` peut être un JSON `null` (sujet sans représentant).
        SELECT
            subject_item->'actu_article' AS article_item,
            'actu'::text AS slot
        WHERE subject_item->'actu_article' IS NOT NULL
          AND subject_item->'actu_article' <> 'null'::jsonb
        UNION ALL
        SELECT extra AS article_item, 'extra'::text AS slot
        FROM jsonb_array_elements(
            CASE
                WHEN jsonb_typeof(subject_item->'extra_actu_articles') = 'array'
                    THEN subject_item->'extra_actu_articles'
                ELSE '[]'::jsonb
            END
        ) AS extra
    ) AS art
),
digest_items AS (
    SELECT * FROM flat_items
    UNION ALL
    SELECT * FROM topic_items
    UNION ALL
    SELECT * FROM editorial_items
),
parsed_items AS (
    SELECT
        digest_id,
        user_id,
        target_date,
        generated_at,
        mode,
        is_serene,
        format_version,
        topic_rank,
        subject_label,
        slot,
        NULLIF(item_json->>'content_id', '') AS content_id_text,
        COALESCE(NULLIF(item_json->>'rank', '')::integer, topic_rank) AS rank,
        COALESCE(
            NULLIF(item_json->>'final_score', '')::double precision,
            NULLIF(item_json->>'score', '')::double precision
        ) AS final_score,
        COALESCE(item_json->'pillar_scores', '{}'::jsonb) AS pillar_scores
    FROM digest_items
    WHERE item_json ? 'content_id'
)
SELECT
    pi.digest_id,
    pi.user_id,
    pi.target_date,
    pi.generated_at,
    pi.mode,
    pi.is_serene,
    pi.format_version,
    pi.topic_rank,
    pi.subject_label,
    pi.slot,
    pi.content_id_text::uuid AS content_id,
    pi.rank,
    pi.final_score,
    pi.pillar_scores,
    ucs.status::text AS status,
    c.topics,
    c.entities
FROM parsed_items pi
JOIN contents c ON c.id = pi.content_id_text::uuid
LEFT JOIN user_content_status ucs
    ON ucs.user_id = pi.user_id
   AND ucs.content_id = pi.content_id_text::uuid
ORDER BY pi.generated_at DESC, pi.rank NULLS LAST
LIMIT :row_limit
"""


async def _fetch_rows(args: argparse.Namespace) -> list[dict[str, Any]]:
    url = _database_url()
    connect_args: dict[str, Any] = {}
    if "+psycopg" in url:
        connect_args["prepare_threshold"] = None

    engine = create_async_engine(url, pool_pre_ping=False, connect_args=connect_args)
    try:
        async with engine.connect() as conn:
            result = await conn.execute(
                text(SQL),
                {
                    "since": args.since,
                    "until": args.until,
                    "mode": args.mode,
                    "include_serene": args.include_serene,
                    "row_limit": args.row_limit,
                },
            )
            return [dict(row._mapping) for row in result.fetchall()]
    finally:
        await engine.dispose()


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--days", type=int, default=14, help="Fenêtre en jours")
    parser.add_argument("--since", help="Borne basse UTC (ISO)")
    parser.add_argument("--until", help="Borne haute UTC (ISO)")
    parser.add_argument("--mode", help="Filtre daily_digest.mode")
    parser.add_argument(
        "--include-serene",
        action="store_true",
        help="Inclure les variantes sereines",
    )
    parser.add_argument(
        "--denominator",
        choices=DENOMINATORS,
        default=DEFAULT_DENOMINATOR,
        help="Dénominateur retenu (les 3 sont publiés côte à côte de toute façon)",
    )
    parser.add_argument("--min-shown", type=int, default=5)
    parser.add_argument("--top", type=int, default=25)
    parser.add_argument(
        "--row-limit",
        type=int,
        default=200_000,
        help="Garde-fou mémoire ; le rapport signale si la limite est atteinte",
    )
    parser.add_argument("--tag", default="latest")
    parser.add_argument("--out-json", type=Path)
    parser.add_argument("--out-md", type=Path)
    parser.add_argument("--no-write", action="store_true")
    parser.add_argument(
        "--compare",
        nargs=2,
        metavar=("BASELINE", "AFTER"),
        help="2 JSON produits par ce script",
    )
    args = parser.parse_args(argv)

    now = dt.datetime.now(dt.UTC)
    args.until = _parse_date(args.until) or now
    args.since = _parse_date(args.since) or (args.until - dt.timedelta(days=args.days))
    if args.since >= args.until:
        raise SystemExit("--since must be earlier than --until")
    return args


async def _main(argv: list[str]) -> int:
    args = _parse_args(argv)

    if args.compare:
        baseline = json.loads(Path(args.compare[0]).read_text(encoding="utf-8"))
        after = json.loads(Path(args.compare[1]).read_text(encoding="utf-8"))
        print(render_compare(baseline, after))
        return 0

    rows = await _fetch_rows(args)
    metrics = build_metrics(
        rows=rows,
        denominator=args.denominator,
        min_shown=args.min_shown,
        top=args.top,
    )
    report = render_report(
        metrics,
        since=args.since,
        until=args.until,
        mode=args.mode,
        include_serene=args.include_serene,
        tag=args.tag,
        row_limit_hit=len(rows) >= args.row_limit,
    )
    print(report)

    if args.no_write:
        return 0

    today = dt.datetime.now(dt.UTC).date().isoformat()
    out_json = args.out_json or CONTEXT_DIR / f"feed-ranking-{args.tag}-{today}.json"
    out_md = args.out_md or CONTEXT_DIR / f"feed-ranking-{args.tag}-{today}.md"
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_md.parent.mkdir(parents=True, exist_ok=True)

    payload = {
        "generated_at": dt.datetime.now(dt.UTC).isoformat(),
        "tag": args.tag,
        "since": args.since.isoformat(),
        "until": args.until.isoformat(),
        "mode": args.mode,
        "include_serene": args.include_serene,
        "row_limit_hit": len(rows) >= args.row_limit,
        "metrics": metrics,
    }
    out_json.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    out_md.write_text(report, encoding="utf-8")

    print(f"✅ Résultats : {out_json}")
    print(f"✅ Rapport   : {out_md}")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(_main(sys.argv[1:])))
