## Remettre en place un environnement `staging` séparé de la prod

Sépare l'environnement **continu** (que je teste) des **releases hebdo propres** pour les
vrais users, **sans** changer le workflow quotidien (PRs vers `main`, Conductor, `/go`).

| Branche | Backend Railway | Flavor | applicationId | Canal | Tag |
|---|---|---|---|---|---|
| `main` | `api-staging-40d3` (staging) | `staging` | `com.example.facteur.staging` | `beta` | `beta-*` |
| `production` | `facteur-production` (prod) | `prod` | `com.example.facteur` | `stable` | `release-*` |

Les deux APK cohabitent sur un device (applicationId distincts). PRs continuent de cibler `main`.

### Changements (code)
- **Flavors Android** `prod`/`staging` + `android:label="${appLabel}"` (Facteur / Facteur STG).
- **Mobile** : `AppUpdateConstants.updateChannel` (`UPDATE_CHANNEL`, défaut `stable`) propagé aux 2 call-sites (`?channel=…`).
- **Backend** `app_update.py` : filtre par canal (`stable→release-`, `beta→beta-`), cache **clé par préfixe**, `channel` dans les 3 endpoints. **Rétro-compat** : apps prod sans `channel` → `stable` → `release-*`, vu « plus récent » que `beta-*` (lexicographique) → migration propre. +tests pytest.
- **Workflows** : `build-apk`→staging/beta ; `deploy-staging`→`[main]` ; `promote-to-production`→`[production]` ; `build-docker`→`[main, production]`. **Nouveau** `weekly-release.yml` (bouton `workflow_dispatch` : `--ff-only` `production`←`main`, build prod, tag `release-*`, smoke prod).
- **Docs/hook** : `CLAUDE.md` (branches/env, règle migrations expand-contract, note flavor) ; `pre-bash-no-staging.sh` (messages, logique inchangée). Doc `docs/maintenance/maintenance-restore-staging-env.md`.

### Vérifié localement
- `pytest tests/routers/test_app_update.py` → **5 passed** (3 canaux + cache par préfixe + redirect existant).
- `flutter analyze` (fichiers touchés) → aucun nouvel issue.
- `flutter build apk --debug` **staging** + **prod** → OK ; merged manifests : `com.example.facteur.staging`/"Facteur STG" et `com.example.facteur`/"Facteur".
- 5 workflows YAML valides.

### ⚠️ Après merge — séquence sûre (PO, dashboards)
La branche `production` est **déjà créée** (= `main`, `ab6430d2`). Restent les dashboards :
1. **Avant de merger** : Railway `facteur-production` deploy branch `main`→`production` ; `api-staging-40d3` `staging`→`main` (confirmer `RAILWAY_ENVIRONMENT_NAME=staging` + `DATABASE_URL`=DB prod).
2. **Merger cette PR** → `main` redéploie staging + 1er `beta-*` staging.
3. **Cliquer immédiatement « Weekly Production Release »** → `production` rattrape `main`, backend prod passe au filtre `release-` (ignore les `beta-*`), publie la 1ère `release-*` → anciens users prod : 1 prompt → update in-place.

Détails + follow-ups (iOS/Web encore sur `main` avec URL prod, branche parasite `fix/mute-logic-debug`) : voir `docs/maintenance/maintenance-restore-staging-env.md`.
