"""Score de couverture multi-sources d'un sujet.

Un événement couvert par plusieurs médias distincts est plus probablement
"l'essentiel du sujet du jour" qu'un scoop isolé. La formule log2 fait que
le 5e relais apporte moins que le 2e — on rémunère la diversité initiale
puis on plafonne.

`1→0  2→+12  3→+19  4→+24  5→+28  6→+30 (cap)  8+→+30`

Cette fonction est la source de vérité pour Essentiel, feed thématique et
digest. Toute évolution des constantes passe par `ScoringWeights`.
"""

import math

from app.services.recommendation.scoring_config import ScoringWeights


def compute_coverage_score(cluster_size: int) -> float:
    """Score non-linéaire de couverture d'un cluster.

    `min(CAP, BASE × log2(max(cluster_size, 1)))`. Un cluster de taille 1
    (scoop isolé) ne reçoit aucun bonus.
    """
    n = max(int(cluster_size or 0), 1)
    if n <= 1:
        return 0.0
    return min(
        ScoringWeights.COVERAGE_CAP,
        ScoringWeights.COVERAGE_BASE * math.log2(n),
    )
