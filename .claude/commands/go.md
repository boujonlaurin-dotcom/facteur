# /go — Vérifier, simplifier, ouvrir la PR

Tu viens de terminer une tâche (feature, bug, maintenance). `/go` est l'étape
**VERIFY → SIMPLIFY → PR** : tu dois **prouver** que ton code marche avant de
demander une review, puis ouvrir la PR.

Règle absolue : si une étape échoue, tu **corriges** avant de passer à la
suivante. Ne jamais marquer une étape OK sans preuve (output de test, screenshot,
requête réseau).

---

## 1. VERIFY — Tester bout-en-bout

Choisis les vérifications selon ce qui a été modifié dans le diff
(`git diff --stat origin/main...HEAD`).

### Backend modifié (`packages/api/**`)

1. **Tests unitaires** : `cd packages/api && pytest -v` — 0 échec requis.
2. **Démarre l'API locale** en arrière-plan :
   `cd packages/api && uvicorn app.main:app --port 8080 --reload`
3. **Teste les endpoints touchés** avec `curl` (cas nominal + au moins 1 cas
   limite : auth manquante, payload invalide, ressource inexistante). Capture
   status code + body.
4. **Script QA dédié** s'il existe : `bash docs/qa/scripts/verify_<task>.sh`.
5. Arrête le serveur une fois les tests passés.

### Mobile / UI modifié (`apps/mobile/**`)

1. **Tests Flutter** : `cd apps/mobile && flutter test` puis `flutter analyze`.
2. **Validation navigateur via Playwright MCP** (viewport 390x844) :
   - Démarre l'API locale si la feature en dépend
   - Navigate vers la route touchée, screenshot avant/après chaque interaction
   - Vérifie `read_console_messages(onlyErrors: true)` — aucune erreur JS
   - Vérifie `read_network_requests` — aucun 4xx/5xx inattendu
   - Teste au moins 1 edge case (saisie vide, double-clic, retour arrière)
3. Si un `.context/qa-handoff.md` existe, exécute tous ses scénarios.

### Migration Alembic

1. `cd packages/api && alembic heads` — exactement 1 head.
2. `alembic upgrade head` sur une DB locale — doit passer sans erreur.
3. **Ne JAMAIS exécuter Alembic sur Railway** (règle LOCKED de CLAUDE.md).

### Suite complète (toujours, à la fin)

```bash
cd packages/api && pytest -v
cd apps/mobile && flutter test && flutter analyze
```

Le hook `stop-verify-tests.sh` refusera de te laisser conclure si des tests
échouent — anticipe-le.

---

## 2. SIMPLIFY — Invoke la skill `simplify`

Invoque la skill `simplify` via le Skill tool. Elle relit le diff et corrige
les problèmes de réutilisation, qualité et efficacité. Re-run VERIFY (étape 1)
si `simplify` a modifié du code.

---

## 3. PR — Créer la pull request

1. Vérifie la branche courante : elle doit commencer par `claude/` (jamais
   `staging`, jamais `main`).
2. Vérifie qu'il n'y a rien d'oublié :
   `git status` (clean) · `git log origin/main..HEAD --oneline` (≥1 commit).
3. Push : `git push -u origin <branche>` (retry 4x avec backoff 2s/4s/8s/16s
   si échec réseau).
4. **Crée la PR avec `mcp__github__create_pull_request`** — base `main`
   **obligatoire**. Repo : `boujonlaurin-dotcom/facteur`.
5. Si `.context/pr-handoff.md` existe, utilise son contenu comme body.
   Sinon, génère un body :

   ```markdown
   ## Quoi
   <résumé 2-3 lignes>

   ## Pourquoi
   <contexte métier / bug résolu>

   ## Comment ça a été vérifié
   - [ ] pytest (N tests OK)
   - [ ] flutter test + analyze OK
   - [ ] Scénarios Playwright OK (si UI)
   - [ ] /simplify passé

   ## Zones à risque
   <modules sensibles touchés>
   ```

6. **STOP** et notifie : `PR #<num> prête pour review — <url>`.
7. Propose à l'utilisateur de s'abonner aux events CI/review via
   `mcp__github__subscribe_pr_activity`.

---

## Règles non négociables

- `--base main` **toujours**. `staging` est DÉPRÉCIÉ — toute tentative sera
  bloquée par `pre-bash-no-staging.sh`.
- Ne jamais `--no-verify`, `--force-with-lease` sur `main`, ni amender un commit
  déjà poussé.
- Si VERIFY échoue à la 2e tentative après fix, **stop** et demande à
  l'utilisateur au lieu de boucler.
- Ne crée pas de fichiers de planning / rapport intermédiaires — le body de
  PR et les commits sont la seule documentation.
