# 🧠 Agile Retrospective: Auth & Startup Failure (E2E)

## 📝 Rapport macro pour la suite du projet (Handoff AI)

### 1. Analyse des Défaillances (Post-Mortem)

| Incident | Cause Racine (Technique) | Cause Process (BMAD) |
| :--- | :--- | :--- |
| **Infinite Loader** | Timeouts manquants sur `Supabase.initialize` & logique Router bloquante (`if (isOnSplash) return null`). | **Measure** : Pas de check de santé automatique des ports (8080 vs 8000). **Analyze** : Manque de vision e2e sur le cycle de vie du démarrage. |
| **403 Forbidden** | Désynchronisation entre le Backend (Strict) et le Mobile (Permissif sur `isEmailConfirmed`). | **Analyze** : Le "Cerveau" a ignoré la validation croisée des claims JWT entre le pack API et l'app Mobile. |
| **Silent Bounce** | Race condition : `signOut()` déclenche un refresh global de l'Auth State qui écrase le message d'erreur spécifique. | **Decide** : Utilisation d'un "HACK" (force logout) au lieu d'une gestion par état (Router). |

---

### 2. Leçons Apprises (Axes d'amélioration)

#### A. Le "Cerveau" (Process - `.agent/workflows/start-bmad.md`)
Les agents sautent trop vite sur l'implémentation. Le protocole BMAD doit forcer une **Phase de Mesure d'Environnement** (Checklist de ports, connectivité API, validité des tokens réels) avant de modifier une seule ligne.

#### B. Le "Corps" (Codebase - `.bmad-core/agents/architect.md`)
L'architecture actuelle gère l'Auth de manière réactive et fragmentée.
- **Solution** : Centraliser le statut d'Auth. Le message "403 Forbidden" doit être une branche d'état légitime de l'application, pas une erreur bloquante traitée par un logout sauvage.

#### C. Les "Tests" (Vérification)
Le manque de tests E2E automatisés sur simulateur (ex: `patrol` ou `integration_test`) rend la validation dépendante de l'utilisateur.
- **Solution** : Un script de "Doctor Check" doit précéder chaque commit pour valider la chaîne complète (Mobile -> Port -> API Path -> DB Health).

---

### 3. Recommandations de Stack

1. **Environment Guard** : Implémenter un script `bin/doctor` (Python/Bash) qui vérifie les variables d'env, les ports occupés et la réponse `/api/health` avant de lancer Flutter.
2. **State Flow Mapping** : Interdire les side-effects bloquants (timeouts obligatoires sur tout `await` au démarrage).
3. **Zod/Pydantic Sync** : Utiliser un générateur de types (ex: `swagger-typescript-api` ou équivalent Dart) pour garantir que le Mobile et le Backend partagent le même contrat de validation (fini les 403 surprises).
