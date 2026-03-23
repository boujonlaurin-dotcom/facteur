# Handoff — Digest UX/UI itération 2 : 4 ajustements restants

## Contexte

On a déjà implémenté 5 corrections UX/UI sur le digest (branche `make-digest-great`) :
- Barre de progression → compteur discret (mini-barres)
- Header statique "L'Essentiel du jour"
- Carrousel : hauteur augmentée (170→200) + ClipRect + dots agrandis
- Badges éditoriaux : nouveau widget `EditorialBadge` + intégration TopicSection/PepiteBlock/CoupDeCoeurBlock
- Typo "Et aussi" : 15px w400 italic

Après tests visuels, 4 problèmes subsistent.

---

## 1. Carrousel : overflow vertical persistant

**Problème** : Malgré l'augmentation de `_bodyFooterHeight` à 200px, le footer des cartes du carrousel est toujours rogné sur certaines cartes (titres longs, descriptions présentes). La capture montre le bas de la carte coupé avec les barres jaunes/noires de warning overflow.

**Fichier** : `apps/mobile/lib/features/digest/widgets/topic_section.dart`

**Approche recommandée** :
- Le `_bodyFooterHeight` fixe (200px) est fondamentalement fragile — il ne peut pas anticiper toutes les variations de contenu.
- **Option A** (recommandée) : Remplacer le `SizedBox(height: computedHeight)` + `PageView.builder` par un `PageView` dont la hauteur est calculée dynamiquement. Comme `PageView` exige une hauteur fixe, mesurer la hauteur max de la première page au premier build avec un `GlobalKey` + `WidgetsBinding.instance.addPostFrameCallback`, puis `setState` avec la hauteur mesurée. Fallback initial : `_bodyFooterHeight` actuel (200).
- **Option B** (pragmatique) : Augmenter `_bodyFooterHeight` à ~230px (marge confortable pour 3 lignes de titre + description + footer) et garder le `ClipRect` comme filet de sécurité.
- La ligne à modifier est `static const double _bodyFooterHeight = 200.0;` (ligne ~79).
- Le `ClipRect` wrapper (déjà en place) empêche l'overflow visible en mode debug, mais le contenu reste tronqué.

**Références code** :
```dart
// topic_section.dart ligne ~79
static const double _bodyFooterHeight = 200.0;

// topic_section.dart lignes ~111-126 — le LayoutBuilder + SizedBox
LayoutBuilder(
  builder: (context, constraints) {
    final cardWidth = constraints.maxWidth * 0.88;
    final hasAnyImage = topic.articles.any((a) => ...);
    final imageHeight = hasAnyImage ? cardWidth / (16 / 9) : 0.0;
    const bodyHeight = _bodyFooterHeight;
    final computedHeight = imageHeight + bodyHeight;
    return ClipRect(
      child: SizedBox(height: computedHeight, child: _buildPageView(topic)),
    );
  },
)
```

---

## 2. Badges éditoriaux : aligner avec le design system

**Problème** : Les badges (`EditorialBadge`) utilisent des couleurs sémantiques (primary rouge, info bleu, success vert) qui créent un "arc-en-ciel" visuel non cohérent avec le design system Facteur, qui est très neutre (beiges, gris, touches de rouge subtiles).

**Proposition** : Repartir d'un gris semi-transparent uniforme, déjà présent dans le design system. Garder les emojis comme seul différenciateur visuel entre types de badges.

**Fichier** : `apps/mobile/lib/features/digest/widgets/editorial_badge.dart`

**Changement** : Dans `_badgeConfig()`, remplacer les 4 configs couleur par une seule approche neutre :
```dart
// Remplacer les couleurs individuelles par :
// Light mode : fond = noir 8% alpha, texte = textSecondary
// Dark mode : fond = blanc 12% alpha, texte = textSecondary
// Toutes les balises utilisent la même palette neutre
```

**Référence design system** (`apps/mobile/lib/config/theme.dart`) :
- Light : `backgroundSecondary: Color(0xFFEBE0CC)`, `textSecondary: Color(0xFF7A7775)`
- Dark : `backgroundSecondary: Color(0xFF161616)`, `textSecondary: Color(0xFFA6A6A6)`
- Pattern existant pour gris transparent : `colors.textTertiary.withValues(alpha: 0.25)` (utilisé dans les dots du carrousel)

---

## 3. CTA "Donner un retour" n'apparaît pas

**Problème** : Le `ClosureBlock` s'affiche maintenant systématiquement (fix précédent : fallback `"Bonne lecture !"`), mais le bouton "Donner un retour" n'apparaît que si `ctaText != null`. Or le backend renvoie `cta_text: null` par défaut (voir `editorial_prompts.yaml` ligne 104 : `cta_text : toujours null`).

**Fichier** : `apps/mobile/lib/features/digest/widgets/closure_block.dart`

**Fix** : Le bouton "Donner un retour" et son texte introductif ne dépendent pas réellement du contenu de `ctaText` — c'est toujours le même CTA statique. Rendre le bouton inconditionnel :

```dart
// closure_block.dart lignes 78-108
// AVANT :
if (widget.ctaText != null) ...[
  const SizedBox(height: 16),
  Text(widget.ctaText!, ...),
  const SizedBox(height: 12),
  OutlinedButton(...)
]

// APRÈS :
const SizedBox(height: 16),
Text(
  'Une suggestion ? Un avis ?',  // Texte statique de fallback
  style: TextStyle(fontSize: 13, ...),
),
const SizedBox(height: 12),
OutlinedButton(
  onPressed: () { showModalBottomSheet(...FeedbackBottomSheet...) },
  child: const Text('Donner un retour'),
),
```

**Alternative** : Si on veut garder la possibilité d'un texte CTA custom du backend, utiliser `widget.ctaText ?? 'Une suggestion ? Un avis ?'` comme fallback.

---

## 4. Compteur : ajouter le label X/Y et centrer à droite

**Problème** : Le compteur en mini-barres est trop discret sans indicateur numérique. L'utilisateur veut voir `2/4` (ou le ratio approprié) juste à gauche des barres, et que le groupe soit bien aligné à droite du header.

**Fichier** : `apps/mobile/lib/features/digest/screens/digest_screen.dart`

**Changement dans `_buildDiscreteCounter()`** (lignes ~640-657) :
```dart
// AVANT : juste les barres
return Row(
  mainAxisSize: MainAxisSize.min,
  children: List.generate(denominator, (i) { ... }),
);

// APRÈS : label + barres
return Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Text(
      '$processed/$denominator',
      style: TextStyle(
        color: isComplete ? colors.success : colors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
    const SizedBox(width: 6),
    ...List.generate(denominator, (i) {
      final isDone = i < processed;
      return Container(
        width: 14,
        height: 3,
        margin: EdgeInsets.only(right: i < denominator - 1 ? 3 : 0),
        decoration: BoxDecoration(
          color: isDone
              ? (isComplete ? colors.success : colors.primary)
              : colors.textTertiary.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(1.5),
        ),
      );
    }),
  ],
);
```

**Position dans le header** (lignes ~322-329) : déjà bien positionné à droite dans un `Row` avec `MainAxisAlignment.spaceBetween`. Vérifier que le `UpdateButton` ne prend pas trop de place — si besoin, inverser l'ordre (counter après UpdateButton, ou supprimer le `SizedBox(width: space2)` entre les deux).

---

## Fichiers à modifier (résumé)

| # | Fichier | Changement |
|---|---------|-----------|
| 1 | `apps/mobile/lib/features/digest/widgets/topic_section.dart` | Augmenter `_bodyFooterHeight` ou calcul dynamique |
| 2 | `apps/mobile/lib/features/digest/widgets/editorial_badge.dart` | Palette neutre (gris transparent) |
| 3 | `apps/mobile/lib/features/digest/widgets/closure_block.dart` | Rendre le bouton CTA inconditionnel |
| 4 | `apps/mobile/lib/features/digest/screens/digest_screen.dart` | Ajouter label `X/Y` au compteur |

## Vérification

```bash
cd apps/mobile && flutter analyze   # 0 nouvelles erreurs
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080/api/
```

Checklist visuelle :
- [ ] Carrousel : aucune carte tronquée (tester avec titres longs, 1-3 lignes)
- [ ] Badges : tous en gris neutre, emojis visibles, cohérent light/dark
- [ ] CTA "Donner un retour" visible en bas du digest (scroller jusqu'en bas)
- [ ] Compteur : affiche "2/4 ━━━━" avec barres, vert quand complété
