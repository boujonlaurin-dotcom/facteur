# Bug: Première veille — aucune option de relance après échec/timeout/empty

## Statut
- [ ] En cours (date: 2026-05-12)

## Sévérité
🟠 Bloquant onboarding — 2e itération du même symptôme « la 1ère veille n'arrive pas » signalé par le PO. Le précédent fix [bug-veille-config-without-sources.md](./bug-veille-config-without-sources.md) (2026-05-07) a éliminé la branche « config sans sources », mais 4 autres modes d'échec laissent l'user dans un cul-de-sac UX 4 jours plus tard.

## Description

Symptôme PO (2026-05-12) :
> Après avoir configuré une veille, **aucune option n'apparaît / n'est proposée** pour générer la première veille. Réessais multiples sans succès.

## Cause racine

La génération de la « première veille » est déclenchée **exactement une fois**, **automatiquement**, dans `handleSubmit` du Step 4 (`apps/mobile/lib/features/veille/screens/veille_config_screen.dart:69-142`). Aucun mécanisme de récupération pour les 4 modes d'échec :

| # | Mode d'échec | Conséquence |
|---|--------------|-------------|
| 1 | Polling timeout (90 s) alors que la génération met >90 s | Snackbar « on t'enverra une notif », redirect dashboard, livraison finalise plus tard mais user jamais ramené dessus |
| 2 | Génération `failed` (`last_error`) | `_pollFirstDelivery` retourne `false`, snackbar, redirect dashboard, aucune option pour relancer |
| 3 | Digest vide (`succeeded` + `item_count=0`) — encore possible si taxonomy mismatch ou source crawlée trop fraîche | User atterrit sur `_DeliveryEmptyView` ou dashboard, aucune option pour régénérer |
| 4 | Re-tentative depuis zéro : user retourne sur `/veille/configure` | Auto-redirect dashboard (`veille_config_screen.dart:46-52`). User ne peut **plus jamais** repasser par Step 4 |

**Backend** : `POST /api/veille/deliveries/generate-first` (`packages/api/app/routers/veille.py:794-802`) retourne **403 si une row `VeilleDelivery` existe**, quel que soit son état. → Aucun moyen de demander une régénération, même si la précédente a échoué ou a produit un digest vide.

**Dashboard** : `VeilleDashboardScreen` (`apps/mobile/lib/features/veille/screens/veille_dashboard_screen.dart:155-178`) ne propose que **Voir l'historique / Modifier / Pause / Supprimer**. Aucun bouton « Lancer ma première veille » ou « Générer maintenant ».

## Solution

Fix en 2 parties, sans introduire de nouveau cycle d'onboarding ni nouveau endpoint.

### Partie A — Backend : autoriser la régénération propre

Modifier `POST /deliveries/generate-first` pour traiter la première livraison comme **idempotente sur reprise d'erreur** :

- Si la dernière row est `succeeded` avec `item_count > 0` → **403 inchangé** (anti-doublon réel).
- Si la dernière row est `failed`, `succeeded` avec `item_count = 0`, ou `running` depuis >15 min, ou `pending` depuis >15 min → **DELETE** la row précédente puis créer une nouvelle row `PENDING` et planifier le BackgroundTask. **Décision PO Q1 = (a) DELETE** : la row failed/empty n'a aucune valeur user, Sentry/PostHog gardent la trace de l'échec.
- Si la dernière row est `pending`/`running` récente (<15 min) → **409** « génération en cours, patiente quelques instants » (le mobile peut récupérer son `delivery_id` via `GET /deliveries`).

Fichiers :
- `packages/api/app/routers/veille.py` — handler `generate_first_delivery` (lignes 778-825).
- `packages/api/tests/routers/test_veille_routes.py` — étendre `TestGenerateFirstDelivery`.

### Partie B — Mobile : CTA dashboard « Lancer ma première veille »

CTA conditionnelle sur `VeilleDashboardScreen` :
- **Visible** tant qu'aucune livraison `succeeded` avec `item_count > 0` n'existe pour la config active. On fetch la dernière livraison via `repo.listDeliveries(limit: 1)` et on affiche la CTA si la liste est vide OU si la dernière entry est `failed`/`succeeded-empty`/`pending|running >15min`.
- **Texte** : « Lancer ma première veille » (sous-texte « La précédente n'a pas abouti — on retente. » si retry).
- **Action** : `repo.generateFirstDelivery()` puis `FlowLoadingScreen(from: 4)` + `pollFirstDelivery` partagé. Fin → navigation `/veille/deliveries/<id>` (effet Wow identique au flow d'onboarding).

Décision PO Q2 = (b) — garder le polling à 90s, la CTA dashboard rend le timeout visible/analysable et on pourra raccourcir plus tard.

Fichiers :
- `apps/mobile/lib/features/veille/screens/veille_dashboard_screen.dart` — ajout d'un widget CTA conditionnel au-dessus de « Voir l'historique ».
- `apps/mobile/lib/features/veille/screens/veille_config_screen.dart` — déplacer `_pollFirstDelivery` vers un helper partagé.
- `apps/mobile/lib/features/veille/utils/poll_first_delivery.dart` — nouveau helper.
- `apps/mobile/test/features/veille/screens/veille_dashboard_screen_test.dart` — 4 cas (no delivery / failed / empty / valid → CTA cachée).

## Hors scope

- Stabilisation de `/api/veille/suggestions/sources` (bug séparé)
- Refonte du mode édition (la CTA n'apparaît qu'en post-onboarding, pas en edit)
- Notification push de relance après échec (follow-up éventuel)

## Validation

1. `cd packages/api && pytest tests/routers/test_veille_routes.py -v -k generate` — 4 cas (202 first, 202 retry-after-failed, 202 retry-after-empty, 409 retry-after-running, 403 retry-after-success).
2. `cd apps/mobile && flutter test test/features/veille/screens/veille_dashboard_screen_test.dart`.
3. Suite complète : `pytest -v` backend + `flutter test && flutter analyze` mobile.
4. `/go` pour enchaîner verify → simplify → PR vers `main`.
