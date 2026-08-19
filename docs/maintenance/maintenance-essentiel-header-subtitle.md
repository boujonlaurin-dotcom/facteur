# Maintenance — sous-titre de l'en-tête Essentiel accordé à la sélection

> Type : **Maintenance** (copy UI). Périmètre : mobile only, 1 helper + 1 widget.
> Aucun changement d'API, de schéma DB ni de navigation.

## Constat

En haut de l'onglet Essentiel, sous le titre de la carte héros, une ligne
annonce le geste à faire : « Choisis les articles que tu liras aujourd'hui. »

Cette ligne était **codée en dur** dans `_Header`
(`apps/mobile/lib/features/flux_continu/widgets/essentiel_hi_fi_card.dart`),
alors que le titre juste au-dessus, lui, suit déjà la sélection
(`editionPillLabel` → « Hier », « Cette semaine », « mar. 24 »).

Conséquence : quand on remonte le temps via le rewind (timeline overlay), la
carte affiche « Hier » **et** « Choisis les articles que tu liras aujourd'hui. »
La phrase ment deux fois :

- une lettre passée est **figée / lecture seule** (`_singleDaySlivers` ne passe
  que `onTapArticle` ; le tri est explicitement désactivé pour tout ce qui n'est
  pas `EditionToday`, cf. `canTriage` dans `essentiel_hi_fi_card.dart`) — il n'y
  a donc aucun choix à y faire ;
- « aujourd'hui » désigne un jour qui n'est pas celui affiché.

Même problème sur la rétro « Cette semaine ».

## Correctif

Un helper pur, co-localisé avec `editionPillLabel` dans
`selected_edition_date_provider.dart` (même convention : `now` injectable, testé
sans widget) :

```dart
String editionSubtitleLabel(EditionSelection selection, {DateTime? now})
```

| Sélection | Sous-titre |
|---|---|
| `EditionToday` | « Choisis les articles que tu liras aujourd'hui. » (inchangé) |
| `EditionPastDay` (J-1) | « Voici les articles de ton Essentiel d'hier. Bonne lecture. » |
| `EditionPastDay` (J-2+) | « Voici les articles de ton Essentiel du vendredi 19 juin. Bonne lecture. » |
| `EditionWeek` | « Voici le récap de ta semaine. Bonne lecture. » |

Le jour courant garde le **geste** (la carte y est une pile à trier) ; le passé
**présente** ce qui est là. Pas de nouveau token ni de nouveau composant : le
`Text` existant reçoit désormais une `String` en paramètre (`_Header.subtitle`),
le style (`FacteurTypography.bodySmall`, `height: 1.35`) est intact — donc aucun
impact sur les budgets snap/fit.

> Note : `kEditionMaxPastDays == 1` ⇒ seule « Hier » est atteignable depuis le
> rewind aujourd'hui. La branche J-2+ est là parce que `EditionPastDay` accepte
> n'importe quelle date (deep-link, futur élargissement) et qu'un `switch` sur
> un sealed type doit rester total.

## Fichiers touchés

- `apps/mobile/lib/features/flux_continu/providers/selected_edition_date_provider.dart` — helper `editionSubtitleLabel`
- `apps/mobile/lib/features/flux_continu/widgets/essentiel_hi_fi_card.dart` — `_Header.subtitle` + câblage sur la sélection
- `apps/mobile/test/features/flux_continu/providers/selected_edition_date_provider_test.dart` — 4 cas (today / J-1 / J-2+ / semaine)
- `apps/mobile/test/features/flux_continu/widgets/essentiel_hi_fi_card_test.dart` — 2 widget tests (lettre passée, rétro hebdo) : la description suit la sélection et « Choisis les articles » disparaît

## Vérification

- `flutter test test/features/flux_continu/providers/selected_edition_date_provider_test.dart` → 16/16 ✅
- `flutter test test/features/flux_continu/widgets/essentiel_hi_fi_card_test.dart` → 96/96 ✅
- `flutter test test/features/flux_continu` → 729 passés, **1 échec pré-existant**
  (`theme_section_screen_test.dart` — « ThemeDetailFooter + discovery render even
  when section.hasMore is true » ; vérifié rouge aussi sur l'arbre sans ce diff)
- `flutter analyze --no-fatal-infos --no-fatal-warnings` → **0 erreur** (531 infos
  pré-existants, inchangés)
