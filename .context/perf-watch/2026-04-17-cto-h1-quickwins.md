# CTO H1 — Déblocage immédiat (J+1) : rendre perf-watch voyant

> Horizon 1 / 3 du handoff CTO 2026-04-17. Objectif : que la session nocturne de
> demain (2026-04-18) ait accès à Sentry + Railway logs + `/api/health/pool`
> **sans intervention humaine**. Fenêtre de validation R4 (post-PR #417,
> déployée ~2026-04-16 14:00 UTC) passe sinon sans signal.

## Constat observationnel (ce matin, cette session)

- `.context/perf-watch/2026-04-17.md` **absent** du filesystem. Le rapport
  nocturne annoncé par le handoff n'a pas été produit / committé.
- `railway --version` → `command not found` malgré le message
  `[session-start] railway installé.` affiché par le hook au SessionStart.
- `sentry-cli --version` → `command not found`.
- `mcp-servers/sentry/server.py` **existe** (`.claude/settings.json` déclare
  déjà le MCP sentry avec `SENTRY_AUTH_TOKEN`/`SENTRY_ORG`/`SENTRY_PROJECT`).
  Le serveur n'a simplement pas les secrets peuplés au démarrage.
- `/api/health/pool` existe en prod (`packages/api/app/main.py:455`).

## Cause racine du feedback trompeur

`.claude-hooks/session-start.sh:22`

```bash
if bash <(curl -fsSL https://railway.app/install.sh) 2>&1; then
  echo "[session-start] railway installé."
```

Le `if` teste le code retour du pipeline. Le script officiel Railway imprime
ses erreurs mais ne retourne pas toujours un non-zero quand le binaire n'atterrit
pas dans `$PATH` (install dans `~/.railway/bin/` non ajouté au PATH du shell
Claude). Résultat : `echo "installé"` systématique dès que `curl` réussit.

## Tickets — à distribuer à un subagent infra

### QW1-infra — Corriger le hook session-start (feedback véridique)

**Owner** : subagent infra (Claude Agent SDK)
**Taille** : S (~20 LOC + test)
**Branche** : `claude/qw1-session-start-honest-status`

**Spec** :
1. Après l'appel au script officiel, re-vérifier `command -v railway` **dans
   le même shell** ; si absent, rapporter `WARN: railway install failed` au
   lieu de `installé.` (même pattern pour supabase).
2. Si l'install pose le binaire dans un répertoire non-PATH (par ex.
   `~/.railway/bin/`), ajouter `export PATH="$HOME/.railway/bin:$PATH"` en
   fin de hook et dans `~/.bashrc` / `~/.zshrc` (idempotent).
3. Test : lancer `bash .claude-hooks/session-start.sh` dans un conteneur
   sans `curl`/sans réseau → doit afficher `WARN:` et sortir `0` (non-bloquant
   préservé, ligne `exit 0` déjà en place).

**Acceptance** : dans une session neuve, si `railway` n'est pas installé, le
hook affiche `WARN: railway install failed` et `which railway` reste vide.
Si installé, le hook affiche `railway OK (v…)`.

---

### QW2-infra — Provisionner `sentry-cli` + `railway` dans l'image dev

**Owner** : subagent infra
**Taille** : S (Dockerfile devcontainer ou script de bootstrap)
**Dépendance** : aucune

**Spec** :
- Option A (préférée) : ajouter à `scripts/setup-cli-tools.sh` (existe déjà,
  `scripts/setup-cli-tools.sh:1`) un bloc **sentry-cli** (binaire statique
  depuis `https://sentry.io/get-cli/`) + faire appeler `setup-cli-tools.sh`
  par le hook `session-start.sh` en fallback idempotent.
- Option B : pré-baker les binaires dans l'image devcontainer si Dockerfile
  spécifique CC-on-web existe. À confirmer avec infra — pas de `.devcontainer/`
  détecté dans le repo à date.

**Acceptance** : après un SessionStart neuf, `railway --version` ET
`sentry-cli --version` répondent. Hook rapporte les deux `OK`.

---

### QW3-infra — Activer le MCP Sentry (secret peuplé)

**Owner** : subagent infra (+ coordination avec détenteur du Sentry token)
**Taille** : S (config env, pas de code)
**Dépendance** : aucune

**Spec** :
1. Vérifier que `SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT` sont
   disponibles dans l'environnement CC-on-web (session-env ou variables
   Claude Code settings). Aujourd'hui `.claude/settings.json` les référence
   via `${VAR}` mais le MCP ne peut pas s'activer sans leur peuplement.
2. Tester `mcp-servers/sentry/server.py` en lançant le MCP manuellement une
   fois les secrets posés, vérifier qu'il remonte la liste des issues
   ouvertes sur le projet `facteur-production`.
3. Documenter la procédure de renouvellement du token dans
   `docs/infra/mcp-sentry-setup.md` (nouveau fichier, ≤30 lignes).

**Acceptance** : dans une session CC-on-web, l'agent perf-watch peut appeler
le MCP Sentry et récupérer les 20 derniers événements sans erreur d'auth.

---

### QW4-infra — Allowlist WebFetch `facteur-production.up.railway.app`

**Owner** : subagent infra
**Taille** : XS (1 ligne de config)
**Dépendance** : aucune

**Spec** :
- Ajouter `facteur-production.up.railway.app` à la liste `allowedDomains`
  de la config WebFetch (harness CC-on-web, pas `.claude/settings.json` du
  projet — le scope harness n'est pas dans ce repo). Si le réglage est
  côté utilisateur : le documenter dans
  `docs/infra/cc-web-setup.md` pour que Laurin l'active manuellement.
- Test : `WebFetch(https://facteur-production.up.railway.app/api/health/pool)`
  doit rendre un JSON `{checked_out, overflow, checked_in, status, usage_pct}`.

**Acceptance** : l'agent perf-watch peut scraper `/api/health/pool` sans
intervention humaine pendant la session nocturne.

---

## Ordre de bataille suggéré

1. QW1 (corrige un bug actif qui maquille tous les diagnostics futurs) — en
   premier, 30 min.
2. QW4 (débloque le seul canal Sentry-indépendant pour le pool) — en parallèle
   de QW1 si la config harness est rapide.
3. QW3 (canal Sentry principal) — après QW2 si sentry-cli est un fallback, ou
   indépendamment si le MCP suffit.
4. QW2 (filet CLI) — moins urgent si QW3 fonctionne, mais utile pour les
   commandes Railway custom qui n'ont pas d'équivalent MCP.

Budget total : **≤ ½ journée infra** pour restaurer la visibilité complète.
