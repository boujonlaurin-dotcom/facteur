# Bug: WebView reader — overlays bloquent les modales (cookies, paywalls)

## Statut
- [ ] En cours d'investigation
- [x] En cours de correction
- [ ] Corrigé (date: YYYY-MM-DD)

## Sévérité
🔴 Critique — interface inutilisable sur les sites avec cookie-wall (Contexte, La Croix, etc.)

## Description

Dans le reader (mode "scroll-to-site"), une fois que l'utilisateur tape « Lire sur [Source] », la WebView s'active et charge le site original. Les overlays Flutter (header en haut, footer en bas) restent visibles et **couvrent la modale de cookies / paywall** qui apparaît au chargement. Quand cette modale verrouille le scroll du `body` (`overflow: hidden`, courant sur les CMP), aucun événement scroll n'arrive au JS bridge → impossible de cacher les overlays par geste.

Résultat : impossible d'accepter les cookies, impossible de naviguer dans la modale.

## Étapes de reproduction
1. Ouvrir l'app, se rendre sur un article d'un site avec cookie-wall (ex : Contexte, La Croix)
2. Lire le contenu in-app jusqu'à voir le bouton « Lire sur [Source] » au footer
3. Taper « Lire sur [Source] » → la WebView s'active
4. **Constat** : la modale cookies apparaît, mais le footer Flutter couvre les boutons « Accepter / Refuser »
5. Tenter de scroller pour cacher le footer → ne fonctionne pas (modale lock body scroll)

## Cause racine

Dans `apps/mobile/lib/features/detail/screens/content_detail_screen.dart` :

1. `_footerOffset` est initialisé à `0.0` (visible) — ligne 161.
2. À l'activation de la WebView (`_onScrollToSite`, ligne 648), aucune action n'est prise pour masquer les overlays.
3. Le `_scrollStopTimer` armé pendant l'animation CTA `_scrollController.animateTo(maxScrollExtent)` ré-affiche le footer 2 s plus tard (`_onScrollDelta`, ligne 726-732).
4. Le JS bridge `ScrollBridge` n'observe que les événements `scroll` du document — quand le body est `overflow:hidden`, il n'en reçoit jamais.

## Solution

UX validée :
- À l'activation WebView : masquer **immédiatement** header + footer (vue maximale → modale visible en entier).
- Après **2 s** : header réapparaît automatiquement (pour permettre le retour).
- Footer reste caché jusqu'à scroll-up explicite (puis comportement reader standard).

Implémentation : modification unique dans `_onScrollToSite` (ligne ~648) :

```dart
if (shouldActivate && !_isWebViewActive) {
  setState(() => _isWebViewActive = true);

  _scrollStopTimer?.cancel(); // annule le timer hérité du scroll CTA
  _animateHeaderTo(1.0);
  _animateFooterTo(1.0);

  Timer(const Duration(seconds: 2), () {
    if (mounted && _isWebViewActive) _animateHeaderTo(0.0);
  });
}
```

## Fichiers concernés
- `apps/mobile/lib/features/detail/screens/content_detail_screen.dart`

## Notes
- Décision UX : pas de tap-to-toggle JS bridge, pas de détection heuristique de modale — l'approche timing suffit.
- Comportement post-arrivée identique au reader d'article (scroll-down cache, scroll-up réaffiche, etc.).
- Screenshots : modale cookies Contexte + La Croix bloquée par footer (joints à la PR).
