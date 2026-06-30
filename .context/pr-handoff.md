# PR2 — Affinité entités (le levier)

Apprend une **affinité positive** sur les entités nommées (`contents.entities`) — jusqu'ici utilisées seulement pour le mute — en **miroir exact** de la boucle sujets de PR1, et la récompense de façon **bornée, calibrée et transparente** dans le pilier Pertinence (feed + digest). Aucune vectorisation.

## Ce que ça change (user-visible)
- Le flux récompense désormais les personnalités / sujets que tu lis souvent, avec une raison claire : « Parce que tu lis souvent {entité} ».
- Borné (cap diversité), calibrable sur la jauge PR1.

## Implémentation
- **Modèle + migration** : `UserEntityAffinity` (`user_entity_affinity`), enregistré dans `app/models/__init__.py` (sinon non créé par `Base.metadata.create_all` selon l'ordre de collecte des tests) ; migration additive idempotente `ue01_user_entity_affinity` chaînée sur `ufb01` (head courant de main après rebase, #909) → 1 seul head. `CREATE TABLE` pur + index → sûre en expand-contract sur la DB partagée staging/prod.
- **Boucle d'apprentissage** : `ContentService._adjust_entity_affinity` (miroir de `_adjust_subtopic_weights`), câblée aux 5 mêmes call sites (read/like-unlike/save/hide/note) avec le même delta. Clamp [0.1, 3.0], cap 5 entités/article, skip entités mutées.
- **Decay quotidien** : `decay_user_entity_affinity` à 06:50 Paris (avant digest), miroir du decay subtopics.
- **Scoring** : `ScoringContext.user_entity_affinity` + `PertinencePillar._score_entities` (bonus `BASE*(aff-1)` plafonné à `ENTITY_AFFINITY_MAX_BONUS`). `MAX_PERTINENCE_RAW` 130→160 pour laisser le bonus respirer dans la normalisation.
- **Raison** : `reason_builder` reconnaît la phrase entité comme top label si elle domine la pertinence. Préfixe `ENTITY_AFFINITY_REASON_PREFIX` partagé (pilier construit / reason_builder détecte) — pas de chaîne magique dupliquée.
- **Chargement contexte** : feed (`_load_entity_affinity_safe`, défensif, dans `_batch_personalization`) + digest (`DigestContext.user_entity_affinity`). Tolérant au schema drift.
- **Helper partagé** : `helpers/entities.py::iter_entity_names` (parse `Content.entities` une fois, réutilisé par la boucle d'apprentissage et le pilier). Skip des entités mutées via `_load_muted_entities_safe` (loader défensif réutilisé, tolérant au drift).

## Constantes (défauts de spec, tunables sur la jauge)
`ENTITY_AFFINITY_BASE=8.0`, `ENTITY_AFFINITY_MAX_BONUS=30.0`, `ENTITY_AFFINITY_MAX_ENTITIES=5`, `ENTITY_AFFINITY_DECAY=0.98`, `MAX_PERTINENCE_RAW=160.0`.

## Changelog
- Ajout de l'entrée PR2 (tag « Pour toi ») dans `unreleased` ; conflit de rebase avec l'entrée « Tournée » (#912) résolu en gardant les deux. JSON valide.

## Vérification
- Backend : suite complète verte (**1998 passed**, 0 échec). Migration `upgrade head` OK sur DB **vide** (1 head `ue01`, table/index/FK/contrainte conformes).
- `ruff check app/` + `ruff format --check app/` : clean (gate CI, ruff 0.15.14 épinglé).
- Mobile : `flutter test test/features/release_notes/` → 18 passed (changelog valide). `flutter analyze` : seulement des `info` pré-existants, aucun sur les fichiers touchés.
- Tests ajoutés : `_adjust_entity_affinity` (parse/cap5/skip-muté/clamp/count/négatif-no-op), `_score_entities` (bonus/cap/raison/0-si-aff≤1), reason_builder (top label entité), job decay scheduler.

## Calibration (post-merge, gate PO)
Comparer le CTR par entité et global avant/après sur la jauge PR1 (staging ≥1 sem.) ; ajuster `ENTITY_AFFINITY_BASE` sans écraser la diversité (nb sources/sujets distincts au digest).

## Hors scope (= spec)
Feed + digest uniquement. `topic_selector` hérite du dict amont ; veille passe `{}`.
