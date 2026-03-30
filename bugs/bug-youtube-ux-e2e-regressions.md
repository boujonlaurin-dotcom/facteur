# Bug Report: YouTube Video UX — E2E Test Regressions (4 Issues)

**Date**: 2026-03-30
**Reporter**: Laurin (E2E testing post-PR #302)
**Severity**: Critique (4 issues bloquants)
**Source PR**: #302 (`feat: YouTube UX polish — header fix, video card design, Shorts, 2x speed`)
**Screenshots**: Fournis par l'utilisateur (detail screen + feed card)

---

## Contexte

PR #302 a implémenté 4 améliorations YouTube. Les tests E2E révèlent que les 4 fonctionnalités ont des problèmes significatifs. Ces issues sont **structurantes** et doivent être distribuées à des agents dev séparés sur une nouvelle branche.

---

## Issue 1 — Shorts : Player horizontal, pas vertical

### Symptôme
Le player YouTube Shorts affiche toujours un player horizontal 16:9 standard. Le `LayoutBuilder` change la hauteur du conteneur mais le player iframe YouTube reste en 16:9 à l'intérieur, créant un décalage avec beaucoup d'espace vide sous la vidéo.

### Root Cause
`_buildVideoContent()` (`content_detail_screen.dart:1842`) change `playerHeight` via LayoutBuilder mais ne modifie PAS l'aspect ratio du player YouTube lui-même. Le `YouTubePlayerWidget` passe toujours `aspectRatio: 16/9` au player web (ligne 209 de `youtube_player_widget.dart`). Le conteneur SizedBox est plus grand, mais le player reste horizontal dedans.

### Fix requis
- Passer un paramètre `aspectRatio` à `YouTubePlayerWidget` (9:16 pour Shorts)
- Le player `web.YoutubePlayer` accepte déjà un `aspectRatio` param — le propager
- Le player `mobile.YoutubePlayerBuilder` n'accepte pas d'aspect ratio — explorer les options (ex: `FittedBox`, `Transform.scale`, ou migration vers `youtube_player_iframe` pour mobile aussi)
- Tester que les contrôles YouTube restent accessibles dans le format vertical

### Fichiers concernés
- `apps/mobile/lib/features/detail/widgets/youtube_player_widget.dart` — ajouter param `aspectRatio`
- `apps/mobile/lib/features/detail/screens/content_detail_screen.dart` — passer `aspectRatio: 9/16` pour Shorts

### Complexité : Haute
Migration potentielle vers `youtube_player_iframe` pour toutes les plateformes.

---

## Issue 2 — Card design : pas de play overlay, emoji pellicule inélégant

### Symptôme
Sur le screenshot "Mon flux", les cards vidéo (ex: ARTE) :
1. N'ont **aucun play overlay** sur la thumbnail malgré une image présente
2. Affichent une icône **pellicule filmStrip** (`PhosphorIcons.filmStrip`) dans la barre de métadonnées — inélégant, pas premium
3. Aucun élément visuel discret rappelant YouTube

### Root Cause
**Play overlay manquant** : `FeedCard` (`feed_card.dart:99-104`) utilise `FacteurThumbnail` SANS passer `overlay`, `durationLabel`, ni `isVideo`. Seul `DigestCard` a été mis à jour dans PR #302 — le `FeedCard` (écran "Mon flux") n'a pas reçu le même traitement.

**Emoji pellicule** : `_buildTypeIcon()` existe en doublon dans `feed_card.dart:522-540` et `digest_card.dart:503-521` — les deux utilisent `PhosphorIcons.filmStrip(PhosphorIconsStyle.fill)` pour les vidéos.

### Fix requis
1. **FeedCard** : ajouter le traitement vidéo identique à DigestCard :
   - Passer `overlay: isVideo ? const VideoPlayOverlay() : null` à `FacteurThumbnail`
   - Passer `durationLabel` pour les vidéos
   - Passer `isVideo: true` pour le placeholder (quand pas de thumbnail)
   - Ajouter la red accent line (3px) en haut de la card
2. **Retirer l'icône filmStrip** dans les deux fichiers (`_buildTypeIcon`). Pour les vidéos, le play overlay + red accent suffisent. Retourner `SizedBox.shrink()` pour video/youtube comme pour les articles.
3. **Optionnel** : ajouter un élément design discret rappelant YouTube (le red accent line fait déjà ce job si appliqué au FeedCard)

### Fichiers concernés
- `apps/mobile/lib/features/feed/widgets/feed_card.dart` — ajouter traitement vidéo
- `apps/mobile/lib/features/digest/widgets/digest_card.dart` — retirer filmStrip
- `apps/mobile/lib/features/feed/widgets/feed_card.dart` — retirer filmStrip

### Complexité : Moyenne

---

## Issue 3 — Fullscreen : header/FABs persistants, contrôles inaccessibles

### Symptôme (voir screenshot detail screen)
En lecture vidéo :
1. Le **header** (back button + source + share) ne disparaît **jamais** — reste visible en permanence
2. Les **FABs** (open external, like, bookmark) restent visibles en bas à droite
3. La **barre de contrôle YouTube** (timecode, play/pause, vitesse, fullscreen) est **inaccessible** — probablement masquée/clippée par le SizedBox du player + le header qui pousse tout vers le bas

### Root Cause
Le mécanisme de hide/show (`_onScrollFabOpacity` dans `content_detail_screen.dart:434-456`) est déclenché par les `ScrollNotification`. Or pour le contenu vidéo, l'utilisateur ne scrolle pas — il regarde la vidéo. Le header ne se cache donc jamais car aucun scroll n'est détecté.

Le `SizedBox(height: headerHeight)` ajouté en ligne 1847 pousse le player vers le bas, ce qui fait que la barre de contrôles YouTube (en bas du player) est potentiellement clippée ou hors zone visible.

### Fix requis
1. **Auto-hide header** pendant la lecture vidéo :
   - Détecter l'état de lecture (playing/paused) depuis le player controller
   - Quand playing : fade out le header après 2-3s d'inactivité
   - Quand paused ou tap : fade in le header
   - Style : header quasi-transparent ou slide-up (comme YouTube)
2. **Masquer les FABs** pendant la lecture vidéo active
3. **Fix contrôles YouTube** : vérifier que le player n'est pas clippé. Le `SizedBox(height: headerHeight)` + le player SizedBox pourraient dépasser la hauteur disponible. Utiliser `Flexible` ou `ConstrainedBox` pour s'assurer que le player entier (y compris ses contrôles) est visible.
4. **Mode fullscreen landscape** : quand l'utilisateur passe en plein écran YouTube, tout le chrome Facteur (header, FABs, metadata) doit disparaître.

### Fichiers concernés
- `apps/mobile/lib/features/detail/screens/content_detail_screen.dart` — header/FAB auto-hide pour vidéo
- `apps/mobile/lib/features/detail/widgets/youtube_player_widget.dart` — exposer l'état de lecture (playing/paused) via callback

### Complexité : Haute
Nécessite une refonte du comportement d'immersion pour le mode vidéo.

---

## Issue 4 — Vitesse 2x : aucun effet réel sur la lecture

### Symptôme
Le long-press sur le player affiche l'indicateur "2x" (overlay visuel) mais la vitesse de lecture réelle de la vidéo ne change pas.

### Root Cause
`youtube_player_flutter` v9.1.1 (`YoutubePlayerController`) n'expose PAS de méthode `setPlaybackRate()`. Le code actuel (`youtube_player_widget.dart:148-150`) ne fait l'appel que pour `kIsWeb` :

```dart
void _startSpeedBoost() {
  setState(() => _isSpeedBoosted = true);
  if (kIsWeb) {
    _webController.setPlaybackRate(2.0);
  }
  // Mobile: youtube_player_flutter v9 doesn't expose setPlaybackRate()
}
```

Sur mobile (Android/iOS), l'indicateur visuel s'affiche mais aucune action n'est effectuée.

### Fix requis
**Option A (recommandée)** : Migrer vers `youtube_player_iframe` pour TOUTES les plateformes. Ce package supporte nativement `setPlaybackRate()` sur mobile ET web. Avantage : résout aussi les issues 1 (aspect ratio) et 3 (meilleur contrôle du player).

**Option B** : Utiliser le JS bridge interne de `youtube_player_flutter` pour injecter `player.setPlaybackRate(2.0)` via l'API JavaScript YouTube IFrame. Fragile et non documenté.

**Option C** : Retirer la feature sur mobile, la garder uniquement sur web. Documenter la limitation.

### Fichiers concernés
- `apps/mobile/lib/features/detail/widgets/youtube_player_widget.dart` — migration ou JS bridge
- `apps/mobile/pubspec.yaml` — si migration de package

### Complexité : Moyenne-Haute

---

## Recommandation architecturale

Les issues 1, 3 et 4 convergent vers un même constat : **`youtube_player_flutter` est limitant** pour les besoins de Facteur. Une migration vers `youtube_player_iframe` (qui fonctionne sur mobile via WebView ET web) résoudrait potentiellement :
- Issue 1 : aspect ratio configurable
- Issue 3 : meilleur contrôle des events player (play/pause state)
- Issue 4 : `setPlaybackRate()` natif

Cette migration devrait être évaluée comme pré-requis avant de traiter les issues individuellement.

---

## Distribution suggérée pour agents

| Agent | Scope | Branche suggérée |
|-------|-------|-----------------|
| Agent A | Migration `youtube_player_iframe` + Issue 4 (2x speed) | `dev-youtube-player-migration` |
| Agent B | Issue 2 (FeedCard video treatment + retirer filmStrip) | `dev-feed-card-video-design` |
| Agent C | Issue 3 (fullscreen immersion) + Issue 1 (Shorts vertical) — dépend de Agent A | `dev-youtube-fullscreen-immersion` |

**Ordre** : Agent B peut travailler en parallèle. Agent A doit finir avant Agent C.

---

## Vérification (post-fix)

- [ ] Shorts : player vertical 9:16, contrôles accessibles
- [ ] Feed cards : play overlay visible sur les thumbnails vidéo, pas d'icône pellicule
- [ ] Digest cards : play overlay visible, pas d'icône pellicule
- [ ] Fullscreen : header et FABs disparaissent pendant la lecture, réapparaissent au tap/pause
- [ ] Contrôles YouTube (seek, play/pause, volume) accessibles en mode normal et fullscreen
- [ ] Long-press 2x : vitesse réelle change sur mobile ET web
- [ ] Pas de régression sur les articles (header, scroll, reader mode)
