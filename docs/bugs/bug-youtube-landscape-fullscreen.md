# Bug : Vidéo YouTube horizontale ne passe pas en paysage

## Symptôme

Quand l'utilisateur clique sur "agrandir" (bouton fullscreen) dans le player YouTube pour une vidéo horizontale, la vidéo reste en portrait au lieu de pivoter en paysage.

## Cause racine

`main.dart` verrouille l'orientation en portrait uniquement (`SystemChrome.setPreferredOrientations([portraitUp, portraitDown])`). Le `InAppWebView` ne configure pas les callbacks `onEnterFullscreen` / `onExitFullscreen` pour débloquer temporairement l'orientation.

## Fix

Dans `youtube_player_widget.dart` :
- `onEnterFullscreen` : déverrouiller toutes les orientations + cacher status bar
- `onExitFullscreen` : re-verrouiller en portrait + restaurer status bar

## Fichiers modifiés

- `apps/mobile/lib/features/detail/widgets/youtube_player_widget.dart`

## Status

- [x] Implémenté
