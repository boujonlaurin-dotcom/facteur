# Handoff: Debug personnalisation + Isolation branches Git

## Contexte pour le prochain agent

**Date** : 26/01/2026  
**Priorité** : HAUTE  
**Statut** : En attente de résolution

## 🚨 Problèmes identifiés

### 1. Feature personnalisation toujours cassée
- **Symptôme** : L'erreur UI "Impossible de masquer ce contenu" persiste après déploiement du fix
- **Fix déployé** : Logs client + création automatique profil utilisateur
- **Action requise** : Debug approfondi pour identifier la cause racine

### 2. Contamination de branches Git
- **Symptôme** : Feature "AJOUT DE SOURCES VIA FLUX RSS" s'est retrouvée en prod lors du merge
- **Cause** : Branches non correctement isolées avant merge
- **Action requise** : Suivre strictement le protocole d'isolation des branches

## 📚 Documents de référence OBLIGATOIRES

**Lire AVANT toute action** :

1. **Guide de debug** : `docs/bugs/bug-personalization-api-failure-debug.md`
   - Contient toutes les hypothèses à vérifier
   - Plan de debug étape par étape
   - Commandes utiles

2. **Protocole branches** : `docs/maintenance/maintenance-git-branch-isolation.md`
   - Protocole strict d'isolation des branches
   - Checklist avant chaque commit/merge
   - Workflow correct avec exemples

## 🎯 Objectifs pour le prochain agent

### Objectif 1 : Débugger la feature personnalisation

**Actions prioritaires** (dans l'ordre) :

1. **Capturer l'erreur exacte**
   - Obtenir les logs client Flutter avec le code d'erreur HTTP
   - Chercher `❌ PersonalizationRepository.muteSource failed:`
   - Noter le status code (422, 500, 401, etc.) et le message d'erreur

2. **Vérifier l'état de la DB prod**
   - Se connecter à Supabase (DB prod)
   - Vérifier que la FK `user_personalization.user_id` pointe vers `user_profiles(user_id)`
   - Vérifier que la migration `1a2b3c4d5e6f` est appliquée

3. **Tester l'endpoint directement**
   - Obtenir un token JWT valide depuis l'app
   - Tester avec curl pour isoler le problème (client vs backend)
   - Vérifier les logs Railway pour erreurs backend

4. **Vérifier que le fix est déployé**
   - Confirmer que `personalization.py` contient `get_or_create_profile()`
   - Vérifier que les logs client sont bien dans le code déployé

**Ressources** :
- Guide complet : `docs/bugs/bug-personalization-api-failure-debug.md`
- Fichiers à examiner listés dans le guide

### Objectif 2 : Éviter les mélanges de branches

**RÈGLE ABSOLUE** : Suivre le protocole dans `docs/maintenance/maintenance-git-branch-isolation.md`

**Checklist obligatoire AVANT chaque commit** :
- [ ] `git status` montre uniquement les fichiers liés à l'objectif
- [ ] `git diff` vérifié pour chaque fichier
- [ ] Fichiers non liés stasher ou dans une autre branche

**Checklist obligatoire AVANT chaque merge** :
- [ ] `git diff main...branch --name-only` montre uniquement les fichiers attendus
- [ ] `git log main..branch` montre uniquement les commits liés
- [ ] Test du merge dans une branche de test (recommandé)

**Workflow correct** :
1. Partir de `main` propre et à jour
2. Créer une branche dédiée avec un objectif unique
3. Modifier UNIQUEMENT les fichiers liés à cet objectif
4. Vérifier avant commit : `git status` et `git diff`
5. Vérifier avant merge : `git diff main...branch --name-only`
6. Merger avec `--no-ff` et message descriptif
7. Vérifier après merge : `git log --oneline -3` et `git diff HEAD~1 --name-only`

## 🛠️ Stack technique

- **Mobile** : Flutter (Riverpod, Dio)
- **Backend** : FastAPI (Python 3.12+)
- **Database** : Supabase PostgreSQL
- **Auth** : Supabase Auth (JWT)
- **Deployment** : Railway

## 📝 Historique des actions

- **26/01/2026** : Fix déployé (logs client + création profil auto)
- **26/01/2026** : Test en prod → Erreur persiste
- **26/01/2026** : Contamination de branches identifiée
- **26/01/2026** : Documents de référence créés

## ⚠️ Avertissements importants

1. **NE PAS modifier `constants.dart`** pour pointer vers local en prod
2. **NE PAS merger** sans vérifier `git diff main...branch --name-only`
3. **NE PAS commit** de fichiers non liés à l'objectif de la branche
4. **TOUJOURS vérifier** les logs client AVANT de modifier le code backend

## 🎓 Ressources supplémentaires

- Architecture : `docs/architecture.md`
- PRD : `docs/prd.md`
- Protocole BMAD : `.agent/workflows/agent-brain.md`
- Cursor rules : `.cursorrules`

## ✅ Critères de succès

### Pour le debug personnalisation
- [ ] Code d'erreur HTTP identifié et documenté
- [ ] Cause racine trouvée (FK, validation, auth, etc.)
- [ ] Fix appliqué et testé en prod
- [ ] Feature fonctionne sans erreur UI

### Pour l'isolation des branches
- [ ] Protocole suivi pour tous les futurs développements
- [ ] Aucune contamination de branches lors des merges
- [ ] Chaque branche a un objectif unique et clair
- [ ] Vérifications effectuées avant chaque commit/merge

## 📞 Support

En cas de doute :
1. Relire les documents de référence
2. Vérifier l'historique Git avec `git log --all --graph --oneline`
3. Consulter les commits précédents pour voir les patterns corrects

---

**Bon courage ! 🚀**
