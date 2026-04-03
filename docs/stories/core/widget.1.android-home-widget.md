# Story: Widget Android Home Screen — Digest Preview

## Contexte

Les utilisateurs Android swipent left sur leur home screen et atterrissent sur Google News par réflexe. Un widget Facteur sur la home screen intercepte cette habitude en rendant le digest visuellement présent.

## Scope

Widget Android affichant :
- Header "Facteur" + streak
- Message contextuel ("Ton essentiel du jour t'attend !")
- Card du 1er article (thumbnail + titre + source/topic)
- 2 boutons : "Voir N autres news" (→ digest) et "Explorer" (→ feed)

## Architecture

- **Dart** : `WidgetService` pousse les données digest vers SharedPreferences via `home_widget`
- **Kotlin** : `FacteurWidget` (AppWidgetProvider + RemoteViews) lit SharedPreferences et affiche le layout
- Pont de données : `home_widget` package (v0.7.0)
- Images : téléchargées en local par Flutter, chemin passé au widget

## Fichiers

### Nouveaux
- [x] `lib/core/services/widget_service.dart`
- [x] `android/.../kotlin/.../FacteurWidget.kt`
- [x] `android/.../res/layout/facteur_widget.xml`
- [x] `android/.../res/xml/facteur_widget_info.xml`
- [x] `android/.../res/values/strings.xml`

### Modifiés
- [x] `pubspec.yaml` — home_widget dependency
- [x] `AndroidManifest.xml` — widget receiver
- [x] `digest_provider.dart` — sync widget on load/action/complete
- [x] `streak_provider.dart` — sync widget on streak fetch
- [x] `main.dart` — home_widget init

## Statut

- [x] Implementation
- [x] Build OK (flutter build apk --debug)
- [x] Pre-existing tests unaffected (157 pass, 35 pre-existing failures)
- [ ] Manual test on Android device
