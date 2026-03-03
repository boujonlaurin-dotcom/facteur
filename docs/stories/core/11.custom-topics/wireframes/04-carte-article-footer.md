# Wireframe : Carte Article — Nouveau Footer

> Modification du footer de la `ContentCard` existante

## Avant (actuel)

```
┌─────────────────────────────────────────┐
│ ┌─────────────────────────────────────┐ │
│ │          IMAGE THUMBNAIL            │ │
│ └─────────────────────────────────────┘ │
│  Titre du contenu sur deux lignes max   │
│  📄 8 min                               │
├─────────────────────────────────────────┤
│  🔵 Source · 2h    ❤️  🔖  👁️  ℹ️       │  ← 4 boutons d'action
└─────────────────────────────────────────┘
```

## Après (Epic 11)

```
┌─────────────────────────────────────────┐
│ ┌─────────────────────────────────────┐ │
│ │          IMAGE THUMBNAIL            │ │
│ └─────────────────────────────────────┘ │
│  Titre du contenu sur deux lignes max   │
│  📄 8 min                               │
├─────────────────────────────────────────┤
│  🔵 Source · 2h    ❤️  🔖  [IA ☑️]      │  ← Chip topic remplace 👁️ + ℹ️
└─────────────────────────────────────────┘
```

## Chip Topic — 2 états

### État 1 : Topic suivi

```
┌──────────┐
│ 📌 IA ☑️  │  ← Fond terracotta/10, bord terracotta
└──────────┘
```
- **Tap** → Navigation vers page "Mes Intérêts"
- **Fond** : `#E07A5F` à 10% opacity
- **Texte** : `#E07A5F` (Terracotta)
- **Icône** : `PhosphorIcons.pushPin` (fill)

### État 2 : Topic non suivi

```
┌───────────────────┐
│ IA  [+ Suivre]     │  ← Fond surface (#1E1E1E), bord #333
└───────────────────┘
```
- **Tap "Suivre"** → Ajoute le topic en 1 tap (pas de page, juste un toast "IA ajouté !")
- **Tap sur le nom** → Navigation vers Topic Explorer
- **Fond** : `#1E1E1E` (Surface)
- **Texte** : `#F5F5F5` à 70% (Text Secondary)

## Mapping boutons : Avant → Après

| Avant | Après | Raison |
|-------|-------|--------|
| ❤️ Like | ❤️ Like | **Inchangé** |
| 🔖 Bookmark | 🔖 Bookmark | **Inchangé** |
| 👁️ Masquer | ~~Supprimé~~ | Remplacé par le chip topic. Le masquage reste accessible via long-press → menu contextuel |
| ℹ️ Personnalisation | ~~Supprimé~~ | Fonctionnalité absorbée par la page "Mes Intérêts" accessible via le chip |

## Notes

- Le **match topic** est déterminé par l'article : `content.topics[0]` (topic principal)
- Si l'article n'a aucun topic matché → pas de chip (cas rare, les articles ont tous un `topic_slug` Mistral)
- Le bouton "Masquer" (👁️) se retrouve dans un **menu long-press** sur la carte (3 points ou context menu) pour ne pas perdre la fonctionnalité
