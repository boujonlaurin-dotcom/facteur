# Bug: Veille — digests vides en historique + pas d'effet « Wow » en fin de config

## Statut
- [x] Corrigé (date: 2026-05-06)

## Sévérité
🔴 Critique — la fonctionnalité Veille était silencieusement cassée pour ~94 % des utilisateurs (16/17 configs en prod ne produisaient aucun digest), et le flow d'onboarding ne montrait jamais le résultat de la première veille.

## Description

Deux symptômes signalés par le PO :

1. **Effet « Wow » absent en fin de configuration** : après validation du Step 4, l'utilisateur ne voyait pas sa première veille se construire ni s'afficher.
2. **Toutes les générations passées (visibles dans Historique) avaient un contenu vide** : 4/4 livraisons en `succeeded` ces 30 derniers jours avaient `item_count = 0`.

## Cause racine

### P1 — Effet Wow absent

`apps/mobile/lib/features/veille/screens/veille_config_screen.dart`

- L'écran `FlowLoadingScreen(from=4)` n'était poussé qu'**après** le retour de `submitAndGenerateFirst()` (~700 ms-1 s) → l'utilisateur voyait Step 4 figé pendant ce délai au lieu de l'écran de chargement.
- Une fois la génération terminée, on naviguait vers `/veille/dashboard` (config statique), **pas vers la livraison** → l'utilisateur ne voyait jamais son premier digest.
- Le titre du loader (`'Première veille en cours'`) ne portait pas l'intention « ta veille se construit pour toi ! ».

### P2 — Digests vides

`packages/api/app/services/veille/digest_builder.py:171` (avant fix) :

```python
Content.topics.op("&&")(ctx.user_topic_ids)
```

- `Content.topics` ne contient que les ~51 slugs canoniques de la taxonomie classifier (`ai`, `tech`, `cybersecurity`, `politics`...) — cf `app/services/ml/classification_service.py:57` `VALID_TOPIC_SLUGS`.
- `ctx.user_topic_ids` contient des slugs **LLM-générés** par `topic_suggester.py` (kebab-case libres : `custom-agents-llm-frameworks`, `optimisation-cout-inference-llm`, `automatisation-processus-devops`...). Sur 17 valeurs distinctes en prod, **seul `ai` matchait un slug canonique**.
- Conséquence : l'intersection `&&` retournait 0 ligne pour 16 users sur 17, même quand 36-77 articles étaient disponibles dans la fenêtre de lookback. Une 2e barrière au niveau Python (`_filter_clusters_for_topics`) achevait ce qui restait.
- Symptôme secondaire : 1 livraison `running` depuis le 2026-05-04 (config `6f3529f7…`), aucun watchdog ne la repassait en `failed` après crash worker.

## Solution

### Mobile (P1)

`apps/mobile/lib/features/veille/screens/veille_config_screen.dart`

1. Appel `notifier.setLoadingFrom(4)` **avant** tout `await` → loader full-screen instantané.
2. `_pollFirstDelivery` retourne `bool` ; en succès, navigation directe vers `/veille/deliveries/<deliveryId>` (digest reader). Échec/timeout → fallback `/veille/dashboard` + snackbar (comportement précédent).

`apps/mobile/lib/features/veille/screens/transitions/flow_loading_screen.dart` :

- Titre `from=4` → « Votre première veille se construit ! ».

### Backend (P2)

`packages/api/app/services/veille/digest_builder.py` :

- Suppression du filtre SQL `Content.topics &&` dans `_fetch_contents` : on garde uniquement `source_id IN (...)` + fenêtre `published_at`. Les sources sont pickées explicitement par le user, c'est déjà un signal d'intention fort.
- Suppression de `_filter_clusters_for_topics` (et de son appel) : le top-N par taille de cluster + le « why it matters » LLM (qui reçoit `topics` + `purpose` dans son prompt) gèrent la sélection éditoriale.
- Log de cluster vide renommé `veille_pipeline.no_clusters` (avant : `no_relevant_clusters`).

`packages/api/app/jobs/veille_generation_job.py` :

- Hard cap `asyncio.wait_for(builder.build(...), timeout=300)` dans `run_veille_generation_for_config` : en cas de hang LLM/DB, l'exception remonte et `_mark_scanner_delivery_failed` persiste FAILED + Sentry.
- Watchdog explicit dans `_phase1_mark_running` : si une row RUNNING > 10 min existe, log `veille.stuck_running_reset` (Sentry) avant le `on_conflict_do_update` qui la reset.

### One-shot prod

UPDATE Supabase de la livraison stuck (config `6f3529f7…`, target_date 2026-05-04) :

```sql
UPDATE veille_deliveries
SET generation_state = 'failed',
    finished_at = now(),
    last_error = 'watchdog_backfill: stuck running since 2026-05-04 (worker SIGKILL/restart, no FAILED transition)'
WHERE id = '90adb2e5-da1a-46f6-8fb1-38f6d54ad62c'
  AND generation_state = 'running';
```

Vérification : `SELECT COUNT(*) FROM veille_deliveries WHERE generation_state='running' AND started_at < now() - interval '10 minutes'` → 0.

## Tests

- `tests/test_veille_digest_builder.py::TestBuild::test_includes_all_source_articles_regardless_of_topic` (renommé depuis `test_filters_by_topic_overlap`) : tous les articles des sources entrent dans le pipeline.
- `tests/test_veille_digest_builder.py::TestBuild::test_returns_items_when_user_topics_mismatch_classifier_taxonomy` (nouveau) : reproduit la cause racine (slugs LLM `custom-…` vs `Content.topics=['ai']`) et asserte que `build` retourne ≥ 1 item.
- Mobile : tests `veille_config_provider_test.dart` + `flow_loading_screen_test.dart` re-passent inchangés (les changements `handleSubmit` sont dans le widget host, pas dans le notifier).

## Risques résiduels

- Drop du filtre topic peut introduire un peu de bruit (articles de la source mais hors-sujet exact du user). Mitigation : le LLM « why it matters » reçoit `topics` + `purpose` et explique la pertinence ; le clustering filtre déjà les bruits de fond. Si le bruit est confirmé en QA, ajouter en v2 un mapping LLM-slug → canonical via embeddings.
- Hard timeout 300 s : à monitorer via le log `veille.scanner_delivery_failed_terminal`.

## Hors scope (à ouvrir séparément)

- Mapping LLM-slug → taxonomie canonique (v2 propre).
- Instrumentation PostHog `veille_first_delivery_*` (utile pour mesurer l'effet Wow, pas bloquant).
- PYTHON-3Z `IdleInTransactionSessionTimeout` sur `/suggestions/sources` (déjà partiellement adressé par PR #572/#575).
