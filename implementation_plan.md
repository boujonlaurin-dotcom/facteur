# Plan d'implémentation - Icônes launcher Android

## Objectif

Corriger l'erreur de build `flutter_launcher_icons` liée au fichier manquant `assets/icons/facteur_logo.png`.

## Hypothèses

- Le build tourne depuis la racine du repo, mais `flutter_launcher_icons` s'exécute bien dans `apps/mobile/`.
- Le fichier `apps/mobile/assets/icons/facteur_logo.png` est présent localement mais non versionné, donc absent en CI.

## Étapes

1. **Vérification**: Confirmer le chemin exact et le nom du fichier d'icône dans `apps/mobile/assets/icons/`.
2. **Correctif**: Ajouter l'asset manquant au repo (ou ajuster `image_path` vers un asset déjà versionné).
3. **Validation**: Relancer la génération des icônes (`flutter pub run flutter_launcher_icons`).
4. **Documentation**: Créer une note de maintenance dans `docs/maintenance/`.

## Test rapide

- Depuis `apps/mobile/`, exécuter `flutter pub run flutter_launcher_icons` et vérifier l'absence d'erreur.

---

# Plan d'implémentation - Briefing manquant

## Objectif

Rétablir l'affichage du briefing quotidien dans le feed, même si un filtre est actif, et éviter les absences liées à la requête API.

## Hypothèses

- Le briefing existe en base mais n'est pas renvoyé car `mode` est défini côté client.
- Les utilisateurs attendent le briefing dans tous les modes de feed.

## Étapes

1. **API**: Assouplir la condition de récupération du briefing dans `packages/api/app/routers/feed.py` pour ne plus dépendre de `mode`.
2. **Validation**: Vérifier que `briefing` est présent dans la réponse du feed avec et sans filtre.
3. **Documentation**: Mettre à jour le bug doc avec la cause racine et la vérification.

## Test rapide

- Appeler `/api/feed?limit=1&offset=0` avec et sans `mode`, et vérifier que `briefing` est non vide.

---

# Plan d'implémentation - Personalization nudge manquant (CI)

## Objectif

Rendre le build APK CI stable en ajoutant les fichiers Dart utilises mais non versionnes.

## Hypotheses

- Les widgets `personalization_nudge.dart` et `personalization_sheet.dart` ainsi que `skip_provider.dart` sont presents localement mais absents du repo.
- La CI compile sur Linux (case-sensitive), donc toute divergence de nom de fichier devient bloquante.

## Etapes

1. **Inventaire**: Lister les imports du feed qui pointent vers des fichiers non versionnes.
2. **Correctif**: Ajouter les fichiers manquants au repo sans refactor.
3. **Verification**: Lancer un `flutter analyze` cible sur les fichiers concernes.
4. **Documentation**: Ajouter un bug doc et un script de verification.

## Test rapide

- Executer `docs/qa/scripts/verify_feed_personalization_nudge.sh`.
