# Hand-off Prompt : Stabilisation Backend & Expansion des Sources

## 🎯 Objectif Critique
Reprendre le projet après une phase de restauration d'urgence. Le focus absolu est la **stabilité du backend** et la **scalabilité du code**.

## 📍 État Actuel (Janvier 2026)
- **Architecture** : Le backend est désormais stabilisé sur le **port 8080** (standardisé pour l'App Web/Mobile).
- **Stabilité** : Correction d'une saturation de ports/connexions DB via une optimisation de `import_sources.py` (utilisation d'un `httpx.AsyncClient` singleton).
- **Documentation** : Consulter `docs/architecture.md` (v1.3) et `docs/etat-avancement-mvp.md` pour le détail technique.

## 🛠 Tâches Prioritaires pour le Prochain Agent

### 1. Investigation Import Sources (Story 7.6)
Certaines sources du fichier `sources/sources_candidates.csv` semblent toujours échouer ou s'importer imparfaitement.
- **Analyse** : Analyser les logs d'échec de `scripts/import_sources.py`.
- **Action** : Corriger les edge cases (encodage, redirections DNS de flux RSS) sans compromettre la stabilité du pool de connexion.

### 2. Revue de la logique `is_curated`
Il y a une confusion potentielle entre les sources "Candidates" (Analyzed) et "Curated".
- **Critère** : Les sources avec `is_curated=False` doivent rester invisibles dans le catalogue utilisateur mais être utilisables pour le moteur de perspectives (Epic 7).
- **Vérification** : S'assurer que le Feed (`/api/feed`) ne se retrouve pas inondé par les 114 sources "candidates" si l'utilisateur n'y a pas souscrit.

### 3. Monitoring & Scalabilité
- Vérifier que les `lifespan` workers ne causent pas de fuites de mémoire ou de "hang" au démarrage (problème rencontré précédemment).
- Assurer que `app/main.py` garde `redirect_slashes=True` pour la compatibilité avec le client Flutter Web (Dio).

## ⚠️ Notes Techniques (Antigravity Context)
- **Terminal CLI** : Si `run_command` est silencieux ou instable, passer par la création de scripts `.sh` et demander une exécution manuelle à l'utilisateur via `notify_user`.

---
**Documents de référence :**
- [Architecture](file:///Users/laurinboujon/Desktop/Projects/Work Projects/Facteur/docs/architecture.md)
- [État MVP](file:///Users/laurinboujon/Desktop/Projects/Work Projects/Facteur/docs/etat-avancement-mvp.md)
- [Story 7.6](file:///Users/laurinboujon/Desktop/Projects/Work Projects/Facteur/docs/stories/7.6.source-expansion.story.md)
