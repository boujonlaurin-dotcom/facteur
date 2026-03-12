# Plan d'Implémentation — Finalisation Progress Bar (Story 10.11)

**Agent** : @dev
**Branche** : `claude/progress-bar-implementation-8AGO2`
**Date** : 2026-03-11
**Type** : Feature (finalisation)

---

## Contexte & État Actuel

### Ce qui existe déjà

1. **`ProgressBar` widget** (`digest/widgets/progress_bar.dart`) — widget standalone avec segments, **non utilisé dans l'UI**
2. **`_buildSegmentedProgressBar()`** inline dans `DigestBriefingSection` (lignes 269-321) — **activement utilisé**, affiche X/N + petits segments dots
3. **`DigestProvider`** — tracking réactif via `processedCount` / `totalCount` getters (lignes 344-359)

### Acceptance Criteria vs État

| AC | Requirement | Status | Gap |
|----|-------------|--------|-----|
| AC 1 | Affichage "X/5" avec indicateur visuel | ✅ Done | — |
| AC 2 | Barre de progression animée | 🟡 Partiel | Segments dots sans animation fluide |
| AC 3 | Messages contextuels selon progression | ❌ Absent | Aucune logique de messages |
| AC 4 | Animation de remplissage à chaque action | ❌ Absent | Pas de pulse/celebration |
| AC 5 | Position fixe en haut (sous le header) | ❌ Absent | Scrolle avec le contenu |

---

## Plan en 4 Tasks

### Task 1 : Créer `DigestProgressBar` — widget complet (StatefulWidget)

**Fichier** : `apps/mobile/lib/features/digest/widgets/digest_progress_bar.dart` (nouveau)

**Spécifications** :
- `StatefulWidget` avec `SingleTickerProviderStateMixin`
- Props : `processedCount`, `totalCount`
- **Barre continue** (pas segments dots) :
  - `AnimatedContainer` avec width proportionnelle à `processedCount / totalCount`
  - Hauteur : 6px, border radius 3px
  - Fond : `colors.backgroundSecondary`
  - Remplissage : gradient `colors.primary`
  - Couleur dynamique : primary (< 60%) → orange (60-99%) → success (100%)
- **Compteur X/N** à droite de la barre
- **Message contextuel** sous la barre :
  - `0/N` → "C'est parti !"
  - `< 50%` → "Bon début"
  - `< 100%` → "Encore un peu..."
  - `= 100%` → "Bravo !"
  - Transition via `AnimatedSwitcher` (200ms fade)
- **Pulse animation** :
  - `AnimationController` (300ms)
  - `Transform.scale(1.0 → 1.03)` déclenché via `didUpdateWidget` quand `processedCount` augmente
  - Subtil, ne re-render pas tout le digest

### Task 2 : Intégrer en position fixe dans `DigestScreen`

**Fichier** : `apps/mobile/lib/features/digest/screens/digest_screen.dart`

**Changements** :
- Placer `DigestProgressBar` **au-dessus** du contenu scrollable
- Structure : `Column → [DigestProgressBar, Expanded(child: existingScrollContent)]`
- Brancher sur `digestProvider.processedCount` et `digestProvider.totalCount`
- La barre reste visible quand l'utilisateur scroll les articles

### Task 3 : Nettoyage

**Fichiers impactés** :
- **Supprimer** `progress_bar.dart` (widget standalone non utilisé, remplacé)
- **Modifier** `digest_briefing_section.dart` :
  - Retirer `_buildSegmentedProgressBar()` (lignes 269-321)
  - Retirer l'appel à cette méthode dans le header
  - Pas de doublon X/N entre header et barre fixe

### Task 4 : MAJ Story + Commit

- MAJ `10.11.barre-progression.story.md` : Status → In Progress, tasks cochées, File List
- `flutter analyze` pour vérifier absence d'erreurs
- Commit descriptif + push

---

## Fichiers Impactés

| Fichier | Action |
|---------|--------|
| `apps/mobile/lib/features/digest/widgets/digest_progress_bar.dart` | **Créer** |
| `apps/mobile/lib/features/digest/widgets/progress_bar.dart` | **Supprimer** |
| `apps/mobile/lib/features/digest/screens/digest_screen.dart` | **Modifier** |
| `apps/mobile/lib/features/digest/widgets/digest_briefing_section.dart` | **Modifier** |
| `docs/stories/core/10.digest-central/10.11.barre-progression.story.md` | **MAJ** |

## Risques

| Risque | Mitigation |
|--------|------------|
| Layout break en position fixe | Tester SafeArea + différentes tailles écran |
| Double compteur X/N | Retirer l'ancien du header briefing |
| Re-render cascade du pulse | Isoler l'animation dans le widget, pas dans le parent |

## Hors Scope

- Backend : aucun changement API
- Widget tests : à traiter dans un follow-up
- Gamification daily progress : système séparé, non impacté
