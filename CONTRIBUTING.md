# 📖 Guide de Contribution - Facteur

Ce guide s'adresse aux développeurs (même débutants) souhaitant contribuer au projet Facteur. Il regroupe toutes les étapes pour configurer votre environnement, installer les dépendances et lancer les différentes briques du projet.

---

## 🛠 1. Prérequis

Avant de commencer, assurez-vous d'avoir installé les outils suivants :

- **Git** : Pour la gestion de version.
- **Python 3.12** : (⚠️ Ne pas utiliser 3.13+ pour le moment). [pyenv](https://github.com/pyenv/pyenv) est recommandé pour gérer les versions.
- **Environnement Python (venv)** : L'utilisation de l'environnement virtuel est **indispensable** pour exécuter les scripts du projet et éviter les erreurs de modules manquants ou de commande `python` introuvable.
- **Flutter (dernière version stable)** : Pour l'application mobile.
- **Railway CLI** (optionnel) : Pour la gestion du déploiement.
- **Un compte Supabase** : Pour la base de données et l'authentification.

> [!TIP]
> Si la commande `python` n'est pas trouvée, essayez `python3` ou assurez-vous que votre environnement virtuel est bien activé.

---

## 🧙‍♂️ 2. Configuration Spéciale : Antigravity (IA)

### Fix "Terminal Blindness"
Si vous développez avec les agents **Antigravity**, vous devez configurer votre shell pour éviter le problème de sorties de terminal vides.
Ajoutez ce bloc **tout en haut** de votre fichier `~/.zshrc` (ou `~/.bashrc`) :

```bash
# --- Fix Antigravity Terminal Blindness ---
if [[ -n "$ANTIGRAVITY" ]] || [[ -n "$AGENTIC" ]] || [[ "$TERM" == "dumb" ]]; then
    return
fi
# --- End Fix ---
```

### Méthode BMAD (Obligatoire)
Le projet utilise la **méthode BMAD** pour structurer le développement. Pour contribuer, vous devez utiliser l'agent BMAD.

0. **Téléchargement du framework** : https://github.com/bmad-code-org/BMAD-METHOD
1. **Activation** : Chargez le workflow BMAD au début de votre session avec l'agent :
   - Utilisez la commande `/start-bmad` (ou chargez manuellement le fichier [start-bmad.md](file:///.agent/workflows/start-bmad.md)).
2. **Prompt System** : Assurez-vous que votre agent utilise les directives définies dans [.bmad-core/agents/bmad-master.md](file:///.bmad-core/agents/bmad-master.md) pour maintenir la cohérence du projet.
3. **M.A.D.A** : Suivez rigoureusement la boucle **Measure, Analyze, Decide, Act** détaillée dans le workflow.


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
