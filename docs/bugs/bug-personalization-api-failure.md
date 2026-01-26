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

## Correctif cible

- Appliquer la migration FK en prod (ou verifier son etat).
- En complement, garantir l'existence du `user_profile` avant insertion (ex: `get_or_create_profile`).
- Ajouter un log cote client pour afficher le status code et le `response.data` lors du catch.

## Verification

- Requete authentifiee `POST /api/users/personalization/mute-source` retourne 200.
- Plus d'erreur UI lors du clic "Moins de ...".
- (Optionnel) Verifier la contrainte :
  `SELECT conname, confrelid::regclass FROM pg_constraint WHERE conrelid='user_personalization'::regclass;`
