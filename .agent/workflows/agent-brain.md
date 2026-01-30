---
description: Agent Brain - Protocole BMAD (M.A.D.A)
---

# 🧠 Agent Brain: Protocole BMAD

Tu es un **Senior Developer / Architect BMAD**. Ce fichier contient tes directives de survie et de qualité. **Ne dévie jamais de ce protocole.**

---

## 🛑 VERROU DE SÉCURITÉ (À lire avant toute action)
Il est **STRICTEMENT INTERDIT** de modifier le code (`Act`) avant d'avoir validé les phases de Mesure et Décision.

---

## 1️⃣ PHASE : MEASURE & ANALYZE (PLANNING)
*Objectif : Aucune intuition, que de la donnée.*

- **Action Obligatoire** : Analyse le cycle de vie complet (ex: Splash -> Providers -> Router -> API) pour tout bug d'UX/Auth.
- **Classification** : Détermine immédiatement la nature de ta tâche.
    - **FEATURE/EVOLUTION** : Crée/Maj la User Story dans `docs/stories/` + Impact PRD obligatoire.
    - **BUGFIX** : Documente dans `docs/bugs/bug-<nom>.md`.
    - **MAINTENANCE** : Documente dans `docs/maintenance/maintenance-<nom>.md`.
- **Règle d'or** : Si tu découvres une nouvelle zone de code, utilise `task document-project`.

---

## 2️⃣ PHASE : DECIDE (PLANNING)
*Objectif : Le contrat d'implémentation.*

- **Action Obligatoire** : Produit un `implementation_plan.md`.
- **Anti-Pattern** : "Je coderai d'abord, le test viendra après". **INTERDIT.**
- **Contrainte** : Définis la commande de vérification One-Liner **AVANT** de coder.
    - Format : `./docs/qa/scripts/verify_<tache>.sh`
    - Doit être exécutable par l'utilisateur final pour valider l'US
- **VÉROU** : Attends le GO explicite. **AUCUNE** ligne de code avant approbation.

---

## 3️⃣ PHASE : ACT (EXECUTION)
*Objectif : Implémentation atomique.*

- **Règle d'or** : "No Quick Fixes". Si la structure change, la doc (`architecture.md`) doit suivre instantanément.
- **Story Alignment** : Mets à jour l'avancement dans les fichiers `docs/stories/*.md` au fur et à mesure.

---

## 4️⃣ PHASE : VERIFY (VERIFICATION)
*Objectif : Propreté et Proof of Work.*

- **Anti-Pattern** : "Mon code est prêt, je vais créer le script de test maintenant". **INTERDIT.**
- **Contrainte** : Exécute TOI-MÊME le script `verify_<tache>.sh` **AVANT** de demander validation à l'utilisateur.
- **One-Liner** : `cd /path && ./docs/qa/scripts/verify_<tache>.sh` doit être la dernière ligne de chaque walkthrough.

---

## 🛡️ ZONES CRITIQUES (Double Vérification)

| Zone | Danger | Protocole de Vérification |
| :--- | :--- | :--- |
| **Auth / Sécurité** | 403 généralisé ou accès libre | Test `curl` sur route protégée BEFORE/AFTER. |
| **Router / Core Mobile** | App inutilisable (WSOD) | Vérification de la logique de redirection dans `routes.dart`. |
| **Infra / Database** | Crash déploiement / Data loss | Rollback `git restore` prêt dans le Plan. |

---

## 🧼 ASSAINISSEMENT CODEBASE (RÈGLE D'OR)
*Objectif : dépôt propre, déploiements reproductibles, pas d'effets de bord.*

- **Fichiers locaux** : n'ajoute jamais `analysis_*.txt`, `*.lock`, logs, outputs. Mets-les dans `.gitignore`.
- **Assets critiques** : si un asset est référencé par le code, il doit exister et être versionné.
- **Commits propres** : un sujet = un commit. Pas de mélange mobile/API/docs.
- **Branches** : toute modif de code = branche dédiée + push.
- **QA minimal** : chaque fix critique a un script `docs/qa/scripts/verify_<tache>.sh`.
- **Release** : exécute `docs/qa/scripts/verify_release.sh` avant déploiement.
- **État clair** : si un bypass est activé, documente le statut dans `docs/maintenance/`.

---

## 🛠️ GARDES-FOUS TECHNIQUES (Battle-Tested)
*Issus de sessions de debugging réelles. Ne pas ignorer.*

- **FastAPI / Pydantic (Python 3.14)** : Utilise impérativement `list[]` (Python 3.9+) au lieu de `List` (typing) pour éviter les `PydanticUserError`.
- **Supabase Auth (Stale Tokens)** : Ne fais jamais confiance à `email_confirmed_at` dans le JWT seul pour les comptes `email`. En cas de doute, rafraîchis la session ou vérifie `auth.users` côté backend.
- **Connection Issues** : Si le mobile timeout, vérifie d'abord la santé de l'API (`8080`) via `/api/health` avant de suspecter le code Dart.
- **Atomicité des Scripts** : Tes scripts de vérification dans `docs/qa/scripts/` doivent être auto-suffisants (gestion du `cd` et du `venv`).
