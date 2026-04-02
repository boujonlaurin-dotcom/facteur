# Handoff : YouTube Error 152-4 on Android — 3ème tentative

## Contexte

L'app Facteur (Flutter) affiche **Error 152-4** sur **tous** les players YouTube dans l'APK Android. Les vidéos fonctionnent parfaitement en Flutter Web (Railway). Le bug est apparu après la mise à jour YouTube de juillet 2025 qui impose une vérification stricte de l'identité de l'embedder.

**2 fix complets ont été tentés, déployés, re-testés sur APK fraîchement téléchargé — l'erreur persiste.**

---

## Ce qui a été tenté (et a ÉCHOUÉ)

### Tentative 1 (PR #313, branche `claude/fix-youtube-android-player-1H38s`)
- Ajout `android:usesCleartextTraffic="true"` dans AndroidManifest.xml
- Ajout `desktopMode: true` dans YoutubePlayerParams → paramètre INVALIDE dans youtube_player_iframe v5.2.2, a causé un build break web → retiré dans PR #316
- **Résultat** : Seul `usesCleartextTraffic` est resté. N'a rien changé au problème.

### Tentative 2 (PR #319, branche `claude/fix-youtube-android-error-yuRHO`)
- **Théorie** : `youtube_player_iframe` charge le HTML via `loadHtmlString()` sans `baseUrl`, donc origin = `about:blank`, pas de header HTTP Referer → YouTube refuse.
- **Fix** : Remplacement complet de `youtube_player_iframe` par `webview_flutter` direct avec `loadHtmlString(html, baseUrl: 'https://www.youtube.com')` + YouTube IFrame API JS inline.
- **Résultat** : Deploy OK, APK re-téléchargé, **MÊME ERREUR 152-4**. La théorie du baseUrl/Referer est donc insuffisante ou incorrecte.

### Ce qui reste en place actuellement (HEAD de main)
- `youtube_player_iframe` RETIRÉ du pubspec.yaml
- Widget `YouTubePlayerWidget` utilise `webview_flutter` directement avec `loadHtmlString(html, baseUrl: 'https://www.youtube.com')`
- `android:usesCleartextTraffic="true"` dans AndroidManifest.xml
- Fichier : `apps/mobile/lib/features/detail/widgets/youtube_player_widget.dart`

---

## Ce qu'on SAIT

1. **YouTube Error 152** = "The video requested cannot be played in an embedded player" — lié à la vérification d'identité de l'embedder
2. **Fonctionne sur Web** (Flutter Web via Railway) mais **PAS sur Android** (APK)
3. Depuis juillet 2025, YouTube utilise le **Android WebView Media Integrity API** pour vérifier l'authenticité de l'app qui embed
4. Le `baseUrl` dans `loadHtmlString` ne suffit PAS à résoudre le problème sur Android
5. Le package `youtube_player_iframe` (qui utilisait `webview_flutter` en interne) avait la même erreur
6. L'article CORSPROXY mentionne que la solution la plus fiable est un **CORS proxy** ou servir depuis **localhost** (pas juste un baseUrl)

## Pistes NON explorées

### Piste A : Servir le HTML depuis un serveur localhost réel
`loadHtmlString` avec `baseUrl` pourrait ne pas suffire car Android WebView traite ça comme du contenu local. Un vrai serveur HTTP localhost (genre `shelf` ou `HttpServer` de dart:io) servant le HTML pourrait fournir un vrai origin HTTP.

### Piste B : Android WebView Media Integrity API
YouTube utilise maintenant cette API pour vérifier le package name et le signing certificate de l'APK. Ça pourrait nécessiter une configuration spécifique dans `build.gradle.kts` ou dans le WebView Android.
- Docs : https://developer.android.com/develop/ui/views/layout/webapps/manage-webview#media-integrity
- Le WebView doit envoyer un attestation token signé par Google Play Services

### Piste C : Utiliser `flutter_inappwebview` au lieu de `webview_flutter`
Ce package offre plus de contrôle sur les headers HTTP, le user-agent, et les paramètres WebView. Possible de forcer un Referer header manuellement.

### Piste D : CORS Proxy / Proxy backend
Router les embeds YouTube via un proxy backend qui ajoute les bons headers. Plus complexe mais mentionné comme "solution la plus fiable" dans les articles.

### Piste E : Revenir à `youtube_player_flutter` (non-iframe)
Le package `youtube_player_flutter` (attention: pas `youtube_player_iframe`) utilise `flutter_inappwebview` en interne et a publié des fixes spécifiques pour Error 150/152 en 2025-2026. Changelog montre des corrections récentes.

### Piste F : Ce n'est peut-être PAS un problème de Referer
Le problème pourrait être structurellement lié au fait qu'un WebView Android dans une app Flutter n'est PAS reconnu comme un "embedded player autorisé" par YouTube, point final. Si c'est le cas, les alternatives sont :
- Ouvrir YouTube dans l'app YouTube native via `url_launcher`
- Utiliser un Player natif Android (ExoPlayer) via un plugin Flutter
- Utiliser `android_intent_plus` pour ouvrir le player YouTube natif in-app

---

## Fichiers clés

| Fichier | Rôle |
|---------|------|
| `apps/mobile/lib/features/detail/widgets/youtube_player_widget.dart` | Widget player YouTube (à modifier) |
| `apps/mobile/lib/features/detail/screens/content_detail_screen.dart` | Écran qui utilise le widget (3 usages : Shorts 9:16, Regular 16:9, Fullscreen) |
| `apps/mobile/android/app/src/main/AndroidManifest.xml` | Config Android |
| `apps/mobile/android/app/build.gradle.kts` | Build config Android (SDK 36, Kotlin 2.1.0) |
| `apps/mobile/pubspec.yaml` | Dépendances Flutter |
| `docs/bugs/bug-youtube-error-152-android.md` | Doc du bug |

## Interface publique du widget (à conserver)

```dart
YouTubePlayerWidget(
  videoUrl: content.url,        // URL YouTube complète
  title: content.title,         // Titre de la vidéo
  aspectRatio: 16 / 9,          // ou 9/16 pour Shorts
  onProgressChanged: callback,  // 0.0 to 1.0, throttle 2%
  onPlayStateChanged: callback, // true = playing
  description: content.description, // optionnel
  footer: widget,               // optionnel
)
```

## Contraintes

- Python 3.12 backend, Flutter mobile + web
- Railway deploy = Flutter Web (Dockerfile dans `apps/mobile/Dockerfile`)
- Le fix doit fonctionner sur Android ET ne pas casser le build web Railway
- Alembic migrations NE MARCHENT PAS sur Railway (SQL via Supabase SQL Editor)
- Branche de développement : `claude/fix-youtube-android-error-yuRHO`
- Après fix, push sur la branche et créer PR vers main

## Approche recommandée

1. **D'abord valider si le problème est structurel** : tester en ouvrant simplement `https://www.youtube.com/embed/VIDEO_ID` dans un WebView Android nu (sans IFrame API, sans JS custom). Si ça marche, le problème est dans notre implémentation. Si ça échoue aussi, le problème est structurel à Android WebView + YouTube.

2. **Si structurel** : implémenter un fallback — ouvrir dans l'app YouTube native via `url_launcher` ou intent. C'est moins élégant mais ça garantit la lecture.

3. **Si implémentation** : tester les pistes A (localhost), C (flutter_inappwebview), ou E (youtube_player_flutter avec ses fixes récents).

## Références

- [YouTube IFrame Player API](https://developers.google.com/youtube/iframe_api_reference)
- [Android WebView Media Integrity](https://developer.android.com/develop/ui/views/layout/webapps/manage-webview#media-integrity)
- [Fix YouTube Error 150/153 in WebViews (CORSPROXY)](https://corsproxy.io/blog/fix-youtube-error-150-153-webview/)
- [youtube_player_flutter #1084](https://github.com/sarbagyastha/youtube_player_flutter/issues/1084)
- [youtube_player_flutter #1087](https://github.com/sarbagyastha/youtube_player_flutter/issues/1087)
- [Error 153 in flutter_inappwebview #2740](https://github.com/pichillilorenzo/flutter_inappwebview/issues/2740)
