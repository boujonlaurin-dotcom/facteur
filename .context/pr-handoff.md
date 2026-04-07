# Handoff — Ajustements visuels carte expanded digest

## Contexte
Après la PR `recul_intro`, plusieurs ajustements visuels sont nécessaires sur la carte expanded des topics du digest éditorial. Les changements concernent uniquement le mobile Flutter.

---

## Tâches à réaliser

### 1. Retirer le texte "Sujets : ..." après ouverture de la carte
**Fichier :** `apps/mobile/lib/features/digest/widgets/topic_section.dart`
- La méthode `_computeSubjects()` (lignes 1186-1191) est du dead code — elle existe mais n'est jamais appelée.
- Si le texte "Sujets : ..." apparaît malgré tout dans l'UI, il est probable qu'il vienne du champ `DigestTopic.subjects` (liste de strings, ligne 103 de `digest_models.dart`) rendu par un widget parent ou par le `topic.label`.
- **Action :** Supprimer la méthode `_computeSubjects()` (dead code), puis chercher dans l'app où `topic.subjects` ou un texte "Sujets" est affiché à l'ouverture de la carte — possiblement dans `_buildExpandedHeader` ou dans le widget parent `digest_briefing_section.dart`.

### 2. Réduire l'opacité du fond de la carte expanded à 5%/3%
**Fichier :** `topic_section.dart`, méthode `_buildExpandedEditorial()` (lignes 649-660)
```dart
// Actuel :
color: isDark
    ? colors.surface.withValues(alpha: 0.3)
    : colors.surface.withValues(alpha: 0.4),
// Cible :
color: isDark
    ? colors.surface.withValues(alpha: 0.05)
    : colors.surface.withValues(alpha: 0.03),
```

### 3. Repositionner le bouton Toggle (caret up) après retrait du titre
**Fichier :** `topic_section.dart`, méthode `_buildExpandedHeader()` (lignes 773-807)
- Actuellement : Row avec `topic.label` (Expanded) + caret up icon
- Après retrait du titre "Sujets : ...", le toggle "flotte" seul à droite
- **Action :** Repositionner le caret up de façon propre — par exemple l'aligner à droite dans un Row avec un Spacer, ou l'intégrer dans la première carte article comme un bouton overlay en haut à droite. Vérifier le design avec Laurin.

### 4. Aligner les paddings entre les 4 cartes (articles, "De quoi on parle", analyse Facteur, prendre du recul)
**Fichiers concernés :**
- `topic_section.dart` — "De quoi on parle ?" : `EdgeInsets.fromLTRB(16, 0, 16, 12)` + inner padding `EdgeInsets.all(12)` (lignes 693-696)
- `topic_section.dart` — DivergenceAnalysisBlock : `EdgeInsets.symmetric(horizontal: 16)` (ligne 737)
- `divergence_analysis_block.dart` — inner padding : `EdgeInsets.all(12)` (ligne 48)
- `topic_section.dart` — PasDeReculBlock : `EdgeInsets.symmetric(horizontal: 16)` (ligne 759)
- `pas_de_recul_block.dart` — inner padding : `EdgeInsets.all(12)` (ligne 35)
- Articles (carousel/single) : `EdgeInsets.symmetric(horizontal: 12)` (ligne 1031)
- **Action :** Uniformiser le padding horizontal externe à 16px pour les 4 blocs, et le padding interne à 12px.

### 5. CTA "Lire la suite…" — trop voyant et répétitif
**Fichier :** `divergence_analysis_block.dart` (lignes 139-149)
- Actuellement : texte bold en `colors.primary`, fontSize 13, fontWeight w600
- **Action :** Réduire la visibilité — passer en `colors.textSecondary`, fontSize 12, fontWeight w500 pour en faire un nudge discret. Ou le retirer complètement si le tap sur le texte tronqué suffit comme affordance.

### 6. Bouton "Toutes les perspectives" — réduire la hauteur uniquement
**Fichier :** `divergence_analysis_block.dart` (lignes 155-182)
- Actuellement : `Row` avec logos + texte + flèche, pas de padding contraint
- Le bouton doit rester un plain button centré
- **Action :** Réduire l'espacement autour — changer le `SizedBox(height: 8)` avant le bouton (ligne 156) en `SizedBox(height: 4)`, et éventuellement réduire la taille des logos de 18px à 16px.

### 7. Augmenter l'opacité de la border du container "Analyse Facteur"
**Fichier :** `divergence_analysis_block.dart` (lignes 64-67)
```dart
// Actuel :
border: Border.all(
  color: colors.primary.withValues(alpha: isDark ? 0.3 : 0.2),
  width: 1,
),
// Cible (plus visible) :
border: Border.all(
  color: colors.primary.withValues(alpha: isDark ? 0.5 : 0.4),
  width: 1,
),
```

### 8. Renommer le titre "🔍 L'analyse Facteur" → "🔍 Analyse de biais (N sources)"
**Fichier :** `divergence_analysis_block.dart` (lignes 75-81)
```dart
// Actuel :
Text(
  "\u{1F50D} L'analyse Facteur",
  ...
),
// Cible :
Text(
  "\u{1F50D} Analyse de biais (${widget.perspectiveCount} sources)",
  ...
),
```

---

## Fichiers à modifier
| Fichier | Tâches |
|---------|--------|
| `topic_section.dart` | #1, #2, #3, #4 |
| `divergence_analysis_block.dart` | #5, #6, #7, #8 |
| `pas_de_recul_block.dart` | #4 (padding si nécessaire) |

## Comment tester
```bash
cd apps/mobile && flutter analyze
cd apps/mobile && flutter test
```
Puis vérifier visuellement sur iOS/Android : ouvrir un digest éditorial, expand une carte, vérifier les 8 points.
