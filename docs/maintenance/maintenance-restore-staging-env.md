# Maintenance — Remettre en place un environnement `staging` séparé de la prod

> **Type :** Maintenance (infra / release engineering)
> **Branche de travail :** `boujonlaurin-dotcom/restore-staging-env` → PR vers `main`

## Problème

`main` **était** la prod : chaque merge redéployait le backend prod (`facteur-production`)
et `build-apk.yml` publiait une release GitHub `beta-*` que **tous les utilisateurs**
voyaient via l'auto-updater (`/api/app/update` → dernière `beta-*`). D'où les « mises à
jour toutes les heures ».

## Cible

| Branche | Service Railway | `RAILWAY_ENVIRONMENT_NAME` | Flavor | applicationId | API URL | `UPDATE_CHANNEL` | Tag release | Préfixe filtré |
|---|---|---|---|---|---|---|---|---|
| `main` | `api-staging-40d3` | `staging` | `staging` | `com.example.facteur.staging` | `…api-staging-40d3…/api` | `beta` | `beta-AAAAMMJJ-HHMM` | `beta-` |
| `production` | `facteur-production` | `production` | `prod` | `com.example.facteur` | `…facteur-production…/api` | `stable` | `release-AAAAMMJJ-HHMM` | `release-` |

Les deux APK cohabitent (applicationId distincts → `versionCode` indépendants). iOS garde
`ios-beta-*`, jamais matché par les filtres Android. **PRs continuent de cibler `main`.**

## Changements code (cette PR)

- **A.** Flavors Android `prod`/`staging` (`build.gradle.kts`) + `android:label="${appLabel}"` (`AndroidManifest.xml`).
- **B.** `AppUpdateConstants.updateChannel` (`UPDATE_CHANNEL`, défaut `stable`) + propagé aux 2 call-sites (`?channel=…`).
- **C.** Backend `app_update.py` : `_PREFIXES = {"stable":"release-","beta":"beta-"}`, cache **clé par préfixe**, `channel` threadé dans les 3 endpoints. Défaut `stable` ⇒ rétro-compat (vieilles apps prod sans `channel` voient `release-* > beta-*` lexicographiquement). Tests pytest ajoutés.
- **D.** Workflows : `build-apk.yml`→flavor staging/canal beta ; `deploy-staging.yml`→`[main]` ; `promote-to-production.yml`→`[production]` ; `build-docker.yml`→`[main, production]`.
- **E.** Nouveau `weekly-release.yml` (`workflow_dispatch`) : avance `production` en `--ff-only`, build APK flavor prod/canal stable/tag `release-*`, smoke prod best-effort.
- **F.** `CLAUDE.md` (branches/env + règle migrations expand-contract + note flavor) ; `pre-bash-no-staging.sh` (messages reformulés, **logique inchangée**).

## Étapes infra manuelles (dashboards — HORS code, à faire par le PO)

1. ✅ `git branch production main && git push -u origin production` (fait dans cette tâche ; `production` = code prod actuel `ab6430d2`).
2. Railway `facteur-production` : branche de déploiement `main` → **`production`**.
3. Railway `api-staging-40d3` : branche `staging` → **`main`** ; confirmer `RAILWAY_ENVIRONMENT_NAME=staging` et `DATABASE_URL` = **DB Supabase prod**.
4. (Fait dans le code) URLs hardcodées : staging dans `build-apk.yml`, prod dans `weekly-release.yml` → plus de dépendance à `vars.API_BASE_URL`.
5. Secrets keystore (`KEYSTORE_BASE64`, …) : inchangés, réutilisés par `weekly-release.yml`.
6. (Optionnel) Branch protection sur `production` : interdire les push humains directs.
7. (Hygiène) `git remote set-head origin main` en local (le pointeur `origin/HEAD` traîne encore sur `staging`).

## Ordre de déploiement (séquence sûre — fermer la fenêtre de risque)

> ⚠️ Tant que le backend qui sert la prod tourne l'**ancien** code (filtre `beta-`), si `main`
> publie des `beta-*` flavor staging, un user prod pourrait se voir proposer un APK `.staging`
> (applicationId différent). L'ordre ci-dessous l'évite.

1. **Infra d'abord, code inchangé** : étapes 2→3. À ce stade `main` et `production` ont le **même** code → comportement identique à aujourd'hui.
2. **Merger cette PR dans `main`** : `main` redéploie le backend staging et publie le 1er `beta-*` flavor staging (consommé par l'app staging uniquement).
3. **Cliquer immédiatement « Weekly Production Release »** une fois : `production` rattrape `main` → backend prod passe au nouveau code (défaut `stable` → filtre `release-`, **ignore** les `beta-*`) → publie la 1ère `release-*` flavor prod. Les anciens users prod voient `release-* > beta-*` → 1 prompt → update in-place. ✅

Régime permanent : merges → main (staging) en continu ; 1 clic/semaine → `production` (prod).

## Compromis & risques

- **DB partagée ↔ migrations** : `main` (staging) et `production` (prod) partagent **une** DB → migrations **additives / expand-contract** obligatoires (cf. `CLAUDE.md`). `DROP`/rename/`NOT NULL`-sur-peuplé étalés sur 2 cycles hebdo.
- **GITHUB_TOKEN ne re-déclenche pas de workflow** : le `git push origin production` du bouton ne déclenche **pas** `promote-to-production.yml` → `weekly-release.yml` build l'APK prod lui-même + son propre smoke. Railway, lui, redéploie via son webhook propre sur la branche.
- **Follow-ups (hors scope)** : `build-ipa.yml`/`build-web.yml` tournent encore sur `main` avec l'URL prod en fallback → après le flip, `main` = staging → artefact incohérent. À basculer sur `production`/hebdo ou accepter « Android-only » pour l'instant. Nettoyer aussi la branche parasite `fix/mute-logic-debug` dans `build-web.yml`.
- **Gotcha flavor** : une fois `productFlavors` définis, **tout** `flutter build apk`/`flutter run` Android exige `--flavor`. Le smoke Kotlin local devient `flutter build apk --debug --flavor staging`.
