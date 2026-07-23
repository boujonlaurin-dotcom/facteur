# Bug — Divergence `essentiel_mode` DB/local : sources évincées de l'Essentiel à chaque cold-boot

## Symptôme (PO, 22/07/2026)

> « Les sources ajoutées à l'Essentiel ne s'enregistrent toujours pas correctement
> dans la Tournée du jour ! Constamment retirées de mon Essentiel ! »

Persiste malgré les deux fixes précédents : réordre non destructeur
(`mergeVisibleReorder`, [bug-tournee-sources-not-saving](bug-tournee-sources-not-saving.md))
et colonne DB `essentiel_mode`
([bug-essentiel-placement-persistence](bug-essentiel-placement-persistence.md), es01).

## Cause racine — divergence créée localement, puis rejouée à chaque boot

Trois maillons, tous vérifiés dans le code :

1. **Écritures local-first « best-effort » dans les déplacements.**
   `manage_favorites_sheet.dart` — `_moveSourceToEssentiel` (l.258-264),
   `_moveSourceToFlaner`, `_moveThemeToEssentiel`, `_moveThemeToFlaner` :
   les prefs locales (`tournee_order_v1` / `pinned_tabs_order_v1`) sont écrites
   **avant** la DB, puis `_persistSourceMode`/`_persistThemeMode` est explicitement
   best-effort (l.266-278 : `catch` → toast d'erreur, le déplacement local reste
   appliqué). Un échec réseau crée l'état : **clé locale présente + DB
   `essentiel_mode=false`** (ou `false` hérité d'un placement Flâner antérieur).
   NB : `_onAddSource` (l.208-230) fait déjà l'inverse (DB d'abord) — c'est le bon
   pattern.

2. **`promoteSuggestion` avale l'échec et l'UI confirme quand même.**
   `flux_continu_provider.dart:2145-2167` : `catch (e) { debugPrint(...) }` ;
   l'appelant (`flux_continu_screen.dart:913-916`) affiche « Ajoutée à tes
   favoris » inconditionnellement. Même divergence possible, avec en plus un faux
   feedback de succès.

3. **La réconciliation cold-boot rejoue la divergence en éviction.**
   `essentiel_placement_sync.dart:145-148` : pour une source favorite avec
   `essentiel_mode == false` en DB, `reconcileEssentielPlacement` **retire** la clé
   de `tournee_order_v1` et la remet en Flâner, silencieusement, **à chaque cold
   boot**. Le backfill one-shot local→DB ne répare que `essentiel_mode == NULL`
   (l.82-98), jamais un `false` incohérent. D'où le « constamment retirées » : une
   seule écriture DB ratée suffit, l'éviction se répète ensuite indéfiniment.

## Fix (mobile-only, 0 migration, 0 backend)

### 1. DB d'abord, local ensuite (alignement sur le pattern `_onAddSource`)

Dans `manage_favorites_sheet.dart`, réordonner les 4 `_move*` : d'abord
`setSourceState`/`setInterestState` (qui rollback + rethrow déjà), et seulement en
cas de succès appliquer les écritures locales (`_removeTab`/`_appendTournee`, etc.)
et le toast de succès. En cas d'échec : toast d'erreur, **aucun** changement local,
pas de divergence possible. Supprimer les helpers `_persistSourceMode`/
`_persistThemeMode` best-effort (inlinés dans le nouveau flux).

Dans `flux_continu_provider.dart::promoteSuggestion` : ne plus avaler l'erreur
(rethrow après le debugPrint) ; DB d'abord, `_appendTourneeOrder` +
`markCustomized` après succès. Côté écran, `onKeep` n'affiche le succès que si la
promotion a réussi, sinon un message d'erreur.

### 2. Réconciliation self-heal : le local gagne en cas de conflit

Dans `reconcileEssentielPlacement`, branche `mode == false` d'une source : si la
clé `source:<id>` est **déjà présente** dans `tournee_order_v1` local, ne plus la
retirer. Cette présence témoigne d'une action utilisateur explicite sur ce device
(les clés ne s'ajoutent que par action) : on **re-pousse** `essentiel_mode=true`
en DB (best-effort, retenté au boot suivant si échec) au lieu de détruire le
placement. Même logique en miroir pour les thèmes (`mode == false` avec clé
`theme:<slug>` présente dans l'ordre Tournée).

- La restauration après réinstallation reste inchangée : local vide → aucune clé
  présente → la DB hydrate normalement (`mode == true` → ajout).
- **Auto-réparation rétroactive** : tous les utilisateurs déjà divergés sont
  réparés au premier cold boot, sans UI ni backfill.
- Trade-off assumé (documenté ici) : un retrait de l'Essentiel effectué sur un
  **autre device** peut être annulé par un device dont le cache local est plus
  ancien. Cas rare (usage mono-device dominant) et le pire cas devient additif
  (source qui reste dans l'Essentiel) au lieu de destructeur (config perdue).

## Tests (lock de régression)

`apps/mobile/test/features/flux_continu/`

1. `manage_favorites_sheet_test.dart` : `_moveSourceToEssentiel` avec repo qui
   échoue → `tournee_order_v1` et `pinned_tabs_order_v1` inchangés, erreur
   affichée ; avec repo OK → local mis à jour après la DB.
2. `essentiel_placement_sync` : conflit (clé locale présente + DB `false`) → clé
   conservée + `setSourceState(essentielMode: true)` appelé ; local vide + DB
   `true` → hydratation inchangée (réinstall) ; DB `false` sans clé locale →
   comportement inchangé (Flâner).
3. `promoteSuggestion` : échec repo → pas d'append à l'ordre, erreur propagée ;
   pas de toast succès (test widget écran).

## Vérification

```bash
cd apps/mobile
flutter test test/features/flux_continu/
flutter test && flutter analyze
```

QA manuelle : ajouter une source à l'Essentiel, kill app, relancer ×2 → la source
reste. Simuler mode avion pendant le déplacement → erreur visible, état local
intact, pas d'éviction aux boots suivants.

## Statut — implémenté

Mobile-only, 0 migration, 0 backend. Fichiers touchés :

- `manage_favorites_sheet.dart` — déplacements réordonnés DB-first (DB via
  `setSourceState`/`setInterestState`, écritures locales seulement en cas de
  succès) ; helpers best-effort `_persistSourceMode`/`_persistThemeMode` supprimés.
  Les 4 `_move*ToFlaner`/`_move*ToEssentiel` sont consolidés en `_moveSource`/
  `_moveTheme` (`{required bool toEssentiel}`) déléguant à un helper `_moveMode`
  qui porte le try/catch DB-first commun.
- `flux_continu_provider.dart::promoteSuggestion` — `rethrow` après le `debugPrint`.
- `flux_continu_screen.dart::onKeep` — `try/catch` : succès seulement si la
  promotion a persisté, sinon message d'erreur.
- `essentiel_placement_sync.dart` — branche self-heal (source + miroir thème) : clé
  Essentiel locale présente + DB `false` → clé conservée + re-push
  `essentiel_mode=true` (best-effort).

Tests (verts) : `essentiel_placement_sync_test.dart` (self-heal source/thème,
Flâner sans clé locale inchangé, re-push best-effort sur échec),
`manage_favorites_sheet_test.dart` (DB-first : échec DB → prefs locales intactes),
`flux_continu_provider_test.dart` (`promoteSuggestion` échec → exception propagée +
ordre non pollué). `flutter analyze` : 0 issue.
