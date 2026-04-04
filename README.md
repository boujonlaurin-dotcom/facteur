# Facteur ✉️

Facteur est une application mobile (Flutter) et une API (FastAPI) permettant de gérer et de consommer des flux de contenus personnalisés.

## 🚀 Démarrage Rapide

Pour configurer votre environnement de développement et commencer à contribuer, veuillez consulter le guide détaillé :

👉 **[Guide de Contribution (Onboarding)](CONTRIBUTING.md)**

## 🖥 Setup IDE (Cursor / VS Code)

Les launch configurations sont versionnées dans `.vscode/launch.json` et se synchronisent automatiquement via Git — aucune reconfiguration manuelle sur un nouveau Mac.

### Configs disponibles

| Nom | Cible | API |
|-----|-------|-----|
| Chrome — Production | Web (Chrome) | Railway prod |
| Chrome — Local API | Web (Chrome) | `localhost:8080` |
| iOS Simulator — Production | Simulateur iPhone | Railway prod |
| iOS Simulator — Local API | Simulateur iPhone | `localhost:8080` |
| Android Emulator — Production | `emulator-5554` | Railway prod |
| Android Emulator — Local API | `emulator-5554` | `10.0.2.2:8080` |

### Nouveau projet Flutter

Pour initialiser `.vscode/launch.json` sur un projet qui n'en a pas encore :

```bash
bash scripts/init-vscode.sh
# puis remplacer les placeholders <...> dans .vscode/launch.json
```

### Synchronisation globale des configs Cursor

Pour partager les préférences Cursor (thème, keybindings) entre tous vos Macs :

```
Cmd+Shift+P → "Settings Sync: Turn On"
```

> Note : `.vscode/settings.json` et `.vscode/extensions.json` restent ignorés par Git (préférences locales). Seuls `launch.json` et `tasks.json` sont versionnés.

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

## 🛠 Tech Stack

- **Mobile** : Flutter, Riverpod, go_router, Phosphor Icons.
- **Backend** : FastAPI, Python 3.12, SQLAlchemy, Pydantic.
- **Services** : Supabase (Auth/DB), RevenueCat (Paiements).
- **Déploiement** : Railway.

---

*Propulsé par la méthode BMAD.*
