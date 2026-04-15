# Handoff — Stories 13.5 & 13.6 : UI Mobile du Learning Checkpoint

> Ce handoff fait suite à la PR **boujonlaurin-dotcom/facteur#395** (Epic 13 backend + correctifs stabilité mobile).
> Il s'adresse au prochain agent dev Claude Code qui prendra en charge l'implémentation UI.

---

## 🎯 Mission

Implémenter les **Stories 13.5 et 13.6** du Learning Checkpoint :

- **13.5** : Carte Learning Checkpoint dans le feed (présentation d'une ou plusieurs propositions d'ajustement).
- **13.6** : Interaction complète (accept / modify / dismiss / follow-mute entity) avec appels API et feedback utilisateur.

Le backend est **déjà en place** (PR #395, à merger avant ton démarrage). Ta mission est purement côté `apps/mobile`.

---

## ⚠️ IMPORTANT — Commence par un brainstorming

**Ne code rien avant d'avoir validé le design avec l'utilisateur (Laurin).**

Ta première phase est une **brainstorming collaborative** axée sur **l'UI/UX précise de la carte** et surtout **la fréquence / le placement dans le feed**. La spec backend existe, la spec produit existe — la spec visuelle est volontairement laissée ouverte.

### Questions à poser / creuser en brainstorming (ordre suggéré)

1. **Fréquence d'apparition**
   - La carte apparaît à `offset=0` du feed non-saved quand `learning_checkpoint != null`. À quelle cadence le backend doit-il en produire ? Actuellement : dès que `>= CHECKPOINT_MIN_PROPOSALS (2)` propositions `pending` existent. → Le PO pense-t-il qu'une carte par jour max est désirable ? Par semaine ? Liée au reset du digest quotidien ?
   - Règle de snooze côté client : si l'utilisateur dismiss la carte, pendant combien de temps ne réapparaît-elle pas ? Est-ce piloté côté backend (via `status=dismissed` par proposition) ou côté mobile (flag SharedPreferences) ?
   - `CHECKPOINT_DISMISS_AFTER = 3` : une proposition non-résolue s'efface après 3 affichages. C'est au client d'incrémenter `shown_count` via un endpoint dédié ? (⚠️ à vérifier — voir "contrat API" plus bas).

2. **Placement dans le feed**
   - Position : premier slot absolu (avant même le premier article) ? Après le 1er article ? Après la 1ère carrousel source-overflow ? Après N articles lus ?
   - Comportement au scroll : la carte se dismiss-t-elle si l'utilisateur scrolle rapidement au-delà sans interagir ? Reste-t-elle "pinned" en haut ?
   - Comportement après pull-to-refresh : la carte réapparaît-elle si aucune action n'a été prise ? Ou est-elle masquée une fois vue ?
   - Mode Serein (`sereinToggleProvider`) : la carte doit-elle être **masquée** en mode Serein (rupture d'intention) ou affichée mais adoucie ?
   - Modes filtrés (theme/source/entity) : carte visible ou masquée ? Spec backend : carte incluse uniquement si `offset=0 && not savedOnly && (not filter_applied)` — à confirmer dans `routers/feed.py`.

3. **Forme visuelle de la carte**
   - **Format** : pleine largeur type `BriefingCard` ? Ou `FeedCarousel` horizontal listant les propositions ? Ou format expandable (collapsed → teaser 1 ligne, expanded → liste complète) ?
   - **Ton** : conversationnel ("On a remarqué que tu lis rarement X, on diminue ?") vs factuel ("15 articles de X, 0 lus — Réduire ?") ? L'approche éditoriale / "moment de fermeture" du digest suggère un ton doux.
   - **Densité** : combien de propositions montrer d'un coup ? Backend : `CHECKPOINT_MIN_PROPOSALS=2`, `CHECKPOINT_MAX_PROPOSALS=4`. Toutes visibles ? Paginées (swipe) ? Stack avec "tap pour la suivante" ?
   - **Types de propositions mélangés** : `source_priority UP/DOWN`, `follow_entity`, `mute_entity`. UX uniforme ou visuellement typée (icône / couleur par type) ?
   - **Actions disponibles par proposition** : `accept` (1-tap) / `modify` (choisir valeur via slider pour priorité / reject via trash) / `dismiss` (plus tard). Doivent-elles être inline sur chaque proposition ou groupées en fin de carte ("Tout accepter" / "Plus tard") ?
   - **Signal context visible ?** `articles_shown`, `articles_clicked`, `period_days` : afficher "15 articles en 7 jours" comme justification, ou garder invisible pour simplifier ?

4. **Animations / transitions**
   - Apparition : fade in depuis le haut du feed ? Slide in ? Pop-in avec haptic ?
   - Après action : card se replie avec transition ? Snackbar "Préférences mises à jour" ? Les articles filtrés disparaissent-ils en live dans le feed en-dessous (anim) ou seulement après refresh ?
   - Si plusieurs propositions : chaque `accept` retire la proposition et condense le reste, ou l'utilisateur parcourt toutes les propositions avant validation globale ?

5. **Edge cases / erreurs**
   - Loading : skeleton pendant l'appel d'`apply-proposals` ? Optimistic update (disparition immédiate, rollback en cas d'erreur) ?
   - Erreur réseau sur `apply-proposals` : Snackbar + retry ? Revert visuel ?
   - L'utilisateur tap "Plus tard" : on incrémente `shown_count` via un `PATCH /learning-proposals/{id} shown=true` ? Ou côté backend à la prochaine fetch ? (à clarifier avec le PO — voir contrat API)
   - La proposition concerne une source/entité que l'utilisateur a **déjà** modifiée manuellement entre-temps : que faire ? (stale proposal — le backend gère-t-il ce cas via `current_value` ?)

### Livrable du brainstorming

Une fois les réponses obtenues, **tu documentes les décisions** dans `docs/stories/core/13.5-13.6.learning-checkpoint-ui.md` (section "Décisions UI/UX") AVANT de coder. Ce document sert de contrat pour la suite.

---

## 📚 Contexte à lire absolument

### Backend livré (PR #395 → à merger dans `main` avant ton démarrage)

- **Migration `ln01`** : tables `user_learning_proposals` + `user_entity_preferences` (avec index partiel `WHERE preference = 'mute'` pour le hot-path feed).
- **Endpoints** (dans `packages/api/app/routers/personalization.py`) :
  - `GET  /api/users/personalization/learning-proposals` → `LearningCheckpointResponse | 204`
  - `POST /api/users/personalization/apply-proposals` → `{ applied, results }`
  - `POST /api/users/personalization/entity-preference` → 201
  - `DELETE /api/users/personalization/entity-preference/{entity}` → 200
- **Intégration feed** : `GET /feed?offset=0` retourne `pagination.has_next` + `learning_checkpoint` (quand dispo) dans le corps de la réponse.
- **Schemas** : voir `packages/api/app/schemas/learning.py` (⚠️ source de vérité pour les types mobile).

### Ce que tu trouveras déjà côté mobile

- `FeedRepository` — `getFeed()` renvoie déjà `FeedResponse`. Tu devras y ajouter le parsing du champ `learning_checkpoint` si ce n'est pas déjà fait (⚠️ à vérifier — actuellement le mobile ignore ce champ car les Stories 13.5/13.6 étaient hors scope).
- `apps/mobile/lib/features/feed/models/content_model.dart` — c'est là que vit `FeedResponse`. Ajouter `LearningCheckpointData? learningCheckpoint`.
- `apps/mobile/lib/features/feed/providers/feed_provider.dart` — exposer la carte depuis le state du notifier.
- `apps/mobile/lib/features/feed/screens/feed_screen.dart` — insérer la carte dans le `SliverList` à la position décidée en brainstorming.
- **Widgets existants comme référence visuelle** :
  - `briefing_card.dart` — format plein-largeur expandable, bon exemple pour un container proéminent.
  - `feed_carousel.dart` — format horizontal multi-items.
  - `caught_up_card.dart` — format "fin de feed" informatif.
  - `feed_refresh_undo_banner.dart` — bannière temporaire avec auto-dismiss.
  - `dismiss_banner.dart` — bannière avec action.

### Règles projet (CLAUDE.md — à respecter strictement)

1. **Workflow PLAN → CODE+TEST → PR** avec STOP-check entre chaque phase (spec dans `CLAUDE.md`).
2. **Branche dédiée** pour les Stories 13.5/13.6 : `claude/learning-checkpoint-ui-<random>` (PAS sur `claude/learning-checkpoint-algo-UDwDy` qui est la branche backend déjà mergée).
3. **PR vers `main` uniquement** (`staging` est DÉPRÉCIÉ, hook `pre-bash-no-staging.sh` bloque sinon).
4. **Tests** :
   - Unit tests sur tout nouveau provider / notifier.
   - Tests widget pour la carte (golden tests optionnels si design figé).
   - Hook `post-edit-auto-test.sh` lance auto les tests liés à chaque edit — fixe tout échec avant de continuer.
5. **Validation UI via Playwright MCP** (ou Chrome `/validate-feature`) avant la PR.
6. **QA handoff obligatoire** : `.context/qa-handoff.md` rédigé avant de notifier le user.
7. **Hook `stop-verify-tests.sh`** bloque la fin de réponse si les tests échouent — tout doit passer.

### Zones à risque (lire `docs/agent-brain/safety-guardrails.md` si modif)

- **Auth / JWT** : non touché pour ces stories (endpoints déjà JWT-gated backend).
- **Router mobile (go_router)** : probablement non touché si la carte vit dans le feed. Si tu ajoutes une route modale plein-écran, ajouter au router avec soin.
- **Providers Riverpod** : respecter les 2 patterns anti-régression fixés dans la PR #395 :
  - **Pattern A** : si ajout d'un nouveau `ConsumerStatefulWidget`, placer tout accès `ref`/`Supabase.instance` dans `dispose()` **AVANT** `super.dispose()`.
  - **Pattern B** : si usage de `Future.delayed` avec `ref.read`, **capturer le notifier AVANT** le `delayed`, pas à l'intérieur du callback.
- **Pagination feed** : ne pas casser la logique hybride `_hasNext = pagination.hasNext && items.isNotEmpty` de `feed_provider.dart:208`.

---

## 🔧 Implémentation (après GO sur le brainstorming)

### Modèles & parsing
- [ ] Ajouter `LearningCheckpointData`, `ProposalData`, `SignalContextData` dans `content_model.dart` avec `fromJson` défensif (clés optionnelles, types invalides → fallback).
- [ ] Parser `learning_checkpoint` dans `FeedRepository.getFeed` (à côté de `parsePagination`, idéalement en méthode statique testable).
- [ ] Exposer le checkpoint dans `FeedState` (ajouter `final LearningCheckpointData? learningCheckpoint;`).

### Repository learning
- [ ] Nouveau `learning_repository.dart` avec 3 méthodes : `applyProposals(actions)`, `setEntityPreference(entity, pref)`, `removeEntityPreference(entity)`.
- [ ] Provider Riverpod `learningRepositoryProvider`.

### Widget carte
- [ ] Nouveau `learning_checkpoint_card.dart` (sous `features/feed/widgets/` ou nouveau dossier `features/learning/widgets/` — à trancher en brainstorming).
- [ ] Sous-widgets par type de proposition (`_SourcePriorityProposal`, `_EntityFollowProposal`, `_EntityMuteProposal`) si l'UX le demande.
- [ ] Intégration dans `feed_screen.dart` au bon index du `SliverList`.

### State & logique
- [ ] Gestion de l'état local "propositions en cours de résolution" (optimistic update).
- [ ] Refresh du feed après `apply-proposals` si des propositions changent la visibilité d'articles (entity mute → articles disparaissent).
- [ ] Hook analytics : `trackLearningCheckpointShown`, `trackProposalAction(type, action)` dans `analytics_service.dart`.

### Tests
- [ ] Unit tests sur le parsing `LearningCheckpointData.fromJson` (équivalent de `feed_repository_pagination_test.dart`).
- [ ] Unit tests sur `learningRepository` avec mock `ApiClient`.
- [ ] Widget test sur la carte : rendu de chaque type de proposition, tap sur accept/dismiss, optimistic update.
- [ ] `flutter analyze` : 0 errors, 0 warnings sur les fichiers modifiés.
- [ ] `flutter test` : suite verte.

### Validation
- [ ] `/validate-feature` ou test manuel via Playwright MCP : apparition de la carte en feed, interactions, refresh post-action.
- [ ] QA handoff `.context/qa-handoff.md` rédigé (reprendre le template, couvrir happy path + edge cases + zones de risque).

### PR
- [ ] Nouvelle PR vers `main` — titre suggéré : `Epic 13 — Learning Checkpoint mobile UI (Stories 13.5/13.6)`.
- [ ] Linker #395 dans la description pour traçabilité.

---

## 📎 Références rapides

| Fichier | Rôle |
|---------|------|
| `packages/api/app/schemas/learning.py` | Schémas API (source de vérité pour les types mobile) |
| `packages/api/app/routers/personalization.py` | Endpoints `/learning-proposals`, `/apply-proposals`, `/entity-preference` |
| `packages/api/app/services/learning_service.py` | Logique métier backend (signal, génération, apply) |
| `apps/mobile/lib/features/feed/models/content_model.dart` | `FeedResponse`, à étendre avec `learningCheckpoint` |
| `apps/mobile/lib/features/feed/repositories/feed_repository.dart` | `parsePagination` comme modèle pour le parsing défensif |
| `apps/mobile/lib/features/feed/providers/feed_provider.dart` | `FeedState` — y brancher le checkpoint |
| `apps/mobile/lib/features/feed/screens/feed_screen.dart` | `SliverList` — point d'insertion de la carte |
| `apps/mobile/lib/features/feed/widgets/briefing_card.dart` | Widget de référence visuelle (format plein-largeur) |
| `docs/stories/core/13.learning-checkpoint.md` | Story backend (déjà livrée, contexte produit) |
| `docs/agent-brain/navigation-matrix.md` | Workflows par type de tâche |
| `.context/qa-handoff-template.md` | Template QA à remplir en fin de story |

---

## ✅ Checklist de démarrage pour le prochain agent

1. [ ] Lire ce handoff en entier.
2. [ ] Lire `docs/stories/core/13.learning-checkpoint.md` (contexte backend).
3. [ ] Lire `packages/api/app/schemas/learning.py` (contrat API).
4. [ ] Vérifier que la PR #395 est **mergée sur `main`** (sinon demander à Laurin de merger avant).
5. [ ] Créer la nouvelle branche `claude/learning-checkpoint-ui-<random>` depuis `main` à jour.
6. [ ] Créer `docs/stories/core/13.5-13.6.learning-checkpoint-ui.md` avec les sections "Plan Technique" + "Décisions UI/UX" (vides pour l'instant).
7. [ ] **Lancer le brainstorming** avec Laurin en reprenant les 5 axes de questions ci-dessus.
8. [ ] Documenter les décisions dans la story doc.
9. [ ] **STOP** → présenter le plan technique à Laurin → attendre GO.
10. [ ] Implémenter + tester + QA handoff + PR vers `main`.

---

**Bonne chance — la moitié est faite, la moitié la plus visible reste !** 🚀
