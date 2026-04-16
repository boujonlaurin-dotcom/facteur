# PR — Reader: WebView isolation + Perspectives inline (scroll-to-site) + footer UI

## Quoi

3 corrections dans le reader article (`_buildScrollToSiteContent`) et ajustements UI du footer :
1. **WebView isolation** : `_isWebViewActive` devient un verrou one-way — impossible de revenir au reader après activation de la WebView.
2. **Perspectives inline en scroll-to-site** : `PerspectivesInlineSection` est maintenant rendue dans le layout scroll-to-site (articles >= 100 chars), ce qui manquait. Le FAB "œil" scroll vers elle au lieu d'ouvrir la modal.
3. **Footer UI** : footer +20% plus haut, boutons icônes +20%, border-radius "Lire sur" 8→16px, fond orange (alpha 0.18) sur le bouton Tournesol quand actif.

## Pourquoi

- **Bug critique** : après tap "Lire sur...", l'utilisateur pouvait remonter dans l'article et interagir avec le reader au lieu de la WebView. La WebView n'était pas cliquable tant que `_isWebViewActive` était false.
- **Bug perspectives** : `PerspectivesInlineSection` existait dans `_buildInAppContent` mais pas dans `_buildScrollToSiteContent`, le layout utilisé par tous les articles complets. Le FAB ne trouvait jamais `_perspectivesKey.currentContext` → fallback modal systématique.
- **UI** : footer jugé trop compact visuellement.

## Fichiers modifiés

- Mobile :
  - `apps/mobile/lib/features/detail/screens/content_detail_screen.dart` — tous les changements

## Zones à risque

- `_onScrollToSite()` — le verrou one-way empêche `_isWebViewActive` de repasser à `false`. Si la WebView échoue à charger, l'utilisateur ne peut plus revenir au reader sans quitter l'écran. C'est intentionnel (comportement attendu), mais à surveiller si des cas de WebView en erreur remontent.
- `_buildScrollToSiteContent` — la section perspectives est insérée entre l'article et le spacer transparent. Elle a un fond opaque `colors.backgroundPrimary` pour masquer la WebView sous-jacente. Si ce fond venait à manquer, la WebView serait visible à travers.
- `_kFooterContentHeight` 68→82 — tous les calculs qui référencent cette constante (offset de slide du footer, clearance en bas des listes) sont impactés. Vérifier visuellement sur iPhone SE (petit écran).

## Points d'attention pour le reviewer

1. **Verrou one-way** (`_onScrollToSite`, ligne ~619) : `shouldActivate && !_isWebViewActive` remplace `shouldActivate != _isWebViewActive`. Simple mais critique — vérifier que le reset de `_isWebViewActive` se fait bien à la destruction du widget (dispose) et non pendant la session.
2. **Fond opaque sur les containers perspectives** : chaque container a `color: colors.backgroundPrimary`. Sans ça, la WebView (Layer 0) saignerait visuellement pendant le scroll. Tester sur un article avec perspectives chargées puis taper "Lire sur...".
3. **`_ctaTapped` vs `_isWebViewActive` pour la transparence** : le `ColoredBox` utilise maintenant `_isWebViewActive` au lieu de `_ctaTapped` pour passer en transparent, évitant l'artefact visuel entre le tap CTA et le seuil d'activation.
4. **Tournesol** : fond via `SunflowerIcon.sunflowerYellow.withValues(alpha: 0.18)` — constante exposée par le widget, cohérent avec le bookmark qui change d'icône à l'état actif.

## Ce qui N'A PAS changé (mais pourrait sembler affecté)

- `_buildInAppContent` — inchangé, les perspectives inline y existent déjà depuis PR #400.
- `PerspectivesInlineSection` widget — inchangé, utilisé tel quel.
- `_showPerspectives` / `_showPerspectivesSheet` (modal fallback) — inchangé. Le fallback modal reste pour les cas où la section n'est pas encore rendue (loading).
- `pubspec.lock` — bump automatique de `flutter_lints` 3→6 et `lints` 3→6, sans changement de fonctionnalité.

## Comment tester

1. Ouvrir un article complet (>100 chars de contenu).
2. **Bug 1** : Taper "Lire sur [Source]" → la WebView s'anime. Essayer de scroller vers le haut → impossible de revenir au reader. La WebView est cliquable et interactive.
3. **Bug 2** : Attendre que les perspectives se chargent (pill FAB). Taper le bouton œil → la page scrolle vers la `PerspectivesInlineSection` intégrée (pas de modal). Vérifier que la section apparaît bien avant le bouton "Lire sur...".
4. **UI Footer** : Vérifier la hauteur du footer sur iPhone SE et grand écran. Le bouton Tournesol doit avoir un fond orange clair quand l'article est liké.
