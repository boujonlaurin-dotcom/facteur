# Bug — Nouveaux utilisateurs bloqués sur "Essentiel loading..." après onboarding

- **Statut** : IMPLEMENTED (tests backend verts, mobile test runtime indisponible dans le sandbox)
- **Branche** : `claude/fix-onboarding-loading-0iUm9`
- **Date** : 2026-04-16
- **Zone à risque** : Backend digest pipeline + onboarding — moyen

---

## 1. Symptôme

Un utilisateur qui termine l'onboarding **en dehors de la fenêtre batch (6h00 Paris)** arrive sur l'écran "Essentiel" et voit un spinner de chargement **qui ne se termine jamais**. Il faut typiquement attendre le batch du lendemain matin pour que le digest apparaisse.

## 2. Root cause

Trois défauts cumulés dans le pipeline de génération du digest pour les nouveaux users :

### 2.1 Aucun trigger de génération après onboarding

- `POST /api/users/onboarding` (`packages/api/app/services/user_service.py:106-340`) sauvegarde profil, préférences, intérêts, subtopics et `UserSource`, puis retourne immédiatement.
- **Aucun digest n'est généré** ni planifié.
- Le batch quotidien (`app/jobs/digest_generation_job.py:378-380`) snapshot `SELECT user_id FROM UserProfile ORDER BY user_id` au démarrage à 6h. Un user qui finit l'onboarding à 14h n'est pas dans le snapshot et ne sera servi qu'au prochain batch.

### 2.2 Génération on-demand fragile pour un compte vide

Quand le mobile appelle `GET /api/digest/both`, le code tombe dans `DigestService.get_or_create_digest()` :

- Pas de `DailyDigest` existant (nouveau user) → `DigestSelector.select_for_user()` s'exécute.
- L'utilisateur n'a aucun historique de lecture → la sélection principale renvoie `[]`.
- **Emergency fallback** (`digest_service.py:603-657`) cherche les contenus récents des `UserSource`. Si les sources n'ont pas d'articles indexés dans les 168h, retourne aussi `[]`.
- Pas de digest de la veille à servir (nouveau user, jour 1) → `return None` à la ligne 690.

### 2.3 La réponse d'erreur bloque la boucle de retry mobile

- Côté serveur, `None` remonte au router qui transforme ça en `HTTPException 503` (`routers/digest.py:268-276`).
- Côté mobile (`digest_provider.dart:103-166`), la boucle retry :
  - **202** → retry avec backoff 5s / 10s / 15s (total 30s) — OK
  - **503** → retry **aussi** avec le même backoff (30s total), puis erreur terminale
  - Après épuisement → `AsyncError` → l'écran reste bloqué sur le spinner sans message clair
- La génération LLM peut prendre 1-3 minutes → 30s de retry ne suffisent pas, même si un bg job tourne.

### 2.4 Résultat

Spinner indéfini pour tout utilisateur qui ne tombe pas pile dans la fenêtre batch 6h-7h30.

## 3. Pourquoi `/digest/both` renvoie souvent null

Confirmé par lecture du code : le router `/digest/both` (`routers/digest.py:292-384`) retourne
`DualDigestResponse(normal=None, serein=None, …)` dès que les deux variantes renvoient `None` (sans 503 ni 202). Le mobile reçoit un 200 avec `normal=null` et tombe probablement dans un état mal géré qui relance la requête.

## 4. Plan de correction

Objectif : **temps de chargement minimal, propre, sans hack**. Le stratégie est de **pré-générer le digest pendant l'animation de conclusion (10s)** et de **rendre les réponses API idempotentes et pollables** pour les cas où la génération prend plus de temps.

### 4.1 Pré-générer le digest à la fin de l'onboarding (cœur du fix)

**Fichiers :**
- `packages/api/app/routers/users.py:70-86` — `POST /onboarding`
- `packages/api/app/services/digest_service.py:74` — exposer `_schedule_background_regen` via un helper public dédié

**Action :**
1. Ajouter un paramètre `background_tasks: BackgroundTasks` au handler `save_onboarding`.
2. Après succès de `service.save_onboarding(...)`, appeler via `background_tasks.add_task(...)` une nouvelle fonction publique `schedule_initial_digest_generation(user_id)` qui planifie en fire-and-forget la génération des deux variantes (`is_serene=False` et `is_serene=True`) pour `today_paris()`.
3. L'usage de `BackgroundTasks` de FastAPI garantit l'exécution **après commit + réponse envoyée** → pas de race avec la transaction d'onboarding (les `UserSource` sont visibles).
4. Réutiliser `_schedule_background_regen()` en interne (rate-limit, gestion d'erreur, session dédiée, skip si batch en cours — tout existe déjà). Renommer en `schedule_digest_regen` (sans underscore) pour clarifier son statut.

**Gain :** l'animation de conclusion dure **10s minimum** (`conclusion_notifier.dart:56`). Pendant ce temps le serveur peut sélectionner les articles + générer le digest. Pour un compte sans historique mais avec des sources (cas nominal post-onboarding), l'emergency-fallback-wrap-as-topics produit un digest "topics_v1" en ~2-5s. Par le temps que le mobile appelle `/digest/both`, le digest existe → réponse immédiate.

### 4.2 Rendre `/digest` et `/digest/both` pollables quand rien n'est prêt

**Fichiers :**
- `packages/api/app/routers/digest.py:268-276` (GET `/digest`)
- `packages/api/app/routers/digest.py:380-384` (GET `/digest/both`)

**Action :**
1. Quand `get_or_create_digest()` retourne `None` :
   - **Avant** : `raise HTTPException(503)` → mobile tente 3 retries puis échoue.
   - **Après** : déclencher `schedule_digest_regen(user_id, target_date, is_serene)` et **retourner `202 {"status":"preparing"}`** comme le fait déjà la branche "batch running". Aligne le contrat mobile sur un seul code polling (202).
2. Dans `/digest/both`, si `normal is None` ou `serein is None` **sans exception**, renvoyer aussi 202 au lieu d'un 200 partiel. Le mobile ne sait pas quoi faire d'un `DualDigestResponse(normal=null, serein=null)`.

**Gain :** le contrat devient simple : "202 = encore pas prêt, repolle" ; "200 = voici ton digest" ; "503 = vraie erreur transitoire". Ça couvre le cas où la génération prend >10s (ex. LLM pipeline editorial_v1 pour les users en format editorial).

### 4.3 Mobile : backoff plus tolérant pour le premier digest

**Fichier :** `apps/mobile/lib/features/digest/providers/digest_provider.dart:103-108`

**Action :**
- Augmenter les retries 202 à `[5s, 10s, 15s, 20s, 30s]` (total ~80s) — couvre le cas LLM editorial qui peut prendre 60-90s.
- Les autres chemins (503, timeout) gardent leur logique actuelle (agressivité limitée).

**Pourquoi seulement sur 202 :** le 202 signifie "le serveur sait et travaille dessus", donc on a le droit d'attendre. On **n'augmente pas** le retry sur 503 pour ne pas masquer les vraies pannes.

### 4.4 (Optionnel, séparable) Log / observabilité

- Ajouter un compteur Sentry/structlog `digest_pre_generated_on_onboarding` (succès/échec) pour suivre la qualité du fix en prod.
- Ajouter un log `digest_first_load_after_onboarding` côté mobile au premier `200 OK` post-onboarding avec `elapsed_ms` — pour mesurer le temps réel de chargement.

## 5. Ce que ce plan **ne** fait **pas** (volontairement)

- Pas de changement du scheduler batch 6h — inutile pour ce fix.
- Pas de nouveau flag DB (`onboarding_just_completed`) — la table n'en a pas besoin, `UserProfile.onboarding_completed` + `created_at` suffisent.
- Pas de digest "éditorial synchrone" dans la transaction d'onboarding — on ne veut pas payer 2-5s de LLM dans un endpoint user-facing.
- Pas de refonte de l'emergency fallback — il fait correctement son job une fois qu'il est déclenché.

## 6. Tests

### 6.1 Tests unitaires backend

- `packages/api/tests/routers/test_users.py` : vérifier que `POST /users/onboarding` ajoute bien une tâche à `BackgroundTasks` avec le bon user_id et les deux variantes.
- `packages/api/tests/routers/test_digest.py` : vérifier que `GET /digest` et `GET /digest/both` renvoient 202 (pas 503) quand le service retourne `None`, et qu'une bg task est schedulée.

### 6.2 Tests unitaires mobile

- `apps/mobile/test/features/digest/digest_provider_test.dart` : vérifier que 5 retries 202 avec les nouveaux delays sont respectés.

### 6.3 Test E2E manuel (à valider via /validate-feature)

1. Créer un compte neuf
2. Compléter l'onboarding (choisir des sources, thèmes, etc.)
3. Observer : l'écran Essentiel doit afficher les articles en **<15s** après la fin de l'animation de conclusion
4. Vérifier logs backend : `digest_background_regen_scheduled` présent juste après `onboarding_saved`

## 7. Rollback

Changements isolés et additifs :
- Désactiver la pré-génération : retirer l'appel `background_tasks.add_task` dans `users.py`.
- Rétablir le 503 : un seul endroit dans `digest.py`.
- Mobile : les nouveaux delays peuvent rester sans impact.

## 8. Fichiers touchés (estimation)

| Fichier | Lignes modifiées | Nature |
|---|---|---|
| `packages/api/app/services/digest_service.py` | ~10 (rename + export) | Refactor |
| `packages/api/app/routers/users.py` | ~15 | Ajout BackgroundTasks |
| `packages/api/app/routers/digest.py` | ~30 (2 blocs) | 503→202 |
| `apps/mobile/lib/features/digest/providers/digest_provider.dart` | ~5 | Backoff tuning |
| Tests | ~80 | Nouveaux tests |

**Total : ~140 lignes, isolées, réversibles.**
