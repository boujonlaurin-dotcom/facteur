# Rapport de Debugging Infrastructure & Connexion (16/01/2026)

Ce document récapitule les causes racines et les solutions apportées lors de la session de debug critique sur les erreurs 500/502/403/405 rencontrées en production (Railway).

## 1. Erreur 500/502 (Base de Données)

### Symptôme
Le backend retournait une erreur 500 systématique sur `/api/feed` et `/api/health`. Les logs indiquaient une erreur `DuplicatePreparedStatementError` ou des erreurs de driver.

### Causes racines
1. **Incompatibilité Driver/PgBouncer** : `asyncpg` ne gère pas nativement la désactivation des "prepared statements", ce qui est requis par le mode "Transaction" de PgBouncer (utilisé par Supabase).
2. **Pool de connexion** : Le pooling par défaut de SQLAlchemy entrait en conflit avec celui de PgBouncer.

### Solution
- **Driver** : Passage de `asyncpg` à `psycopg` (v3).
- **Pooling** : Utilisation de `NullPool` dans SQLAlchemy pour laisser PgBouncer gérer entièrement les connexions.
- **Config** : Désactivation des prepared statements côté client.

## 2. Erreur 405 Method Not Allowed (CORS)

### Symptôme
Chrome bloquait les requêtes vers l'API avec une erreur de connexion (DioException). Les requêtes `OPTIONS` retournaient 405.

### Cause racine
**Ordre des Middlewares** : Dans FastAPI, un middleware défini avec le décorateur `@app.middleware("http")` enveloppe tout le reste. S'il ne gère pas spécifiquement la méthode `OPTIONS`, la requête atteint le routeur qui retourne 405 avant que le `CORSMiddleware` (ajouté plus tard) ne puisse l'intercepter.

### Solution
- Réorganisation de `main.py` : S'assurer que `app.add_middleware(CORSMiddleware, ...)` est appelé **après** les autres middlewares custom pour qu'il soit exécuté **en premier** (plus à l'extérieur).
- Correction de la config : `allow_credentials` doit être `False` si `allow_origins=["*"]`.

## 3. Erreurs de Redirection 307 & 403

### Symptôme
Les requêtes mobiles étaient redirigées de `https` vers `http` ou perdaient le header `Authorization`.

### Causes racines
1. **Trailing Slash** : Les routes sans slash final (ex: `/api/feed`) provoquaient une redirection 307 vers `/api/feed/` par FastAPI. Certains clients perdent les headers sensibles lors d'une redirection 307.
2. **Proxy Headers** : Le serveur ne savait pas qu'il était derrière un proxy SSL (Railway). Il générait donc des URLs de redirection en `http` (Mixed Content error).

### Solution
- **Code** : Utilisation systématique du trailing slash dans les appels `ApiClient` et routes (`feed/`).
- **Dockerfile** : Ajout de `--proxy-headers` et `--forwarded-allow-ips='*'` à la commande Uvicorn.

## 4. Latence d'authentification (Mobile)

### Symptôme
Erreurs 403 intermittentes au démarrage de l'app sur Android/Chrome.

### Cause racine
Race condition entre l'initialisation de l'`ApiClient` et la restauration de la session Supabase.

### Solution
Ajout d'un délai préventif de 100ms dans l'intercepteur de l'`ApiClient` pour laisser le temps au SDK Supabase de récupérer le token depuis le stockage local.

## 5. Erreur 405 via fetch API sur Flutter Web (17/01/2026)

### Symptôme
`DioException [connection error]` sur Flutter Web/Chrome malgré API fonctionnelle via curl et XHR. Les tests montrent que `fetch` retourne 405, mais `XHR` retourne 200 pour le même endpoint.

### Cause racine
Le paramètre `redirect_slashes` (activé par défaut dans FastAPI) cause des redirections **307** pour les endpoints définis sans trailing slash. L'API `fetch` (utilisée par Dio sur Flutter Web) gère ces redirections différemment de XHR, perdant le contexte CORS.

### Solution
Désactivation des redirections automatiques dans FastAPI :
```python
app = FastAPI(
    ...
    redirect_slashes=False,
```

## 6. Erreur 500 sur tous les endpoints DB (17/01/2026)

### Symptôme
Tous les endpoints authentifiés (`/feed/`, `/streak/`, `/catalog`) retournent 500, alors que `/api/health` retourne 200.

### Cause racine
Le paramètre `command_timeout` dans `connect_args` de SQLAlchemy n'est **pas supporté** par le driver `psycopg` (v3). Cela cause une exception lors de toute tentative de connexion à la base de données :
```
sqlalchemy.exc.ProgrammingError: invalid connection option "command_timeout"
```

### Solution
Suppression du paramètre `connect_args` dans `database.py`.

