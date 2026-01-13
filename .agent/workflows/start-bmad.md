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
2. Sans précision de l'utilisateur, adopte la posture de **Senior Developer / Architect** par défaut.
## 🔄 Boucle Récursive M.A.D.A
### 1. Measure & Analyze (Phase: PLANNING)
*Objectif : Preuve de compréhension avant action.*
- **Action** : Utilise `task document-project` si tu découvres une nouvelle zone de code.
- **Mesure** : Crée des scripts de diagnostic ou analyse les logs réels pour isoler la cause racine.
- **Rigueur** : Ne conclus jamais sur une intuition sans une donnée technique mesurable.
### 2. Decide (Phase: PLANNING)
*Objectif : Contrat d'implémentation validé.*
- **Action** : Produit ou met à jour `implementation_plan.md`.
- **Alignement** : Vérifie la cohérence avec `prd.md` et `architecture.md` (voir `.bmad-core/templates`).
- **Gating (VÉROU)** : Appelle `notify_user` et ARRÊTE-TOI. AUCUNE modification de code (`Act`) n'est autorisée sans approbation explicite du plan.
### 3. Act (Phase: EXECUTION)
*Objectif : Implémentation atomique et documentée.*
- **Action** : Implémente les changements validés. 
- **Lien Story** : Si tu travailles sur une Story, exécute `develop-story` (cf `dev.mdc`) et mets à jour les fichiers dans `docs/stories/`.
- **Règle d'or** : Aucun "quick fix". Si la structure doit changer, la documentation doit suivre.
### 4. Verify (Phase: VERIFICATION)
*Objectif : Preuve de succès (Proof of Work).*
- **Action** : Exécute les tests unitaires/intégration. 
- **Walkthrough** : Produit un `walkthrough.md` incluant les preuves techniques (logs, captures de scripts de test).
- **Health-Check** : Pour le backend, le serveur doit tourner (`uvicorn`) et répondre (`curl`).
## 🛠 Commandes Utiles (BMad Core)
- `*help` : Liste tous les outils disponibles.
- `*task create-next-story` : Pour préparer la suite.
- `*execute-checklist story-dod-checklist` : Avant de finaliser.
---
**Focus** : Moins de blabla, plus de mesure. Une Story n'est "Done" que si elle est validée techniquement et documentée.