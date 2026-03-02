# Wireframe : Nudge Post-Lecture

> Suggestion de suivi après consommation d'un article (écran Détail ou retour au feed)

## Déclenchement

Affiché comme **bottom sheet** après :
- Consommation d'un article marqué `consumed` (seuil de lecture atteint)
- L'article matche un topic que l'utilisateur **ne suit pas encore**
- L'utilisateur a lu ≥2 articles du même topic dans les 48 dernières heures (signal d'intérêt répété)

## Wireframe

```
┌─────────────────────────────────────────┐
│                                         │
│  (Feed ou Détail en arrière-plan        │
│   avec overlay sombre)                  │
│                                         │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │          ── handle ──            │    │  ← Drag handle
│  │                                 │    │
│  │  Tu lis souvent sur l'IA.       │    │  ← Titre (Fraunces 20px)
│  │  En faire un sujet prioritaire ? │    │
│  │                                 │    │
│  │  📌 Intelligence Artificielle   │    │  ← Topic détecté
│  │  🔬 Tech & Futur               │    │     + thème parent
│  │                                 │    │
│  │  ┌───────────────────────────┐  │    │
│  │  │     Oui, suivre ce sujet   │  │    │  ← CTA Primary (Terracotta)
│  │  └───────────────────────────┘  │    │
│  │                                 │    │
│  │  Non merci                      │    │  ← Ghost link
│  │  Ne plus me demander            │    │  ← Caption link (Text Tertiary)
│  │                                 │    │
│  └─────────────────────────────────┘    │
│                                         │
└─────────────────────────────────────────┘
```

## Variante : Topic déjà suivi, boost suggéré

Si l'utilisateur suit déjà le topic mais au cran Normal (3) :

```
│  │  Tu lis beaucoup sur l'IA !     │    │
│  │  Augmenter sa priorité ?         │    │
│  │                                 │    │
│  │  📌 IA — Priorité actuelle :    │    │
│  │  ◻ ◼ ◼ [◼] ◻                   │    │  ← Slider inline
│  │  Moins  Normal  Ultra           │    │     (highlight cran suggéré)
│  │                                 │    │
│  │  [Augmenter]     [C'est bien]   │    │
```

## Logique de fréquence

| Règle | Valeur |
|-------|--------|
| Max nudges par session | 1 |
| Délai minimum entre nudges | 48h |
| "Ne plus me demander" | Désactive tous les nudges topics (flag `nudge_topics_disabled`) |
| Seuil d'articles pour trigger | ≥2 articles du même topic en 48h |

## Notes

- **Component** : `ModalBottomSheet` standard Flutter avec `DraggableScrollableSheet`
- **Animation** : Slide up 250ms, spring easing (cohérent avec les modales existantes)
- **Dismiss** : Swipe down, tap outside, ou boutons explicites
- Ce nudge remplace la logique "The End screen" si elle n'est pas encore implémentée — c'est un point d'insertion naturel post-consommation
