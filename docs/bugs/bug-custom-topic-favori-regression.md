# Bug : régression Explorer tabs suite au blocage des custom_topic en favori

## Contexte

PR `#636 / commit 8adc5d41` ("fix: custom_topic→favori interdit") a bloqué la
mise en favori des `custom_topic` pour éviter la régression "Plongée → tous les
sports" (résolution coarse via `slug_parent` Mistral).

Erreur produit oubliée à ce moment-là : ce path **alimentait aussi les onglets
de la section Explorer** (`get_tab_counts` filtre les `user_topic_profiles`
sur `priority_multiplier == 2.0`, qui était le marqueur de l'état favori). La
section Explorer est précisément la raison d'être des sujets précis dans le
modèle produit.

## Vision produit (rappel)

- **Thème** (large, prédéfini) → Tournée du jour, top 3 visibles.
- **Veille** (précis, désambigué, 4 axes) → futur path canonique pour le suivi fin.
- **Sujet** (mot-clé, secondaire) → alimentation onglets Explorer + alertes
  événements identifiables (ex. "Coupe du Monde", "Anthropic").

## Problème

1. Impossible d'ajouter un `custom_topic` en favori (422 `custom_topic_favorite_forbidden`).
2. Les onglets dynamiques de la section Explorer ne se créent plus.
3. La migration `23a3_custom_topic_fav_drop` a `DELETE` 62 favoris (15 users
   impactés) sans downgrade fonctionnel. Données apparemment perdues.

## Attendu

- Réautoriser `state=favorite` pour les `custom_topic` côté backend.
- Côté mobile, **renommer le concept** en "Sujets épinglés" (et non "favori")
  pour éviter la collision sémantique avec le top 3 de la Tournée du jour
  (qui reste réservé aux thèmes/veilles).
- Section dédiée "Sujets épinglés" dans "Mes intérêts", **non-draggable** dans
  le top 3.
- Restauration automatique des 62 favoris perdus (cf. découverte ci-dessous).
- Différencier visuellement thème (large) vs sujet (précis) dans "Mes intérêts".

## Recovery — découverte clé

La migration `23a3_custom_topic_fav_drop` a fait :

```sql
UPDATE user_topic_profiles SET state = 'followed' WHERE state = 'favorite';
DELETE FROM user_favorite_interests WHERE custom_topic_id IS NOT NULL;
```

Elle a **oublié de réinitialiser** `user_topic_profiles.priority_multiplier`.
Conséquence inattendue : les profils impactés sont aujourd'hui dans l'état
`state='followed' AND priority_multiplier = 2.0`, ce qui constitue une
**signature non-ambiguë** des anciens favoris.

Requête de diagnostic (exécutée 2026-05-20) :

```
state='followed', priority_multiplier=2.0  →  62 lignes, 15 users impactés
                                              (min 1, max 12, moyenne 4.13 par user)
```

Pas besoin de PITR Supabase : la recovery est déterministe via cette
heuristique.

## Pistes techniques

### Backend

- `services/user_interests_service.py` : retirer le check
  `CustomTopicFavoriteForbidden` dans `set_state` ; le conserver dans
  `reorder_favorites` (un custom_topic ne peut pas être placé dans le top 3
  reorderable).
- `schemas/user_interests.py` : exposer deux listes distinctes dans
  `UserInterestsResponse` : `top_favorites` (theme/veille, ordonné) et
  `pinned_custom_topics` (custom_topic, non-ordonné).
- Vérifier que la transition `set_state(custom_topic, favorite)` met aussi à
  jour `priority_multiplier=2.0` (et la transition inverse → `1.0`).
- Nouvelle migration Alembic (revision courte, ≤4 chars + slug) qui :
  1. `UPDATE user_topic_profiles SET state='favorite' WHERE state='followed' AND priority_multiplier=2.0`
  2. `INSERT INTO user_favorite_interests (user_id, custom_topic_id, position) SELECT ...`

### Mobile

- `my_interests/screens/my_interests_screen.dart` : nouvelle section
  "Sujets épinglés", séparée du `FavoritesReorderableSection`, micro-copy
  expliquant le lien avec Explorer.
- `my_interests/widgets/interest_state_picker_sheet.dart` : labels
  différenciés selon le `kind` cible (📌 Épinglé pour custom_topic, ⭐ Favori
  pour theme).
- Provider qui répartit les listes API entre les deux sections.

### Hors scope (PR séparées)

- Fix de la résolution `slug_parent` → keywords/canonical_name dans
  `get_tab_counts` : résout définitivement la régression "Plongée → tous les
  sports" qui avait motivé la PR initiale. **À traiter en suivant.**
- CTA "Créer une Veille à partir de ce sujet" : attente refonte veille.

## Vérification

- `pytest tests/test_user_interests_service.py -v`
- `pytest tests/test_user_interests_router.py -v`
- `flutter test` + `flutter analyze`
- Manuel : créer un custom_topic → épingler → vérifier qu'il apparaît dans
  "Sujets épinglés" ET comme onglet dans Explorer.
- Manuel : drag d'un sujet épinglé vers le top 3 → doit être impossible.
- Migration : `alembic upgrade head` sur DB locale vide → OK ; sur DB de prod
  (Railway boot) → restaure les 62 lignes attendues, idempotent.

## Référence

- Story 23.3 (à mettre à jour avec errata) :
  `docs/stories/core/23.3.read-only-custom-topics.md`
- Story 23.1 (veille comme 3ᵉ type de favori) :
  `docs/stories/core/23.1.veille-refonte-filtre-temps-reel.md`
- Migration source du bug :
  `packages/api/alembic/versions/23a3_custom_topic_fav_drop.py`
