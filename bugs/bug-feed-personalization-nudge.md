# Bug: Personalization nudge manquant en CI

## Status: ✅ Done

## Date: 24/01/2026

## Symptome

- Build CI echoue avec "PersonalizationNudge isn't defined".

## Cause probable

- Fichiers utilises par le feed non versionnes (widget nudge + provider).

## Impact

- APK non generable en CI.
- Boucles d'iterations longues (15 min) pour une erreur triviale.

## Resolution

### Fichiers ajoutes au repo
- `apps/mobile/lib/features/feed/widgets/personalization_nudge.dart` - Widget du nudge de personnalisation
- `apps/mobile/lib/features/feed/widgets/personalization_sheet.dart` - Bottom sheet de personnalisation
- `apps/mobile/lib/features/feed/providers/skip_provider.dart` - Provider pour tracker les skips par source

### Commit
- `fix: add missing feed personalization files` (commit `5cabb39`)

### Verification
- Script de verification cree : `docs/qa/scripts/verify_feed_personalization_nudge.sh`
- Build CI fonctionne correctement apres ajout des fichiers

## Notes

Les fichiers etaient presents localement mais absents du repo Git, causant des erreurs de compilation en CI. Le correctif minimal a ete applique sans refactoring pour preserver les features existantes.
