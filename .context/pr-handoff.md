# Handoff: Quota amorti (cap 4x) + CTA source avec logo — Epic 12 Diversification

## Contexte

Branch `boujonlaurin-dotcom/digest-fixes-features`. La diversification chrono actuelle est **proportionnelle au volume** de publication : une source prolific (ex: Contrepoints, 20 articles/jour) monopolise le feed avec jusqu'à 14 articles sur 20. L'utilisateur a validé un **cap à 4x** : aucune source ne peut avoir plus de 4x le quota de la source la moins représentée. Le surplus alimente un CTA overflow renforcé (avec logo source).

## Décisions produit validées

| Décision | Valeur | Justification |
|----------|--------|---------------|
| Cap max quota | **4 × min_quota** | Compromis diversité/remplissage (cf. simulations ci-dessous) |
| Seuil CTA | **overflow >= 3** | En-dessous = bruit visuel |
| `priority_multiplier` outrepasse le cap | **Oui** | Cap effectif = `4 × min_quota × multiplier` |
| Feed sous-rempli acceptable | **Oui** | Cohérent Slow Media, CTA compense |
| Logo source dans le CTA | **Oui** | Rendre le CTA plus attractif |

## Simulations validées

### Profil A — peu de sources, 1 prolific (5 sources, feed 20 slots)

| Source | Articles | Quota actuel | Quota cap 4x |
|--------|----------|-------------|--------------|
| Contrepoints | 20 | 14 | **4** (+16 overflow → CTA) |
| Le Monde | 4 | 3 | 4 |
| Mediapart | 2 | 2 | 2 |
| France Inter | 2 | 2 | 2 |
| The Conversation | 1 | 1 | 1 |
| **Total affiché** | | **20** | **13** |

### Profil B — varié, 2 prolific (10 sources, feed 20 slots)

| Source | Articles | Quota actuel | Quota cap 4x |
|--------|----------|-------------|--------------|
| Le Figaro | 12 | 6 | **4** (+8 overflow → CTA) |
| Libération | 10 | 5 | **4** (+6 overflow → CTA) |
| France 24 | 4 | 2 | 2 |
| Arte | 3 | 2 | 2 |
| Courrier Inter | 2 | 1 | 1 |
| Les Echos | 2 | 1 | 1 |
| Blast | 2 | 1 | 1 |
| Reporterre | 1 | 1 | 1 |
| AOC | 1 | 1 | 1 |
| Vert | 1 | 1 | 1 |
| **Total affiché** | | **20** | **18** |

---

## Changements à implémenter

### 1. Backend — Quota amorti dans `_apply_chronological_diversification()`

**Fichier** : `packages/api/app/services/recommendation_service.py` (lignes 570-617)

**Modifier le PASS 2** — après le calcul des quotas proportionnels, ajouter un cap basé sur le min_quota. Le `priority_multiplier` est appliqué au cap (pas au quota brut) pour permettre à l'utilisateur d'outrepasser :

```python
# PASS 2: Compute quotas with user multipliers (EXISTANT — inchangé)
quotas: dict[UUID, int] = {}
for source_id, articles_src in by_source.items():
    ratio = len(articles_src) / total
    multiplier = max(0.1, source_priority_multipliers.get(source_id, 1.0))
    quota = max(1, ceil(ratio * limit * multiplier))
    quotas[source_id] = quota

# --- NOUVEAU: PASS 2b — Diversity cap ---
# No source gets more than MAX_SOURCE_RATIO × min_quota (× its own multiplier)
MAX_SOURCE_RATIO = 4
min_quota = min(quotas.values())  # Toujours >= 1
for source_id in quotas:
    multiplier = max(0.1, source_priority_multipliers.get(source_id, 1.0))
    cap = max(1, ceil(MAX_SOURCE_RATIO * min_quota * multiplier))
    quotas[source_id] = min(quotas[source_id], cap)

# PASS 2c: Normalize if sum > limit (EXISTANT — renommé de 2b à 2c)
```

**Modifier le PASS 3** — filtrer l'overflow avec seuil >= 3 pour ne pas polluer le feed avec des CTAs pour 1-2 articles :

```python
# PASS 3: Select articles + compute overflow (MODIFIÉ)
MIN_OVERFLOW_FOR_CTA = 3
retained: list[Content] = []
source_overflow: dict[UUID, int] = {}
for source_id, articles_src in by_source.items():
    quota = quotas[source_id]
    retained.extend(articles_src[:quota])
    overflow_count = len(articles_src) - quota
    if overflow_count >= MIN_OVERFLOW_FOR_CTA:
        source_overflow[source_id] = overflow_count
```

### 2. Mobile — Logo source dans le CTA overflow

**Fichier** : `apps/mobile/lib/features/feed/widgets/source_overflow_chip.dart`

Ajouter le logo 16×16 de la source dans le Row, entre l'icône caretRight et le texte. Réutiliser le pattern existant de `feed_card.dart` (lignes 160-179) :

```dart
// Ajout import
import '../../../widgets/design/facteur_image.dart';

// Dans le Row children, après le caretRight Icon + SizedBox :
if (content.source.logoUrl != null &&
    content.source.logoUrl!.isNotEmpty) ...[
  ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: FacteurImage(
      imageUrl: content.source.logoUrl!,
      width: 16,
      height: 16,
      fit: BoxFit.cover,
      errorWidget: (context) => const SizedBox(width: 16, height: 16),
    ),
  ),
  const SizedBox(width: FacteurSpacing.space1),
],
```

### 3. Aucun changement requis sur

- **Schemas** (`feed.py`) : `SourceOverflowInfo` inchangé
- **Router** (`feed.py`) : passage overflow inchangé
- **Mobile repo** (`feed_repository.dart`) : parsing overflow inchangé (seuil géré backend)
- **Mobile model** (`content_model.dart`) : `sourceOverflowCount` inchangé

---

## Fichiers modifiés (résumé)

| Fichier | Changement |
|---------|-----------|
| `packages/api/app/services/recommendation_service.py` | PASS 2b: cap `4 × min_quota × multiplier`, PASS 3: seuil overflow >= 3 |
| `apps/mobile/lib/features/feed/widgets/source_overflow_chip.dart` | Ajout logo source (`FacteurImage` 16×16) dans le Row |

## Vérification

1. `ruff check && ruff format --check` sur `recommendation_service.py`
2. `flutter analyze` sur le projet mobile
3. Test manuel :
   - Utilisateur avec source prolific → **max 4 articles** de cette source dans le feed
   - CTA "N autres articles de [Source]" avec **logo visible** sur la dernière carte
   - CTA **n'apparaît PAS** si overflow < 3
   - Utilisateur ayant boosté une source (multiplier > 1) → cap relevé proportionnellement
   - Tap CTA → filtre par source → X pour revenir au feed normal

## Contraintes rappel

- Python 3.12, `list[]` natif (pas `List` de typing)
- `ruff check && ruff format` (backend)
- `flutter analyze` (mobile)
- `FacteurImage` pour les images réseau (cross-platform web/mobile)
