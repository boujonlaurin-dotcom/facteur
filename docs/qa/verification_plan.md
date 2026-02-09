# Plan de Vérification Synthétique - Daily Briefing (M6 & M7)

Ce document sert de guide de validation pour les fonctionnalités "Top 3 Daily Briefing" récemment implémentées.

## 1. Validation Backend (Data & API)
**Objectif** : Vérifier que le cycle de vie des données (Génération -> Lecture -> Persistance) fonctionne correctement.

**Commande** :
```bash
cd packages/api && python scripts/verify_briefing_flow.py
# Ou via le script helper créé :
# cd packages/api && bash run_checks.sh
```

**Résultats Attendus** :
- ✅ `Briefing items exist in DB.` (Génération OK)
- ✅ `Item rank X is marked as consumed.` (Mise à jour statut OK)
- 🎉 `SUCCESS: Backend Briefing Flow Verified!`

**Statut Analyse Statique** : ✅ **Validé**. Le script `verify_briefing_flow.py` est présent et implémente correctement la simulation de création, lecture et mise à jour du statut de lecture en base de données.

## 2. Validation Frontend (Logique & State Management)
**Objectif** : Vérifier que la logique Flutter (`FeedNotifier`) met à jour l'état local correctement et appelle les bons endpoints API lorsqu'un article du briefing est consommé.

**Commande** :
```bash
cd apps/mobile && flutter test test/features/feed/briefing_logic_test.dart
```

**Résultats Attendus** :
- `All tests passed!`
- Vérifie spécifiquement que `state.briefing[0].isConsumed` devient `true` et que `repository.markBriefingAsRead` est appelé.

**Statut Analyse Statique** : ✅ **Validé**. Le test `briefing_logic_test.dart` et l'implémentation de `FeedNotifier` (`feed_provider.dart`) sont cohérents. La logique de mise à jour optimiste et d'appel API est correctement codée.

## 3. Validation Visuelle (Manuelle)
**Objectif** : Confirmer le rendu UI final et les animations.

**A faire sur le simulateur** :
1. Lancer l'app (`flutter run`).
2. Vérifier la présence de la section "Top 3" en haut du feed.
3. Cliquer sur un article du Top 3.
4. Fermer la modal d'article.
5. **Constat** : Le titre de l'article doit être barré (strikethrough) et grisé immédiatement.

## 📝 Résumé des Composants Validés

| Composant | Méthode | Couverture | Statut |
|-----------|---------|------------|--------|
| **Backend Data** | `verify_briefing_flow.py` | Création, Lecture DB | ✅ Code Ready |
| **State Logic** | `briefing_logic_test.dart` | Riverpod State, Repository Calls | ✅ Code Ready |
| **UI Widgets** | `flutter analyze` | Syntaxe, Types, Imports | ✅ Code Ready |

L'analyse statique confirme que l'implémentation est prête pour la validation dynamique.
