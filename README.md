# Facteur ✉️

Facteur est une application mobile (Flutter) et une API (FastAPI) permettant de gérer et de consommer des flux de contenus personnalisés.

## 🚀 Démarrage Rapide

Pour configurer votre environnement de développement et commencer à contribuer, veuillez consulter le guide détaillé :

👉 **[Guide de Contribution (Onboarding)](CONTRIBUTING.md)**

## 📁 Structure du Projet

- `apps/mobile/` : Application mobile Flutter.
- `packages/api/` : Backend FastAPI (Python).
- `docs/` : Documentation du projet (PRD, Architecture, Stories).
- `scripts/` : Scripts utilitaires pour le build et le déploiement.

## 📊 Data Architecture

Documentation complète de l'architecture data pour les ingénieurs data/backend :

- [Vue d'ensemble](docs/data-architecture/README.md) — Stack data, fichiers clés
- [Database Schema](docs/data-architecture/database-schema.md) — 20+ tables, diagrammes ER par domaine
- [Data Pipeline](docs/data-architecture/data-pipeline.md) — Ingestion RSS → Classification ML → Digest
- [Recommendation Engine](docs/data-architecture/recommendation-engine.md) — Scoring, apprentissage, taxonomie
- [Scheduled Jobs](docs/data-architecture/scheduled-jobs.md) — Jobs background et workers
- [Backoffice & Monitoring](docs/data-architecture/backoffice-agent.md) — Dashboard Streamlit, agent IA analyste, alertes

## 🛠 Tech Stack

- **Mobile** : Flutter, Riverpod, go_router, Phosphor Icons.
- **Backend** : FastAPI, Python 3.12, SQLAlchemy, Pydantic.
- **Services** : Supabase (Auth/DB), RevenueCat (Paiements).
- **Déploiement** : Railway.

---

*Propulsé par la méthode BMAD.*
