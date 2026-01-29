# Bug: Échec API personnalisation (mute source/theme) - Guide de Debug

## Status: EN COURS - Fix déployé mais problème persiste

## Date: 26/01/2026

## Contexte

La feature de personnalisation (mute source/theme) échoue systématiquement en production après déploiement du fix. L'utilisateur voit le message "Impossible de masquer ce contenu" dans l'UI.

## Fix déployé (26/01/2026)

### Modifications appliquées
1. **`apps/mobile/lib/features/feed/repositories/personalization_repository.dart`**
   - ✅ Ajout de logs détaillés (status code, path, body, response)
   - ✅ Gestion explicite des `DioException` avec rethrow

2. **`packages/api/app/routers/personalization.py`**
   - ✅ Ajout de `get_or_create_profile()` avant chaque insertion
   - ✅ Correction de `updated_at` : `func.now()` au lieu de `'now()'`
   - ✅ Import de `UserService` et `func` de SQLAlchemy

3. **`packages/api/app/services/source_service.py`**
   - ✅ Fix bug `feed_data` non défini pour YouTube detection

### Commit déployé
- `090ca50` : fix(personalization): corrige les échecs API mute source/theme
- `277ee7e` : Merge fix/personalization-clean (inclut fix source_service)

## Problème persistant

**Symptôme** : Après déploiement en prod, l'erreur UI "Impossible de masquer ce contenu" persiste.

**Hypothèses à vérifier** :

### 1. Migration FK non appliquée en prod
La migration `1a2b3c4d5e6f` (fix FK `user_personalization`) pourrait ne pas être appliquée en prod.

**Vérification** :
```sql
-- Se connecter à la DB prod (Supabase)
SELECT conname, confrelid::regclass 
FROM pg_constraint 
WHERE conrelid='user_personalization'::regclass;
```

**Attendu** : La FK doit pointer vers `user_profiles(user_id)`, pas `user_profiles(id)`.

**Si FK incorrecte** :
```bash
# Appliquer la migration en prod
railway run -- alembic upgrade head
```

### 2. Logs client non visibles
Les nouveaux logs côté client (`❌ PersonalizationRepository.muteSource failed:`) ne sont peut-être pas visibles dans la console.

**Action** :
- Vérifier les logs Flutter (console ou `adb logcat` pour Android)
- Chercher les messages commençant par `❌ PersonalizationRepository`
- Noter le **status code exact** (422, 500, 401, etc.)

### 3. Erreur de validation UUID
Le backend attend un `UUID` pour `source_id`, mais l'app envoie peut-être un string non-UUID.

**Vérification** :
- Vérifier le format de `source.id` dans le modèle `Source` (Flutter)
- Vérifier que `source_id` envoyé est bien un UUID valide

### 4. Problème d'authentification
Le token JWT pourrait être invalide ou expiré.

**Vérification** :
- Vérifier les logs backend pour erreurs 401/403
- Vérifier que `get_current_user_id` fonctionne correctement

## Plan de debug étape par étape

### Étape 1 : Capturer l'erreur exacte
**Objectif** : Obtenir le code d'erreur HTTP exact et le message d'erreur.

**Actions** :
1. Lancer l'app en mode debug
2. Activer les logs Flutter (si pas déjà fait)
3. Cliquer sur "Masquer la source" dans l'UI
4. **Copier les logs complets** de la console, notamment :
   - `❌ PersonalizationRepository.muteSource failed:`
   - `Status: XXX`
   - `Response: {...}`
   - `API Error: {...}`

### Étape 2 : Vérifier l'état de la DB en prod
**Objectif** : Confirmer que la FK est correcte et que les migrations sont à jour.

**Actions** :
1. Se connecter à Supabase (DB prod)
2. Exécuter la requête SQL ci-dessus pour vérifier la FK
3. Vérifier la version Alembic :
   ```sql
   SELECT version_num FROM alembic_version;
   ```
4. Comparer avec le head attendu : `1a2b3c4d5e6f`

### Étape 3 : Tester directement l'endpoint
**Objectif** : Isoler le problème (client vs backend).

**Actions** :
1. Obtenir un token JWT valide depuis l'app (logs `ApiClient: Attaching token`)
2. Tester avec curl :
   ```bash
   curl -X POST https://facteur-production.up.railway.app/api/users/personalization/mute-theme \
     -H "Authorization: Bearer <TOKEN>" \
     -H "Content-Type: application/json" \
     -d '{"theme": "tech"}' \
     -v
   ```
3. Noter le status code et le body de la réponse

### Étape 4 : Vérifier les logs backend Railway
**Objectif** : Voir les erreurs côté serveur.

**Actions** :
1. Accéder aux logs Railway
2. Filtrer sur `/api/users/personalization`
3. Chercher les erreurs :
   - Foreign key violations
   - Validation errors (422)
   - Auth errors (401/403)
   - Server errors (500)

### Étape 5 : Vérifier que le fix est bien déployé
**Objectif** : Confirmer que le code déployé contient bien `get_or_create_profile()`.

**Actions** :
1. Vérifier le code déployé sur Railway (ou via git)
2. Confirmer que `personalization.py` contient :
   ```python
   user_service = UserService(db)
   await user_service.get_or_create_profile(current_user_id)
   await db.flush()
   ```

## Fichiers à examiner

- `apps/mobile/lib/features/feed/repositories/personalization_repository.dart`
- `packages/api/app/routers/personalization.py`
- `packages/api/app/services/user_service.py` (méthode `get_or_create_profile`)
- `packages/api/app/models/user_personalization.py` (modèle)
- `packages/api/alembic/versions/1a2b3c4d5e6f_fix_user_personalization_fk.py` (migration FK)

## Commandes utiles

```bash
# Vérifier l'état des migrations
cd packages/api
alembic current
alembic history

# Tester l'endpoint localement (avec venv activé)
curl -X POST http://localhost:8080/api/users/personalization/mute-theme \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"theme": "tech"}'

# Voir les logs Railway (si accès)
railway logs
```

## Notes importantes

- ⚠️ **Ne pas modifier `constants.dart`** pour pointer vers local en prod
- ⚠️ **Vérifier les logs client AVANT de modifier le code backend**
- ⚠️ **Le problème pourrait être la migration FK non appliquée, pas le code**

## Prochaines actions recommandées

1. **PRIORITÉ 1** : Capturer les logs client avec le code d'erreur exact
2. **PRIORITÉ 2** : Vérifier l'état de la FK en prod (migration appliquée ?)
3. **PRIORITÉ 3** : Tester l'endpoint directement avec curl + token valide
4. **PRIORITÉ 4** : Vérifier les logs Railway pour erreurs backend

---

## Historique des tentatives

- **26/01/2026** : Fix déployé (logs client + création profil auto)
- **26/01/2026** : Test en prod → Erreur persiste
- **26/01/2026** : Migration FK suspectée mais non vérifiée
