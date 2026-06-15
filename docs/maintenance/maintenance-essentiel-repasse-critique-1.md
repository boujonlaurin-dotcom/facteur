# Maintenance — Essentiel : repasse critique #1 (mutes, bulletins, trending/une)

> **Date** : 2026-05-27
> **Branche** : `boujonlaurin-dotcom/ton-essentiel-curation`
> **PR ciblée** : `main`
> **Type** : 3 bug fixes consolidés sur la carte « Ton Essentiel »
> **Audit source** : [`.context/audit-essentiel-2026-05-27.md`](../../.context/audit-essentiel-2026-05-27.md)

## Contexte

Audit bout-en-bout d'« Essentiel » sur 3 profils réels × 3 jours (25-27 mai
2026) = 9 audits. **6 constats critiques** remontés ; les 3 premiers sont
livrés dans cette PR consolidée parce qu'ils sont **interdépendants côté
qualité du pool** :

- PR 2 (filtre bulletin élargi) et PR 3 (correction trending/une) compensent
  partiellement le rétrécissement du pool causé par PR 1 (mutes appliqués).
- Livrer les 3 ensemble évite une fenêtre où Essentiel passerait par un état
  plus mince sans les compensations qualité.

## Bugs adressés

### #1 — `muted_themes` / `muted_topics` / `muted_sources` ignorés (criticité ⭐⭐⭐)

`fetch_user_essentiel_context` (`packages/api/app/services/essentiel_service.py:104`)
ne lit que `hide_non_fr_sources` depuis `user_personalization`. Les 3 listes
de mutes existent en DB mais ne sont jamais consultées par la chaîne
Essentiel.

**Preuve.** Sylvie (`f95320a6-…`) mute `tech` / `international` / `sport`
et reçoit Corée du Nord, Présidentielle 2027, Moyen-Orient dans son
Essentiel des 2026-05-25 et 26.

### #4 — Chroniques France Culture passent le filtre (criticité ⭐⭐)

`is_news_bulletin_title` (`packages/api/app/services/recommendation/filter_presets.py:487`)
laisse passer :

- « L'humeur du jour, émission du mercredi 27 mai 2026 »
- « La revue de presse internationale, émission du lundi 25 mai 2026 »

Cause : les patterns existants ancrent au début (`^l['']émission`,
`^revue de presse`) ; ici un préfixe descriptif précède le mot-clé.

### #6 — `is_une` et `is_trending` lus depuis le même champ (criticité ⭐⭐)

`_build_editorial_response` (`packages/api/app/services/digest_service.py:2343-2344`)
alimente `is_trending` ET `is_une` depuis `subject["is_a_la_une"]`. Tout
subject « à la une » reçoit `+_W_TRENDING (40) + _W_UNE (30) = +70` au lieu
du +30 attendu pour `is_une` seul. Casse la sémantique documentée
« trending = ≥3 sources couvrent le topic ».

## Changements

| Fichier | Modification |
|---|---|
| `packages/api/app/services/essentiel_service.py` | + 3 champs sur `EssentielUserContext` ; + 1 SELECT `UserPersonalization` dans `fetch_user_essentiel_context` ; + fonction `_filter_articles_by_mutes` ; appel en tête de `_pick_transversal_articles` |
| `packages/api/app/services/recommendation/filter_presets.py` | + 3 patterns dans `NEWS_BULLETIN_PATTERNS` |
| `packages/api/app/services/digest_service.py` | 1 ligne : `is_trending` ← `source_count >= 3` (et non `is_a_la_une`) |
| `packages/api/tests/test_low_priority_cap.py` | + 7 tests `TestIsNewsBulletinTitle` (cas réels + régressions) |
| `packages/api/tests/test_essentiel_endpoint.py` | + tests mutes (theme / source / topic / no-regression / fetch) + tests scoring découplé |

**Pas de migration Alembic** — aucun changement schéma. Les champs
`muted_*` existent déjà sur `user_personalization`.

## Résultat attendu

- Mutes respectés : 100 % (vs 0 % aujourd'hui)
- 0 chronique radio en lead-slot Essentiel
- `is_a_la_une=true` + `source_count=2` → +30 seul (pas +70)
- `is_a_la_une=false` + `source_count=5` → +40 seul (trending légitime)

## Risques

- **Pool plus mince pour profils très-mutants** (Sylvie : 3 thèmes
  + 2 topics + 0 sources). Bénéfice qualité > régression quantité ;
  surveiller post-merge le taux d'Essentiels < 5 articles. Le hand-off
  audit propose une « PR 5 » fallback robuste (non incluse ici) si
  nécessaire.
- **Patterns bulletin trop larges** : mitigé par listes fermées et tests
  de non-régression (« Une chronique du conflit », « La revue d'un livre »).
- **Pas de cache à invalider** : `_build_editorial_response` reconstruit
  la réponse à chaque requête depuis le JSONB stocké.

## Vérification

```bash
# Tests ciblés
cd packages/api && pytest tests/test_low_priority_cap.py::TestIsNewsBulletinTitle -v -x
cd packages/api && pytest tests/test_essentiel_endpoint.py -v -x

# Suite complète (le hook stop-verify-tests.sh la rejouera)
cd packages/api && pytest -v
```
