# Handoff — Reading Progress Feature: Ajustements Post-Test

## Contexte

La feature "reading progress" a été implémentée sur la branche `claude/add-rich-content-feature-iMo58` (2 commits: `21c9363`, `f1605d7`). Le user a testé et identifié 6 ajustements nécessaires, classés par priorité.

## Branche de travail

`claude/add-rich-content-feature-iMo58` — continuer dessus.

## Ce qui existe déjà (NE PAS refaire)

- **Backend complet** : champ `reading_progress` sur `UserContentStatus`, migration Alembic (`rp01`), schemas, services avec `GREATEST()`, collection_service, recommendation_service
- **Mobile** : modèle `Content.readingProgress`, `ReadingBadge` widget, `FeedCard` intégration, progress bar dans le reader, scroll tracking via `NotificationListener<ScrollNotification>`, WebView JS bridge, persistence au `dispose()`
- **Migration SQL** (à appliquer manuellement) : `ALTER TABLE user_content_status ADD COLUMN reading_progress SMALLINT NOT NULL DEFAULT 0;`

---

## Issues à résoudre (par priorité)

### 1. [CRITIQUE] Scroll très lent sur les longs articles — Performance ruinée

**Symptôme** : L'app est très ralentie au scroll, surtout sur les longs articles.

**Cause probable** : Le `NotificationListener<ScrollNotification>` à la ligne 855 de `content_detail_screen.dart` appelle `setState()` à chaque `ScrollUpdateNotification`, ce qui reconstruit tout le widget tree à chaque pixel de scroll.

**Fichier** : `apps/mobile/lib/features/detail/screens/content_detail_screen.dart` (lignes 855-874)

**Piste de fix** :
- Ne PAS appeler `setState()` pour chaque scroll event. Utiliser un `ValueNotifier<double>` pour `_maxReadingProgress` et un `ValueListenableBuilder` uniquement sur la progress bar
- Ou throttler les updates (ex: ne mettre à jour que si delta > 1%)
- La progress bar elle-même peut utiliser `RepaintBoundary` pour isoler les repaints
- Vérifier aussi que `_onScrollFabOpacity()` (ligne 858) n'appelle pas `setState()` trop fréquemment

```dart
// Problème actuel (ligne 866-869):
if (capped > _maxReadingProgress) {
  setState(() {        // <-- reconstruit TOUT le widget tree
    _maxReadingProgress = capped;
  });
}
```

### 2. [IMPORTANT] Détection de contenu partiel insuffisante

**Symptôme** : La détection `plainTextLength(articleText) < 500` est trop basique.

**Fichier** : `apps/mobile/lib/features/detail/screens/content_detail_screen.dart` (lignes 306-310)

**Amélioration demandée** : Compléter la détection avec des patterns récurrents de contenu tronqué dans les flux RSS :
- Article finissant par `(...)`
- Article finissant par `...`
- Contenu contenant `Lire la suite sur...` / `Lire la suite`
- Contenu contenant `L'article [...] est apparu en premier sur [...]`
- `Read more on...` / `Continue reading`
- Article finissant par `[...]`

**Fichier util existant** : `apps/mobile/lib/core/utils/html_utils.dart` (contient déjà `plainTextLength()`) — ajouter une fonction `isPartialContent(String htmlContent)` qui combine la longueur + les patterns.

### 3. [IMPORTANT] Design de la progress bar — "pas assez visible et trop visible"

**Symptôme** : La barre est à la fois trop discrète (on ne la remarque pas) et visuellement dérangeante quand on la voit.

**Fichier** : `content_detail_screen.dart` lignes 1158-1171

**État actuel** : `LinearProgressIndicator` de 2.5px, couleur `primary` à 0.7 alpha, fond `border` à 0.3 alpha.

**Pistes de redesign** :
- Passer à une barre de **1.5-2px** mais avec une couleur plus nette (alpha 1.0) et un fond transparent → plus subtile mais plus lisible
- Utiliser la couleur `success` (vert) plutôt que `primary` pour donner un sentiment positif de progression
- Animation smooth avec `Curves.easeOut`
- Optionnel : la barre n'apparaît qu'après 5% de scroll (pas dès l'ouverture)

### 4. [IMPORTANT] Badge affiche "Lu" après seulement 10% de lecture

**Symptôme** : Après avoir scrollé ~10% dans le reader, le badge passe à "Lu" au lieu de "Parcouru".

**Cause probable** : Le `readingLabel` getter dans `content_model.dart` (ligne 134-141) fonctionne correctement en théorie (< 30% → "Parcouru"), MAIS le problème vient probablement du fait que l'article est marqué `ContentStatus.consumed` par le timer de 30s (`_startViewTimer`), et le getter retourne "Lu" pour `consumed` sans `readingProgress > 0` (ligne 140). Vérifier aussi que le `readingProgress` persisté est correct.

**Fichier** : `apps/mobile/lib/features/feed/models/content_model.dart` (lignes 134-141)

**Fix** : Le statut `consumed` ne devrait PAS overrider le label basé sur le `readingProgress` quand celui-ci est > 0. Ajuster la logique :
```dart
String? get readingLabel {
  if (status == ContentStatus.unseen && readingProgress == 0) return null;
  if (readingProgress >= 90) return 'Lu jusqu\'au bout';
  if (readingProgress >= 30) return 'Lu';
  if (readingProgress > 0) return 'Parcouru';
  if (status == ContentStatus.consumed) return 'Lu';
  return null;
}
```
Vérifier aussi que le progress est bien persisté ET rechargé côté feed (le `readingProgress` est-il bien renvoyé par l'API dans le feed listing ?).

### 5. [NICE-TO-HAVE] Badge "Lu" pas assez positif

**Fichier** : `apps/mobile/lib/features/feed/widgets/reading_badge.dart`

**Suggestion** : Remplacer le texte/icône du badge "Lu" (30-89%) pour le rendre plus engageant. Exemples :
- Icône : `PhosphorIcons.bookOpen` ou `PhosphorIcons.checkCircle` au lieu de `Icons.check`
- Texte alternatif : "Bien lu" ou garder "Lu" avec une icône plus chaleureuse
- Cohérence icônes : utiliser uniquement PhosphorIcons (pas mixer avec Material Icons)

### 6. [NICE-TO-HAVE] Nudges en fin d'article

**Contexte** : Fonctionnalités P2 discutées mais non encore implémentées.

**Demande** : Ajouter des nudges contextuels quand `readingProgress >= 90%` :
- **"Ajouter une note"** — si l'article n'a pas de note
- **"Enregistrer l'article"** — si l'article n'est pas dans une collection

**Emplacement** : En bas de l'article dans le reader, ou via un subtle bottom sheet/snackbar après quelques secondes à >= 90%.

**Fichiers concernés** : `content_detail_screen.dart` (détection du seuil), nouveau widget ou intégration dans le flow existant des notes/collections.

---

## Fichiers principaux à modifier

| Fichier | Issues |
|---------|--------|
| `apps/mobile/lib/features/detail/screens/content_detail_screen.dart` | #1, #2, #3, #6 |
| `apps/mobile/lib/features/feed/models/content_model.dart` | #4 |
| `apps/mobile/lib/features/feed/widgets/reading_badge.dart` | #5 |
| `apps/mobile/lib/core/utils/html_utils.dart` | #2 |

## Contraintes techniques

- **Python 3.12 only** (pas 3.13+)
- **`list[]` natif** (pas `List` de typing)
- **Alembic migrations via Supabase SQL Editor** (pas CLI)
- **Flutter SDK >=3.0.0 <4.0.0**
- **Riverpod 2.5** pour le state management

## Ordre d'implémentation recommandé

1. **#1 Performance** (critique, doit être fait en premier — l'app est inutilisable sinon)
2. **#4 Badge "Lu" à 10%** (bug logique, fix rapide)
3. **#3 Redesign progress bar** (UX)
4. **#2 Détection partielle** (amélioration fonctionnelle)
5. **#5 Badge plus positif** (polish)
6. **#6 Nudges** (nouvelle mini-feature)
