"""Harnais de mesure de la détection paywall — matrice de confusion sur corpus.

Rejoue le **vrai** `detect_paywall()` sur les fixtures de
`tests/fixtures/paywall_corpus/`, sans DB ni réseau, et produit la matrice de
confusion globale et par source. C'est l'instrument de la refonte : aucune
modification de `paywall_detector.py` ne se justifie sans un avant/après mesuré
ici.

### La métrique qui décide

Le **taux de faux positifs** (article gratuit marqué payant) est bloquant, pas
indicatif. Un FP est irréversible en production : `_save_content`
(`sync_service.py` l.620) n'upgrade `is_paid` que de `False` vers `True`, jamais
l'inverse. Un article gratuit masqué à tort le reste définitivement, et retire
silencieusement de l'offre gratuite que l'app promet.

Le taux de faux négatifs est une gêne : l'utilisateur clique et tombe sur un
paywall. Une amélioration qui corrige 20 FN en créant 1 FP est donc à rejeter,
et le harnais est construit pour rendre ce verdict mécanique.

### Reconstitution des entrées

Les arguments passés à `detect_paywall()` sont reconstruits **comme
`_parse_entry` le fait** pour un article (`sync_service.py`, branche ARTICLE) :
`description` = `html.unescape(entry.summary)`, `html_content` =
`content:encoded`. Le `html_head` vient du fichier capturé par
`build_paywall_corpus.py`.

Usage :
    cd packages/api
    PYTHONPATH=. python scripts/paywall_benchmark.py
    PYTHONPATH=. python scripts/paywall_benchmark.py --markdown
    PYTHONPATH=. python scripts/paywall_benchmark.py --errors
    PYTHONPATH=. python scripts/paywall_benchmark.py --write-baseline
"""

from __future__ import annotations

import argparse
import html as html_lib
import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml

from app.services.paywall_detector import (
    DEFAULT_PAYWALL_CONFIG,
    PAYWALL_THRESHOLD,
    clear_cache,
    detect_paywall,
    detect_paywall_from_html,
)

CORPUS_DIR = Path(__file__).resolve().parent.parent / "tests/fixtures/paywall_corpus"
MANIFEST_PATH = CORPUS_DIR / "manifest.yaml"
LABELS_PATH = CORPUS_DIR / "labels.json"
BASELINE_PATH = CORPUS_DIR / "baseline.json"
RSS_DIR = CORPUS_DIR / "rss"
HTML_DIR = CORPUS_DIR / "html"


@dataclass
class Case:
    """Un article étiqueté, avec les deux surfaces que la prod voit."""

    article_id: str
    source: str
    url: str
    label: str  # "paid" | "free"
    title: str
    description: str | None
    html_content: str | None
    html_head: str | None
    paywall_config: dict | None

    @property
    def expected(self) -> bool:
        return self.label == "paid"


@dataclass
class Matrix:
    """Matrice de confusion. `fp` est la valeur qui décide d'un merge."""

    tp: int = 0
    fp: int = 0
    tn: int = 0
    fn: int = 0
    errors: list[dict] = field(default_factory=list)

    @property
    def total(self) -> int:
        return self.tp + self.fp + self.tn + self.fn

    @property
    def fp_rate(self) -> float:
        """FP / (articles réellement gratuits) — 0.0 si aucun gratuit."""
        free = self.fp + self.tn
        return self.fp / free if free else 0.0

    @property
    def fn_rate(self) -> float:
        paid = self.fn + self.tp
        return self.fn / paid if paid else 0.0

    def as_dict(self) -> dict[str, Any]:
        return {
            "tp": self.tp,
            "fp": self.fp,
            "tn": self.tn,
            "fn": self.fn,
            "fp_rate": round(self.fp_rate, 4),
            "fn_rate": round(self.fn_rate, 4),
        }


def load_corpus() -> list[Case]:
    """Charge les articles étiquetés. Les `label: null` sont ignorés."""
    if not LABELS_PATH.exists():
        return []

    manifest = yaml.safe_load(MANIFEST_PATH.read_text(encoding="utf-8"))
    configs = {s["slug"]: s.get("paywall_config") for s in manifest["sources"]}
    labels = json.loads(LABELS_PATH.read_text(encoding="utf-8"))

    entries_by_url: dict[str, dict] = {}
    for rss_file in sorted(RSS_DIR.glob("*.json")) if RSS_DIR.exists() else []:
        payload = json.loads(rss_file.read_text(encoding="utf-8"))
        for entry in payload.get("entries", []):
            if entry.get("link"):
                entries_by_url[entry["link"]] = entry

    cases = []
    for article_id, row in sorted(labels.items()):
        if row.get("label") not in ("paid", "free"):
            continue
        entry = entries_by_url.get(row["url"], {})
        html_path = HTML_DIR / f"{article_id}.html"
        cases.append(
            Case(
                article_id=article_id,
                source=row["source"],
                url=row["url"],
                label=row["label"],
                title=entry.get("title") or "",
                description=_description_from(entry),
                html_content=_html_content_from(entry),
                html_head=(
                    html_path.read_text(encoding="utf-8")
                    if html_path.exists()
                    else None
                ),
                paywall_config=configs.get(row["source"]),
            )
        )
    return cases


def _description_from(entry: dict) -> str:
    """Comme `_parse_entry` branche ARTICLE : unescape du summary."""
    summary = entry.get("summary") or ""
    return html_lib.unescape(summary) if summary else ""


def _html_content_from(entry: dict) -> str | None:
    """Comme `_parse_entry` : premier bloc `content` HTML, sinon le premier."""
    blocks = entry.get("content") or []
    for block in blocks:
        if "html" in (block.get("type") or ""):
            return block.get("value")
    return blocks[0].get("value") if blocks else None


def diagnose(case: Case) -> dict[str, Any]:
    """Explique quel signal a décidé — ou manqué — pour un article.

    Sans ça, une erreur du corpus n'est qu'un compteur : on saurait qu'on rate
    Novethic sans savoir si le marqueur est absent du HTML, absent du RSS, ou
    présent mais non reconnu.
    """
    html_signal = detect_paywall_from_html(case.html_head) if case.html_head else None
    config = case.paywall_config or DEFAULT_PAYWALL_CONFIG

    searchable = (case.title or "").lower()
    if case.description:
        searchable += " " + case.description.lower()
    if case.html_content:
        searchable += " " + case.html_content.lower()

    matched = [k for k in config.get("keywords", []) if k.lower() in searchable]
    url_hits = [
        p for p in config.get("url_patterns", []) if p.lower() in case.url.lower()
    ]

    return {
        "html_head_present": case.html_head is not None,
        "html_signal": html_signal,
        "keywords_matched": matched,
        "url_patterns_matched": url_hits,
        "score": (3 if matched else 0) + (3 if url_hits else 0),
        "threshold": PAYWALL_THRESHOLD,
    }


def evaluate(cases: list[Case]) -> tuple[Matrix, dict[str, Matrix]]:
    """Rejoue `detect_paywall()` et agrège global + par source."""
    clear_cache()
    overall = Matrix()
    by_source: dict[str, Matrix] = {}

    for case in cases:
        matrix = by_source.setdefault(case.source, Matrix())
        # `source_id` unique par cas : le cache de config de `detect_paywall`
        # est mémoïsé par source_id, et deux cas d'une même source partageant
        # un id feraient fuiter la config d'un cas sur l'autre.
        predicted = detect_paywall(
            title=case.title,
            description=case.description,
            url=case.url,
            html_content=case.html_content,
            source_id=case.article_id,
            paywall_config=case.paywall_config,
            html_head=case.html_head,
        )

        if predicted and case.expected:
            outcome = "tp"
        elif predicted and not case.expected:
            outcome = "fp"
        elif not predicted and not case.expected:
            outcome = "tn"
        else:
            outcome = "fn"

        setattr(overall, outcome, getattr(overall, outcome) + 1)
        setattr(matrix, outcome, getattr(matrix, outcome) + 1)

        if outcome in ("fp", "fn"):
            error = {
                "id": case.article_id,
                "source": case.source,
                "url": case.url,
                "kind": outcome,
                "diagnosis": diagnose(case),
            }
            overall.errors.append(error)
            matrix.errors.append(error)

    return overall, by_source


def render_markdown(overall: Matrix, by_source: dict[str, Matrix]) -> str:
    """Tableau prêt à coller dans la description de PR."""
    lines = [
        "| Source | Articles | TP | FP | TN | FN | Taux FP | Taux FN |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for slug in sorted(by_source):
        m = by_source[slug]
        lines.append(
            f"| {slug} | {m.total} | {m.tp} | {m.fp} | {m.tn} | {m.fn} | "
            f"{m.fp_rate:.0%} | {m.fn_rate:.0%} |"
        )
    lines.append(
        f"| **Global** | **{overall.total}** | **{overall.tp}** | **{overall.fp}** | "
        f"**{overall.tn}** | **{overall.fn}** | **{overall.fp_rate:.0%}** | "
        f"**{overall.fn_rate:.0%}** |"
    )
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--markdown", action="store_true", help="sortie tableau Markdown"
    )
    parser.add_argument("--errors", action="store_true", help="détaille chaque erreur")
    parser.add_argument(
        "--write-baseline",
        action="store_true",
        help="gèle la mesure courante comme référence anti-régression",
    )
    args = parser.parse_args()

    cases = load_corpus()
    if not cases:
        print(
            "Corpus vide ou non étiqueté. Lance d'abord :\n"
            "  PYTHONPATH=. python scripts/build_paywall_corpus.py\n"
            'puis étiquette labels.json ("paid" / "free").'
        )
        return 1

    overall, by_source = evaluate(cases)
    print(
        render_markdown(overall, by_source)
        if args.markdown
        else _plain(overall, by_source)
    )

    if args.errors:
        print("\nErreurs :")
        for error in overall.errors:
            print(f"\n  [{error['kind'].upper()}] {error['source']} — {error['url']}")
            for key, value in error["diagnosis"].items():
                print(f"      {key}: {value}")

    if args.write_baseline:
        BASELINE_PATH.write_text(
            json.dumps(
                {
                    "cases": len(cases),
                    "overall": overall.as_dict(),
                    "by_source": {k: v.as_dict() for k, v in sorted(by_source.items())},
                },
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )
        print(f"\nBaseline écrite : {BASELINE_PATH}")

    return 0


def _plain(overall: Matrix, by_source: dict[str, Matrix]) -> str:
    lines = [f"{'source':<18}{'n':>4}{'TP':>4}{'FP':>4}{'TN':>4}{'FN':>4}  FP%   FN%"]
    for slug in sorted(by_source):
        m = by_source[slug]
        lines.append(
            f"{slug:<18}{m.total:>4}{m.tp:>4}{m.fp:>4}{m.tn:>4}{m.fn:>4}"
            f"  {m.fp_rate:>4.0%} {m.fn_rate:>5.0%}"
        )
    lines.append(
        f"{'GLOBAL':<18}{overall.total:>4}{overall.tp:>4}{overall.fp:>4}"
        f"{overall.tn:>4}{overall.fn:>4}  {overall.fp_rate:>4.0%} {overall.fn_rate:>5.0%}"
    )
    return "\n".join(lines)


if __name__ == "__main__":
    raise SystemExit(main())
