# Plan QA pré-release Facteur

## 1. Métadonnées

- Date de passe : 2026-06-16
- Front testé : build web local `apps/mobile/build/web` servi sur `http://localhost:8099/`, bundle pointant `https://api-staging-40d3.up.railway.app/api`
- Backend candidat : `api-staging-40d3`
- Viewport : 390 x 844 via `./node_modules/.bin/playwright-cli`
- Comptes :
  - `test.facteur@proton.me` : compte rempli
  - `laurin.facteur@proton.me` : attendu vierge, mais login invalide pendant cette passe
- Preuve principale : `.context/qa/2026-06-16-full-pass/`

## 2. Préconditions

- PR #851 : vérifiée côté bundle local, appels API vers staging et favicons via `images/proxy`.
- PR #852 : non mergée au moment de la passe (`gh pr view 852` = `OPEN`, `mergedAt=null`).
- Précheck Grille authentifié : `GET /api/grille/today` retourne `HTTP 500 {"error_type":"ProgrammingError"}`.

## 3. Périmètre priorisé

| Niveau | Parcours | Résumé |
|---|---|---|
| Critique | C1 Onboarding vierge | Login compte vierge, objectifs, sous-sujet custom, calibration, sources, finalisation |
| Critique | C2 Essentiel & fit | Feed du jour, cartes, mode Minimaliste, snap |
| Critique | C3 Reader | Article, couverture médiatique, Analyse Facteur, modes, deep reco |
| Critique | C4 Fiche source & ajout | Profil source, évaluation, couverture thèmes, ajout/mute |
| Important | Smokes | Flâner, Tournée, Veille, Grille, Progression |

## 4. Résultats Critiques

| Parcours | Statut | Preuves | Notes |
|---|---|---|---|
| C1 Onboarding vierge | BLOCKED | `c1-after-login.png`, `c1-login-retry.png`, `requests-c1-login-retry.txt` | `laurin.facteur@proton.me` + `09091997` retourne `Email ou mot de passe incorrect` deux fois. Onboarding non atteignable. |
| C2 Essentiel & fit | PASS partiel | `c2-feed-top.png`, `c2-display-options.png`, `c2-after-close-attempt.png` | Feed du 16 juin, 5 articles, mode Minimaliste disponible et appliqué, pas d'effondrement à 1 carte. Haptique non vérifiable sur web. |
| C3 Reader | PASS partiel | `c3-reader-top.png`, `requests-c3-reader-top.txt`, `c3-analyze-direct.txt` | Article ouvert, `/contents/{id}` 200, `/perspectives` 200, favicons proxy 200. `perspectives/analyze` répond 200 mais `analysis:null`. Scroll reader difficile à piloter via CLI, deep reco non confirmé visuellement. |
| C4 Fiche source | PASS partiel | `c4-source-profile-collapsed.png`, `c4-source-profile-expanded.png`, `requests-c4-source-profile.txt` | Header source, profil, couverture thèmes, 3 derniers articles, évaluation repliée puis dépliée avec jauges OK. Ajout source et mute ArticleSheet non exécutés. |

## 5. Smokes Importants

| Smoke | Statut | Preuves | Notes |
|---|---|---|---|
| Flâner | WARNING | `smoke-flaner.png` | Liste récente et filtres chargés. Libellés attendus "Tes sources discrètes" / "Actu chaude par sujet" non visibles dans le premier viewport. |
| Tournée | PASS API | `smoke-api-precheck.txt` | `/api/digest/both` 200 avec digest du 2026-06-16. |
| Veille | PASS attendu | `smoke-api-precheck.txt` | `/api/veille/config` 404 `Aucune veille active`, conforme empty-state attendu. |
| Grille | FAIL bloquant | `grille-direct-precheck.txt`, `smoke-api-precheck.txt` | `/api/grille/today` 500 `ProgrammingError`; #852 non mergée/déployée. |
| Progression | PASS API | `smoke-api-precheck.txt` | `/api/letters` 200, lettres 03 active et 04 upcoming visibles. |

## 6. Observations Transverses

- Aucune requête vers `facteur-production` observée dans `requests-final.txt`.
- Console : erreurs dominantes liées à `/api/grille/today` CORS/`ERR_FAILED`, cause serveur confirmée par appel direct 500.
- `/api/veille/config` 404 est attendu pour empty-state.
- Un proxy image favicon a retourné 404 pour `www.sismique.world`; non bloquant observé sur Flâner, à tracer en warning.
- Météo Open-Meteo a eu des `ERR_ABORTED` pendant navigation; non bloquant.

## 7. Verdict GO / NO-GO

**NO-GO pré-release au 2026-06-16.**

Raisons bloquantes :

1. PR #852 non mergée/non déployée : Grille reste en `HTTP 500 ProgrammingError`.
2. C1 impossible à exécuter : le compte vierge fourni ne s'authentifie pas.

Raisons non bloquantes mais à suivre :

- C3 et C4 restent partiels : Analyse Facteur répond 200 mais sans synthèse, deep reco non confirmé visuellement, ajout/mute source non exécutés.
- Flâner ne montre pas dans le premier viewport les sections attendues par le plan.

Recommandation : merger/déployer #852, corriger ou recréer le compte vierge C1, puis rejouer C1, Grille, et les sous-cas C3/C4 restés partiels avant GO.
