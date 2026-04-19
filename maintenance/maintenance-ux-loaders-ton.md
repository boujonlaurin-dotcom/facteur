# Maintenance: UX Loaders & Ton Facteur

**Date:** 2026-04-19
**Classification:** MAINTENANCE (UI/UX uniquement, hors performance)
**Branche:** `boujonlaurin-dotcom/ux-loaders-tone`

---

## Problème

L'app subit des chargements lents (digest et feed), parfois infinis. Les loaders et écrans d'erreur actuels :

- `CircularProgressIndicator` générique avec un seul message neutre.
- Messages d'erreur peu chaleureux (« Erreur de chargement »).
- Aucun fallback en cas d'échecs persistants — l'utilisateur reste bloqué sans canal pour signaler le problème.

Cela amplifie la frustration des problèmes de performance et ne reflète pas le ton de Facteur (sérieux mais décontracté, amical, parfois drôle).

**Out-of-scope** : optimiser les requêtes ou les providers.

---

## Approche

Trois couches d'expérience UI selon la durée du chargement / la persistance de l'erreur :

| Phase | Quand | UI |
|-------|-------|-----|
| **Loading court** (<3s) | t=0 → 3s | `FacteurLoader` animé seul (Lottie dotLottie, `loading_facteur.lottie`) |
| **Loading prolongé** (≥3s) | t≥3s | `FacteurLoader` + `EditorialLoaderCard` rotative (citation/stat/anecdote, change toutes les ~6s) |
| **Erreur 1ère fois** | premier échec | `FriendlyErrorView` : message contextuel par type d'erreur + bouton « Réessayer » |
| **Erreur persistante** (≥2 échecs consécutifs OU 503) | après retry échoué | `LaurinFallbackView` : message « navrés », presse-papier auto-rempli, boutons Mail / WhatsApp |

Le compteur d'échecs est tenu côté UI (`StatefulWidget`), pas dans les providers Riverpod, pour rester strictement UI/UX.

---

## Fichiers touchés

### Nouveaux

```
apps/mobile/lib/shared/data/loader_blurbs.dart
apps/mobile/lib/shared/strings/loader_error_strings.dart
apps/mobile/lib/shared/widgets/loaders/facteur_loader.dart
apps/mobile/assets/loaders/loading_facteur.lottie  # Lottie animation (dotLottie)
apps/mobile/lib/shared/widgets/loaders/editorial_loader_card.dart
apps/mobile/lib/shared/widgets/loaders/loading_view.dart
apps/mobile/lib/shared/widgets/states/friendly_error_view.dart
apps/mobile/lib/shared/widgets/states/laurin_fallback_view.dart
apps/mobile/test/shared/widgets/states/friendly_error_view_test.dart
apps/mobile/test/shared/widgets/states/laurin_fallback_view_test.dart
```

### Modifiés

```
apps/mobile/lib/config/constants.dart                            (ajout LaurinContact)
apps/mobile/lib/features/digest/screens/digest_screen.dart       (intégration LoadingView/FriendlyErrorView/LaurinFallbackView)
apps/mobile/lib/features/feed/screens/feed_screen.dart           (idem, variant inline pour Sliver)
```

---

## Vérification

```bash
cd apps/mobile
flutter pub get
flutter analyze                               # doit rester clean
flutter test                                  # tests widgets verts
flutter run                                   # test manuel
```

**Test manuel :**
1. Loader court : ouvrir digest, vérifier FacteurLoader fluide pendant <3s.
2. Loader prolongé : couper le wifi 5s pendant chargement → carte éditoriale apparaît à 3s, pivote toutes les 6s.
3. Erreur friendly : couper le réseau avant ouverture digest → message à ton chaleureux + retry.
4. Fallback Laurin : forcer 2 erreurs consécutives → `LaurinFallbackView`, tap copie le presse-papier (snackbar OK), boutons Mail/WhatsApp ouvrent les apps natives avec messages pré-remplis.
5. Idem feed.
6. Light + Dark mode : rendu FacteurLoader et cartes correct.

---

## Décisions de cadrage

- **Loader animé** : animation Lottie (dotLottie `.lottie`) via package `lottie: ^3.1.2`. Source : [LottieFiles — Paper plane](https://lottiefiles.com/free-animation/paper-plane-ReywoIFDuD) (Lottie Simple License). Asset stocké dans `apps/mobile/assets/loaders/loading_facteur.lottie`. Remplace l'ancien `BikeLoader` CustomPainter jugé esthétiquement insatisfaisant.
- **Contenu éditorial** : liste hardcodée locale Dart (~40 entrées), pas d'API.
- **Périmètre copy** : strict — uniquement loaders, erreurs, retry, fallback. Pas de revue des labels/onboarding.
- **Fallback contact** : copie presse-papier + 2 boutons Mail / WhatsApp (`url_launcher` déjà présent au pubspec).
- **Numéro WhatsApp Laurin** : à confirmer avant merge ; sinon le bouton WhatsApp est masqué et un TODO inscrit.
