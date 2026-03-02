# Wireframe : Feed Principal (Custom Topics) — v2

> Wireframe LQ — Modifications par rapport au feed actuel

```
┌─────────────────────────────────────────┐
│ ▄▄▄                              ●●●    │  ← Status bar iOS
├─────────────────────────────────────────┤
│  📬 Facteur                             │  ← Header avec logo
├─────────────────────────────────────────┤
│  🔥 12    ████████░░ 7/10    →          │  ← Widget progression (inchangé)
├─────────────────────────────────────────┤
│ [Tous] [🔬 Tech] [🌍 Société] [📌 IA]   │  ← NOUVEAU : Barre mixte scrollable
│         [📌 Mobilité douce] [💰 Éco]   │     Thèmes macro + Topics customs
├─────────────────────────────────────────┤
│                                         │
│  ┌─────────────────────────────────┐    │
│  │ ┌─────────┐                     │    │
│  │ │ 🖼️      │  Hugo Décrypte      │    │  ← Article #1 (représentant cluster IA)
│  │ │ Thumb   │  GPT-5 va changer   │    │
│  │ │         │  📄 8 min · 2h      │    │
│  │ └─────────┘                     │    │
│  ├─────────────────────────────────┤    │
│  │ 🔵 Hugo D. · 2h  ❤️ 🔖 [IA ✓]     │    │  ← NOUVEAU footer : chip topic
│  ├─────────────────────────────────┤    │     remplace 👁️ (icône ✓ sobre)
│  │ ▸ 4 autres articles sur l'IA    │    │  ← NOUVEAU : Chip de cluster
│  │   📌 Supris                        │    │     cliquable → Topic Explorer
│  └─────────────────────────────────┘    │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │ ┌─────────┐                     │    │
│  │ │ 🖼️      │  TTSO              │    │  ← Article hors-cluster
│  │ │ Thumb   │  La dette publique  │    │     (normal)
│  │ │         │  🎧 45 min · Hier   │    │
│  │ └─────────┘                     │    │
│  ├─────────────────────────────────┤    │
│  │ 🔵 TTSO · Hier  ❤️ 🔖 [Éco]    │    │  ← Chip "Éco" non suivi
│  └─────────────────────────────────┘    │     (pas de ✓, mais [+ Suivre])
│                                         │
│  ┌─────────────────────────────────┐    │
│  │ ┌─────────┐                     │    │
│  │ │ 🖼️      │  Vert.eco          │    │  ← Article #3 (représentant cluster)
│  │ │ Thumb   │  ZFE : les villes   │    │
│  │ │         │  📄 5 min · 3h      │    │
│  │ └─────────┘                     │    │
│  ├─────────────────────────────────┤    │
│  │ 🔵 Vert · 3h  ❤️ 🔖 [Mobilité ✓] │    │
│  ├─────────────────────────────────┤    │
│  │ ▸ 2 autres articles             │    │
│  │   📌 Suivi                      │    │
│  └─────────────────────────────────┘    │
│                                         │
├─────────────────────────────────────────┤
│  🌅            🌍            ⚙️        │  ← Bottom tab bar VRAIE (3 tabs)
│  Essentiel      Explorer     Settings   │     (Digest, Feed principal, Profil)
└─────────────────────────────────────────┘
```

## Éléments modifiés vs feed actuel

| Élément | Avant | Après |
|---------|-------|-------|
| **Barre de filtres** | `[Tous] [📄 Articles] [🎧 Podcasts] [🎬]` (types seulement) | `[Tous] [🔬 Tech] [🌍 Société] [📌 IA] [📌 Mobilité]` (thèmes + topics, scrollable) |
| **Topic Headers** | Inexistant | ~~Supprimés en v2 (trop de pollution visuelle)~~ |
| **Chip de cluster** | Inexistant | `▸ N autres articles sur [Topic]` sous la carte représentative |
| **Footer carte** | `Source · 2h  ❤️ 🔖 👁️ ℹ️` | `Source · 2h  ❤️ 🔖 [Topic ✓]` — chip remplace 👁️ + ℹ️ |
| **Bottom Bar** | 4 tabs (Feed, Saved, Sources, Profil) | **3 tabs réelles** (Essentiel, Explorer, Settings) — L'Explorer correspond au mockup ci-dessus |

## Notes d'implémentation v2

- Les **Topic Headers** (comme "📌 Intelligence Artificielle — 3 articles récents") ont été retirés. La chip de cluster sous l'article suffit à signaler le regroupement sans polluer le flux vertical.
- L'icône de suivi sur la chip de la carte est passée de `☑️` à un simple `✓` (plus premium/sobre, type `PhosphorIcons.check`).
- La bottom tab bar a été corrigée pour refléter les vrais 3 onglets (Essentiel = `/digest`, Explorer = `/feed`, Settings = `/settings`).
