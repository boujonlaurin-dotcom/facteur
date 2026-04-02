# Bug: YouTube Error 152-4 on Android WebView

**Status**: In Progress
**Branch**: `claude/fix-youtube-android-error-yuRHO`
**Severity**: Blocking — all YouTube videos unplayable on Android

---

## Symptômes

- Tous les players YouTube affichent "Error 152-4" sur Android (APK)
- Fonctionne normalement sur Flutter Web (navigateur)
- Erreur apparue après la mise à jour YouTube du 9 juillet 2025 (stricter embedder verification)

## Root Cause

### Le problème réseau : absence de header HTTP Referer

Le package `youtube_player_iframe` utilise `webview_flutter` sous le capot. Sur Android, il charge le HTML du player via `WebViewController.loadHtmlString()` **sans paramètre `baseUrl`**.

Résultat :
- L'origin du WebView est `about:blank`
- **Aucun header HTTP Referer** n'est envoyé aux serveurs YouTube
- Depuis juillet 2025, YouTube bloque les embeds sans Referer valide → Error 152/153

### Pourquoi ça marche sur Web

Sur Flutter Web, le player utilise un iframe natif du navigateur. Le navigateur envoie automatiquement le Referer de la page hôte → YouTube accepte.

### Pourquoi les fix précédents n'ont pas marché

| Fix tenté | Pourquoi inefficace |
|-----------|-------------------|
| `android:usesCleartextTraffic="true"` | Ne concerne que HTTP vs HTTPS, pas le Referer |
| `desktopMode: true` (YoutubePlayerParams) | Paramètre invalide dans v5.2.2, a causé un build break web |

## Solution

**Remplacer le widget `YoutubePlayer` du package par un `WebView` direct** utilisant `webview_flutter` avec :

```dart
controller.loadHtmlString(playerHtml, baseUrl: 'https://www.youtube.com');
```

Le paramètre `baseUrl` configure l'origin du WebView, garantissant que le header HTTP Referer est envoyé correctement à YouTube.

Communication Flutter ↔ JavaScript via `JavaScriptChannel` pour :
- Progress tracking (currentTime / duration)
- Play state changes
- Playback rate control (2x speed boost)

## Fichiers modifiés

- `apps/mobile/lib/features/detail/widgets/youtube_player_widget.dart` — réécriture complète
- `apps/mobile/pubspec.yaml` — retrait éventuel de `youtube_player_iframe`

## Références

- [YouTube IFrame Player API](https://developers.google.com/youtube/iframe_api_reference)
- [Fix YouTube Error 150/153 in WebViews](https://corsproxy.io/blog/fix-youtube-error-150-153-webview/)
- [youtube_player_flutter #1084](https://github.com/sarbagyastha/youtube_player_flutter/issues/1084)
- [youtube_player_flutter #1087](https://github.com/sarbagyastha/youtube_player_flutter/issues/1087)
