# Prompts d'implémentation — Story 13.5-13.6 « Construire son flux »

> Deux prompts prêts à copier-coller dans de nouvelles sessions Claude Code pour lancer les phases PLAN des workstreams mobile et backend. Spec de référence sur branche `claude/facteur-usage-cards-MLbEp` (commit `1cac49e`).

---

## 🧭 Ordre de lancement suggéré

1. **Prompt 1 (Mobile Flutter)** en premier — c'est le gros du travail ; la carte consomme l'API existante telle qu'elle est.
2. **Prompt 2 (Backend)** en parallèle ou après — porte uniquement sur de petits ajustements éventuels (incrément `shown_count`, enrichissement `signal_context`). Peut rester no-op si le backend Epic 13 est déjà suffisant.

Les deux prompts respectent le workflow `CLAUDE.md` : **PLAN → GO → CODE+TEST → PR**. Chaque agent doit s'arrêter après avoir produit son plan et attendre ton GO.

---

## Prompt 1 — Mobile Flutter (carte « Construire ton flux »)

```
Tu es l'agent dev Facteur (cf. CLAUDE.md). Mission : implémenter l'intégration
mobile de la carte « Construire ton flux » (Epic 13 — Learning Checkpoint UX).

### Spec de référence (déjà validée par le PO)

Branche spec : `claude/facteur-usage-cards-MLbEp`
Docs à lire DANS CET ORDRE :
1. `docs/stories/core/13.5-13.6.construire-son-flux.md` (hub, principe directeur, décisions verrouillées)
2. `docs/stories/core/13.5-13.6.format-visuel.md` (wireframe, interactions)
3. `docs/stories/core/13.5-13.6.regles-affichage.md` (fréquence, placement feed, analytics)
4. `docs/stories/core/13.5-13.6.contrat-api.md` (endpoints backend existants)

Handoff backend d'origine : `.context/handoff-13.5-13.6-mobile-ui.md`
(sur branche `claude/learning-checkpoint-algo-UDwDy` — à lire si besoin de contexte
backend supplémentaire).

### Branche de travail

Crée une branche dédiée à l'implémentation mobile, séparée de la branche spec :
`feature/13.5-13.6-construire-flux-mobile` (ou nom équivalent approuvé).

NE PAS développer sur `claude/facteur-usage-cards-MLbEp` (branche de spec).

### Scope

- Provider Riverpod qui appelle `GET /learning-proposals` et applique les seuils
  de gating côté client (N≥3, signal_strength max ≥ 0.6, cooldown 24h, 1/session).
- Widget `ConstruireSonFluxCard` unifié gérant les 3 types de propositions
  (`source_priority`, `follow_entity`, `mute_entity`) selon wireframe format-visuel.md.
- Injection dans `feed_screen.dart` (SliverList, position 3 — à confirmer selon
  encarts existants).
- Flux d'action (dismiss individuel, Valider, Plus tard) → `POST /apply-proposals`.
- Panneau de stats déplié via bouton ℹ︎ affichant `signal_context`.
- Persistance locale du cooldown 24h + flag "1 carte par session".
- Feature flag `learning_checkpoint_mobile_enabled` (on par défaut, kill-switch).
- Événements analytics : shown / expand / dismiss_item / validate / snooze.

### Hors-scope explicite (ne pas implémenter)

- Ajout de nouvelles sources (v1 exclu)
- Recap hebdo / miroir éditorial / filter reminder / carrousel discover
- Modification des endpoints backend (voir Prompt 2 si besoin)

### Contraintes techniques (LOCKED — cf. CLAUDE.md)

- Python 3.12.x si tu touches au backend (mais tu n'es pas censé)
- `list[]` / `dict[]` / `X | None` natifs (jamais `from typing import List`)
- Tests : Flutter `flutter test` + `flutter analyze` — doivent passer avant PR
- PR cible OBLIGATOIREMENT `main` (`--base main`, pas `staging`)

### Livrable de cette phase PLAN

1. Classification : Feature
2. Crée `docs/stories/core/13.5-13.6.construire-son-flux.plan-mobile.md`
   (ou ajoute une section « Plan technique mobile » dans le hub — à ta discrétion
   selon convention projet)
3. Plan technique détaillé :
   - Arbre des fichiers à créer / modifier (Flutter)
   - Providers Riverpod (nom, responsabilités, dépendances)
   - Modèles Dart correspondant aux schémas API
   - Stratégie de persistance du cooldown (SharedPreferences ? Hive ?)
   - Points d'injection dans `feed_screen.dart`
   - Plan de tests (unitaires providers + widget tests + scénarios QA handoff
     Playwright MCP)
   - Risques identifiés + mitigations
4. STOP → présente le plan au PO → attends GO explicite

Ne code rien avant le GO. Rédige uniquement le plan.
```

---

## Prompt 2 — Backend (ajustements Epic 13 si nécessaire)

```
Tu es l'agent dev Facteur (cf. CLAUDE.md). Mission : évaluer et éventuellement
implémenter les petits ajustements backend nécessaires pour supporter la carte
mobile « Construire ton flux » (Epic 13).

### Spec de référence

Branche spec : `claude/facteur-usage-cards-MLbEp`
Doc principal : `docs/stories/core/13.5-13.6.contrat-api.md`
(sections « Tracking d'affichage `shown_count` » et « Ajustements backend potentiels »)

Backend Epic 13 d'origine : `docs/stories/core/13.learning-checkpoint.md`
(sur branche `claude/learning-checkpoint-algo-UDwDy`)

### Branche de travail

`feature/13.5-13.6-construire-flux-backend` (ou équivalent).

NE PAS développer sur `claude/facteur-usage-cards-MLbEp` ni sur `staging` (déprécié).

### Scope d'évaluation

Auditer le backend Epic 13 actuel et répondre aux questions :

1. **Incrément `shown_count`** : où et quand est-il incrémenté aujourd'hui ?
   Sur `GET /learning-proposals` automatiquement ? Sur appel explicite ? Sur
   `dismiss` via `/apply-proposals` ? Le mobile a besoin de la garantie
   suivante : une proposition affichée dans une carte voit son `shown_count`
   incrémenté UNE fois par session. Si ce n'est pas le cas, proposer la
   solution minimale (endpoint `POST /learning-proposals/mark-shown` en batch,
   ou incrément auto sur `GET`).

2. **Contenu de `signal_context`** : vérifier que les champs `articles_shown`,
   `articles_clicked`, `period_days` sont bien remplis et suffisants pour
   afficher le panneau stats côté mobile. Identifier les gaps éventuels.

3. **Filtrage de pertinence backend** : actuellement le seuil côté backend
   est `CHECKPOINT_MIN_PROPOSALS=2`. Le mobile filtre en plus côté client
   (N≥3, signal≥0.6). Faut-il ajouter un paramètre `min_signal` optionnel
   au `GET /learning-proposals` ? (Opinion : non v1, mais à documenter.)

4. **Cohérence sémantique `dismiss` / snooze** : le bouton « Plus tard » côté
   mobile envoie un batch de `dismiss` pour toutes les propositions restantes.
   Est-ce aligné avec l'intention backend ? Ou faut-il un statut `snoozed`
   dédié pour ne pas polluer les métriques ?

### Contraintes techniques (LOCKED — cf. CLAUDE.md)

- Python 3.12.x uniquement
- `list[]` / `dict[]` / `X | None` natifs — JAMAIS `from typing import List/Dict/Optional`
- Alembic : exactement 1 head, jamais d'exécution sur Railway (SQL via Supabase SQL Editor)
- Si migration nécessaire, lire `docs/agent-brain/safety-guardrails.md` AVANT
- Tests : `pytest -v` dans `packages/api/`
- PR cible OBLIGATOIREMENT `main` (`--base main`)

### Livrable de cette phase PLAN

1. Classification : Maintenance (ajustements mineurs) OU Feature (si nouveau endpoint)
2. Crée le doc approprié :
   - Si maintenance → `docs/maintenance/maintenance-13.5-13.6-backend.md`
   - Si feature → `docs/stories/core/13.5-13.6.construire-son-flux.plan-backend.md`
3. Rapport d'audit des 4 points ci-dessus avec conclusion par point :
   - ✅ OK no-op (rien à faire)
   - ⚠ Petit ajustement (avec plan concret + diff estimé)
   - 🚨 Refactor nécessaire (à escalader au PO)
4. Plan d'implémentation des ajustements identifiés (si applicable) :
   - Fichiers à modifier
   - Tests à ajouter/modifier
   - Migration Alembic (si nécessaire — attention guardrails)
5. STOP → présente le rapport au PO → attends GO explicite

Si l'audit conclut « 0 ajustement nécessaire », produire quand même le rapport
et clôturer proprement (pas de PR, juste notification).

Ne code rien avant le GO. Rédige uniquement le plan.
```

---

## Après les deux PLAN

Une fois les deux plans reviewés et GO donné :

1. Les agents codent en parallèle (mobile + backend) sur leurs branches dédiées
2. Si le backend requiert un changement bloquant pour le mobile → mobile attend le merge backend
3. PR mobile et PR backend séparées vers `main`
4. Validation QA via Playwright MCP (cf. `/validate-feature`) sur la PR mobile

---

## Checklist PO avant de lancer

- [ ] Spec 13.5-13.6 (4 docs) relue et approuvée
- [ ] Ordre de lancement OK (mobile d'abord ou parallèle)
- [ ] Nommage branches d'implémentation validé
- [ ] Convention doc plan (fichier séparé vs section dans hub) tranchée
