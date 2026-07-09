# Bug — Onboarding : sujets personnalisés « n'ont pas pu être enregistrés »

**Type** : Bug
**Statut** : Corrigé (branche `boujonlaurin-dotcom/onboarding-custom-topic-save-error`)
**Décision PO** : Variant B — réutiliser la fenêtre de désambiguïsation (`EntityAddSheet`)
dans l'onboarding. Scope complet : UX + robustesse backend + observabilité.

## Symptôme

En toute fin d'onboarding, quand l'utilisateur avait ajouté des sujets personnalisés,
une modale s'affichait parfois : « Certains sujets personnalisés n'ont pas pu être
sauvés (…). Tu pourras les réajouter depuis Mes Intérêts. »

## Cause racine (deux couches cumulées)

1. **Architecture — sauvegarde différée en batch terminal.** L'onboarding stockait
   les sujets custom en simples chaînes locales (`_customTopics`) et différait toutes
   les sauvegardes à la toute fin (`_continue`, `Future.wait`). Comme `followTopic`
   passe par un mutex (`_serialized`), ce batch s'exécutait en chaîne séquentielle de
   N appels lents. Chaque appel frappe `POST /personalization/topics/` →
   `create_topic`, qui **bloquait sur un enrichissement LLM Mistral (timeout httpx
   15 s)** avant d'écrire la ligne. Tout appel dépassant le `receiveTimeout` Dio
   (30 s), ou trébuchant sur le refresh de session 5 s, renvoyait `null` → marqué en
   échec → modale de synthèse.
2. **UX — aucun retour à l'ajout.** L'utilisateur ne découvrait l'échec qu'à la ligne
   d'arrivée, quand plus rien n'était actionnable.

**Observabilité aveugle** : l'échec était avalé côté client (`catchError` +
`debugPrint`), rien n'allait dans Sentry ⇒ fréquence réelle sous-estimée. Signaux
corroborants dans Sentry : `FLUTTER-1E` (DioException receive timeout > 30 s) et
`FLUTTER-6` (TimeoutException 5 s dans le session refresher).

## Correctif

### Mobile
- `subtopics_question.dart` : l'ajout inline (champ texte local) est remplacé par
  l'ouverture d'`EntityAddSheet.show(context, themeSlug: …)` — même composant que
  « Mes Intérêts ». Le sujet est **validé, désambiguïsé, créé et confirmé au moment
  de l'ajout** (snackbar immédiat, retry inline sur erreur). Plus de batch terminal
  pour les sujets custom.
- Les chips « saved » sont **dérivés de `customTopicsProvider`** filtré par
  `slugParent == themeSlug` (source de vérité, hydratés au restart). Le X appelle
  `unfollowTopic(id)`. Cap 3/thème conservé côté client.
- `_continue` ne persiste plus que les entités populaires cochées, séquentiellement,
  avec observabilité (Sentry + analytics) et 409 traité comme « déjà suivi » (succès).
- `recordFailedCustomTopics` + la modale finale deviennent un **vrai dernier recours** :
  dans le cas nominal la liste est vide et la modale ne s'affiche jamais.

### Observabilité
- `analytics_service.dart` : nouvel event `trackCustomTopicSaveFailed({name, origin,
  theme, error})`.
- `custom_topics_provider.dart` : `Sentry.addBreadcrumb` dans les `catch` de
  `followTopic` / `followEntity` (couvre réglages + onboarding).
- `entity_add_sheet.dart` : `Sentry.captureException` en plus du snackbar dans les
  catchs `_submit` / `_followSuggestion`.

### Backend — borne la latence LLM (`_LLM_BUDGET_SECONDS = 8s`)
- `topic_enrichment_service.enrich` / `disambiguate` acceptent un `llm_timeout` qui
  enveloppe l'appel LLM dans `asyncio.wait_for`. Sur timeout, retombée sur le
  fallback fuzzy existant (`_fallback_enrich`). Comme `slug_parent` de la requête
  prime, la perte de qualité est minime en onboarding (thème connu).
- `create_topic` et l'endpoint `/disambiguate` passent le budget (8 s < 30 s client).
- Le `receiveTimeout` client n'est **pas** augmenté (masquerait le problème).

### Migration
**Aucune.** Fix UX = client-only ; le budget backend est un tweak comportemental dans
des endpoints existants, sans changement de schéma. Idempotence et cap 3/thème
inchangés.

## Vérification
- `flutter test` (custom_topics + onboarding), `flutter analyze` (pas de net-new).
- `pytest packages/api/tests/test_custom_topics*.py` : idempotence, cap 3 → 409,
  fallback rapide quand l'enrichissement LLM traîne/échoue (budget).
- E2E web : sujet ambigu (désambiguïsation) + sujet non ambigu (confirmation directe),
  échec réseau → retry inline + absence de la modale de fin.
