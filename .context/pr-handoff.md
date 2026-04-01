# PR — Fix beta bugs: scroll, gestures, serein filter & UI polish

## Quoi
Correction d'un ensemble de bugs identifiés en beta sur le feed mobile : scroll qui ne revient pas en haut lors des changements de filtre, conflits de gestes entre la carte et ses boutons de footer, haptic feedback tardif sur le bouton "Pas serein". Côté backend, le filtre serein est découplé du mode de feed et appliqué de manière orthogonale.

## Pourquoi
Bugs accumulés sur la branche beta affectant l'expérience utilisateur principale (navigation dans le feed). Le filtre serein était couplé à `FeedFilterMode.INSPIRATION`, ce qui empêchait de l'utiliser indépendamment des autres modes de filtrage.

## Fichiers modifiés

**Backend :**
- `packages/api/app/routers/feed.py` — suppression de la logique de surcharge de mode, passage explicite de `serein`
- `packages/api/app/services/recommendation_service.py` — ajout du paramètre `serein`, appliqué orthogonalement aux autres filtres

**Mobile — Screens :**
- `apps/mobile/lib/features/feed/screens/feed_screen.dart` — scroll-to-top sur tous les changements de filtre, callbacks overflow chips, tracking du filtre interest
- `apps/mobile/lib/features/feed/screens/cluster_view_screen.dart` — timing du haptic feedback (déplacé hors du try block)
- `apps/mobile/lib/features/detail/screens/content_detail_screen.dart` — trigger feedScrollTriggerProvider au retour depuis la vue detail, style container source

**Mobile — Widgets Feed :**
- `apps/mobile/lib/features/feed/widgets/feed_card.dart` — isolation des gestes (footer sorti de la zone de tap), style pill container source, `GestureDetector` avec `HitTestBehavior.opaque` pour le bouton serein
- `apps/mobile/lib/features/feed/widgets/entity_overflow_chip.dart` — ajout callback `onOverflowTap`
- `apps/mobile/lib/features/feed/widgets/keyword_overflow_chip.dart` — ajout callback `onOverflowTap`
- `apps/mobile/lib/features/feed/widgets/source_overflow_chip.dart` — ajout callback `onOverflowTap`
- `apps/mobile/lib/features/feed/widgets/topic_overflow_chip.dart` — signature de callback enrichie `Function(String slug, String label, {bool isTheme})?`
- `apps/mobile/lib/features/feed/widgets/perspectives_bottom_sheet.dart` — suppression du `canLaunchUrl()` check

**Mobile — Digest :**
- `apps/mobile/lib/features/digest/widgets/topic_section.dart` — `_footerHeight` : 37 → 57 px

## Zones à risque

- **`feed_screen.dart`** : beaucoup de points de déclenchement de `_scrollToTop()` ajoutés — un oubli ou un doublon pourrait créer un comportement erratique
- **`recommendation_service.py`** : le filtre serein s'applique maintenant **avant** le mode, ce qui change l'ordre de filtrage — à vérifier sur des datasets avec peu d'articles serein
- **`topic_overflow_chip.dart`** : signature de callback changée, la compatibilité avec tous les call sites est à vérifier

## Points d'attention pour le reviewer

1. **Isolation des gestes dans `feed_card.dart`** : le `GestureDetector` ne wrape plus le footer — vérifier que les boutons source, share, et serein fonctionnent correctement sans propager le tap vers la card
2. **`topic_overflow_chip.dart`** : le callback reçoit maintenant `(slug, label, {isTheme})` — s'assurer que tous les endroits où ce widget est utilisé ont bien été mis à jour
3. **Serein orthogonal au mode** : côté backend, `serein=True` filtre les candidats **avant** le mode. Tester les combinaisons serein + Deep Dive pour s'assurer qu'il reste des résultats
4. **`perspectives_bottom_sheet.dart`** : suppression du guard `canLaunchUrl()` — acceptable sur iOS/Android récents, mais à surveiller si des URLs malformées peuvent arriver

## Ce qui N'A PAS changé (mais pourrait sembler affecté)

- La logique de recommandation en elle-même (scoring, ranking) n'a pas changé — seul l'ordre d'application des filtres serein/mode
- Le modèle de données `FeedFilterMode` est inchangé — seul son usage dans `feed.py` a évolué
- Le digest (hors `topic_section.dart` footer height) n'a pas été touché

## Comment tester

**Backend (local) :**
```bash
cd packages/api && uvicorn app.main:app --port 8080
# Tester les combinaisons :
# 1. serein=true + mode=deep_dive → doit retourner des articles serein uniquement
# 2. serein=true + mode=default → idem
# 3. serein=false + mode=inspiration → comportement inchangé vs avant
curl "http://localhost:8080/feed?serein=true&mode=deep_dive"
```

**Tests automatisés :**
```bash
cd packages/api && pytest -v
cd apps/mobile && flutter test && flutter analyze
```

**Mobile (simulateur ou device) :**
1. Ouvrir le feed → appliquer un filtre source/topic → vérifier que le feed scroll revient en haut
2. Tapper sur une card → vérifier que le footer (source, actions) ne déclenche pas la navigation detail
3. Appuyer sur "Pas serein" → vérifier que le haptic se déclenche immédiatement
4. Ouvrir un article detail → tapper sur la source → vérifier le retour au feed avec scroll en haut
5. Activer le filtre serein → tester combiné avec Deep Dive
