"""Composition du push quotidien « coup d'œil » (Epic 30, PR #1).

Bullets = titres bruts des 3 premiers articles de l'Essentiel (déjà ordonnés
par intérêts et filtrés du racolage en amont) ; intro unique neutre. Aucun LLM
au dispatch. iOS ne rend qu'un alert APNS statique : le body est donc
« intro + 1er titre » ; Android reconstruit les bullets côté client depuis
`data["teasers"]` + `data["intro"]` (vieux clients : `intro` ignorée, zéro
casse).
"""

import json
from dataclasses import dataclass
from datetime import date

PUSH_TITLE = "Facteur"
DAILY_DIGEST_INTRO = "À retenir aujourd'hui :"
MAX_TEASERS = 3
MAX_FACT_LEN = 90


@dataclass(frozen=True)
class ComposedPush:
    title: str
    body: str
    data: dict[str, str]


def _truncate_fact(title: str, max_len: int = MAX_FACT_LEN) -> str:
    """Tronque un titre au mot le plus proche sous `max_len`, avec "..."."""
    cleaned = " ".join(title.split())
    if len(cleaned) <= max_len:
        return cleaned
    cut = cleaned[: max_len - 3]
    if " " in cut:
        cut = cut.rsplit(" ", 1)[0]
    return cut.rstrip() + "..."


def compose_daily_digest(essentiel, target_date: date) -> ComposedPush:
    """Compose le push digest quotidien depuis la réponse Essentiel exacte."""
    teasers = [
        _truncate_fact(article.title) for article in essentiel.articles[:MAX_TEASERS]
    ]
    body = f"{DAILY_DIGEST_INTRO} {teasers[0]}"
    return ComposedPush(
        title=PUSH_TITLE,
        body=body,
        data={
            "route": "/digest",
            "target_date": target_date.isoformat(),
            "kind": "daily_digest",
            "intro": DAILY_DIGEST_INTRO,
            "teasers": json.dumps(teasers, ensure_ascii=False),
        },
    )
