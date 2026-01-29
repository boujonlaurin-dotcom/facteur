# Bug: Echec API personnalisation (mute source/theme)

## Status: InProgress

## Date: 26/01/2026

## Symptome

- L'UI affiche "Impossible de masquer la source/le theme/le sujet" a chaque clic.
- Les appels `POST /api/users/personalization/*` echouent cote client.

## Cause probable

- **FK incoherente en prod** : la table `user_personalization.user_id` reference encore
  `user_profiles.id` (migration initiale), alors que le backend envoie `user_profiles.user_id`.
  Si la migration de correction n'est pas appliquee, cela provoque un **foreign key violation**
  pour tous les utilisateurs.
- Variante possible : le profil utilisateur n'existe pas encore, donc la FK (meme corrigee)
  echoue quand `user_profiles.user_id` n'est pas cree.

## Indices / preuves

- Migration initiale `f7e8a9b0c1d2` reference `user_profiles.id`.
- Migration de fix `1a2b3c4d5e6f` corrige la FK vers `user_profiles.user_id`.
- Le backend utilise `current_user_id` (Supabase `sub`) comme valeur pour `user_personalization.user_id`.

## Correctif applique (26/01/2026)

### Cote client (Flutter)
- ✅ Ajout de logs detailles dans `PersonalizationRepository` pour capturer:
  - Status code HTTP
  - Path de la requete
  - Body envoye
  - Response du serveur
  - Type d'erreur Dio

### Cote backend (FastAPI)
- ✅ Ajout de `get_or_create_profile()` avant chaque insertion dans `user_personalization`
  - Garantit l'existence du profil utilisateur (requis pour la FK)
  - Applique dans `mute_source`, `mute_theme`, `mute_topic`
- ✅ Correction de `updated_at` : utilisation de `func.now()` au lieu de la chaine `'now()'`

### Script de verification
- ✅ Creation de `docs/qa/scripts/verify_personalization_mute.sh`
  - Teste GET /api/users/personalization
  - Teste POST mute-source, mute-theme
  - Verifie les reponses HTTP

## Verification

- [ ] Requete authentifiee `POST /api/users/personalization/mute-source` retourne 200.
- [ ] Plus d'erreur UI lors du clic "Moins de ...".
- [ ] (Optionnel) Verifier la contrainte FK en prod :
  `SELECT conname, confrelid::regclass FROM pg_constraint WHERE conrelid='user_personalization'::regclass;`
- [ ] Executer `./docs/qa/scripts/verify_personalization_mute.sh <TOKEN>`

## Fichiers modifies

- `apps/mobile/lib/features/feed/repositories/personalization_repository.dart`
- `packages/api/app/routers/personalization.py`
- `docs/qa/scripts/verify_personalization_mute.sh` (nouveau)
