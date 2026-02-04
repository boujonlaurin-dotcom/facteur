---
phase: 02-frontend
context_type: ui_ux_rework
based_on: existing_briefing_section
created: 2026-02-04
priority: high
---

# Phase 2: Adaptation UI/UX - Réutilisation du Système Briefing Existant

## Contexte

La Phase 2 Frontend a été initialement implémentée avec de nouveaux composants (`DigestScreen`, `DigestCard`, etc.) créés de zéro. Cependant, l'application dispose déjà d'un système **BriefingSection** (anciennement `daily_top3`) très travaillé visuellement dans le Feed, qui doit être réutilisé comme base pour le nouveau digest de 5 articles.

## État Actuel (À Décommissionner)

### Ancien Système: BriefingSection dans le Feed
**Localisation:** `apps/mobile/lib/features/feed/widgets/briefing_section.dart`

**Fonctionnement actuel:**
- Affiche 3 articles dans une section "L'Essentiel du Jour"
- Container premium avec gradient, border radius 24px, ombre
- Header avec titre "L'Essentiel du Jour", temps de lecture, et badge de progression X/3
- Utilise `FeedCard` pour afficher chaque article
- Bouton personnalisation (œil barré) via `onPersonalize` callback
- Lecture marquée automatiquement au clic sur l'article (pas de bouton "Lu")
- État collapsed quand tous les articles sont consommés

**Intégration actuelle dans FeedScreen:**
```dart
BriefingSection(
  briefing: briefing,
  onItemTap: (item) => _showArticleModal(item.content),
  onPersonalize: (item) => _showPersonalizationSheet(context, item.content),
)
```

### Nouveau Système (Phase 2 Actuelle) - À Refondre
**Localisation:** `apps/mobile/lib/features/digest/`

**Problèmes identifiés:**
- `DigestCard` recrée de zéro au lieu de réutiliser `FeedCard`
- Design différent du BriefingSection premium existant
- Bouton "Lu" inutile (redondant avec le clic sur article)
- Footer d'actions séparé au lieu d'utiliser celui de FeedCard
- Header "Votre Essentiel" différent du header Feed

---

## Spécifications Détaillées

### 1. RÉUTILISATION COMPLÈTE DU BRIEFINGSECTION

#### Composant Base à Réutiliser
**Fichier:** `apps/mobile/lib/features/feed/widgets/briefing_section.dart`

**Éléments à conserver EXACTEMENT:**
```dart
// Container principal premium
Container(
  decoration: BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: containerBgColors, // Adaptatif dark/light
    ),
    borderRadius: BorderRadius.circular(24),
    border: Border.all(
      color: colors.primary.withValues(alpha: isDark ? 0.3 : 0.15),
      width: 1,
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
        blurRadius: 15,
        offset: const Offset(0, 8),
      ),
    ],
  ),
)

// Header avec progression
Row(
  children: [
    // Titre "L'Essentiel du Jour"
    // Temps de lecture
    // Badge de progression X/5
  ],
)

// Liste des articles avec rang
_buildRankedCard(...) // Conserver le design avec N°1, N°2, etc.
```

**Adaptation nécessaire:**
- Changer `itemCount` de 3 à 5
- Adapter le badge de progression pour X/5 au lieu de X/3

---

### 2. SUPPRESSION DU BOUTON "LU"

**Rationale:** Dans le système Briefing existant, la lecture se marque automatiquement quand l'utilisateur clique sur l'article pour l'ouvrir. Le bouton "Lu" séparé est redondant et encombre l'interface.

**Action:**
- Supprimer le bouton "Lu" du footer
- Conserver la logique: `onTap` sur la carte → marquer comme lu + ouvrir l'article
- La carte passe en opacité 0.6 automatiquement après lecture

---

### 3. AJOUT DES BOUTONS "SAUVEGARDER" ET "PAS INTÉRESSÉ" DANS LE FOOTER EXISTANT

#### Contrainte Critique
**PAS DE NOUVEAU FOOTER** - Les boutons doivent s'intégrer dans le footer EXISTANT de FeedCard, pas créer un footer supplémentaire comme dans l'implémentation actuelle.

#### FeedCard Footer Actuel (à adapter)
**Fichier:** `apps/mobile/lib/features/feed/widgets/feed_card.dart` (lignes 125-210)

Le footer actuel contient:
```dart
Container(
  decoration: BoxDecoration(
    color: colors.backgroundSecondary.withValues(alpha: 0.5),
    border: Border(
      top: BorderSide(
        color: colors.textSecondary.withValues(alpha: 0.1),
        width: 1,
      ),
    ),
  ),
  padding: const EdgeInsets.symmetric(
    horizontal: FacteurSpacing.space3,
    vertical: FacteurSpacing.space1,
  ),
  child: Row(
    children: [
      // PARTIE GAUCHE: Source logo + name + recency
      Expanded(
        child: Row(...),
      ),
      
      // PARTIE DROITE: Actions (actuellement juste onPersonalize)
      if (onPersonalize != null)
        InkWell(
          onTap: onPersonalize,
          child: Icon(PhosphorIcons.dotsThreeCircle()),
        ),
    ],
  ),
)
```

#### Nouvelle Structure du Footer
```dart
Row(
  children: [
    // GAUCHE: Info source (compactée si nécessaire)
    Flexible(
      flex: 2,
      child: Row(...),
    ),
    
    // CENTRE/DROITE: Actions en ligne
    Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Bouton Sauvegarder (Bookmark)
        _buildActionButton(
          icon: isSaved 
            ? PhosphorIcons.bookmark(PhosphorIconsStyle.fill)
            : PhosphorIcons.bookmark(),
          color: isSaved ? colors.primary : colors.textSecondary,
          onTap: onSave,
        ),
        
        SizedBox(width: 12),
        
        // Bouton Pas Intéressé (EyeSlash)
        _buildActionButton(
          icon: PhosphorIcons.eyeSlash(),
          color: colors.textSecondary,
          onTap: onNotInterested,
        ),
      ],
    ),
  ],
)
```

#### Design des Boutons d'Action
```dart
Widget _buildActionButton({
  required IconData icon,
  required Color color,
  required VoidCallback onTap,
}) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      padding: EdgeInsets.all(6),
      child: Icon(icon, size: 20, color: color),
    ),
  );
}
```

**Contraintes de taille:**
- Ne PAS augmenter la hauteur du footer (reste à ~40px)
- Utiliser des icônes compactes (20px)
- Espacement minimal entre les boutons (12px)
- Si manque de place, réduire la largeur du nom de source (ellipsis)

---

### 4. BOUTON "PAS INTÉRESSÉ" = FONCTIONNEMENT IDENTIQUE À LA PERSONNALISATION ACTUELLE

#### Fonctionnement à Répliquer
**Référence:** `apps/mobile/lib/features/feed/widgets/personalization_sheet.dart`

Quand l'utilisateur tape sur l'œil barré (Pas Intéressé):

1. **Ouvrir le même PersonalizationSheet** que dans le Feed
2. **Montrer les options:**
   - "Moins de [nom_source]"
   - "Moins sur le thème [thème]"
3. **Actions identiques:**
   - `feedProvider.notifier.muteSource(content)`
   - `feedProvider.notifier.muteTheme(theme)`
4. **Notifications:**
   - `NotificationService.showInfo('Source ${content.source.name} masquée')`

**Note:** Réutiliser EXACTEMENT le même `PersonalizationSheet`, pas créer un nouveau `NotInterestedSheet`.

---

### 5. BARRE DE PROGRESSION INTÉGRÉE AU HEADER

#### Design Actuel BriefingSection (à adapter)
```dart
// Badge de progression actuel dans le header
_buildProgressBadge(FacteurColors colors) {
  final readCount = briefing.where((item) => item.isConsumed).length;
  final isDone = readCount == briefing.length;

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: isDone ? colors.success : colors.primary,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      '$readCount/${briefing.length}',
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 12,
      ),
    ),
  );
}
```

#### Nouvelle Barre de Progression (Élégante et Compacte)
**Complémenter** le simple badge texte par une barre de progression visuelle intégrée:

```dart
// Dans le header, à droite du titre
Row(
  children: [
    // Titre et sous-titre
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("L'Essentiel du Jour"),
        Row(
          children: [
            Icon(Icons.clock, size: 14),
            Text('$totalMinutes min de lecture'),
          ],
        ),
      ],
    ),
    
    Spacer(),
    
    // NOUVEAU: Barre de progression compacte
    Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Texte X/5
        Text(
          '$readCount/5',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isDone ? colors.success : colors.textPrimary,
          ),
        ),
        SizedBox(height: 4),
        // Barre segments
        Row(
          children: List.generate(5, (index) {
            final isFilled = index < readCount;
            return Container(
              width: 8,
              height: 4,
              margin: EdgeInsets.only(right: 2),
              decoration: BoxDecoration(
                color: isFilled 
                  ? (isDone ? colors.success : colors.primary)
                  : colors.backgroundSecondary,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        ),
      ],
    ),
  ],
)
```

**Contraintes:**
- Barre très fine (4px de hauteur)
- Segments carrés arrondis (8px de large)
- Pas d'animation complexe pour éviter les rebuilds
- Couleur verte quand complété (isDone)

---

### 6. HEADER AU LOOK & FEEL DU FEED

Le header doit reprendre le style des headers du Feed, pas le titre "Votre Essentiel" actuel.

#### Style Feed à Répliquer
**Référence:** `apps/mobile/lib/features/feed/screens/feed_screen.dart` (lignes 195-230)

```dart
// Header Feed actuel avec FacteurLogo
SliverToBoxAdapter(
  child: Padding(
    padding: EdgeInsets.symmetric(
      horizontal: FacteurSpacing.space6,
      vertical: FacteurSpacing.space4,
    ),
    child: Center(child: FacteurLogo(size: 32)),
  ),
)
```

#### Header Digest (Adapté)
```dart
// Option 1: Logo seul (comme Feed)
SliverToBoxAdapter(
  child: Padding(
    padding: EdgeInsets.symmetric(
      horizontal: FacteurSpacing.space6,
      vertical: FacteurSpacing.space4,
    ),
    child: Center(child: FacteurLogo(size: 32)),
  ),
)

// Puis BriefingSection avec son propre header interne
```

**OU** intégrer le titre dans le BriefingSection comme actuellement mais avec:
- Police et style identiques au Feed
- "L'Essentiel du Jour" (pas "Votre Essentiel")

---

### 7. PLANCIFICATION DU DÉCOMMISSIONNEMENT

#### Phase 1: Migration (Immédiat)
- Créer `DigestBriefingSection` basé sur `BriefingSection`
- Adapter pour 5 articles
- Intégrer dans `DigestScreen`
- Tester en parallèle de l'ancien système

#### Phase 2: Validation (1-2 semaines)
- Valider que le nouveau système fonctionne correctement
- S'assurer que toutes les métriques sont préservées
- Vérifier la fermeture (closure screen) avec streak

#### Phase 3: Décommissionnement
**Fichiers à supprimer/modifier:**

1. **Supprimer de FeedScreen:**
   ```dart
   // Dans feed_screen.dart
   // Supprimer:
   import '../widgets/briefing_section.dart';
   
   // Supprimer l'appel à BriefingSection dans le build
   if (briefing.isNotEmpty) {
     return BriefingSection(...);
   }
   ```

2. **Marquer comme obsolète:**
   - `briefing_section.dart` (ajouter @deprecated)
   - `briefing_card.dart` (si existe)

3. **Nettoyer les modèles:**
   - `DailyTop3Item` peut être remplacé par `DigestItem`
   - Migrer les données si nécessaire

4. **Backend:**
   - L'endpoint `/api/feed` ne doit plus inclure `briefing` dans la réponse
   - Ou garder pour compatibilité mais vide

---

## Implémentation Technique

### Nouveaux Fichiers à Créer

1. `apps/mobile/lib/features/digest/widgets/digest_briefing_section.dart`
   - Copie adaptée de `briefing_section.dart`
   - 5 articles au lieu de 3
   - Footer avec Save + Not Interested
   - Barre de progression dans header

2. `apps/mobile/lib/features/digest/widgets/digest_feed_card.dart`
   - Extension de `feed_card.dart` OU
   - Wrapper qui ajoute les callbacks Save/NotInterested

### Fichiers à Modifier

1. `apps/mobile/lib/features/digest/screens/digest_screen.dart`
   - Remplacer `ListView` avec `DigestCard` par `DigestBriefingSection`
   - Supprimer le header "Votre Essentiel" personnalisé
   - Utiliser le header standard Feed

2. `apps/mobile/lib/features/feed/widgets/feed_card.dart`
   - Ajouter paramètres optionnels: `onSave`, `onNotInterested`
   - Modifier le footer pour afficher ces boutons quand fournis

3. `apps/mobile/lib/config/routes.dart`
   - Aucun changement nécessaire

---

## Anti-Patterns à ÉVITER

❌ **NE PAS:**
- Créer un nouveau footer séparé sous le FeedCard
- Ajouter un bouton "Lu" (redondant avec le clic)
- Créer un nouveau PersonalizationSheet
- Changer le design du container premium BriefingSection
- Augmenter la hauteur du footer
- Utiliser des animations complexes pour la barre de progression

✅ **FAIRE:**
- Réutiliser EXACTEMENT le BriefingSection existant
- Intégrer les boutons dans le footer FeedCard existant
- Utiliser le PersonalizationSheet existant
- Conserver le container avec gradient/ombre/border radius 24px
- Garder le footer compact (~40px)
- Utiliser des icônes PhosphorIcons comme partout dans l'app

---

## Checklist de Validation

### UI/UX
- [ ] Container avec gradient, border radius 24px, ombre
- [ ] Header "L'Essentiel du Jour" avec temps de lecture
- [ ] Barre de progression X/5 segments dans le header
- [ ] 5 cartes avec numérotation N°1 à N°5
- [ ] FeedCard réutilisé sans modification du layout principal
- [ ] Footer avec source (compact) + boutons Sauvegarder/Pas Intéressé
- [ ] Pas de bouton "Lu"
- [ ] Opacité 0.6 sur les articles lus
- [ ] Badge "Sauvegardé" visible quand isSaved=true

### Fonctionnalités
- [ ] Clic sur carte → ouvre article + marque comme lu
- [ ] Bouton Sauvegarder → toggle isSaved
- [ ] Bouton Pas Intéressé → ouvre PersonalizationSheet
- [ ] PersonalizationSheet → muteSource/muteTheme
- [ ] Notifications de confirmation
- [ ] État collapsed quand tous les articles traités

### Décommissionnement
- [ ] BriefingSection retiré du FeedScreen
- [ ] Ancien code marqué @deprecated
- [ ] Navigation Digest par défaut fonctionne
- [ ] Closure screen avec streak fonctionne toujours

---

## Références Code

### Fichiers Clés à Étudier
1. `apps/mobile/lib/features/feed/widgets/briefing_section.dart` (composant base)
2. `apps/mobile/lib/features/feed/widgets/feed_card.dart` (footer à adapter)
3. `apps/mobile/lib/features/feed/widgets/personalization_sheet.dart` (actions)
4. `apps/mobile/lib/features/feed/screens/feed_screen.dart` (header style)
5. `apps/mobile/lib/features/digest/screens/digest_screen.dart` (à refondre)

### Patterns à Respecter
- FacteurColors, FacteurSpacing, FacteurRadius depuis theme.dart
- PhosphorIcons pour toutes les icônes
- NotificationService pour les toasts
- HapticFeedback léger sur les actions

---

**Note importante:** Ces ajustements sont **DES DECISIONS VERROUILLÉES** suite à discussion avec l'utilisateur. Ne pas revisiter ces choix - les implémenter exactement comme spécifié.
