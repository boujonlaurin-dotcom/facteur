# Maintenance — Allègement visuel Couverture médiatique

> Type : **Maintenance UI**. Ajustement de la section inline « Couverture
> médiatique » dans le reader article. Aucun changement backend / DB / Alembic.
> Plan confirmé PO.

## Objectif

Rendre la section moins chargée visuellement dans l'état vide et dans l'état
ouvert, tout en réutilisant les composants existants :
`DivergenceInlineBadge`, la logique de wash du pivot, et le wording de
transparence de l'analyse IA.

## Changements

1. État vide plus discret : padding réduit, label plus petit et atténué,
   filets externes supprimés quand aucune perspective n'est disponible.
2. Polarisation : remplacement de la phrase longue par une balise
   `DivergenceInlineBadge`.
3. Explication du surlignage : paragraphe inline supprimé, texte placé derrière
   un bouton info.
4. Analyse Facteur : CTA/résultat remontés avant la liste des variantes.
5. Transparence IA : mention « Analyse générée par Mistral Large · l'IA peut
   faire des erreurs. » sous le résultat.
6. Bloc « CET ARTICLE » retiré ; le wash du pivot est appliqué au titre du
   reader via `PivotWashTitle`.

## Fichiers modifiés

| Fichier | Changement |
|---|---|
| `apps/mobile/lib/features/feed/widgets/perspectives_bottom_sheet.dart` | Header vide, body inline, badge/info, analyse, `PivotWashTitle` |
| `apps/mobile/lib/features/detail/screens/content_detail_screen.dart` | Dividers conditionnels, wash pivot sur le titre reader |
| `apps/mobile/test/features/feed/widgets/perspectives_inline_*` | Tests ciblés mis à jour |

## Statut

- [x] Plan confirmé PO
- [x] Header vide allégé
- [x] Badge polarisation + bouton info
- [x] Analyse remontée + disclaimer IA
- [x] Bloc référence inline retiré
- [x] Wash pivot sur le titre reader
- [x] Tests ciblés perspectives inline
- [x] Analyse ciblée perspectives widget/tests
- [ ] `flutter analyze` global propre

## Vérification

- `flutter test test/features/feed/widgets/perspectives_inline_intro_test.dart test/features/feed/widgets/perspectives_inline_states_test.dart test/features/feed/widgets/perspectives_inline_animation_test.dart test/features/feed/widgets/perspectives_inline_overflow_test.dart test/features/feed/widgets/perspectives_inline_filter_test.dart test/features/feed/widgets/perspective_opens_in_app_reader_test.dart test/features/feed/widgets/variant_row_source_below_test.dart` — **OK**, 22 tests.
- `flutter analyze lib/features/feed/widgets/perspectives_bottom_sheet.dart test/features/feed/widgets/perspectives_inline_intro_test.dart test/features/feed/widgets/perspectives_inline_states_test.dart test/features/feed/widgets/perspectives_inline_animation_test.dart test/features/feed/widgets/perspective_opens_in_app_reader_test.dart test/features/feed/widgets/variant_row_source_below_test.dart` — **OK**.
- `flutter analyze` global — **non OK**, 522 issues pré-existantes dans le package mobile.
- `flutter analyze ... content_detail_screen.dart ...` — **non OK**, uniquement des infos async/context déjà présentes dans `content_detail_screen.dart`.
