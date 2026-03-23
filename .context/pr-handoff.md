# Handoff: Fix Reader header transparency + note nudge positioning

## Branche cible
Continuer sur la branche actuelle `boujonlaurin-dotcom/fix-reader-webview-ux`.

## Contexte
Deux bugs toujours visibles dans le reader (content_detail_screen) apres les premiers correctifs :
1. La status bar Android est transparente quand le header WebView est affiche
2. Le SnackBar "Article termine. Ajouter une note ?" apparait trop haut sur l'ecran

---

## Bug A : Status bar Android transparente dans le header WebView

**Fichier** : `apps/mobile/lib/features/detail/screens/content_detail_screen.dart`

**Symptome** : Quand l'utilisateur est en mode WebView (apres "Lire sur..."), la barre de status Android (heure, batterie, reseau) a un fond transparent au lieu de reprendre la couleur du header (`backgroundPrimary`). On voit le contenu de la WebView (elements de la page web) transparaitre derriere les icones systeme. Voir captures image-v20.png et image-v21.png.

**Cause** : Le header (`_buildHeader()`, ligne 1147) utilise `SafeArea(bottom: false)` qui pousse le `Container` avec `color: backgroundPrimary` SOUS la zone de status bar. La status bar elle-meme n'a pas de fond colore — elle est transparente par defaut sur Android. Le header est dans un `Positioned(top: 0)` dans le Stack (ligne 981), mais la `SafeArea` cree un padding top qui laisse la zone status bar sans couleur de fond.

**Architecture actuelle** (lignes 981-994 + 1147-1161) :
```dart
// Dans le body Stack :
Positioned(
  top: 0, left: 0, right: 0,
  child: AnimatedSlide(
    // ...
    child: _buildHeader(context, content),  // line 993
  ),
),

// _buildHeader() :
Widget _buildHeader(...) {
  return SafeArea(          // line 1152 — pushes content below status bar
    bottom: false,
    child: Container(       // line 1154 — backgroundPrimary starts BELOW status bar
      decoration: BoxDecoration(color: colors.backgroundPrimary),
      child: Column(...)    // header content
    ),
  );
}
```

**Fix** : Wrapper la `SafeArea` dans un `Container`/`ColoredBox` qui remplit la zone status bar avec `backgroundPrimary` :

```dart
Widget _buildHeader(...) {
  return ColoredBox(
    color: colors.backgroundPrimary,  // ← fills status bar area
    child: SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: FacteurSpacing.space2,
          vertical: FacteurSpacing.space3,
        ),
        // Remove decoration since parent ColoredBox handles bg color
        child: Column(...)
      ),
    ),
  );
}
```

Cela garantit que la couleur `backgroundPrimary` s'etend depuis le bord superieur de l'ecran (top: 0 du Positioned) jusqu'en dessous du contenu header. La `SafeArea` continue de pousser le contenu interactif sous la status bar, mais la couleur de fond couvre toute la zone.

**Alternative** : Garder le `Container` avec `decoration`, mais l'envelopper d'un `ColoredBox` parent. L'important est qu'un widget avec la bonne couleur soit rendu AVANT (au-dessus dans le widget tree de) la SafeArea.

---

## Bug B : SnackBar "Article termine. Ajouter une note ?" positionne trop haut

**Fichier** : `apps/mobile/lib/features/detail/screens/content_detail_screen.dart`

**Symptome** : Le SnackBar de nudge "Article termine. Ajouter une note ?" (declenche a 90% de progression de lecture) apparait trop haut sur l'ecran, loin du bouton bookmark. Voir capture image-v22.png.

**Cause** : Le nudge utilise `NotificationService.showInfo()` (ligne 349-352) qui passe par le **root `ScaffoldMessenger`** (via `messengerKey` sur `MaterialApp`, `app.dart:23`). Le SnackBar floating est positionne par le root scaffold, pas par le Scaffold local du detail screen. Comme le root scaffold a une `bottomNavigationBar` (tabs Essentiel/Mon flux/Parametres), le SnackBar est positionne au-dessus de cette nav bar, ce qui sur la page detail (full-screen) correspond a une position trop haute.

**Code actuel** (lignes 341-361) :
```dart
void _onReadingProgressNudge() {
  if (_endNudgeShown || _readingProgress.value < 0.9) return;
  _endNudgeShown = true;
  final content = _content;
  if (content == null || !mounted) return;

  if (!content.hasNote) {
    NotificationService.showInfo(          // ← root ScaffoldMessenger
      'Article termine. Ajouter une note ?',
      actionLabel: 'Ajouter une note',
      onAction: _openNoteSheet,
    );
  } else if (!content.isSaved) {
    NotificationService.showInfo(
      'Article termine. Ajouter une note ?',
      actionLabel: 'Enregistrer',
      onAction: _toggleBookmark,
    );
  }
}
```

**Fix** : Utiliser le `ScaffoldMessenger` **local** du detail screen au lieu du global. Remplacer `NotificationService.showInfo(...)` par `ScaffoldMessenger.of(context).showSnackBar(...)` directement dans `_onReadingProgressNudge` :

```dart
void _onReadingProgressNudge() {
  if (_endNudgeShown || _readingProgress.value < 0.9) return;
  _endNudgeShown = true;
  final content = _content;
  if (content == null || !mounted) return;

  final String message = 'Article termine. Ajouter une note ?';
  final String actionLabel;
  final VoidCallback onAction;

  if (!content.hasNote) {
    actionLabel = 'Ajouter une note';
    onAction = _openNoteSheet;
  } else if (!content.isSaved) {
    actionLabel = 'Enregistrer';
    onAction = _toggleBookmark;
  } else {
    return;
  }

  final colors = context.facteurColors;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              onAction();
            },
            child: Text(
              actionLabel,
              style: TextStyle(
                color: colors.primary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
      backgroundColor: colors.backgroundSecondary,
      behavior: SnackBarBehavior.floating,
      elevation: 4,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      duration: const Duration(seconds: 3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
  );
}
```

En utilisant `ScaffoldMessenger.of(context)` dans le build context du detail screen, le SnackBar sera positionne par le Scaffold local (ligne 950) qui connait son propre `floatingActionButton`. Le SnackBar floating apparaitra au bas du detail screen, juste au-dessus du FAB bookmark — exactement la bonne position.

**Note importante** : Le `context` utilise doit etre celui du widget detail screen (pas un context d'un builder interne). Verifier que `_onReadingProgressNudge` a acces au bon context (probablement via `this.context` dans le State).

**Fichiers references** :
- `apps/mobile/lib/features/detail/screens/content_detail_screen.dart` : `_onReadingProgressNudge()` (lignes 341-361), `_buildHeader()` (lignes 1147-1281)
- `apps/mobile/lib/core/ui/notification_service.dart` : SnackBar styling de reference (lignes 44-88)
- `apps/mobile/lib/app.dart:23` : root ScaffoldMessenger key

---

## Fichiers modifies
- `apps/mobile/lib/features/detail/screens/content_detail_screen.dart` (les deux bugs)

## Verification
- **Bug A** : Ouvrir un article → taper "Lire sur [source]" → la status bar Android doit avoir le fond `backgroundPrimary` (beige/blanc), pas transparent. Tester sur emulateur Android.
- **Bug B** : Lire un article jusqu'a ~90% → le SnackBar "Article termine. Ajouter une note ?" doit apparaitre en bas de l'ecran, pres du FAB bookmark, pas au milieu de l'ecran.
- `cd apps/mobile && flutter analyze` doit passer sans nouveaux warnings
