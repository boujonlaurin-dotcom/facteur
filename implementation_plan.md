# Plan d'implémentation - Centralisation des wordings Onboarding

Ce plan détaille la migration des chaînes de caractères codées en dur dans le module d'onboarding vers un fichier de constantes centralisé.

## 1. Analyse des sources
Extraction des wordings depuis :
- `IntroScreen`
- `ObjectiveQuestion` (4 options)
- `AgeQuestion` (4 options)
- `ApproachQuestion` (2 options)
- `PerspectiveQuestion` (2 options)
- `ResponseStyleQuestion` (2 options)
- `RecencyQuestion` (2 options)
- `GamificationQuestion` (2 options)
- `WeeklyGoalQuestion`
- `SourcesQuestion` (Search hint, title, subtitle)
- `ThemesQuestion`
- `FinalizeQuestion`
- `AnimatedMessageText` (Liste de messages de transition)

## 2. Création du fichier de constantes
Fichier : `lib/features/onboarding/onboarding_strings.dart`
Structure :
```dart
class OnboardingStrings {
  // Intro
  static const String introTitle = "...";
  // ...
}
```

## 3. Mise à jour des Widgets (Action atomique par fichier)
Pour chaque fichier identifié :
1. Importer `onboarding_strings.dart`.
2. Remplacer les chaînes littérales par `OnboardingStrings.nomDeLaConstante`.

## 4. Vérification
- Analyse statique (`flutter analyze`).
- Vérification visuelle rapide si possible.
