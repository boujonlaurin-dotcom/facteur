## fix(api): upsert atomique sur user_interests (race condition Sentry PYTHON-4P)

### Problème
`update_content_status` (SEEN au scroll + CONSUMED au retour WebView) déclenchait une
re-pondération des intérêts via un **check-then-insert non atomique** (SELECT `UserInterest` ;
si absent → `add()`). Deux requêtes concurrentes pour le même `(user_id, interest_slug)`
voyaient toutes deux « absent » et inséraient → `IntegrityError / UniqueViolation` sur
`user_interests_user_slug_uniq` → **500**, lecture non retenue (progression + perso intérêts).
Sentry **PYTHON-4P** : 260 occurrences / 24h, 11 personnes.

### Fix
Remplacement de tous les points d'insertion `UserInterest` par un **upsert Postgres atomique**
(`INSERT ... ON CONFLICT (user_id, interest_slug) DO UPDATE`), pattern déjà utilisé dans le repo
(`UserContentStatus`, `grille_seed`). La sémantique métier est préservée :

- **`content_service._adjust_interest_weight`** (culprit) : poids `= least(weight + boost, 3.0)` ;
  `state` non touché sur conflit (préserve FAVORITE).
- **`content_service._adjust_subtopic_weights`** (branche intérêt) : `delta > 0` → upsert borné
  `[0.1, 3.0]` ; `delta < 0` → UPDATE ciblé (pas d'INSERT, jamais de création au dislike).
- **`user_interests_service.set_state`** : création implicite de thème → upsert (set `state`).
- **`user_service`** (onboarding) : état FAVORITE précalculé avant insertion, upsert par thème.

Aucun DDL / migration (la contrainte unique existe déjà). Hors périmètre : le jumeau
`UserSubtopic` (table `user_subtopics`). Attention, ce n'est **pas** le même bug shape :
la contrainte unique `(user_id, topic_slug)` y a été **supprimée** (migration `4d497ce7bcc2`),
donc son check-then-insert ne lève pas d'`UniqueViolation` — sous concurrence il insère
des lignes dupliquées en silence (poids faussé). Le corriger proprement exigerait d'abord
de re-créer la contrainte unique via migration → hors scope de ce hotfix de crash.

### Tests
`tests/test_interest_weight_concurrency.py` : création → incrément (1 seule ligne), cap 3.0,
préservation FAVORITE. Le chemin `ON CONFLICT DO UPDATE` est exactement celui qu'emprunte la
requête perdante d'une course ; exercé ici par double-appel séquentiel (la fixture `db_session`
mono-connexion ne permet pas une vraie concurrence 2-connexions).

Tests exécutés en local contre `facteur_test` (Postgres 5432) : les 3 tests de régression
passent, ainsi que la suite complète (1895 passed ; les 2 seuls échecs —
`test_notification_preferences` et `test_sources_recent_items` — sont pré-existants sur
`main`, sans rapport avec ce diff, vérifié en revertant les services). Tests adaptés au
nouveau chemin upsert : `test_onboarding_sources` (l'intérêt passe par `execute` et non plus
`db.add` ; offset des appers `execute` recalculé), `test_like_feature` (1 seul `add` + 1
upsert intérêt). `ruff check` + `ruff format` OK sur les fichiers touchés.

### Post-merge (PO)
Vérifier que le compteur Sentry **PYTHON-4P** retombe à ~0 après déploiement.
