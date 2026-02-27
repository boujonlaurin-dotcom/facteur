# Pipeline Facteur — Schéma Complet

> Copier dans un bloc Code Notion pour le rendu.

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                       PIPELINE FACTEUR — VUE COMPLÈTE                       ║
║                                                                              ║
║  Légende:  [AUTO] = aucune action       [TOI] = action manuelle requise     ║
║            [SKIP] = skippable (easy)    ──✗──► = chemin d'erreur            ║
╚══════════════════════════════════════════════════════════════════════════════╝


═══════════════════════════════════════════════════════════════════════════════
 ÉTAPE ① — DÉVELOPPEMENT                                         [AUTO]
═══════════════════════════════════════════════════════════════════════════════

  Conductor (workspace dev)           Git
  ─────────────────────────           ───
  Agent dev code sur branche    ───►  Commits sur branche feature
  Agent écrit pr-handoff.md           (.context/pr-handoff.md)

  Déclencheur : Toi, tu lances un workspace Conductor avec ta demande
  Résultat    : Code prêt + handoff écrit + agent STOP

  💡 Le handoff est auto : dis juste "prépare le handoff" à l'agent
     ou mentionne le prompt docs/workflow/prompts/handoff-review.md


═══════════════════════════════════════════════════════════════════════════════
 ÉTAPE ② — TEST LOCAL                                    [TOI] [SKIP:easy]
═══════════════════════════════════════════════════════════════════════════════

  Toi                                 Local
  ───                                 ─────
  Tu testes l'app en local      ───►  flutter run / uvicorn
  sur la même branche                 Tu vérifies le comportement

  Résultat OK  ──────────────────────────────────────────────►  Étape ③
  Résultat KO  ──✗──►  Retour workspace dev : "Fix <problème>"  ──► Étape ①

  [SKIP] Pour changements docs-only, config, ou très petit fix évident.


═══════════════════════════════════════════════════════════════════════════════
 ÉTAPE ③ — PEER REVIEW (avant PR)                               [TOI]
═══════════════════════════════════════════════════════════════════════════════

  Toi                                 Conductor (workspace review)
  ───                                 ────────────────────────────
  Ouvre un NOUVEAU workspace    ───►  Agent review lit :
  Conductor sur la MÊME branche        • .context/pr-handoff.md (contexte)
                                       • workspace diff (code)
  Colle le prompt review :             • CLAUDE.md (guardrails)
  (docs/workflow/prompts/
   peer-review.md)                   Agent produit :
                                      • DiffComments inline sur le code
                                      • Verdict : APPROVED / NOT APPROVED

  APPROVED     ──────────────────────────────────────────────►  Étape ④
  NOT APPROVED ──✗──►  Copie blockers dans workspace dev  ────► Étape ①
                       Agent dev fix ► re-test ► re-review


═══════════════════════════════════════════════════════════════════════════════
 ÉTAPE ④ — CRÉATION PR + CI                                      [TOI+AUTO]
═══════════════════════════════════════════════════════════════════════════════

  Toi / Agent dev                     GitHub Actions
  ───────────────                     ──────────────
  git push + gh pr create       ───►  CI se lance automatiquement :
                                       │
  [TOI] 1 action :                     ├─ ci-tests.yml
  demander à l'agent dev              │   ├─ lint  (ruff check + format)
  "ouvre la PR" ou le faire            │   └─ test  (pytest)
  toi-même sur GitHub UI               │
                                       ├─ build-docker.yml
                                       │   └─ build (Docker image)
                                       │
                                       └─ qa-bmad.yml
                                           └─ verify (BMAD scripts)

  Tous green  ───────────────────────────────────────────────►  Étape ⑤
  Échec lint  ──✗──►  Agent dev fix formatting ► re-push       (auto re-run)
  Échec test  ──✗──►  Agent dev fix tests ► re-push            (auto re-run)
  Échec build ──✗──►  Agent dev fix Dockerfile/deps ► re-push  (auto re-run)

  💡 Les fix CI sont rapides : l'agent dev peut corriger dans le même
     workspace, re-push, et CI re-run automatiquement. Pas besoin de
     refaire la review si le fix est trivial (lint, import manquant).


═══════════════════════════════════════════════════════════════════════════════
 ÉTAPE ⑤ — STAGING (automatique)                                 [AUTO]
═══════════════════════════════════════════════════════════════════════════════

  GitHub Actions                      Railway STAGING
  ──────────────                      ───────────────
  deploy-staging.yml se déclenche     Déploiement sur staging :
  automatiquement quand CI green :    facteur-staging.up.railway.app
   │
   ├─ check-gates                     Smoke tests automatiques :
   │   └─ lint=✓ test=✓ build=✓ ?     ├─ /api/health      → 200 ?
   │                                   ├─ /api/health/ready → 200 ?
   ├─ deploy                           └─ environment       → "staging" ?
   │   └─ railway up --env staging
   │
   └─ smoke-test
       └─ health + ready + env check

  Smoke OK   ────────────────────────────────────────────────►  Étape ⑥
  Smoke FAIL ──✗──►  Problème infra/config (pas de code)
                     Actions :
                     • Vérifier variables Railway staging (Dashboard)
                     • Vérifier DATABASE_URL staging
                     • Vérifier que l'env staging existe dans Railway
                     • Si migration DB manquante → agent dev ajoute + re-push
                     ❌ NE PAS créer une nouvelle branche, fix sur la même


═══════════════════════════════════════════════════════════════════════════════
 ÉTAPE ⑥ — MERGE + PRODUCTION                                   [TOI]
═══════════════════════════════════════════════════════════════════════════════

  Toi                                 GitHub → Railway PRODUCTION
  ───                                 ────────────────────────────
  Tu vois TOUS les checks verts ───►  PR mergée dans main
  sur la PR GitHub                     │
                                       └─►  Railway auto-deploy production
  [TOI] 1 action :                          facteur-production.up.railway.app
  Clic "Squash and merge"
  sur GitHub UI                       promote-to-production.yml (optionnel) :
                                       └─ smoke tests production auto

  Deploy prod OK  ──►  ✅ TERMINÉ
  Deploy prod KO  ──✗──►  Railway rollback auto (dernier deploy sain)
                          + debug via logs Railway


═══════════════════════════════════════════════════════════════════════════════
 RÉSUMÉ — TES ACTIONS À CHAQUE ÉTAPE
═══════════════════════════════════════════════════════════════════════════════

  Étape    Toi                           Durée attente    Skippable ?
  ─────    ───                           ─────────────    ───────────
  ① Dev    Lance workspace Conductor     —                Non
  ② Test   Test en local                 —                Oui (easy)
  ③ Review Ouvre workspace review        2-5 min          Non
  ④ PR+CI  Demande "ouvre la PR"         2-3 min          Non
  ⑤ Stag.  Rien (auto)                   3-4 min          Oui (docs-only)
  ⑥ Merge  Clic "Squash and merge"       1-2 min          Non

  Total actions manuelles : 3 (lance review, lance PR, clic merge)
  Total attente passive   : ~8 min (CI + staging en parallèle)


═══════════════════════════════════════════════════════════════════════════════
 FAST TRACK — EASY DEVS (docs, config, petit fix évident)
═══════════════════════════════════════════════════════════════════════════════

  ① Dev → ③ Review → ④ PR+CI → ⑥ Merge
           (skip ②)    (staging N/A dans PR template)

  Pour les changements qui ne touchent PAS le backend :
  • Docs (stories, README, CLAUDE.md)
  • Config (env, railway.json)
  • Fix typo / renommage évident

  Cocher "N/A" dans la section Staging de la PR template.
```
