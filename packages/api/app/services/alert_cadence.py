"""Cadence de publication d'une cible d'alerte (source ou sujet) — alertes v2.

La v1 (story 30.2) faisait de la rareté un **gate** : la cloche n'était posable
que sous 1 article/semaine. Le test PO a tranché l'inverse — interdire, et
*montrer* l'interdiction, vend une frustration. La v2 autorise partout et
remplace le gate par un **devis de bruit honnête** : on annonce la cadence
avant l'activation, et au-delà de `NOISY_PER_WEEK` on propose le mode filtré.

Module partagé par `source_alert_producer` et `topic_alert_producer` (l'import
croisé entre les deux serait circulaire). Miroir exact de
`apps/mobile/lib/features/sources/utils/publication_frequency.dart`.
"""

from datetime import datetime, timedelta

#: Au-delà de ce rythme (articles / semaine), la cible est « bruyante » : on
#: affiche un avertissement et on pré-coche le mode filtré.
NOISY_PER_WEEK = 3.0
#: Fenêtre de comptage, en jours, avant clamp sur l'âge réel de la cible.
FREQUENCY_WINDOW_DAYS = 30


def _per_day(
    articles_30d: int, oldest_content_at: datetime | None, now: datetime
) -> float:
    """Volume quotidien moyen, fenêtre 30 j clampée sur l'âge réel de la cible.

    Le clamp évite de sous-estimer une cible fraîchement ingérée : 6 articles
    en 3 jours, c'est 2/jour, pas 0,2/jour.
    """
    window_days = FREQUENCY_WINDOW_DAYS
    if oldest_content_at is not None:
        age_days = (now - oldest_content_at).days
        window_days = min(max(age_days, 1), FREQUENCY_WINDOW_DAYS)
    return articles_30d / window_days


def cadence_per_week(
    articles_30d: int, oldest_content_at: datetime | None, now: datetime
) -> float:
    """Rythme de parution en articles par semaine."""
    return _per_day(articles_30d, oldest_content_at, now) * 7


def is_noisy(
    articles_30d: int, oldest_content_at: datetime | None, now: datetime
) -> bool:
    """Vrai si la cible publie assez pour que la cloche devienne du bruit."""
    return cadence_per_week(articles_30d, oldest_content_at, now) > NOISY_PER_WEEK


def cadence_phrase(
    articles_30d: int, oldest_content_at: datetime | None, now: datetime
) -> str:
    """Phrase de cadence adaptative — jamais une promesse non soutenue.

    L'unité suit le rythme réel (mois → semaine → jour) pour que le chiffre
    reste lisible : « 21 fois par semaine » ne se visualise pas, « environ
    3 par jour » si.
    """
    per_week = cadence_per_week(articles_30d, oldest_content_at, now)
    if per_week <= 0:
        return "Publie rarement"
    if per_week < 0.5:
        return "Publie environ une fois par mois"
    if per_week < 1.5:
        return "Publie environ une fois par semaine"
    if per_week < NOISY_PER_WEEK:
        return f"Publie environ {round(per_week)} fois par semaine"
    per_day = per_week / 7
    if per_day < 1.5:
        return "Publie environ une fois par jour"
    return f"Publie environ {round(per_day)} fois par jour"


def expected_alerts_phrase(
    articles_30d: int, oldest_content_at: datetime | None, now: datetime
) -> str:
    """Devis de bruit affiché avant l'activation d'une cloche bruyante."""
    per_week = cadence_per_week(articles_30d, oldest_content_at, now)
    if per_week >= 7:
        return f"Environ {round(per_week / 7)} alertes par jour"
    return f"Environ {round(per_week)} alertes par semaine"


#: Fenêtre de fraîcheur d'un contenu pour déclencher une alerte.
ALERT_LOOKBACK = timedelta(hours=24)
#: Plafond de cloches actives par utilisateur, **partagé** sources + sujets.
ALERT_CAP = 5
