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

from app.services.source_alert_producer import SourceAlertCandidate

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


def compose_source_alert(
    candidate: SourceAlertCandidate, rarity_phrase: str
) -> ComposedPush:
    """Compose l'alerte « cette source rare vient de publier ».

    Le body est le titre de l'article seul : c'est l'info. La ligne de rareté
    ne vient qu'en `big_text` (Android déplié) — elle justifie la notification
    sans la parasiter, et sa formulation est dérivée des mêmes seuils que
    `is_rare_source`, jamais une affirmation que les chiffres ne soutiennent
    pas.
    """
    body = _truncate_fact(candidate.content_title)
    return ComposedPush(
        title=f"📯 Alerte : {candidate.source_name} vient de publier",
        body=body,
        data={
            "route": f"/article/{candidate.content_id}",
            "kind": "source_alert",
            "source_id": str(candidate.source_id),
            "source_name": candidate.source_name,
            "content_id": str(candidate.content_id),
            "channel": "alerts",
            "big_text": f"{body}\n{rarity_phrase}",
        },
    )
