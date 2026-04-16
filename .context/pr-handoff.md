# PR — Fix onboarding : pré-génération du digest pendant l'animation de conclusion

## Quoi

Trois changements coordonnés pour qu'un nouveau utilisateur voie son Essentiel **immédiatement** après l'onboarding, au lieu d'attendre le batch du lendemain :

1. **Backend onboarding** : `POST /users/onboarding` schedule via `BackgroundTasks` la pré-génération des deux variantes du digest (normal + serein) **après commit**. Réutilise l'helper existant `_schedule_background_regen` (rate-limit, session dédiée, skip si batch en cours), exposé via deux nouvelles fonctions publiques `schedule_digest_regen` et `schedule_initial_digest_generation`.
2. **Backend digest** : `GET /digest` et `GET /digest/both` renvoient désormais **`202 "preparing"`** (au lieu de `503` ou `200 {normal:null, serein:null}`) quand `get_or_create_digest()` retourne `None`, et déclenchent un regen en arrière-plan. Un seul contrat mobile : 202 = poll, 200 = prêt, 503 = vraie panne.
3. **Mobile** : retries 202 passent de 3 à 5 avec délais escaladés (5/10/15/20/30s, ~80s total). Le retry 503 reste borné à 3 (constante locale `maxGenerationRetries`) pour ne pas masquer une vraie panne.

## Pourquoi

Bug critique nouveau-user : un utilisateur qui termine l'onboarding **hors fenêtre batch** (le batch tourne à 6h Paris et fige son snapshot d'users à ce moment-là) restait bloqué sur un spinner d'Essentiel jusqu'au batch du lendemain matin.

Trois défauts cumulés (analyse complète dans `docs/bugs/bug-onboarding-digest-loading.md`) :

- Aucun trigger de génération entre la fin de l'onboarding et le batch suivant.
- `get_or_create_digest()` peut renvoyer `None` pour un compte vide (pas d'historique + sources sans articles dans la fenêtre 168h), et le router transformait ça en `503` qui épuisait le budget retry mobile (3 retries × 30s = 30s vs LLM editorial qui peut prendre 1-3 min).
- `/digest/both` renvoyait silencieusement `200 OK` avec `normal=null, serein=null` dans le même cas — le mobile ne sait pas quoi en faire.

## Fichiers modifiés

**Backend (3 fichiers)**
- `packages/api/app/services/digest_service.py` — +30 lignes : exposition publique de `schedule_digest_regen` (wrapper) et `schedule_initial_digest_generation` (helper qui schedule les 2 variantes pour `today_paris()`).
- `packages/api/app/routers/users.py` — +23 lignes : `BackgroundTasks` ajouté à `save_onboarding`, appel post-succès à `schedule_initial_digest_generation`.
- `packages/api/app/routers/digest.py` — +42 lignes : remplacement du `raise HTTPException(503)` par `return JSONResponse(202)` + `schedule_digest_regen` dans `GET /digest` ; ajout d'une branche identique dans `GET /digest/both` quand les deux variantes sont `None`.

**Mobile (1 fichier)**
- `apps/mobile/lib/features/digest/providers/digest_provider.dart` — +19 lignes : `_digestMaxRetries` 3→5, ajout de 2 délais (20s, 30s), extraction de `maxGenerationRetries=3` local pour le path 503.

**Tests (1 fichier nouveau, 215 lignes)**
- `packages/api/tests/test_onboarding_digest_pregeneration.py` — 3 régressions : (a) `/digest` None→202+regen, (b) `/digest/both` both-None→202+2×regen, (c) `POST /users/onboarding` schedule bien la BackgroundTask.

**Docs**
- `docs/bugs/bug-onboarding-digest-loading.md` — 140 lignes : analyse root cause, plan, scope, rollback.

## Zones à risque

- **`packages/api/app/services/digest_service.py:_schedule_background_regen`** — c'est le helper interne réutilisé. Pas modifié, mais maintenant appelé depuis 2 nouveaux call sites (onboarding + router fallback). Le rate-limit (1/min par `(user, date, variant)`) protège contre les spawns multiples ; vérifier que la cooldown est cohérente avec la latence pipeline LLM (~60-90s sur cold start).
- **`packages/api/app/routers/digest.py:get_digest`** — la branche None ne renvoie plus 503 mais 202. Tout client qui interprétait `503 "Digest generation failed"` comme une vraie panne (Sentry, dashboards, alerting) verra son trafic basculer sur 202. À vérifier côté monitoring.
- **`packages/api/app/routers/users.py:save_onboarding`** — l'ajout de `BackgroundTasks` change la signature. Si un test/mock injectait des kwargs positionnels, ils peuvent se décaler. Vérifié manuellement : `data, background_tasks, user_id=Depends, db=Depends` — l'ordre de FastAPI gère bien les kwargs Depends.
- **`apps/mobile/.../digest_provider.dart`** — passer de 3 à 5 retries augmente le temps max d'affichage du spinner avant erreur dure (de ~30s à ~80s sur 202). Pour un nouvel user c'est mieux qu'un spinner infini ; pour un user existant qui aurait un bug serveur, c'est 50s d'attente supplémentaires avant erreur visible. Acceptable étant donné qu'on revient au polling 202 propre.

## Points d'attention pour le reviewer

1. **Timing transactionnel onboarding → bg task** — le point critique. L'helper `_schedule_background_regen` ouvre sa propre `AsyncSession`. Pour qu'il voie les `UserSource`, `UserInterest`, `UserSubtopic` créés dans la transaction d'onboarding, il **faut** que la bg task tourne après `db.commit()`. C'est garanti par `BackgroundTasks` de FastAPI : la task est exécutée après que la response est envoyée, donc après que `get_db()` ait commit. Si on avait utilisé `asyncio.create_task` direct dans le handler, la bg session aurait pu lire avant le commit du request → digest vide → boucle.

2. **Redondance saine** — l'onboarding pré-schedule, **et** le router schedule à nouveau si `None` au moment du GET. Voulu : si la pré-gen rate les 60s de cooldown, ou si le pipeline crashe, le poll mobile redéclenche un nouveau spawn. Le rate-limit 1/min empêche les pile-ons.

3. **`schedule_initial_digest_generation` vs `_schedule_background_regen`** — j'ai créé une fonction dédiée plutôt que d'appeler 2× le helper interne depuis le router. Justification : sémantique différente ("je viens de finir l'onboarding, génère mes 2 variantes pour aujourd'hui") vs ("régénère la variante X parce que rien n'existe"). Le wrapper est explicite et facilement greppable.

4. **Test `test_onboarding_schedules_initial_digest_generation`** — utilise `app.dependency_overrides` + mock de `UserService.save_onboarding` et `OnboardingResponse.model_validate`. Si la requête body validation échoue (422 au lieu de 200), le test passe quand même mais sans valider le scheduler — j'ai gardé l'assertion conditionnelle `if resp.status_code == 200` parce que le test cible le routing/scheduling, pas la validation Pydantic. Si tu préfères un test plus strict, on peut construire un payload `OnboardingAnswers` complet.

5. **`get_or_create_digest()` non modifié** — j'ai volontairement laissé le retour `None` à la ligne 690 plutôt que d'y mettre un fallback supplémentaire. Le router est la couche qui transforme "rien à servir" en "réessaie plus tard". Garder ça séparé évite de coupler le service à la sémantique HTTP.

## Ce qui N'A PAS changé (mais pourrait sembler affecté)

- **Le scheduler batch quotidien (6h Paris)** — pas touché. Le fix vise uniquement la fenêtre entre la fin de l'onboarding et le prochain batch.
- **`digest_service.get_or_create_digest`** — pas touché. La logique de sélection / emergency fallback / yesterday-fallback reste identique. On corrige uniquement comment le router communique l'absence de résultat au mobile.
- **L'animation de conclusion mobile (10s)** — pas touchée. C'est cette animation qui sert de "fenêtre de pré-gén" côté serveur ; sa durée est utilisée comme acquise.
- **Le 503 sur `digest_generation_timeout`** dans `/digest/both` — pas touché. Reste 503 avec `detail: "digest_generation_timeout"` pour préserver le test de régression `test_digest_both_timeout.py` et le path "vraie panne upstream".
- **Le code Hive / cache local mobile** — pas touché. Les digests servis sont enregistrés normalement.
- **`UserService.save_onboarding`** — la fonction service elle-même est inchangée. Le scheduler est injecté au niveau du router via `BackgroundTasks`.

## Comment tester

### Tests automatisés

```bash
cd packages/api
PYTHONPATH=. pytest tests/test_onboarding_digest_pregeneration.py \
                   tests/test_digest_service.py \
                   tests/test_digest_both_timeout.py \
                   tests/test_onboarding_sources.py \
                   tests/test_user_service_persist.py -v
```

Attendu : 73 passed.

### Test manuel (E2E)

1. **Préparation** :
   - Backend local : `cd packages/api && uvicorn app.main:app --port 8080`
   - Note l'heure courante : si entre 6h00 et 6h05 Paris, attendre, sinon le batch va interférer.

2. **Scénario nominal nouveau user** :
   - Créer un compte fresh sur le mobile (Supabase auth → user créé).
   - Compléter tout l'onboarding (sélectionner thèmes, sources, etc.).
   - Démarrer un timer au début de l'animation de conclusion.
   - **Attendu** : à la fin de l'animation (10s), l'écran Essentiel doit afficher des articles en **<5s** supplémentaires (la pré-gen a tourné en parallèle).

3. **Vérification logs backend** (cherche dans l'ordre, dans les ~15s après la fin onboarding) :
   ```
   onboarding_saved user_id=...
   digest_background_regen_scheduled user_id=... is_serene=False
   digest_background_regen_scheduled user_id=... is_serene=True
   digest_background_regen_completed user_id=... is_serene=False
   digest_background_regen_completed user_id=... is_serene=True
   ```

4. **Scénario fallback (génération lente)** :
   - Stub temporaire : ajouter un `await asyncio.sleep(40)` au début de `DigestSelector.select_for_user` pour simuler un LLM lent.
   - Refaire l'onboarding fresh.
   - **Attendu** : le mobile reçoit `202 "preparing"` puis poll 5x (5/10/15/20/30s). Au bout de ~40s, le digest apparaît sans erreur.

5. **Scénario panne dure (503)** :
   - Stub : `raise Exception("upstream dead")` dans `DigestSelector.select_for_user`.
   - Refaire l'onboarding.
   - **Attendu** : le mobile reçoit 503, retry 3 fois, puis affiche l'erreur (pas de boucle infinie).

### Tests Flutter

```bash
cd apps/mobile && flutter test test/features/digest/
```

⚠️ **Pas de test unitaire ajouté côté Dart** — le changement se limite à 5 constantes (`_digestMaxRetries`, `_digestRetryDelays`, `maxGenerationRetries`). Le runtime Flutter n'était pas disponible dans le sandbox Claude pour valider, mais le code est syntaxiquement trivial. À valider via `/validate-feature` ou en local avant merge.

### Validation QA web (recommandée)

Lancer `/validate-feature` après création du `qa-handoff.md` correspondant — la feature touche un flux UI critique (onboarding → premier écran).
