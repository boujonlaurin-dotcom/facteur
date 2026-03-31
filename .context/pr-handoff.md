# PR — YouTube Shorts 9:16 aspect ratio + fullscreen immersion (auto-hide header/FABs)

## Quoi
- Passe le player YouTube en ratio 9:16 pour les Shorts (au lieu du 16:9 par defaut)
- Auto-hide du header et des FABs apres 2.5s de lecture video, restauration immediate a la pause
- Resolution du conflit scroll/video: les timers se cancel mutuellement

## Pourquoi
Issues 1 et 3 du bug doc `docs/stories/core/bug-youtube-ux-e2e-regressions.md`. Les Shorts s'affichaient en letterbox 16:9 (mauvais ratio). Le header et les FABs restaient visibles pendant la lecture video car le mecanisme d'auto-hide ne se declenchait que sur scroll — or l'utilisateur ne scrolle pas en regardant une video.

## Fichiers modifies
- Mobile : `apps/mobile/lib/features/detail/screens/content_detail_screen.dart`

C'est le seul fichier modifie. Le `YouTubePlayerWidget` exposait deja `aspectRatio` et `onPlayStateChanged` (travail Agent A), il suffisait de les wirer.

## Zones a risque
- **`_onVideoPlayStateChanged` + `_onScrollFabOpacity`** : Ces deux methodes manipulent les memes ValueNotifiers (`_headerOpacity`, `_fabOpacity`). Un timer conflict pourrait causer un flash ou un etat incoherent. Le cancel mutuel est la pour ca, mais a verifier en conditions reelles.
- **Timing du hide (2.5s)** : Choix arbitraire aligne sur le delai FAB existant dans `_onScrollFabOpacity`. Peut necessiter un ajustement UX.

## Points d'attention pour le reviewer
1. **Cancel mutuel des timers** : Dans `_onScrollFabOpacity`, `_videoPlayHideTimer?.cancel()` est appele en premier. Dans `_onVideoPlayStateChanged(false)`, les scroll timers sont cancel. Verifier qu'il n'y a pas de scenario ou les deux fires en meme temps.
2. **`mounted` check** : Le timer callback verifie `mounted && _isVideoPlaying` avant de modifier les ValueNotifiers. C'est necessaire car le timer peut fire apres navigation away.
3. **Pas de `setState`** : Tout passe par ValueNotifier, coherent avec le pattern existant du fichier.

## Ce qui N'A PAS change (mais pourrait sembler affecte)
- Le comportement scroll pour les articles (non-video) est inchange — `_onVideoPlayStateChanged` n'est wire que dans `_buildVideoContent()`
- Le `SizedBox(height: headerHeight)` spacer au-dessus du player est conserve tel quel — le header slide away comme overlay, le layout ne bouge pas
- Le `YouTubePlayerWidget` lui-meme n'a pas ete modifie

## Comment tester
1. **Shorts 9:16** : Ouvrir un contenu Short (URL contenant `/shorts/`) -> le player doit etre en format vertical portrait, pas de bandes noires laterales
2. **Video normale** : Ouvrir une video YouTube classique -> ratio 16:9 inchange
3. **Auto-hide** : Lancer une video -> attendre ~3s -> header et FABs doivent disparaitre (slide up / fade)
4. **Restore on pause** : Mettre la video en pause -> header et FABs reapparaissent immediatement
5. **Scroll pendant video** : Scroller la zone metadata pendant la lecture -> le comportement scroll prend le dessus normalement
6. **Article (regression)** : Ouvrir un article texte -> header/FABs se comportent comme avant (hide on scroll, restore on stop)

```bash
cd apps/mobile && flutter analyze  # Pas de nouvelles erreurs
```
