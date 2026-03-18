# PR — Fix batch job editorial + fallback digest J-1

## Quoi
Deux bugs lies au digest editorial decouverts en test whitelist :
1. **Batch job crash silencieux pour users editorial** — `select_for_user()` retourne un `EditorialPipelineResult` pour les users whitelistes, mais le batch job attendait une liste plate → `AttributeError` → digest jamais pre-genere.
2. **Pas de fallback J-1** — Sans digest pre-genere, `get_or_create_digest()` lance le pipeline complet synchroniquement (~20s). Ajout d'un fallback qui sert le digest de la veille instantanement.

## Pourquoi
Les users editorial whitelist subissent 20s de chargement a chaque premiere connexion du jour. Le batch de 8h ne gerait pas le format editorial, donc le probleme se reproduisait quotidiennement.

## Zones a risque
- `digest_generation_job.py` — session management (flush vs commit)
- `digest_service.py` — fallback J-1 edge cases (force_regenerate, J-1 absent)

## Ce que le reviewer doit verifier en priorite
1. **Bug 1** (`digest_generation_job.py:291-307`): Le `isinstance` check + delegation a `DigestService._create_digest_record_editorial()`. Verifier que le `flush()` interne n'interfere pas avec le `commit()` par batch (ligne 143).
2. **Bug 2** (`digest_service.py:173-183`): Le fallback J-1 est place APRES le block existing_digest (qui gere force_regenerate + corrupt digest). Verifier que `force_regenerate=True` bypass bien le fallback.
3. **Tests** (`test_digest_generation_job.py`, `test_digest_service.py`): 5 nouveaux tests couvrent les deux bugs + edge cases.

## Fichiers modifies
- `packages/api/app/jobs/digest_generation_job.py` — editorial branch dans `_generate_digest_for_user()`
- `packages/api/app/services/digest_service.py` — fallback J-1 dans `get_or_create_digest()`
- `packages/api/tests/test_digest_generation_job.py` — NEW: 2 tests batch editorial
- `packages/api/tests/test_digest_service.py` — 3 tests fallback J-1

## Decision produit
Option A retenue pour le fallback: servir J-1 sans lancer de generation background. Le batch de 8h (maintenant fonctionnel pour editorial) s'en charge.
