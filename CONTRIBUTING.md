# 📖 Guide de Contribution - Facteur

Ce guide s'adresse aux développeurs (même débutants) souhaitant contribuer au projet Facteur. Il regroupe toutes les étapes pour configurer votre environnement, installer les dépendances et lancer les différentes briques du projet.

---

## 🛠 1. Prérequis

Avant de commencer, assurez-vous d'avoir installé les outils suivants :

- **Git** : Pour la gestion de version.
- **Flutter (dernière version stable)** : Pour l'application mobile.
- **Un compte Supabase** : Pour la base de données et l'authentification.
- **CLI tools** (pyenv, Railway, Supabase, Sentry, ggshield) : Installés en une commande depuis la racine du repo :
  ```bash
  brew bundle
  ggshield auth login            # authentification GitGuardian
  ggshield secret scan repo .    # scan initial de sécurité
  pyenv install 3.12             # installer Python 3.12 (⚠️ ne pas utiliser 3.13+)
  pyenv local 3.12               # définir la version locale du projet
  ```
- **Environnement Python (venv)** : L'utilisation de l'environnement virtuel est **indispensable** pour exécuter les scripts du projet et éviter les erreurs de modules manquants ou de commande `python` introuvable.

> [!TIP]
> Si la commande `python` n'est pas trouvée, essayez `python3` ou assurez-vous que votre environnement virtuel est bien activé.

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

Le backend se trouve dans `packages/api`.

1. **Environnement virtuel** :
   ```bash
   cd packages/api
   python3 -m venv venv
   source venv/bin/activate  # Mac/Linux
   # .\venv\Scripts\activate # Windows
   ```
   > [!IMPORTANT]
   > Une fois activé, votre terminal affichera `(venv)`. Vous pouvez alors utiliser simplement la commande `python`.

2. **Installation** :
   ```bash
   pip install -r requirements.txt
   ```

3. **Variables d'environnement** :
   Copiez le fichier d'exemple et remplissez-le avec vos clés Supabase :
   ```bash
   cp .env.example .env
   ```

4. **Lancement** :
   ```bash
   uvicorn app.main:app --reload
   ```

---

## 📱 4. Setup Mobile (Flutter)

L'application mobile se trouve dans `apps/mobile`.

1. **Installation des packages** :
   ```bash
   cd apps/mobile
   flutter pub get
   ```

2. **Lancement** :
   Vous devez fournir vos clés Supabase via les `--dart-define` :
   ```bash
   flutter run -d chrome \
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
   packages/api/venv/bin/python packages/api/scripts/import_sources.py --file sources/sources_candidates.csv
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
