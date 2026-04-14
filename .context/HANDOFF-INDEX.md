# 📋 Smart Source Search — Index des agents

Fichiers d'aiguillage pour les 3 agents qui vont développer la feature "Smart Source Search".

## 📖 Documents de référence (lecture obligatoire pour les agents)

| Doc | Contenu |
|---|---|
| `docs/stories/core/12.1.smart-source-search.story.md` | Vue d'ensemble, user story, AC |
| `docs/stories/core/12.1.smart-source-search.tech.md` | Spec technique complète : pipeline + endpoints + coûts |
| `docs/stories/core/12.1.smart-source-search.ui.md` | Design UI : wireframes, composants, interactions |
| `docs/stories/core/12.1.smart-source-search.prs.md` | Découpage 3 PRs + plan tests |
| `docs/stories/core/12.1.smart-source-search.handoffs.md` | Version longue des prompts (détails additionnels) |

## 🤖 Prompts des 3 agents (copy-paste ready)

| Agent | Fichier | Quand lancer | Prérequis |
|---|---|---|---|
| **Agent A** | `.context/agent-a.prompt.md` | Maintenant | `BRAVE_API_KEY` provisionnée sur Railway |
| **Agent B** | `.context/agent-b.prompt.md` | Après PR1 mergée + staging déployé | Endpoints smart-search fonctionnels |
| **Agent C** | `.context/agent-c.prompt.md` | Après PR2 mergée + staging déployé | Endpoints /by-theme, /themes-followed fonctionnels |

## 🚀 Workflow d'exécution

```
1. Provisionner BRAVE_API_KEY sur Railway (staging + prod)
2. Lancer Agent A → attendre PR #XX
   ├─ Review + merger PR
   ├─ Exécuter migration SQL Supabase SQL Editor
   └─ Déployer staging
3. Lancer Agent B → attendre PR #YY
   ├─ Review + valider /validate-feature
   └─ Merger PR + déployer
4. Lancer Agent C → attendre PR #ZZ
   ├─ Review + valider /validate-feature
   └─ Merger PR
5. Suivi post-merge (cf. prs.md section "Suivi post-merge")
```

## 📝 Comment utiliser

### Pour chaque agent

1. Copie le contenu du fichier `.context/agent-X.prompt.md`
2. Colle-le dans une nouvelle session Claude Code (slash `/` puis lancer l'agent)
3. L'agent exécute en autonomie, lit les docs de référence
4. L'agent s'arrête et notifie quand la PR est prête

### Points d'arrêt utilisateur (validation)

- **Après Agent A** : curl/Postman sur 5 requêtes variées pour confirmer le JSON
- **Après Agent B** : `/validate-feature` pour QA Chrome (scénarios 1-5)
- **Après Agent C** : `/validate-feature` pour QA Chrome complète (scénarios 6-12)

## 🔗 Références rapides

- **CLAUDE.md** : règles du projet (branche main, Python 3.12, Alembic, hooks, etc.)
- **Navigation Matrix** : `docs/agent-brain/navigation-matrix.md`
- **Safety Guardrails** : `docs/agent-brain/safety-guardrails.md`
