# Wireframe : Modale Day 2

> Introduction de la feature Custom Topics — déclenchée à la 2ème ouverture de l'app

```
┌─────────────────────────────────────────┐
│                                    ✕    │  ← Bouton fermer (Text Tertiary)
│                                         │
│                                         │
│              [Illustration]             │  ← Illustration : une loupe
│           📌                            │     sur un journal personnalisé
│                                         │
│                                         │
│     Ton feed s'adapte à toi.            │  ← Titre (Fraunces 24px, bold)
│                                         │
│     Tu as aimé des articles sur         │  ← Corps (DM Sans 15px)
│     l'IA hier — tu peux en faire        │     Personnalisé si données Day 1
│     un sujet prioritaire.               │     dispo (topics les plus lus)
│                                         │
│     Ajoute tes propres sujets           │
│     pour voir plus de ce qui            │
│     t'intéresse vraiment.               │
│                                         │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │    Personnaliser mon feed  ❯     │    │  ← CTA Primary (Terracotta)
│  └─────────────────────────────────┘    │     → Navigate vers Mes Intérêts
│                                         │
│     Plus tard                            │  ← Lien Ghost
│                                         │
│                                         │
│  ─────────────────────────────────────  │
│  ┌───┐ ┌───┐ ┌───┐                     │
│  │ ● │ │ ○ │ │ ○ │  1/3                │  ← Pagination (si multi-slides)
│  └───┘ └───┘ └───┘                     │
│                                         │
└─────────────────────────────────────────┘
```

## Logique de déclenchement

| Condition | Détail |
|-----------|--------|
| **Quand** | 2ème ouverture de l'app (Day 2 ou plus) |
| **Fréquence** | 1 seule fois (flag `has_seen_topics_intro` en local) |
| **Contexte** | Après le chargement du feed, pas pendant le splash |
| **Dismiss** | ✕ ou "Plus tard" → Ne réapparaît jamais |
| **CTA** | "Personnaliser mon feed" → Push navigation Mes Intérêts |

## Personnalisation du message

Si des données de consommation Day 1 sont disponibles :
```
"Tu as lu 3 articles sur l'IA et 2 sur l'économie hier."
```

Si pas de données suffisantes :
```
"Ajoute tes propres sujets pour voir plus de ce qui t'intéresse vraiment."
```

## Notes

- **Animation d'entrée** : Slide up + fade (250ms, spring easing)
- **Style** : Même pattern que le Paywall (modal plein écran, fond `#121212`)
- **Illustration** : Générée ou statique, style minimaliste cohérent avec l'onboarding
- **Pagination** : Optionnelle si on veut ajouter 2 slides bonus (ex: "Comment ça marche" + "Exemples de sujets")
