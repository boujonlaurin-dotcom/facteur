# Facteur API

Backend FastAPI pour l'application Facteur.

## 🚀 Setup

### Prérequis

- Python 3.12 (⚠️ 3.13+ non supporté par pydantic-core)
  ```bash
  # Installation via pyenv recommandée
  brew install pyenv
  pyenv install 3.12.8
  pyenv local 3.12.8
  ```
- PostgreSQL (via Supabase)
- Un compte Supabase
- Un compte RevenueCat

### Installation

1. **Créer un environnement virtuel** :
   ```bash
   cd packages/api
   python -m venv venv
   source venv/bin/activate  # macOS/Linux
   # ou: .\venv\Scripts\activate  # Windows
   ```

2. **Installer les dépendances** :
   ```bash
   pip install -r requirements.txt
   ```

3. **Configurer les variables d'environnement** :
   ```bash
   cp .env.example .env
   # Éditer .env avec vos valeurs
   ```

4. **Lancer le serveur** :
   ```bash
   uvicorn app.main:app --reload
   ```

5. **Accéder à la documentation API** :
   - Swagger UI : http://localhost:8000/api/docs
   - ReDoc : http://localhost:8000/api/redoc

## 📁 Structure

```
app/
├── main.py              # Entry point FastAPI
├── config.py            # Configuration (pydantic-settings)
├── database.py          # SQLAlchemy async setup
├── dependencies.py      # FastAPI dependencies (auth)
├── routers/             # API routes
│   ├── auth.py
│   ├── users.py
│   ├── feed.py
│   ├── contents.py
│   ├── sources.py
│   ├── subscription.py
│   ├── streaks.py
│   └── webhooks.py
├── services/            # Business logic
│   ├── user_service.py
│   ├── feed_service.py
│   ├── content_service.py
│   ├── source_service.py
│   ├── subscription_service.py
│   ├── streak_service.py
│   └── recommendation_service.py
├── models/              # SQLAlchemy models
│   ├── user.py
│   ├── source.py
│   ├── content.py
│   └── subscription.py
├── schemas/             # Pydantic schemas
│   ├── user.py
│   ├── content.py
│   ├── source.py
│   ├── feed.py
│   ├── subscription.py
│   └── streak.py
├── workers/             # Background jobs
│   ├── scheduler.py
│   └── rss_sync.py
└── utils/               # Utilities
    ├── rss_parser.py
    ├── youtube_utils.py
    └── duration_estimator.py
```

## 🔌 API Endpoints

### Auth
- `POST /api/auth/signup` - Créer un compte (via Supabase)
- `POST /api/auth/login` - Se connecter

### Users
- `GET /api/users/profile` - Récupérer le profil
- `PUT /api/users/profile` - Mettre à jour le profil
- `POST /api/users/onboarding` - Sauvegarder l'onboarding
- `GET /api/users/stats` - Statistiques

### Feed
- `GET /api/feed` - Feed personnalisé
- `GET /api/feed/source/{id}` - Feed par source

### Contents
- `GET /api/contents/{id}` - Détail d'un contenu
- `POST /api/contents/{id}/status` - Mise à jour consommation (seen/consumed)
- `POST /api/contents/{id}/save` - Sauvegarder (archive l'item du feed)
- `DELETE /api/contents/{id}/save` - Retirer des sauvegardés
- `POST /api/contents/{id}/hide` - Masquer

## 🧠 Recommendation Engine

L'algorithme de recommandation (`RecommendationService`) génère un feed personnalisé en :
1. **Filtrage** : Exclusion des contenus vus, consommés, masqués ou déjà sauvegardés (Triage).
2. **Scoring** : Pondération basée sur les intérêts de l'utilisateur, l'affinité avec la source et la récence (decay logarithmique).
3. **Diversité** : Application d'une pénalité de "fatigue de source" (chaque article consécutif d'une même source voit son score réduit de 15%).
4. **Pagination** : Support de l'offset/limit pour le scroll infini.

### Sources
- `GET /api/sources` - Liste des sources
- `POST /api/sources` - Ajouter une source custom
- `POST /api/sources/detect` - Détecter le type d'URL

### Subscription
- `GET /api/subscription` - Statut de l'abonnement

### Streaks
- `GET /api/streaks` - Streak et progression

### Webhooks
- `POST /api/webhooks/revenuecat` - Webhook RevenueCat

## 🧪 Tests

```bash
pytest
```

## 🐳 Docker

```bash
# Build
docker build -t facteur-api .

# Run
docker run -p 8000:8000 --env-file .env facteur-api
```

## 📚 Documentation

- [PRD](/docs/prd.md)
- [Architecture](/docs/architecture.md)

