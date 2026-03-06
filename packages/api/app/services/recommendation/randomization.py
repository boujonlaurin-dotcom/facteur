"""Randomisation contrôlée pour le scoring de recommandation.

Utilise le Gumbel-max trick pour shuffler les articles à scores proches,
équivalent à un sampling depuis une distribution softmax.
"""

import math
import random


def randomized_sort[T](
    scored_items: list[tuple[T, float]],
    temperature: float = 0.15,
    seed: int | None = None,
) -> list[tuple[T, float]]:
    """Réordonne les items avec une randomisation contrôlée via bruit de Gumbel.

    Le score déterministe original est préservé (non modifié) — seul l'ordre change.

    Args:
        scored_items: Liste de (item, score_deterministe).
        temperature: Degré de randomisation.
            0.0 = entièrement déterministe (même ordre que sort classique)
            0.10 = shuffle léger (articles à +-5pts)
            0.15 = défaut, découverte modérée
            0.25 = forte découverte
            1.0 = quasi-aléatoire
        seed: Seed optionnel pour reproductibilité.
            None = random système.

    Returns:
        Liste réordonnée de (item, score_deterministe).
        Le score déterministe est inchangé.
    """
    if not scored_items:
        return scored_items

    if temperature <= 0:
        return sorted(scored_items, key=lambda x: x[1], reverse=True)

    rng = random.Random(seed)

    noisy_items: list[tuple[T, float, float]] = []
    scale = max(temperature * 100, 1e-6)

    for item, score in scored_items:
        # Gumbel noise: -log(-log(U)), U ~ Uniform(0,1)
        u = rng.random()
        u = max(u, 1e-10)
        u = min(u, 1 - 1e-10)
        gumbel = -math.log(-math.log(u))

        # Noisy key = score / scale + gumbel
        # Equivalent to sampling from softmax(scores / temperature)
        noisy_key = score / scale + gumbel
        noisy_items.append((item, score, noisy_key))

    noisy_items.sort(key=lambda x: x[2], reverse=True)
    return [(item, score) for item, score, _ in noisy_items]


def compute_seed(user_id: str, granularity: str = "hourly") -> int:
    """Compute a deterministic seed for stable ordering within a time window.

    Args:
        user_id: User identifier (UUID string).
        granularity: "hourly" (feed) or "daily" (digest).

    Returns:
        Integer seed.
    """
    from datetime import UTC, datetime

    now = datetime.now(UTC)

    if granularity == "daily":
        time_key = now.strftime("%Y-%m-%d")
    else:  # hourly
        time_key = now.strftime("%Y-%m-%d-%H")

    return hash((user_id, time_key))
