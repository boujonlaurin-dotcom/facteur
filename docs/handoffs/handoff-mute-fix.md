# Prompt de Hand-off : Fix Final Mute & UX Optimistic

## 1. Contexte & Historique
La fonctionnalité "Masquer cette source/thème" échoue systématiquement (Erreur 500) sur l'application mobile.
Malgré 3 itérations de correctifs backend, le comportement persiste à l'identique.

**Statut des Fixs Backend (théoriquement appliqués dans `packages/api`) :**
1.  **NameError (text)** : Import ajouté.
2.  **SQL Type Mismatch** : Ajout de cast explicite `::uuid[]` dans les `COALESCE` pour PostgreSQL.
3.  **ForeignKeyViolation** : Remplacement de `db.flush()` par `db.commit()` avant l'insertion pour garantir la visibilité du profil utilisateur.

## 2. Le Problème Persistant (Bloquant)
**Les correctifs ne semblent pas être actifs.**
- Les logs personnalisés ajoutés (`>>> MUTE_SOURCE CALLED V3 ...`) n'apparaissent **jamais**.
- Le serveur continue de renvoyer des erreurs qui correspondent à l'ancien code.
- **Hypothèse forte :** L'environnement d'exécution (probablement Docker) n'est pas synchronisé avec les fichiers locaux modifiés. Le `uvicorn` lancé localement sur 8080/8082 n'est pas celui tapé par l'app mobile (qui tape sur l'IP machine ou un conteneur).

## 3. Objectifs de la Session
Ta mission est de **rendre le Mute fonctionnel et fluide**.

### Étape A : Synchronisation Environnement (PRIORITÉ ABSOLUE)
- Ne touche pas au code avant d'avoir prouvé que tu le contrôles.
- Trouve comment l'app mobile communique avec l'API (Docker ? IP locale ?).
- **Rebuild le conteneur** ou redirige l'app vers ton processus local (port 8080).
- Valide que tu vois tes logs `print`.

### Étape B : Validation UX (Cahier des charges)
Une fois le backend réactif (plus de 500), améliore l'UX dans `apps/mobile` :
1.  **Action Immédiate (Optimistic)** : Au clic sur "Masquer", la carte disparaît instantanément.
2.  **Feedback** : Petit toast/snackbar "Source masquée".
3.  **Suppression du Refresh** : L'app ne doit **JAMAIS** recharger tout le feed après un mute.
    - Si l'API répond 200 : Parfait.
    - Si l'API répond erreur : On loggue l'erreur, éventuellement on reaffiche la carte (ou on ignore), mais on ne bloque pas l'utilisateur.

## 4. Fichiers Clés
- **Backend** : `packages/api/app/routers/personalization.py` (Logique corrigée mais non déployée ?)
- **Frontend** :
    - `apps/mobile/lib/features/feed/providers/feed_provider.dart` (Gestion état & appels API)
    - `apps/mobile/lib/features/feed/widgets/personalization_sheet.dart` (UI BottomSheet)

---
*Note technique pour l'agent : Commence par vérifier si un Docker tourne (`docker ps` a échoué car command not found, vérifier le path ou si c'est `podman`?). Si l'app tourne sur un émulateur/device physique, vérifie `API_BASE_URL`.*
