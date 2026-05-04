# QA Handoff — Veille V3 PR3 « UX polish »

## Feature développée

Trois améliorations UX du flow de configuration veille (mobile, 4 étapes) :
- **T4** — Pré-loading actif des suggestions LLM entre les steps (animation halo + checklist déclenche désormais le fetch en arrière-plan, durée adaptive 1.5 s min → data|error).
- **T5** — Nouvel écran d'introduction veille au premier accès (single-page : pitch + halo + CTA « C'est parti »), affiché avant Step1.
- **T6** — Repositionnement des pré-sets : suppression de la section bas de Step1, ajout d'un teaser tappable haut + bottom sheet listant tous les pré-sets.

## PR associée

À créer via `/go` — base `main`.

## Écrans impactés

| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| `VeilleIntroScreen` | `/veille/config` (état pré-Step1) | NOUVEAU (T5) |
| `VeilleConfigScreen` | `/veille/config` | Modifié (T4 + T5) |
| `Step1ThemeScreen` | `/veille/config` (étape 1) | Modifié (T6) |
| `VeillePresetsSheet` | bottom sheet de Step1 | NOUVEAU (T6) |
| `FlowLoadingScreen` | écran de transition | Inchangé (déjà multi-step) |

## Scénarios de test

### Scénario 1 — Happy path complet (premier accès)

**Parcours** :
1. Aller sur `/veille/config` (compte sans config active).
2. Vérifier qu'on voit l'écran **VeilleIntroScreen** (eyebrow « Le facteur prépare ta veille » + titre « Une veille pensée pour toi » + halo animé + CTA « C'est parti »).
3. Tap « C'est parti ».
4. Sur Step1 : vérifier le **teaser pré-sets** (« Pas inspiré ? Pioche un pré-set ») visible dès l'ouverture (sans scroll).
5. Sélectionner un thème (ex. Tech).
6. Sélectionner un sujet pré-suggéré, tap « Continuer ».
7. **Animation halo** + checklist (FlowLoadingScreen) ≥ 1.5 s.
8. Step2 affiché : suggestions topics **déjà chargées** (pas de spinner secondaire en cas nominal).
9. Cocher 1-2 suggestions, tap « Continuer ».
10. **Animation halo** vers Step3 puis sources **déjà chargées**.
11. Tap « Continuer ».
12. Step4 (rythme), tap « Démarrer ma veille ».
13. Animation post-submit (from=4) + redirection dashboard.

**Résultat attendu** : flow ininterrompu, halo entre chaque step, pas de spinner secondaire à l'arrivée sur Step2/Step3.

### Scénario 2 — Pré-set via bottom sheet

**Parcours** :
1. Aller sur `/veille/config` (sans config), passer l'intro.
2. Sur Step1, tap teaser « Pas inspiré ? Pioche un pré-set ».
3. Vérifier la **bottom sheet** : titre « Pré-sets », liste des PresetCard.
4. Tap sur un pré-set.
5. Vérifier que la sheet se ferme et que **Step1.5 preview** s'affiche (label + accroche + topics + sources).
6. Tap « Utiliser ce pré-set » → bascule Step4 (jumpToStep4).
7. Tap « Démarrer ma veille » → submit.

**Résultat attendu** : workflow preview→use inchangé. Pas d'intro réaffichée pendant la session.

### Scénario 3 — Mode édition (skip intro)

**Parcours** :
1. Avoir une config active.
2. Naviguer sur `/veille/config?mode=edit`.
3. Vérifier que **Step1 est affiché directement** (pas d'intro).
4. Vérifier que les sélections sont hydratées depuis la config existante.

**Résultat attendu** : intro skipped, hydratation OK.

### Scénario 4 — Config active sans edit (redirect)

**Parcours** :
1. Avoir une config active.
2. Naviguer sur `/veille/config` (sans `?mode=edit`).

**Résultat attendu** : redirect immédiat vers `/veille/dashboard`. Pas d'intro affichée.

### Scénario 5 — LLM lent (>1.5 s)

**Parcours** :
1. Throttler le réseau (Chrome devtools → Slow 3G), repasser le happy path Step1→Step2.

**Résultat attendu** : animation halo dépasse 1.5 s, attend le provider jusqu'à `data|error` (cap 8 s). Au-delà, Step2 affiche son skeleton normal — pas de blocage.

### Scénario 6 — Close depuis l'intro

**Parcours** :
1. Sur l'intro, tap la croix (haut droite).

**Résultat attendu** : retour `/feed` (pas de pop si pas de history).

## Critères d'acceptation

- [ ] Premier accès `/veille/config` sans config → intro affichée.
- [ ] Tap « C'est parti » → bascule Step1 (animation AnimatedSwitcher).
- [ ] `?mode=edit` → intro skipped (Step1 directement).
- [ ] `activeConfig != null` → redirect dashboard.
- [ ] Step1 : teaser pré-sets visible sans scroll.
- [ ] Tap teaser → bottom sheet liste tous les pré-sets.
- [ ] Tap pré-set → sheet ferme + Step1.5 preview.
- [ ] Plus aucune section "Inspirations" en bas du scroll Step1.
- [ ] Step1→Step2 : animation halo ≥ 1.5 s + suggestions topics chargées à l'arrivée (cas nominal).
- [ ] Step2→Step3 : animation halo ≥ 1.5 s + sources chargées à l'arrivée (cas nominal).
- [ ] Si LLM lent : on attend jusqu'à 8 s puis on passe (skeleton normal).

## Zones de risque

- **Params identiques entre `goNext()`/`FlowLoadingScreen` et Step2/Step3** : si différents (ordre topicLabels, sort des topicIds), `family.autoDispose` créera deux instances → double-fetch et perte du préload. Helpers `topicsParamsFromState` / `sourcesParamsFromState` sont la single source of truth, alignés sur l'instanciation des Steps.
- **`introCompleted` marqué dans `applyPreset` et `hydrateFromActiveConfig`** : critique pour ne pas réafficher l'intro après un preset apply ou en mode édition.
- **Annulation du loading** : si l'utilisateur close le flow pendant l'animation halo, la guard `state.loadingFrom != from` dans `_waitAndAdvance` évite un push de transition stale.

## Dépendances

- Backend : aucune modif (les endpoints `/api/veille/suggestions/topics` et `/sources` sont inchangés).
- Mobile : `flutter_riverpod` (ProviderSubscription, déjà utilisé).
- Pas de migration DB.
