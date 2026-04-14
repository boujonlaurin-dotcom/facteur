# Handoff — Résilience Backend : prévenir les pannes liées au schéma & aux dépendances optionnelles

> Ce handoff fait suite à l'incident de production survenu après le merge de la PR **boujonlaurin-dotcom/facteur#395** (Epic 13 backend).
> Symptôme utilisateur : **infinite loading** du feed mobile pendant 30-40 min, puis récupération spontanée (sans rollback).
> Hypothèse retenue : migration `ln01_create_learning_tables` livrée par le code Railway mais **non appliquée dans Supabase** au moment du déploiement → toutes les requêtes `/api/feed/` sont tombées en 500 sur la table `user_entity_preferences` manquante → récupération = application manuelle de la migration via le SQL Editor Supabase.
>
> Mission : **éliminer la famille de pannes "schema drift" côté backend**, et rendre le feed tolérant aux défaillances de ses dépendances secondaires.

---

## 🎯 Objectifs

1. Aucune dépendance secondaire (learning, entity preferences, personalization optionnelle) ne doit pouvoir faire tomber `/api/feed/`.
2. Le backend doit **refuser de servir** (readiness 503 + logs CRITICAL répétés) tant que le schéma DB est drifté, au lieu de "continuer en mode dégradé" silencieusement.
3. Le workflow de merge `main → Railway` doit rendre **impossible** le déploiement d'un code incluant une migration non appliquée.
4. L'app mobile doit dégrader visiblement (banner "Backend indisponible, retry") plutôt que rester en spinner infini.

---

## 🔍 Diagnostic — à lire avant de coder

### Failure path identifié (static analysis, PR #395)

**`packages/api/app/services/recommendation_service.py:140-169`**

```python
async def _batch_personalization():
    async with async_session_maker() as s:
        pz = await s.scalar(personalization_stmt)
        digest = await s.scalar(digest_stmt)
        # Epic 13: Load muted entities
        from app.models.learning import UserEntityPreference
        muted_entities_result = await s.execute(
            select(UserEntityPreference.entity_canonical).where(
                UserEntityPreference.user_id == user_id,
                UserEntityPreference.preference == "mute",
            )
        )
        muted_entities = {row[0] for row in muted_entities_result.all()}
        return pz, digest, muted_entities

(...) = await asyncio.gather(
    _batch_user_context(),
    _batch_personalization(),  # <-- raise ici = tout le feed tombe
)
```

Si `user_entity_preferences` n'existe pas (ou a un schéma incompatible), `await s.execute(...)` lève `UndefinedTable` → `asyncio.gather` propage → `get_feed` renvoie 500 → mobile reste en spinner.

**`packages/api/app/routers/feed.py:164-177`**

```python
checkpoint_data = None
if offset == 0 and not saved_only:
    try:
        learning_service = LearningService(db)
        proposals = await learning_service.get_pending_proposals(user_uuid)
        ...
    except Exception as e:
        logger.warning("learning_checkpoint_error", error=str(e))
```

Le learning checkpoint est bien protégé, **mais uniquement APRÈS** l'appel à `service.get_feed(...)` qui contient la query non protégée. Le guard est inutile pour le failure path réel.

**`packages/api/app/main.py:121-156`**

```python
if not settings.skip_startup_checks:
    from app.checks import check_migrations_up_to_date
    await check_migrations_up_to_date()   # raise RuntimeError si drift
...
except Exception as e:
    logger.critical("lifespan_startup_db_error", error=str(e), ...)
    # Capture to Sentry but do NOT sys.exit(1) — crash loops are worse
    # than degraded mode.
```

Le check de migration **raise**, mais le `except Exception` capture et le process continue. Le liveness probe `/api/health` reste à 200, Railway continue d'envoyer du trafic. Le readiness `/api/health/ready` passe à 503 mais **Railway n'utilise pas readiness pour router le trafic**. Résultat : l'app dégradée sert quand même.

**Mobile — `apps/mobile/lib/core/api/api_client.dart` + `config/constants.dart:31`**

- `receiveTimeout = 30 s`, `RetryInterceptor` 2 retries (1 s + 3 s) → après ~35 s on renvoie l'erreur au caller.
- À vérifier : est-ce que `FeedProvider` surface l'erreur en UI (banner/error state) ou garde l'écran en loading ? Si le provider ne set pas `hasError`, l'utilisateur verra un spinner jusqu'au pull-to-refresh manuel.

---

## 🛠️ Chantiers (ordre suggéré)

### Chantier A — Defensive queries dans `recommendation_service.py` (priorité 1)

**Pourquoi** : élimine le blast radius de l'incident. Même si une future migration tarde, le feed continue de servir.

**Changements** :

1. Isoler le chargement des muted entities derrière un helper tolérant :
   ```python
   async def _load_muted_entities(s: AsyncSession, user_id: UUID) -> set[str]:
       try:
           result = await s.execute(
               select(UserEntityPreference.entity_canonical).where(
                   UserEntityPreference.user_id == user_id,
                   UserEntityPreference.preference == "mute",
               )
           )
           return {row[0] for row in result.all()}
       except Exception as exc:
           logger.warning(
               "feed_muted_entities_unavailable",
               user_id=str(user_id),
               error=str(exc),
               error_type=type(exc).__name__,
           )
           return set()
   ```
2. Remplacer l'appel inline dans `_batch_personalization` par ce helper.
3. Ajouter un test `test_recommendation_service_muted_entities_degraded`: mock la session pour lever `UndefinedTable`, vérifier que `get_feed` renvoie des items (pas de raise).
4. Auditer les autres queries "optionnelles" du même module (subtopics, followed sources, custom_topics) : toute dépendance récente (< 1 mois) doit suivre le même pattern.

**Critère d'acceptation** : `pytest tests/test_recommendation_service.py::test_feed_survives_missing_learning_table` est vert.

### Chantier B — Circuit breaker sur le learning checkpoint (priorité 2)

Déjà partiellement en place (`feed.py:167` try/except). À renforcer :

1. Ajouter un compteur en mémoire (simple `_learning_checkpoint_failure_count` module-level) : après N échecs consécutifs, short-circuit pendant 5 min pour éviter de payer la latence de chaque tentative.
2. Expose une metric Sentry custom `learning_checkpoint_degraded` pour alerte.
3. Test unitaire : 3 échecs consécutifs → la 4e requête ne tente même pas l'appel.

### Chantier C — Startup : fail-hard sur schema drift en production (priorité 2)

**Pourquoi** : "continuer en mode dégradé" est pire que "ne pas démarrer" — Railway a un retry loop, un crash loop est détectable et alertable; un service qui sert du 500 silencieusement ne l'est pas.

**Changements dans `packages/api/app/main.py`** :

1. Si `check_migrations_up_to_date()` raise ET `settings.is_production` ET `FACTEUR_MIGRATION_IN_PROGRESS != "1"` → **laisser l'exception remonter**, ne pas swallow.
2. Option moins agressive (fallback) : swallow mais `health_check` (`/api/health`, liveness) renvoie 503 tant que `_MIGRATION_DRIFT_DETECTED` est True → Railway healthcheck fail → rollback automatique au précédent deploy.
3. Ajouter `/api/health/schema` qui renvoie `{head, current, drift: bool}` pour debug ops.

**Critère d'acceptation** : en environnement prod simulé avec schema drift, le container fail le healthcheck Railway.

### Chantier D — Preflight ciblé sur tables critiques (priorité 3)

Le check alembic est correct mais coarse (compare revisions). Ajouter un preflight léger qui **lit 1 row** sur chaque table critique utilisée par le hot-path feed :

```python
CRITICAL_TABLES = [
    "user_profiles",
    "user_sources",
    "contents",
    "user_content_status",
    "user_entity_preferences",  # Epic 13
    "user_learning_proposals",  # Epic 13
]

async def preflight_critical_tables() -> list[str]:
    """Retourne la liste des tables manquantes/inaccessibles."""
    missing = []
    async with engine.connect() as conn:
        for table in CRITICAL_TABLES:
            try:
                await conn.execute(text(f"SELECT 1 FROM {table} LIMIT 1"))
            except Exception as exc:
                missing.append(table)
                logger.error("preflight_table_missing", table=table, error=str(exc))
    return missing
```

À exécuter dans `lifespan` juste après le migration check. Si `missing`, log CRITICAL + tag Sentry `preflight_failed_tables`.

### Chantier E — Mobile : spinner → retry banner (priorité 2)

Fichiers à auditer/modifier :

- `apps/mobile/lib/features/feed/providers/feed_provider.dart` — vérifier que `loadFeed` set bien un `FeedState.error` quand `catch (e)`, pas juste un log.
- `apps/mobile/lib/features/feed/screens/feed_screen.dart` — si state == error && items.isEmpty → afficher `ErrorRetryBanner` plutôt que `CircularProgressIndicator`.
- Ajouter un widget `ErrorRetryBanner` réutilisable (Cf. style `dismiss_banner.dart`) avec CTA "Réessayer" qui relance `ref.read(feedProvider.notifier).refresh()`.
- Timeout : réduire `receiveTimeout` à **15 s** pour les requêtes non-lourdes (briefing peut rester à 30 s via override par requête si nécessaire).
- Tests widget : vérifier que le banner s'affiche quand `ApiClient` throw `DioException.connectionTimeout`.

### Chantier F — Deploy checklist enforcement (priorité 1)

**Le vrai root cause**. Sans enforcement, les chantiers A-E limitent les dégâts mais la classe de bug revient.

Changements :

1. **`.github/pull_request_template.md`** : ajouter une checklist obligatoire
   ```markdown
   ## 🛢️ Migrations DB
   - [ ] Cette PR ne contient **aucune** nouvelle migration Alembic, OU
   - [ ] J'ai appliqué la migration dans **Supabase SQL Editor** avant de merger
   - [ ] J'ai validé `SELECT current_revision FROM alembic_version` = HEAD attendu
   ```
2. **Hook `pre-push` ou CI** : si le diff contient `packages/api/alembic/versions/*.py` nouveau, fail le CI sauf si le commit contient `[migration-applied]` dans le message ou un label GH `migration-applied-to-supabase`.
3. **CLAUDE.md** : ajouter une section "DEPLOY PROTOCOL" qui explicite le chemin "migration → Supabase SQL Editor → merge → Railway deploy".
4. **Alertes Sentry** : règle sur les events `startup_check_migrations_mismatch` → page l'équipe.

### Chantier G — `/healthz` complet (bonus)

Endpoint `GET /api/health/full` pour les ops : DB ping + preflight tables + migration check en une seule réponse. Utile pour debug post-incident.

---

## 🧪 Tests requis

- **Backend** :
  - `test_feed_survives_missing_learning_table` (chantier A)
  - `test_feed_survives_missing_user_personalization_table`
  - `test_startup_schema_drift_blocks_liveness_in_prod` (chantier C)
  - `test_preflight_reports_missing_tables` (chantier D)
  - `test_learning_checkpoint_circuit_breaker_opens_after_n_failures` (chantier B)
- **Mobile** :
  - Widget test `feed_error_retry_banner_displays_on_timeout`
  - Widget test `feed_retry_button_triggers_refresh`

---

## 📋 Workflow attendu

1. Lire ce handoff + `.context/handoff-13.5-13.6-mobile-ui.md` (pour contexte).
2. Créer branche : `claude/backend-resilience-<random>` depuis `main` à jour.
3. Créer `docs/maintenance/maintenance-backend-resilience.md` avec plan technique (reprendre chantiers A-F ci-dessus).
4. **STOP → valider le plan avec Laurin AVANT de coder** (respect du workflow PLAN → CODE+TEST → PR du `CLAUDE.md`).
5. Implémenter chantier par chantier, commit atomiques.
6. Tests verts à chaque commit (hook `post-edit-auto-test.sh`).
7. QA handoff `.context/qa-handoff.md` pour le mobile (chantier E).
8. PR unique vers `main` intitulée `Backend resilience — prevent feed outages on schema drift`.

---

## 🛡️ Garde-fous

- **Ne pas modifier** `auth`, `router go_router`, `JWT config`, `schemas DB existants`.
- **Respect des patterns Riverpod** déjà établis (Pattern A dispose, Pattern B Future.delayed).
- **Alembic** : aucune nouvelle migration dans cette PR. Uniquement du code défensif.
- **Sentry tags** : tout nouveau `logger.warning/error` doit inclure `user_id` (str) et `error_type` pour faciliter l'agrégation.

---

## 📎 Fichiers à modifier (vue d'ensemble)

| Fichier | Chantier | Nature |
|---------|----------|--------|
| `packages/api/app/services/recommendation_service.py` | A | Wrap muted entities query |
| `packages/api/app/routers/feed.py` | B | Circuit breaker learning checkpoint |
| `packages/api/app/main.py` | C | Fail-hard liveness on drift (prod) |
| `packages/api/app/checks.py` | D | Ajouter `preflight_critical_tables` |
| `packages/api/tests/test_recommendation_service.py` | A | Test degradation path |
| `packages/api/tests/test_startup_checks.py` (NEW) | C, D | Test preflight + drift |
| `apps/mobile/lib/features/feed/providers/feed_provider.dart` | E | Error state propagation |
| `apps/mobile/lib/features/feed/screens/feed_screen.dart` | E | Error banner UI |
| `apps/mobile/lib/features/feed/widgets/error_retry_banner.dart` (NEW) | E | Widget retry |
| `apps/mobile/lib/config/constants.dart` | E | Timeout tuning |
| `.github/pull_request_template.md` | F | Checklist migrations |
| `CLAUDE.md` | F | Deploy protocol section |

---

## ✅ Checklist de démarrage

1. [ ] Lire ce handoff en entier.
2. [ ] Relire `packages/api/app/main.py`, `app/checks.py`, `app/routers/feed.py`, `app/services/recommendation_service.py` (code actuel).
3. [ ] Vérifier dans Sentry que l'incident du merge PR #395 a bien les events `feed_muted_entities_filtered` manquants et des 500 sur `/api/feed/` dans la fenêtre incident.
4. [ ] (Si disponible) vérifier logs Railway du deploy qui a introduit l'incident : présence d'un event `startup_check_migrations_mismatch` au boot.
5. [ ] Créer la branche + la story doc maintenance.
6. [ ] **STOP — plan validé avec Laurin — GO.**
7. [ ] Implémenter chantier A → B → F → C → D → E (ordre priorité).
8. [ ] Tests verts + QA handoff + PR.

---

**Objectif de fond** : qu'un futur merge introduisant une migration non appliquée **ne puisse plus** causer 30 min d'outage silencieux. Le backend doit soit refuser de servir (loud fail), soit dégrader proprement (soft fail). Le mode "500 silencieux sur endpoint critique" doit être impossible.
