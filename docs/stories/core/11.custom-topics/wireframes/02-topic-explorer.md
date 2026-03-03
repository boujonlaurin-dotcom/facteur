# Wireframe : Topic Explorer (Vue filtrée) — v2

> Navigation push depuis la chip de cluster ou le filtre topic du header

```
┌─────────────────────────────────────────┐
│ ▄▄▄                              ●●●    │
├─────────────────────────────────────────┤
│  ←  📌 Intelligence Artificielle        │  ← Header avec back + nom topic
│      🔬 Tech & Futur                    │     + thème parent en sous-titre
├─────────────────────────────────────────┤
│                                         │
│  ┌─────────────────────────────────┐    │
│  │  ☑️ Suivi · Intérêt : ◼ ◼ ◻    │    │  ← État + curseur 3 crans
│  │  [Modifier la priorité]          │    │     (collapsé par défaut)
│  └─────────────────────────────────┘    │
│                                         │
│  5 articles récents                      │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │ ┌─────────┐                     │    │
│  │ │ 🖼️      │  Hugo Décrypte      │    │
│  │ │ Thumb   │  GPT-5 va changer   │    │
│  │ │         │  📄 8 min · 2h      │    │
│  │ └─────────┘                     │    │
│  ├─────────────────────────────────┤    │
│  │ 🔵 Hugo D. · 2h    ❤️  🔖       │    │
│  └─────────────────────────────────┘    │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │ ┌─────────┐                     │    │
│  │ │ 🖼️      │  The Verge          │    │
│  │ │ Thumb   │  OpenAI's next move │    │
│  │ │         │  📄 12 min · 3h     │    │
│  │ └─────────┘                     │    │
│  ├─────────────────────────────────┤    │
│  │ 🔵 The Verge · 3h  ❤️  🔖       │    │
│  └─────────────────────────────────┘    │
│                                         │
│  (... scroll pour plus d'articles)      │
│                                         │
├─────────────────────────────────────────┤
│  🏠        🔖        📚        ⚙️       │
│  Feed    Saved    Sources   Profil      │
└─────────────────────────────────────────┘
```

## Variante : Topic non suivi

```
┌─────────────────────────────────────────┐
│  ←  Intelligence Artificielle           │  ← Pas de 📌 (non suivi)
│      🔬 Tech & Futur                    │
├─────────────────────────────────────────┤
│  ┌─────────────────────────────────┐    │
│  │  [+ Suivre ce sujet]             │    │  ← CTA Primary
│  │  Recevez plus d'articles sur     │    │
│  │  l'IA dans votre feed            │    │
│  └─────────────────────────────────┘    │
│  ...                                     │
```

## Notes (v2)

- **Pas de "Ne plus suivre"** dans le Topic Explorer pour l'instant
- Si topic déjà suivi → **"Modifier la priorité"** ouvre le curseur 3 crans inline
- Pattern identique au "Feed filtré par source" existant
- Endpoint : `GET /feed?topic=slug`
