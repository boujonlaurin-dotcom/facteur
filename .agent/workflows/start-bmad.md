---
description: Agent BMAD
---

---
description: Protocole BMAD (M.A.D.A) - Operational Execution
---
# Protocole BMAD (Measure, Analyze, Decide, Act)
Ce fichier est l'unique directive opérationnelle pour l'exécution des tâches. Il s'appuie sur les capacités définies dans `.bmad-core/agents/bmad-master.md`.
## 🧩 Initialisation
1. Charge immédiatement `.bmad-core/core-config.yaml` pour connaître les chemins du projet.
2. Sans précision de l'utilisateur, adopte la posture de **Senior Developer / Architect BMAD** par défaut.
## 🔄 Boucle Récursive M.A.D.A à utiliser pour tes modifications :
### 1. Measure & Analyze (Phase: PLANNING)
*Objectif : Preuve de compréhension avant action.*
- **Action** : Utilise `task document-project` si tu découvres une nouvelle zone de code.
- **Mesure** : Crée des scripts de diagnostic ou analyse les logs réels pour isoler la cause racine.
- **Santé Environnement** : Vérifie systématiquement les ports (8080?), la santé API (`/health`) et la validité des tokens réels avant d'analyser le code.
- **Rigueur** : Ne conclus jamais sur une intuition sans une donnée technique mesurable.
- **Mapping Flow** : Pour les bugs d'init/auth, trace le cycle de vie complet (ex: Splash -> Providers -> Router -> API) avant de proposer un correctif.

> [!IMPORTANT]
> **Gating (PRE-VÉROU) - Classification de l'intervention :**
> Avant TOUTE création de `implementation_plan.md`, détermine la nature de la tâche :
>
> | Type | Description | Dossier | User Story ? |
> |------|-------------|---------|--------------|
> | **FEATURE (New)** | Nouvelle capacité produit | `docs/stories/` | ✅ Obligatoire |
> | **EVOLUTION** | Modifie/étend une feature existante | `docs/stories/` + lien Parent | ✅ Obligatoire (avec `Parent Story:` header) |
> | **BUGFIX** | Comportement cassé à corriger | `docs/bugs/` | ❌ Non |
> | **MAINTENANCE** | Nettoyage, optimisation technique, ajustements de données | `docs/maintenance/` | ❌ Non |
>
> **Règles de classification :**
> 1. **FEATURE** : Vérifie qu'une User Story existe dans `docs/stories/` ET qu'elle est documentée dans le PRD (`docs/prd.md`). Sinon, ARRÊTE-TOI et crée-les.
> 2. **EVOLUTION** : Le fichier DOIT contenir un header `Parent Story: [[X.Y.nom-story.md]]` pour lier à la story de base.
> 3. **BUGFIX** : Documente dans `docs/bugs/bug-<nom>.md`. Mets à jour les stories/architecture impactées.
> 4. **MAINTENANCE** : Documente dans `docs/maintenance/maintenance-<nom>.md`. Format libre, pas de format US.
>
> **Règle d'or** : Une tâche de "nettoyage", "refactoring" ou "data cleaning" ne doit JAMAIS faire l'objet d'une User Story. Les US sont réservées à la valeur produit.
### 2. Decide (Phase: PLANNING)
*Objectif : Contrat d'implémentation validé.*
- **Action** : Produit ou met à jour `implementation_plan.md`.
- **Alignement** : Vérifie la cohérence avec `prd.md` et `architecture.md` (voir `.bmad-core/templates`).
- **Gating (VÉROU)** : Appelle `notify_user` et ARRÊTE-TOI. AUCUNE modification de code (`Act`) n'est autorisée sans approbation explicite du plan.
- **Stability** : Le focus absolu est la **stabilité du backend** et la **scalabilité du code**. Pas de décision technique risquée sur la structure du back-end.

> [!CAUTION]
> **Fiabilité Terminal (Antigravity)** :
> Les outils de terminal (`run_command`) peuvent être instables ou silencieux.
> En cas de blocage sur une tâche critique (redémarrage de serveur, script long) :
> 1. Crée un script `.sh` robuste.
> 2. Demande à l'utilisateur de l'exécuter manuellement via `notify_user`.
### 3. Act (Phase: EXECUTION)
*Objectif : Implémentation atomique et documentée.*
- **Action** : Implémente les changements validés. 
- **Lien Story** : Si tu travailles sur une Story, exécute `develop-story` (cf `dev.mdc`) et mets à jour les fichiers dans `docs/stories/`.
- **Règle d'or** : Aucun "quick fix". Si la structure doit changer, la documentation doit suivre.
### 4. Verify (Phase: VERIFICATION)
*Objectif : Preuve de succès (Proof of Work) actionnable.*
- **Action** : Exécute les tests unitaires/intégration.
- **Rigueur** : Crée un script self-contained (ex: `docs/qa/scripts/verify_story_XXX.sh`) qui gère lui-même son environnement (activation venv, cd absolu).
- **Propreté** : Ne "pollue" pas la racine du projet. Stocke les scripts de preuve dans `docs/qa/scripts/` ou `packages/*/scripts/`.
- **Preuve (CRITIQUE)** : Fournis à l'utilisateur LA commande "One-Liner" universelle pour exécuter ce script depuis n'importe où. Elle DOIT gérer le `cd` et le `venv` (ex: `cd /absolute/path/to/pkg && source .venv/bin/activate && python scripts/verify.py`).
- **Walkthrough** : Produit un `walkthrough.md` incluant cette commande verbatim et le résultat attendu.
- **Health-Check** : Pour le backend, le serveur doit tourner (`uvicorn`) et répondre (`curl`).
- **Mode Échec (Chaos)** : Ne teste pas seulement le "chemin heureux". Vérifie que l'app gère élégamment une API hors-ligne (timeout) ou un utilisateur non autorisé (403/401).
## 💡 Trucs & Astuces (Senior Tips)
- **FastAPI / Pydantic** : Utilise `list[]` (Python 3.9+) au lieu de `List` (typing) pour éviter les `PydanticUserError` en Python 3.14.
- **Supabase Auth** : Ne fais jamais confiance à `email_confirmed_at` dans le JWT seul pour les comptes `email` (stale token). Vérifie `auth.users` en fallback dans le backend.
- **Connection Issues** : Si l'app mobile timeout sur `users/streak` ou le feed, vérifie d'abord si le backend (8080) est responsive via `/api/health`.

---
**Focus** : Moins de blabla, plus de mesure. Une Story n'est "Done" que si elle est validée techniquement et documentée.