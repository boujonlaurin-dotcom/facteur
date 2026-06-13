# Maintenance — Cleanup UI legacy « PrioritySlider 3-crans » → picker 4-états

> **Date** : 2026-05-19
> **Branche** : `boujonlaurin-dotcom/cleanup-legacy-priority-sliders`
> **PR ciblée** : `main`
> **Type** : cleanup UI + dette technique

## Contexte

La Story 22.1 a introduit le système 4-états (`hidden` / `unfollowed` /
`followed` / `favorite`) et son picker canonique
`InterestStatePickerSheet`. La Story 22.2 (PR #625, mergée le 2026-05-18)
a migré les sujets perdus et levé le cap dur de 3 favoris.

Il reste **8 call-sites Flutter** qui utilisent toujours le legacy
`PrioritySlider` (slider 3-crans 0.2 / 1.0 / 2.0) et appellent les
endpoints `PUT /sources/{id}/weight` ou `PATCH /personalization/topics/{id}`
(champ `priority_multiplier`). Deux CTA mentionnent encore
« pousse leur priorité à 3/3 ».

Cette maintenance retire le slider et ses dépendances UI, reformule les
CTA, et purge les endpoints `PUT` côté API — **sans toucher au schéma DB
ni au scoring ML** (décision « Option A allégée » prise avec le PO).

## Décisions

1. **`priority_multiplier` côté backend** → **Option A allégée**
   - Drop UI + endpoints `PUT` qui l'écrivent.
   - **GARDER** la colonne `priority_multiplier` (toujours `1.0` pour les
     nouveaux rows).
   - **Ne pas toucher** au scoring ML (les anciens rows ≠ 1.0 continuent
     d'être pris en compte, sans nouvelle écriture possible).
   - **Pas de migration Alembic**.

2. **`digest_personalization_sheet.dart`** → migré vers le picker
   4-états (bouton « Pourquoi cet article » dans `digest_screen.dart`
   préservé).

3. **`topic_chip.dart`** → inclus dans le scope (2 PrioritySlider
   internes lignes 477 + 869).

## Inventaire

### Call-sites `PrioritySlider` à migrer (8)

| # | Fichier | Ligne |
|---|---------|-------|
| 1 | `apps/mobile/lib/features/sources/widgets/source_detail_modal.dart` | 200 |
| 2 | `apps/mobile/lib/features/feed/widgets/source_adjust_sheet.dart` | 239 |
| 3 | `apps/mobile/lib/features/sources/widgets/source_list_item.dart` | 179 |
| 4 | `apps/mobile/lib/features/custom_topics/screens/topic_explorer_screen.dart` | 125 |
| 5 | `apps/mobile/lib/features/custom_topics/widgets/topic_chip.dart` | 477 |
| 6 | `apps/mobile/lib/features/custom_topics/widgets/topic_chip.dart` | 869 |
| 7 | `apps/mobile/lib/features/digest/widgets/digest_personalization_sheet.dart` | 435 |

### CTA à reformuler (2)

- `source_filter_sheet.dart:257` — drop *« Pousse leur priorité à 3/3 »*
- `interest_filter_sheet.dart:315` — idem
- Les sous-titres `{N}/3 — ajoute-en encore X` (cap retiré Story 22.2)
  deviennent *« {N} favori(s) — top 3 affiché dans la Tournée du jour »*.

### Backend — endpoints + schémas

- `packages/api/app/routers/sources.py:584-610` (`PUT /sources/{id}/weight`)
  → **drop endpoint** + `SourceService.update_source_weight()`.
- `packages/api/app/schemas/source.py:27, 98-103` (`UpdateSourceWeightRequest`)
  → **drop schéma**.
- `packages/api/app/routers/custom_topics.py:443-479`
  (`PATCH /personalization/topics/{id}`) → retrait du champ
  `priority_multiplier` du `UpdateTopicRequest` (endpoint **conservé**).
- `packages/api/app/services/source_service.py` →
  `_load_user_source_multipliers()` et `SourceResponse.priority_multiplier`
  **conservés** (lecture nécessaire au scoring).
- `packages/api/app/routers/feed.py:574` (détection legacy favori via
  `priority_multiplier == 2.0`) → **conservé** (fallback pour rows
  non-migrés).

### Code mort à supprimer (mobile)

- `apps/mobile/lib/widgets/design/priority_slider.dart` (fichier).
- `customTopicsProvider.updatePriority(topicId, newPriority)`.
- `userSourcesProvider.updateWeight(sourceId, multiplier)`.
- Méthode `sources_repository` pointant vers `PUT /sources/{id}/weight`.
- Champ `priority_multiplier` du payload `PATCH topics` dans
  `topic_repository.dart`.

### Tests

- `packages/api/tests/test_custom_topics.py::test_update_priority_multiplier`
  → **retirer**.
- `packages/api/tests/test_custom_topics.py::test_priority_multiplier_affects_score`
  → **garder** (valide le scoring sur les rows existants).
- Tests `test_sources.py` ciblant `PUT /sources/{id}/weight` → retirer.
- Tests Flutter qui ouvraient `SourceAdjustSheet` / `TopicExplorerScreen`
  / `SourceDetailModal` et cliquaient sur le slider → réécrire pour
  ouvrir le picker.

## Ordre d'exécution

1. **Backend** (avant mobile, pour éviter qu'un build mobile patché
   ne tape un endpoint absent) : drop `PUT weight`, retrait champ
   `priority_multiplier` du PATCH topic, adapter tests, `pytest -v`.
2. **Mobile** dans l'ordre : `topic_explorer_screen` → `topic_chip`
   → `source_detail_modal` → `source_adjust_sheet` → `source_list_item`
   + cascade `sources_screen` → `digest_personalization_sheet`.
3. **Reformulation CTA** (`source_filter_sheet`, `interest_filter_sheet`).
4. **Suppression code mort** (repo → provider → widget).
5. **Tests Flutter** + adaptation des tests rouges.
6. **Purge greps** (`PrioritySlider`, `priority_multiplier`,
   « Pousse leur priorité » → 0 hit dans `apps/mobile/lib/`).

## Vérification

```bash
cd packages/api && pytest -v
cd apps/mobile && flutter test && flutter analyze
```

```bash
grep -rn "PrioritySlider" apps/mobile/lib/                # 0
grep -rn "priority_multiplier" apps/mobile/lib/           # 0
grep -rn "priority_multiplier" packages/api/app/schemas/  # 0 (côté write)
grep -rn "Pousse leur priorité" apps/mobile/lib/          # 0
grep -rn "PUT.*weight" packages/api/app/routers/sources.py # 0
```

Scénarios E2E manuels (Playwright via `/validate-feature`) :
- `SourceDetailModal` → picker ouvre, état persiste après reload.
- Swipe gauche carte feed → `SourceAdjustSheet` avec picker, choix
  « Masqué » fait disparaître l'article.
- `TopicExplorerScreen` → picker dans header, état persiste.
- « Pourquoi cet article » digest → picker visible.
- Filtres feed : nouveaux libellés sans « 3/3 ».
- Devtools réseau : aucun `PUT /sources/{id}/weight`, aucun
  `priority_multiplier` dans les `PATCH` sortants.

## Suivi

- Story doc : ce fichier.
- QA Handoff : `.context/qa-handoff.md` (template
  `.context/qa-handoff-template.md`).
- PR : créée via `/go` vers `main` (base obligatoire).
