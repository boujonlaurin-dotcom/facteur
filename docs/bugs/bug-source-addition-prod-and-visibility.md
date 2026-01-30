# Bug: Ajout de sources en prod + visibilité inter-utilisateurs

## Status: InProgress

## Date: 30/01/2026

## Contexte

Branche dédiée: `fix/source-addition-prod-and-per-user`.

Deux problèmes signalés sur la fonctionnalité d’ajout de sources personnalisées :

1. **L’ajout ne fonctionne plus en production** (même pour des liens précédemment validés : vert.eco, newsletters Substack, etc.).
2. **Les sources ajoutées par un utilisateur semblent apparaître pour tous les utilisateurs.**

---

## Bug 1 : Ajout de source en prod (500 / crash)

### Symptôme

- En production, l’ajout d’une source personnalisée échoue.
- Liens auparavant valides (vert.eco, Substack, etc.) ne passent plus.

### Cause identifiée (Measure)

- **`source_service.py` utilise `logger` sans l’importer.**
- Ligne 155 : `logger.info("Triggered background sync for new source", source_id=source.id)`.
- Aucun `import structlog` ni `logger = structlog.get_logger()` dans le fichier.
- Lors de l’exécution de `add_custom_source`, un **NameError** est levé → 500 côté API.

### Preuve

- Grep dans `packages/api/app/services/source_service.py` : pas d’import de `logger` ; utilisation à la ligne 155.

### Correctif appliqué (30/01/2026)

- ✅ Ajout en tête de `source_service.py` : `import structlog` et `logger = structlog.get_logger()`.

---

## Bug 2 : Sources visibles pour tous les utilisateurs

### Symptôme

- Les sources personnalisées ajoutées par un utilisateur apparaissent pour d’autres utilisateurs.

### Analyse (Measure)

- **Backend (API)**  
  - `GET /api/sources` : `get_all_sources(user_id)` filtre bien les custom par `UserSource.user_id == user_uuid` et `UserSource.is_custom == True`.  
  - `get_feed` : `followed_source_ids` est construit à partir de `UserSource` avec `user_id == user_id`.  
  - Donc le code actuel est cohérent avec une isolation par utilisateur.

- **Hypothèses possibles**  
  1. **Auth en prod** : `get_current_user_id` renvoie le même `sub` pour tout le monde (mauvaise config JWKS / JWT secret / audience).  
  2. **Pas de contrainte d’unicité** sur `(user_id, source_id)` dans `user_sources` : doublons possibles et risque de confusions / requêtes à affiner.  
  3. **Client** : cache ou appel sans token / mauvais token (peu probable si le feed est correct).

### Correctifs appliqués (30/01/2026)

1. **Auth en prod**  
   - À vérifier manuellement : s’assurer que le JWT Supabase renvoie un `sub` différent par utilisateur (test avec 2 comptes).

2. **Modèle et requêtes**  
   - ✅ Migration Alembic `n3o4p5q6r7s8` : suppression des doublons puis `UNIQUE(user_id, source_id)` sur `user_sources`.  
   - ✅ Modèle `UserSource` : `UniqueConstraint("user_id", "source_id", name="uq_user_sources_user_source")`.  
   - ✅ Dans `get_all_sources`, requête custom avec `.distinct()` pour éviter tout doublon.

3. **Idempotence à l’ajout**  
   - ✅ Dans `add_custom_source`, vérification d’un `UserSource(user_id, source_id)` existant avant création ; si présent, pas de nouvel enregistrement (retour de la source existante).

---

## Fichiers concernés

| Fichier | Rôle |
|--------|------|
| `packages/api/app/services/source_service.py` | Bug 1 : ajout `logger` ; Bug 2 : idempotence add + requête custom sans doublon |
| `packages/api/app/models/source.py` | Optionnel : contrainte unique sur `UserSource` |
| `packages/api/alembic/versions/` | Migration : unique `(user_id, source_id)` sur `user_sources` |
| `packages/api/app/dependencies.py` | Aucun changement requis ; vérification manuelle auth en prod |

---

## Vérification (après correctifs)

- **Bug 1** : En prod, ajouter une source (ex. vert.eco) → 200 et source visible dans “Mes sources personnalisées”.  
- **Bug 2** : Deux comptes distincts : chacun ajoute une source différente ; chacun ne voit que ses propres custom dans GET /api/sources et dans le feed.

---

## Références

- Flux ajout : `routers/sources.py` → `SourceService.add_custom_source` → `RSSParser.detect` → `user_sources` + `sources`.  
- Flux liste : `get_all_sources(user_id)` → curated + custom filtré par `UserSource.user_id`.  
- Flux feed : `RecommendationService.get_feed` → `followed_source_ids` depuis `UserSource` par `user_id`.
