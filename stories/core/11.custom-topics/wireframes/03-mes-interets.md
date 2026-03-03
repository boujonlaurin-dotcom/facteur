# Wireframe : Page "Mes Intérêts" (v3)

> Vue unifiée thèmes + topics. Accessible via Settings, Modale Day 2, Nudge, Chip carte.

```
┌─────────────────────────────────────────┐
│ ▄▄▄                              ●●●    │
├─────────────────────────────────────────┤
│  ←  Mes Intérêts                        │
├─────────────────────────────────────────┤
│                                         │
│  🧠 Ton algorithme, tes règles.         │  ← Hero (Fraunces 24px)
│  Facteur apprend de tes lectures.       │     (DM Sans 15px)
│  Ici, tu reprends le contrôle.          │
│                                         │
│  ─────────────────────────────────────  │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │ 🔬 TECH & FUTUR                 │    │  ← Header de l'ExpansionTile (OUVERT)
│  │ ┌─ ◼ ◼ ◼ ─┐                 ▾  │    │  ← NOUVEAU : Slider directement collé
│  │ └─────────────────┘                 │    │     sous le titre du thème, sans label
│  │                                 │    │
│  │  📌 Intelligence Artificielle   │    │  ← Topic custom suivi
│  │  ┌─ ◼ ◼ ◻ ─┐                 │    │  ← Slider topic
│  │  └─────────────────┘                 │    │
│  │  Sources : Dév.com · The Verge  │    │
│  │  [→ Voir mes sources]            │    │
│  │                                 │    │
│  │  📌 GPT-5                       │    │  ← Topic custom suivi
│  │  ┌─ ◼ ◻ ◻ ─┐                 │    │  ← Slider topic
│  │  └─────────────────┘                 │    │
│  │  Sources : The Verge            │    │
│  │  [→ Voir mes sources]            │    │
│  │                                 │    │
│  │  ── Suggestions pour toi ────── │    │  ← In-situ discovery
│  │  ○ Cybersécurité     [+ Suivre] │    │  ← Basé sur lectures récentes
│  │  ○ Blockchain        [+ Suivre] │    │
│  │                                 │    │
│  └─────────────────────────────────┘    │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │ 🌍 SOCIÉTÉ & CLIMAT             │    │  ← Thème macro
│  │ ┌─ ◼ ◼ ◻ ─┐                 ▾  │    │  ← Slider 2/3 (Défaut estimé)
│  │ └─────────────────┘                 │    │
│  │                                 │    │
│  │  (Aucun topic suivi)            │    │
│  │                                 │    │
│  │  ── Suggestions pour toi ────── │    │
│  │  ○ Mobilité douce    [+ Suivre] │    │
│  │  ○ Biodiversité      [+ Suivre] │    │
│  │                                 │    │
│  └─────────────────────────────────┘    │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │ 💰 ÉCONOMIE                     │    │
│  │ ┌─ ◼ ◼ ◻ ─┐                 ▸  │    │  ← Collapsé si nécessaire (mais ouverts 
│  │ └─────────────────┘                 │    │     par défaut si peu nombreux)
│  └─────────────────────────────────┘    │
│                                         │
├─────────────────────────────────────────┤
│  🌅            🌍            ⚙️        │
│  Essentiel      Explorer     Settings   │
└─────────────────────────────────────────┘
```

## Curseur 3 crans (Compact UX)

| Cran | Score Multiplier | Visuel | Interaction |
|------|------------------|--------|-------------|
| 1/3 | ×0.5 | `◼ ◻ ◻` | Tap/Slide |
| 2/3 | ×1.0 (défaut) | `◼ ◼ ◻` | Tap/Slide |
| 3/3 | ×2.0 | `◼ ◼ ◼` | Tap/Slide |

**UX Update (v3) :**
- **Pas de label explicite** ("Suivi", "Intéressé", "Fort") affiché en permanence.
- Les labels n'apparaissent **que brièvement** (tooltip ou texte flottant au-dessus du curseur avec animation fade out) uniquement au moment où l'utilisateur **touche/modifie** le curseur, pour ne pas surcharger l'interface.
- Le curseur du thème macro est **remonté directement dans le bloc header** du `ExpansionTile`, aligné à gauche sous le titre, pour éviter la duplication et économiser de l'espace vertical.

## Layout Contraintes (Mobile)
Si l'espace horizontal manque pour le curseur du thème à côté du titre, on le place juste en-dessous (comme illustré), limitant sa largeur à ~120px, et on décale le chevron `▾` tout à droite.

## Suppression
- Toujours gérée par Swipe-to-delete (pour les thèmes complets comme pour les topics individuels).
