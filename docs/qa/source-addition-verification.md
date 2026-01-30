# Vérification : fix ajout de sources (prod + visibilité par user)

## 1. Plan de test E2E (front)

**Objectif** : valider le flux d’ajout de source personnalisée et l’isolation par utilisateur côté app.

### Prérequis

- App mobile (Flutter) pointant sur l’API cible (prod ou locale).
- Au moins **2 comptes** utilisateur (pour l’isolation).

### Étapes

| # | Action | Résultat attendu |
|---|--------|------------------|
| 1 | Se connecter avec le **compte A**. Aller dans **Paramètres → Mes sources** (ou **Sources**). | Liste des sources (curées + custom du compte A). |
| 2 | Ouvrir **Ajouter une source**. Saisir une URL valide (ex. `https://vert.eco/feed` ou une newsletter Substack). Appuyer sur **Détecter**. | Aperçu de la source (titre, type) sans erreur. |
| 3 | Confirmer l’ajout (**Ajouter**). | Message de succès ; retour à la liste ; la nouvelle source apparaît dans **Mes sources personnalisées**. |
| 4 | Vérifier le feed : ouvrir l’onglet **Feed**. | Les articles de la source ajoutée peuvent apparaître (après sync, 1–2 min si applicable). |
| 5 | **Isolation** : se déconnecter, se connecter avec le **compte B**. Aller dans **Paramètres → Mes sources**. | La source ajoutée par le compte A **n’apparaît pas** dans la liste du compte B. |
| 6 | Compte B : ajouter une **autre** source (URL différente). | Succès ; seule la source du compte B apparaît dans sa liste custom. |
| 7 | Compte A : rouvrir **Mes sources**. | Seules les sources du compte A (dont celle ajoutée à l’étape 3) sont visibles. |

### Critères de succès

- Aucune erreur « Impossible de trouver une source » pour des URLs valides (vert.eco, Substack, etc.).
- Aucun crash à l’ajout (pas de 500 côté API).
- Chaque utilisateur ne voit que **ses** sources personnalisées ; pas de mélange entre comptes.

---

## 2. Backend : one-liner (n’importe quel terminal)

**Sans JWT** (vérifier que la route protégée renvoie 401, pas 500) :

```bash
curl -s -w '%{http_code}' -o /dev/null -X POST -H 'Content-Type: application/json' -d '{"url":"https://vert.eco/feed"}' https://facteur-production.up.railway.app/api/sources/custom
```

- **Attendu** : `401` (ou `403`). Si `500` → problème backend (ex. logger manquant avant le fix).

---

**Avec JWT** (test complet : ajout + réponse 200) :

```bash
TOKEN="<coller_ton_jwt_ici>"; curl -s -w "\n%{http_code}" -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{"url":"https://vert.eco/feed"}' https://facteur-production.up.railway.app/api/sources/custom
```

- **Attendu** : une ligne JSON (ex. `{"id":"...","name":"Vert.eco",...}`) puis une ligne `200`. Si `500` ou erreur dans le JSON → bug backend.

Pour obtenir un JWT : se connecter dans l’app, puis récupérer le token (ex. logs « ApiClient: Attaching token », ou Supabase Auth / DevTools selon ta config).

---

**API en local** : remplacer l’URL par `http://localhost:8080/api` (ou l’URL de ton backend local).
