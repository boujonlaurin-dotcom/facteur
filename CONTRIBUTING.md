# 📖 Guide de Contribution - Facteur

Ce guide s'adresse aux développeurs (même débutants) souhaitant contribuer au projet Facteur. Il regroupe toutes les étapes pour configurer votre environnement, installer les dépendances et lancer les différentes briques du projet.

---

## 🛠 1. Prérequis

Avant de commencer, assurez-vous d'avoir installé les outils suivants :

- **Git** : pour la gestion de version.
- **Docker Desktop** : pour la DB Postgres de test (lancée par `make bootstrap`).
- **Un compte Supabase** : pour la base de données et l'authentification.
- **CLI tools via Brewfile** (pyenv, Flutter, Railway, Supabase, Sentry, gitleaks) — une seule commande depuis la racine du repo :
  ```bash
  brew bundle
  gitleaks git --no-banner       # scan initial de sécurité (no account required)
  ```
- **Python 3.12** (⚠️ 3.13+ casse pydantic — cf [CLAUDE.md](CLAUDE.md#contraintes-techniques-locked)) :
  ```bash
  pyenv install 3.12             # pyenv a été installé par brew bundle
  pyenv global 3.12              # ou `pyenv local 3.12` depuis la racine du repo
  ```

  > [!IMPORTANT]
  > **Activer pyenv dans votre shell** — sinon `python3.12` restera introuvable même après l'install. Ajoutez une fois à `~/.zshrc` (ou `~/.bashrc`) :
  > ```bash
  > cat >> ~/.zshrc << 'EOF'
  >
  > # pyenv
  > export PYENV_ROOT="$HOME/.pyenv"
  > [[ -d "$PYENV_ROOT/bin" ]] && export PATH="$PYENV_ROOT/bin:$PATH"
  > eval "$(pyenv init - zsh)"
  > EOF
  > source ~/.zshrc
  > ```
  >
  > Vérifier :
  > ```bash
  > python3.12 --version         # doit afficher Python 3.12.x
  > ```

  > [!TIP]
  > Le venv Python sera créé automatiquement par `make bootstrap` dans `packages/api/.venv`. Pas besoin de créer un venv manuellement.

Une fois ces prérequis en place :

```bash
make bootstrap       # venv + deps API + DB test + migrations + flutter pub get
make doctor          # vérifie l'état de chaque composant (✅/❌)
```

---

## 🤖 2. Guide pour Agents AI (Claude Code, Antigravity, etc.)

### Quel Fichier Lire en Premier?

Le projet utilise une **architecture à 2 niveaux** pour guider les agents selon la complexité de la tâche:

| Type de Tâche | Fichier de Départ | Exemples |
|--------------|-------------------|----------|
| **Ajustement simple** (<10 lignes) | **[QUICK_START.md](QUICK_START.md)** | Label bouton, typo, condition if manquante |
| **Feature complète** | **[CLAUDE.md](CLAUDE.md)** | Nouvelle fonctionnalité, nouveau endpoint, refactoring |
| **Bug complexe** | **[CLAUDE.md](CLAUDE.md)** | Auth broken, routing broken, DB fail |
| **Zone à risque** (Auth/Router/DB/Infra) | **[CLAUDE.md](CLAUDE.md)** | Migrations, modifications Auth, Router |
| **Maintenance** | **[CLAUDE.md](CLAUDE.md)** | Refactoring, migration, tech debt |

**Règle d'or**: En cas de doute → Lis **[CLAUDE.md](CLAUDE.md)**.

### Méthode BMAD (Obligatoire)

Le projet utilise la **méthode BMAD** pour structurer le développement.

**Ressources**:
- Framework BMAD: [.bmad-core/](file:///.bmad-core/)
- Agents BMAD: [.bmad-core/agents/](file:///.bmad-core/agents/) (@dev, @pm, @po, @architect, @qa)
- Guide utilisateur: [.bmad-core/user-guide.md](file:///.bmad-core/user-guide.md)

**Cycle M.A.D.A** (Measure → Analyze → Decide → Act):
1. **Measure**: Analyse complète, classification (Feature/Bug/Maintenance), création Story/Bug Doc
2. **Decide**: Plan d'implémentation, validation user, **STOP** avant code
3. **Act**: Implémentation atomique, mise à jour Story/Bug Doc
4. **Verify**: Script de vérification QA, one-liner proof

**Détails complets**: Voir [CLAUDE.md](CLAUDE.md) section "Cycle M.A.D.A"

### Configuration Shell (Antigravity - Optionnel)

Si vous utilisez **Antigravity**, configurez votre shell pour éviter le problème de "terminal blindness":

```bash
# Ajoutez en haut de ~/.zshrc ou ~/.bashrc
if [[ -n "$ANTIGRAVITY" ]] || [[ -n "$AGENTIC" ]] || [[ "$TERM" == "dumb" ]]; then
    return
fi
```


---

## 🐍 3. Setup Backend (API FastAPI)

Le backend se trouve dans `packages/api`. `make bootstrap` (§1) a déjà :

- créé le venv `packages/api/.venv` en Python 3.12
- installé les deps (`pip install -e "packages/api[dev]"`)
- démarré la DB Postgres de test (Docker, port 54322)
- appliqué les migrations Alembic

**Variables d'environnement** :

```bash
cp packages/api/.env.example packages/api/.env
# puis remplir SUPABASE_*, DATABASE_URL, etc. (cf §5)
```

**Lancement de l'API** :

```bash
cd packages/api
source .venv/bin/activate
uvicorn app.main:app --reload --port 8080
```

> [!TIP]
> Dans Cursor / VS Code, les launch configs (`iOS Simulator — Local API`, `Chrome — Local API`, …) démarrent l'API automatiquement via la task `Start Backend API`. Pas besoin de terminal séparé.

---

## 📱 4. Setup Mobile (Flutter)

L'application mobile se trouve dans `apps/mobile`. `make bootstrap` a déjà fait `flutter pub get`.

**Lancement** : utilise les launch configs VS Code (cf [README.md](README.md#-setup-ide-cursor--vs-code)) — elles injectent les `--dart-define` requis. En CLI :

```bash
cd apps/mobile
flutter run -d iphone \
  --dart-define=API_BASE_URL=http://localhost:8080/api/ \
  --dart-define=SUPABASE_URL=VOTRE_URL \
  --dart-define=SUPABASE_ANON_KEY=VOTRE_CLE
```

---

## 🌍 5. Variables d'Environnement Clés

| Variable | Description |
| :--- | :--- |
| `SUPABASE_URL` | URL de votre projet Supabase. |
| `SUPABASE_ANON_KEY` | Clé publique anonyme pour l'accès client. |
| `DATABASE_URL` | Chaîne de connexion PostgreSQL (format asyncpg pour l'API). |
| `REVENUECAT_API_KEY` | Clé API pour la gestion des abonnements. |

---

## 🚀 6. Déploiement (Railway)

Le projet est configuré pour être déployé sur **Railway**.
- Le fichier `railway.json` à la racine pointe vers le Dockerfile de l'API (`packages/api/Dockerfile`).
- Chaque push sur la branche principale déclenche généralement un redéploiement automatique si configuré.

---

## 📂 7. Scripts Utiles

Certains scripts automatisés sont disponibles dans le dossier `scripts/` :
- `apk-manager.sh` : Pour la gestion des builds Android.
- `push.sh` : Script utilitaire pour faciliter les commits/pushs.

---

## 📚 8. Gestion des Sources (Curated vs Candidate)

Le fichier central pour gérer les sources est `packages/api/sources/sources_candidates.csv`.
Il pilote l'import et le statut "Curated" (visible dans le catalogue user) ou "Analyzed" (caché, pour comparaison).

### Structure du CSV
- **Name** : Nom de la source.
- **URL** : URL du site principal.
- **In_Catalog** : `TRUE` pour curated (visible), `FALSE` pour candidate (cachée).
- ...autres champs (Bias, Reliability, etc.).

### Promouvoir une Source (Candidate -> Curated)
Pour "curer" une source existante ou en ajouter une nouvelle au catalogue officiel :

1. **Éditer le CSV** : Ouvrez `packages/api/sources/sources_candidates.csv`.
2. **Modifier le statut** : Changez la colonne `In_Catalog` de `FALSE` à `TRUE` pour la source désirée.
3. **Lancer le script d'import** :
   Depuis la racine du projet :
   ```bash
   packages/api/.venv/bin/python packages/api/scripts/import_sources.py --file sources/sources_candidates.csv
   ```
   > Le script détectera que la source existe déjà et mettra à jour son statut `is_curated` en base de données.

> [!WARNING]
> **Attention aux tris Excel/Numbers !**
> Si vous triez le CSV via un tableur externe, assurez-vous de **ne pas inclure la ligne d'en-tête** dans le tri.
> Le script s'attend impérativement à ce que la première ligne du fichier soit : `Name,URL,Type,Thème,Rôle,Rationale,Statut,Bias,Reliability,In_Catalog`.
> Si cette ligne se retrouve déplacée, l'import échouera.

---

## 🤝 9. Flux de Travail (Workflow)

1. Créez une branche descriptive : `git checkout -b feature/ma-nouvelle-feature`.
2. Faites vos modifications.
3. Vérifiez que les tests passent :
   - API : `pytest` dans `packages/api`.
   - Mobile : `flutter test` dans `apps/mobile`.
4. Documentez vos changements si nécessaire.
