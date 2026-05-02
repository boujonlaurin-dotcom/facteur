# PR2 — Lettres du Facteur (mobile data layer) · Story 19.1

## Summary

- Couche data Flutter pour les Lettres du Facteur : models (`Letter`, `LetterAction`, enums), `LettersRepository` (Dio sur `/api/letters`), `lettersProvider` (`AsyncNotifier` avec `refresh`, `silentRefresh`, `refreshLetterStatus`).
- `ProfileAvatarButton` réécrit en `ConsumerWidget` : initiales du user (fallback `'F'`) + anneau de progression (`RingAvatar` CustomPainter, animation 400 ms `easeOutCubic`). L'anneau disparaît dès qu'aucune lettre n'est `active` — pas de FOMO.
- Settings sheet gagne une entrée « Courrier » qui pousse `/lettres` (route placeholder `LettresPlaceholderScreen`, à remplacer en PR3 par l'écran complet).

## Test plan

- [x] `flutter test test/features/lettres/` — 14 tests verts (5 provider + 5 unit RingAvatar + 4 goldens).
- [x] `flutter analyze lib/features/lettres lib/features/feed/widgets/profile_avatar_button.dart lib/config/routes.dart` — 0 issue (warnings préexistants hors scope).
- [ ] Smoke test : login → feed → profile button affiche initiales + anneau (lettre L1 active après PR1).
- [ ] Settings → tap « Courrier » → ouvre `/lettres` (placeholder).
- [ ] Logout → profile button affiche `'F'` sans anneau.

## Décisions

- **Statut par action calculé client-side** : `Letter.fromJson` dérive `LetterActionStatus` (done si `id ∈ completed_actions`, sinon `active` pour la 1ère non-complétée d'une lettre `active`, sinon `todo`). Le serveur ne renvoie que `completed_actions[]`.
- **`letterNum` au lieu de `num`** : le champ `num` shadow le type Dart `num` dans `Letter.fromJson`. Côté JSON la clé reste `num`.
- **Cap min 0.02** sur le progress : sinon dash invisible quand 0/N actions cochées.
- **Pas de `GoogleFonts.dmSans` dans `RingAvatar`** : casse en environnement de test (HTTP fetch). Utilise `TextStyle(fontFamily: 'DMSans', …)` directement — la font est déjà déclarée dans `pubspec.yaml`.
- **`.display()` ctor** sur `ProfileAvatarButton` conservé par prudence ; aucune utilisation externe trouvée — peut être supprimé en PR3 si confirmé.

## Hors scope (PR3)

Écran Courrier complet, écran lettre ouverte, banner notification feed, empty state, animation cachetDrop, branchement `silentRefresh()` après action utilisateur (ajout source / Perspectives ouvert).
