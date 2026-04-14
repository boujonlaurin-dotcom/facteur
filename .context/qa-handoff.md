# QA Handoff — Carte « Construire ton flux · Cette semaine »

> Epic 13 · Stories 13.5-13.6 · branche `claude/mobile-feed-flow-riverpod-NFgHp`

## Feature développée

Injection d'une carte hebdomadaire dans le feed mobile proposant à l'utilisateur
d'ajuster ses préférences (priorité source, mute/follow d'entité) sur la base
des signaux d'usage observés. Gating client (N≥3, max_signal≥0.6, cooldown 24h,
1/session), 3 types de propositions, POST `/apply-proposals`, rafraîchissement
feed + sources + custom_topics après validation/snooze.

## PR associée

À créer après confirmation PO (cible `main`, jamais `staging`).

## Écrans impactés

| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Feed  | `/feed` | Modifié (injection carte en position 3 quand LcVisible) |

## Scénarios de test

### Scénario 1 : Happy path — Validation carte complète

**Parcours** :
1. Lancer l'app, se connecter avec un compte ayant ≥3 propositions `pending` en base et `max_signal_strength ≥ 0.6`, sans action récente (cooldown inactif).
2. Aller sur le feed (`/feed`).
3. Scroller jusqu'à la carte « Construire ton flux · Cette semaine » (insérée en position 3).
4. Tapper **Valider** sans modifier les propositions.

**Résultat attendu** :
- Spinner affiché sur le bouton pendant l'appel POST `/apply-proposals`.
- Toast succès « Tes préférences sont mises à jour ».
- La carte disparaît du feed (état LcApplied).
- Le feed est rafraîchi ; les sources et custom_topics également.
- Cooldown 24h actif : la carte ne réapparaît pas après reload.

---

### Scénario 2 : Edge 1 — Dismiss individuel d'une proposition (✕)

**Parcours** :
1. Sur une carte à 3 propositions, tapper le ✕ de la 2ᵉ proposition.
2. Observer la carte.
3. Tapper **Valider**.

**Résultat attendu** :
- La ligne dismiss disparaît visuellement, les 2 autres restent.
- POST `/apply-proposals` contient `action=dismiss` pour la ligne retirée et `action=accept` pour les deux autres.
- Toast succès, carte masquée, cooldown activé.

---

### Scénario 3 : Edge 2 — Expand / stats

**Parcours** :
1. Sur la carte, tapper l'icône ℹ︎ d'une proposition `source_priority`.
2. Vérifier le panneau ouvert.
3. Tapper ℹ︎ d'une autre proposition.

**Résultat attendu** :
- Le panneau `ProposalStatsPanel` s'ouvre avec la ligne `N articles affichés · M lus · K sauvegardés`, la période et le label de signal (ex. « très fort ») correspondant à `signalStrength`.
- Un seul panneau ouvert à la fois : ouvrir la 2ᵉ referme la 1ʳᵉ.
- Analytics `construire_flux.expand` tracké.

---

### Scénario 4 : Edge 3 — Plus tard (snooze)

**Parcours** :
1. Tapper **Plus tard**.

**Résultat attendu** :
- POST `/apply-proposals` avec `action=dismiss` pour toutes les propositions affichées.
- Carte masquée, cooldown 24h actif.
- Aucun toast succès sur snooze (seul Valider affiche le toast).
- Au prochain cold-start avant 24h : carte toujours masquée.

---

### Scénario 5 : Edge 4 — Modification source_priority via slider

**Parcours** :
1. Sur une proposition `source_priority` (ex. `currentValue=3`, `proposedValue=1`), tapper un autre dot proposé (ex. `2`).
2. Tapper **Valider**.

**Résultat attendu** :
- Le dot actif change visuellement.
- POST `/apply-proposals` contient `action=modify, value=2` pour cette ligne.
- Analytics `construire_flux.validate` avec `modified_count ≥ 1`.

---

### Scénario 6 : Edge 5 — Gating (carte absente)

**Parcours** :
1. Se connecter avec un compte dont le backend retourne < 3 propositions OU `max_signal_strength < 0.6`, OU cooldown actif (`learning_checkpoint_last_action_at` il y a < 24h).
2. Aller sur le feed.

**Résultat attendu** :
- Aucune carte affichée, aucun titre « Construire ton flux · Cette semaine » visible.
- Le feed reste fonctionnel, `CaughtUp` et autres intercalés s'affichent à leur place habituelle.

---

### Scénario 7 : Edge 6 — Dismiss de la dernière proposition → snooze auto

**Parcours** :
1. Carte à 3 propositions. Tapper ✕ sur chacune, l'une après l'autre.

**Résultat attendu** :
- Après le 3ᵉ ✕, la carte se ferme (snooze automatique déclenché, POST `/apply-proposals` avec `action=dismiss` pour les 3).
- Cooldown actif.

---

## Critères d'acceptation

- [ ] Carte visible uniquement si N≥3, max_signal≥0.6, cooldown inactif, 1/session max.
- [ ] 3 types rendus correctement : slider `source_priority`, toggle `mute_entity`, toggle `follow_entity`.
- [ ] Expand : un seul panneau ouvert, stats formatées, label signal correct.
- [ ] Dismiss individuel puis Valider → actions mix `accept`/`dismiss`/`modify` envoyées.
- [ ] Plus tard → toutes les propositions → `dismiss`.
- [ ] Cooldown 24h persisté via `SharedPreferences` clé `learning_checkpoint_last_action_at`.
- [ ] Toast succès uniquement après Valider (pas sur snooze).
- [ ] Feed + sources + custom_topics invalidés après action.
- [ ] Analytics : `construire_flux.shown`, `.expand`, `.dismiss_item`, `.validate`, `.snooze`.
- [ ] Accessibilité : Semantics « Proposition : <label> », tooltips « Détails de la proposition » / « Ignorer cette proposition ».

## Zones de risque

- **Interaction CaughtUp + Carte** : la carte est injectée en position 3, CaughtUp reste à position 8. `caughtUpEffectivePos = caughtUpPos + contentOffset` pour éviter collision avec le contenu. Vérifier visuellement que rien ne se chevauche quand le feed a 8+ articles.
- **Refresh feed après validation** : l'invalidation feed+sources+custom_topics peut provoquer un flicker. Vérifier UX.
- **Cooldown race** : après `_markCooldown()`, le provider cooldown est invalidé mais le notifier ne rebuild PAS (utilise `ref.read`, pas `ref.watch`). La carte doit rester en LcApplied jusqu'à pull-to-refresh ou cold-start.
- **Kill-switch** : `LearningCheckpointFlags.enabled = false` OU SharedPreferences clé `learning_checkpoint_force_disabled = true` → carte jamais affichée (path de secours prod/QA).

## Dépendances

- **Backend** : endpoints `GET /learning-checkpoint/proposals` et `POST /learning-checkpoint/apply-proposals` (stories 13.1-13.4).
- **Providers** : `feedProvider`, `userSourcesProvider`, `customTopicsProvider`, `apiClientProvider`, `analyticsServiceProvider`.
- **Services** : `NotificationService.showSuccess/showError`.
- **Packages** : `shared_preferences`, `flutter_riverpod`, `phosphor_flutter`.
