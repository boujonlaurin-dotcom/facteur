# Vérification : fix ajout de sources (prod + visibilité par user)

## 0. Ordre de validation recommandé

1. **Backend** : lancer les tests pytest (sans config Flutter) → valide que le code ne 500 plus.
2. **Via l’App** : l’API en local + l’app pointant dessus → refaire le flux E2E (étapes 2 et 3) → valide en conditions réelles avant de merger/déployer.
3. **Après déploiement** : l’app en prod (ou pointant sur prod) → même flux pour confirmer en prod.

---

## 0b. Validation via l’App (minimal — avant de valider le fix)

Pour valider le fix **dans l’App** sans déployer en prod :

| Étape | Action |
|-------|--------|
| 1 | Branche `fix/source-addition-prod-and-per-user` à jour. |
| 2 | **Terminal 1** — lancer l’API en local : `cd packages/api && source venv/bin/activate && uvicorn app.main:app --reload --port 8080` (avec `DATABASE_URL` dispo, ex. `.env`). |
| 3 | **Pointer l’app vers l’API locale** : dans `apps/mobile/lib/config/constants.dart`, dans `baseUrl`, décommenter **une** ligne selon le device : `return 'http://10.0.2.2:8080/api/';` (Android Emulator) ou `return 'http://localhost:8080/api/';` (iOS / Web / Mac). Commenter ou laisser le `return` prod en dessous. Sauvegarder. |
| 4 | Lancer l’app (même device/émulateur que l’URL choisie). Se connecter. |
| 5 | **Paramètres → Mes sources → Ajouter une source** : saisir `https://vert.eco/feed` (ou Le Plongeoir), **Détecter**, puis **Ajouter**. |
| 6 | **Succès** = message de succès, pas de DioException 500 → fix validé via l’App. Tu peux commit/push et déployer. |

Ensuite, remettre `baseUrl` sur la prod (ou garder le dart-define en prod) selon ton flux habituel.

---

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

---

## 3. Backend : tests pytest (sans config Flutter)

Pour valider le correctif **sans lancer l’App** (une seule commande) :

```bash
cd packages/api && python -m pytest tests/test_source_addition_fix.py -v
```

- **Attendu** : tous les tests passent (logger présent, add_custom_source sans 500, idempotence).
- Si la DB n’est pas dispo : `cd packages/api && python -m pytest tests/test_source_addition_fix.py -v -k "has_logger"` pour vérifier uniquement que le fix logger est présent.
