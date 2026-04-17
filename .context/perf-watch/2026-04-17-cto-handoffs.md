# Prompts de hand-off — Agents devs H1 + démarrage H2

> 5 prompts self-contained à copier-coller dans des sessions Claude Code neuves.
> Chaque prompt est autonome : l'agent neuf ne voit pas cette conversation.
> Tous les tickets ciblent `main` (règle CLAUDE.md, `staging` déprécié).

---

## Prompt 1 — QW1-infra : Corriger le hook session-start (feedback honnête)

```
Tu es un agent dev Facteur, subagent infra. Lis CLAUDE.md d'abord (workflow
PLAN → CODE+TEST → PR, base main obligatoire, staging déprécié).

## Ticket QW1-infra — Corriger .claude-hooks/session-start.sh pour rapporter
le vrai statut d'installation Railway/Supabase.

## Bug

`.claude-hooks/session-start.sh:22` imprime `[session-start] railway installé.`
dès que `curl` réussit, même si le binaire n'atterrit pas dans `$PATH`.
Vérifié live : message "installé" affiché, puis `which railway` → vide.
Même pattern à vérifier pour Supabase (lignes ~60-70).

## Spec

1. Après l'appel au script officiel, re-tester `command -v railway` dans le
   même shell. Si absent, imprimer `WARN: railway install failed
   (PATH issue? check ~/.railway/bin)` au lieu de `installé.`.
2. Si le binaire est installé dans `~/.railway/bin/` ou autre répertoire
   non-PATH, ajouter `export PATH="$HOME/.railway/bin:$PATH"` en fin de
   hook et dans `~/.bashrc` (idempotent, grep avant append).
3. Même traitement pour Supabase.
4. `exit 0` non-bloquant préservé en toute fin de script.

## Tests

Écris un test `scripts/test-session-start-hook.sh` qui :
- Désinstalle railway (`rm -f $(which railway) ~/.railway/bin/railway`) si présent
- Simule offline (`unset PATH` temporaire ou stub curl qui fail)
- Lance le hook
- Assert : le message contient `WARN:` ET le script sort `0`.

## Contraintes

- Base `main` obligatoire (CLAUDE.md).
- Branche : `claude/qw1-session-start-honest-status`.
- Pas de modif ailleurs que `.claude-hooks/session-start.sh` et
  `scripts/test-session-start-hook.sh`.

## Livrable

PR vers main avec titre "infra(hooks): honest install status for session-start".
Taille attendue : ~30-40 LOC + test. Reviewer : Laurin.

## Références traçables

- Hook actuel : `.claude-hooks/session-start.sh:14-32` (install_railway_cli).
- Livrable CTO : `.context/perf-watch/2026-04-17-cto-h1-quickwins.md` §QW1.
```

---

## Prompt 2 — QW2-infra : Provisionner sentry-cli + railway de façon fiable

```
Tu es un agent dev Facteur, subagent infra. Lis CLAUDE.md d'abord.

## Ticket QW2-infra — Étendre `scripts/setup-cli-tools.sh` pour installer
sentry-cli en plus de railway et supabase, et faire en sorte que le hook
session-start l'appelle en fallback.

## Contexte

Aujourd'hui `scripts/setup-cli-tools.sh` installe railway + supabase. Il
manque sentry-cli (indispensable pour que l'agent perf-watch interroge Sentry
hors MCP). Ce script n'est PAS appelé par le hook session-start actuel — à
changer si c'est simple, sinon documenter.

## Spec

1. Ajouter un bloc "Sentry CLI" dans `scripts/setup-cli-tools.sh` :
   - Check `command -v sentry-cli`
   - Si absent : `curl -sL https://sentry.io/get-cli/ | bash`
   - Verify post-install : `sentry-cli --version` doit renvoyer un numéro
2. (Facultatif, seulement si QW1 est déjà mergé) faire appeler
   `setup-cli-tools.sh` depuis `session-start.sh` en fallback idempotent
   (si railway OU sentry-cli OU supabase est manquant après la première
   passe, lancer le script de setup).
3. Test manuel en conteneur neuf : lancer `bash scripts/setup-cli-tools.sh`,
   vérifier `railway --version && supabase --version && sentry-cli --version`.

## Contraintes

- Base `main`, branche `claude/qw2-provision-sentry-cli`.
- Pas de PR sans QW1 mergé si tu choisis l'intégration hook (point 2).
  Sinon livre juste le script étendu + reviewer décide de l'intégration.

## Livrable

PR vers main. Taille attendue : ~20-30 LOC dans `setup-cli-tools.sh`.
Titre : "infra(cli): provision sentry-cli alongside railway/supabase".

## Références traçables

- Script existant : `scripts/setup-cli-tools.sh:1-40+`.
- Livrable CTO : `.context/perf-watch/2026-04-17-cto-h1-quickwins.md` §QW2.
```

---

## Prompt 3 — QW3-infra : Activer le MCP Sentry (secret + doc)

```
Tu es un agent dev Facteur, subagent infra. Lis CLAUDE.md d'abord.

## Ticket QW3-infra — Activer le MCP Sentry pour que l'agent perf-watch
puisse interroger les issues Sentry sans CLI locale.

## Contexte

- `mcp-servers/sentry/server.py` existe dans le repo.
- `.claude/settings.json` déclare déjà le MCP sentry avec les env vars
  `SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT` (via `${VAR}`).
- Le MCP ne s'active pas aujourd'hui car les secrets ne sont pas peuplés
  dans l'environnement session CC-on-web.

## Spec

1. Vérifier avec Laurin (l'utilisateur) quelle méthode de peuplement est
   disponible pour CC-on-web : session-env, user settings, ou
   `.claude/settings.local.json`. **Ne pas committer de secret en clair.**
2. Tester le MCP manuellement une fois les secrets posés :
   `python mcp-servers/sentry/server.py` doit lister les tools exposés.
3. Créer `docs/infra/mcp-sentry-setup.md` (≤ 30 lignes) qui documente :
   - Où trouver le `SENTRY_AUTH_TOKEN` (Sentry org settings → API tokens)
   - Scopes minimum requis (project:read, event:read, issue:read)
   - Comment le peupler dans CC-on-web
   - Procédure de renouvellement tous les 90 jours
4. Ajouter un log `sentry_mcp_ready` au démarrage (dans `server.py`) pour
   que l'agent perf-watch puisse vérifier que le MCP est opérationnel.

## Contraintes

- Base `main`, branche `claude/qw3-activate-mcp-sentry`.
- **AUCUN secret committé.** Le doc explique comment peupler, sans token.
- Pas de modification du MCP server au-delà du log `sentry_mcp_ready`.

## Livrable

PR vers main. Taille attendue : doc (~30 lignes) + ~5 LOC dans server.py.
Titre : "infra(mcp): document sentry MCP activation + readiness log".

## Références traçables

- MCP config : `.claude/settings.json` §mcpServers.sentry.
- MCP server : `mcp-servers/sentry/server.py`.
- Livrable CTO : `.context/perf-watch/2026-04-17-cto-h1-quickwins.md` §QW3.
```

---

## Prompt 4 — QW4-infra : Allowlist WebFetch pour `/api/health/pool`

```
Tu es un agent dev Facteur, subagent infra. Lis CLAUDE.md d'abord.

## Ticket QW4-infra — Permettre à l'agent perf-watch de scraper
facteur-production.up.railway.app via WebFetch.

## Contexte

`/api/health/pool` existe en prod (`packages/api/app/main.py:455`) et renvoie
`{checked_out, overflow, checked_in, usage_pct, status}`. Sans accès à cette
URL, l'agent perf-watch est aveugle sur l'état du pool DB entre les deux
canaux Sentry (lent, événementiel).

## Spec

1. Identifier où est configurée l'allowlist WebFetch dans cet environnement
   CC-on-web. Pistes : réglages harness utilisateur, `.claude/settings.json`
   projet, `.claude/settings.local.json`, ou config côté Claude Code app.
2. Ajouter `facteur-production.up.railway.app` à la liste des domaines
   autorisés pour WebFetch.
3. Tester depuis une session neuve :
   `WebFetch(https://facteur-production.up.railway.app/api/health/pool)` doit
   renvoyer du JSON valide avec les champs ci-dessus.
4. Si le réglage est côté utilisateur/harness (pas committable), créer
   `docs/infra/cc-web-webfetch-allowlist.md` qui explique à Laurin comment
   l'ajouter manuellement, captures d'écran à l'appui si possible.

## Contraintes

- Base `main`, branche `claude/qw4-webfetch-allowlist-prod`.
- **Ne JAMAIS** ajouter une allowlist globale `*` ou `*.railway.app` :
  seulement le domaine prod cible.

## Livrable

PR vers main (si la config est committable) OU un doc + message
de hand-off à Laurin (si config côté harness).
Titre : "infra(cc-web): allow WebFetch to production health endpoint".

## Références traçables

- Endpoint : `packages/api/app/main.py:455` (route `/api/health/pool`).
- Livrable CTO : `.context/perf-watch/2026-04-17-cto-h1-quickwins.md` §QW4.
```

---

## Prompt 5 — T2-1 : Test de charge synthétique k6 "burst Chrome" en staging

```
Tu es un agent dev Facteur, subagent dev. Lis CLAUDE.md d'abord (workflow
PLAN → CODE+TEST → PR, base main obligatoire).

## Ticket T2-1 — Créer un test de charge k6 reproductible qui simule
le burst de requêtes que Chrome déclenche à l'ouverture de l'app web.
Sert de gate-keeper pour toute PR backend future.

## Contexte

Le bug doc §Round 4 documente le pattern : à l'ouverture web, Chrome envoie
en parallèle `/api/feed/`, `/api/users/streak`, `/api/digest/both`,
`/api/sources/`, `/api/collections/`, `/api/custom-topics/`. À 1-3 conns/req,
un user sature 6-10 slots sur 20 disponibles. R4 (PR #417, `cabc627`) a
réduit `/api/feed/` 3→2 sessions, mais on n'a jamais 24h de données
propres pour valider à cause des bursts imprévus — d'où ce test synthétique.

## Spec

1. Script k6 dans `docs/qa/load-tests/burst-chrome.js` :
   - 1 VU, 10s warmup (1 batch), puis 10 VU pendant 60s, puis 20 VU
     pendant 30s. Ramp progressif, pas de step function.
   - Chaque VU exécute en parallèle via `http.batch` les 6 endpoints avec
     un JWT valide d'un user de staging (variable d'env `STAGING_JWT`).
   - Polling `/api/health/pool` toutes les 15s (stocké dans Summary k6).
2. Assertions k6 (critères go/no-go) :
   - `p95(http_req_duration) < 5000` sur chacun des 6 endpoints.
   - `http_req_failed rate < 0.01` (cible 0, tolérance 1%).
   - `checks` custom sur `/api/health/pool` : `status != "saturated"` et
     `checked_out <= 14`.
3. Makefile target à la racine : `make load-test-burst` qui lance le script
   k6 en pointant sur l'URL de staging (variable `STAGING_BASE_URL`).
4. README `docs/qa/load-tests/README.md` :
   - Prérequis : `k6` installé (binaire statique).
   - Comment générer un JWT staging valide (pointer vers un script existant
     si dispo, sinon documenter le flow Supabase auth).
   - Comment interpréter le rapport.
   - Critères go/no-go pour merger une PR backend.

## Contraintes

- Base `main`, branche `claude/t2-1-load-test-burst-chrome`.
- **Test green obligatoire contre staging R4 avant merge** de ce ticket.
  Si staging échoue le test, ne pas "ajuster les seuils" pour que ça passe :
  c'est le signal qu'il faut Round 5. Dans ce cas, documente l'échec dans
  la PR description et demande escalade.
- Ne PAS lancer ce test contre la prod.

## Livrable

PR vers main. Titre : "qa(load): k6 burst-chrome synthetic test as PR gate".
Taille attendue : ~200-300 lignes (script + README + Makefile).
Joins les résultats du run staging dans la PR description.

## Références traçables

- Bug doc §Round 4 : `docs/bugs/bug-infinite-load-requests.md` L634-L710.
- PR R4 : `cabc627` (#417).
- Endpoint pool : `packages/api/app/main.py:455`.
- Livrable CTO : `.context/perf-watch/2026-04-17-cto-h2-pool.md` §T2-1.
```

---

## Ordre de lancement recommandé

1. **Prompt 1 (QW1)** — en premier, 30 min. Bloque les diagnostics futurs si
   on laisse le feedback menteur.
2. **Prompts 3 et 4 (QW3, QW4) en parallèle** — débloquent respectivement
   Sentry et `/api/health/pool` pour l'agent perf-watch.
3. **Prompt 2 (QW2)** — après QW1 mergé si tu intègres le fallback
   session-start, sinon indépendamment.
4. **Prompt 5 (T2-1)** — peut démarrer en parallèle dès maintenant ; pas de
   dépendance sur H1. Probablement le plus long (M, ~1 jour).

Total : ~½ jour infra (prompts 1-4) + 1 jour dev (prompt 5). Tout terminé
d'ici vendredi si lancé ce matin.
