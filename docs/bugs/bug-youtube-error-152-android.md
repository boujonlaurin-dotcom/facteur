# Bug: YouTube Error 152-4 / 153 on Android WebView

**Status**: Fix implemented — CORS proxy approach (Option A)
**Branch**: `boujonlaurin-dotcom/fix-youtube-android`
**Severity**: Blocking — all YouTube videos unplayable on Android

---

## Symptômes

- Tous les players YouTube affichent "Error 152-4" (puis 153) sur Android (APK)
- Fonctionne normalement sur Flutter Web (navigateur)
- Erreur apparue après la mise à jour YouTube du 9 juillet 2025 (stricter embedder verification)

## Root Cause

YouTube détecte les Android WebView côté serveur (probable TLS fingerprint ou détection binaire du process WebView) et bloque la lecture embed. Le blocage est au-delà de ce que le client peut contrôler — ni les headers HTTP, ni le UA spoofing, ni le JS fingerprinting ne contournent la détection.

## Tentatives (7 approches client-side, toutes échouées)

| # | Approche | Résultat | Preuve |
|---|----------|----------|--------|
| 1 | `usesCleartextTraffic` + `desktopMode` | Error 152-4 | HTTP vs HTTPS, hors sujet |
| 2 | `webview_flutter` + `loadHtmlString` avec `baseUrl` | Error 152-4 | `baseUrl` ne set pas le Referer sur Android |
| 3 | `webview_flutter` + `loadRequest` (navigation directe) | Error 153 | Referer OK (erreur changée 152→153) mais WebView détecté |
| 4 | Approche 3 + Chrome User-Agent | Error 153 | UA spoofé, toujours bloqué |
| 5 | Approche 4 + `youtube-nocookie.com` | Error 153 | Domaine privacy ne change rien |
| 6 | `flutter_inappwebview` + header suppression + Chrome UA | Error 153 | Diagnostic overlay confirme headers corrects |
| 7 | Approche 6 + JS fingerprint spoofing complet | Error 153 | Spoofing actif mais YouTube détecte quand même |

## Solution : CORS Proxy (corsproxy.io)

L'embed YouTube est routé via `corsproxy.io` qui forward la requête à YouTube avec des headers HTTP légitimes côté serveur. YouTube ne voit jamais le WebView.

### Changements

- **URL embed** : `https://corsproxy.io/?url=<encoded youtube embed url>`
- **Nettoyage** : suppression du script de spoofing JS (~80 lignes), du UA custom, de la suppression X-Requested-With
- **Préservé** : JS bridge (progress tracking, 2x speed boost), error state fallback, long-press overlay

### Fallback

Si le proxy échoue, Options B (proxy self-hosted Railway) et C (thumbnail + YouTube externe) sont disponibles. Le widget conserve le bouton "Regarder sur YouTube" en cas d'erreur.

## Fichiers modifiés

- `apps/mobile/lib/features/detail/widgets/youtube_player_widget.dart` — proxy URL + nettoyage spoofing
- `apps/mobile/pubspec.yaml` — `flutter_inappwebview: ^6.1.5` (inchangé)

## Références

- [Fix YouTube Error 150/153 in WebViews — CORSPROXY](https://corsproxy.io/blog/fix-youtube-error-150-153-webview/)
- [flutter_inappwebview #2740 — Error 153](https://github.com/pichillilorenzo/flutter_inappwebview/issues/2740)
- [flutter #178705 — Error 153](https://github.com/flutter/flutter/issues/178705)
- [Simon Willison — Fixing 153 embed](https://til.simonwillison.net/youtube/fixing-153-embed)
