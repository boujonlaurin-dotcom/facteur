# PR — Mute topics/entités + limite 3 topics par thème

## Quoi

Ajout de la capacité à masquer (muter) des sujets et entités depuis MyInterests, l'article sheet, et l'entities sheet. Trois bugs identifiés en test ont été corrigés : un sujet muté restait affiché dans les suivis, la casse était perdue ("Nba" au lieu de "NBA"), et la limite de topics non-entité par catégorie passe de 1 à 3. Le scoring backend applique désormais les malus sur les entités mutées.

## Pourquoi

- **Bug A** : Muter un sujet suivi devait aussi le retirer de la liste des suivis (cohérence UX + scoring)
- **Bug B** : Le slug muté était stocké en lowercase, le fallback `slug[0].toUpperCase()` produisait "Nba" — perte du nom original
- **Feature** : 1 topic non-entité par thème était trop restrictif ; passage à 3 avec message d'erreur clair côté backend
- **Scoring** : Les entités mutées (stockées en JSON dans `content.entities`) n'étaient pas matchées dans PersonalizationLayer ni PenaltyPass

## Fichiers modifiés

**Backend :**
- `packages/api/app/models/user_topic_profile.py` — suppression de `ix_utp_unique_topic` (index unique partiel)
- `packages/api/app/routers/custom_topics.py` — check d'existence → count ≥ 3 + nouveau message 409
- `packages/api/app/services/recommendation/layers/personalization.py` — ajout du parsing JSON des entités pour appliquer `MUTED_TOPIC_MALUS`
- `packages/api/app/services/recommendation/pillars/penalties.py` — idem dans le PenaltyPass
- `packages/api/alembic/versions/ht01_drop_unique_topic_per_category.py` — migration (à appliquer via Supabase SQL Editor, **pas via Railway**)

**Mobile :**
- `widgets/topic_row.dart` — ajout callback `onMute` sur `TopicRow` et `DismissibleTopicRow`
- `widgets/theme_section.dart` — handler `onMute` (muteTopic + unfollowTopic + invalidate) ; `mutedTopicSlugs` passe de `List<String>` à `Map<String, String>` (slug → label original)
- `screens/my_interests_screen.dart` — construction de `mutedByTheme` avec résolution du label original depuis les topics suivis
- `widgets/article_entities_sheet.dart` — ajout mute/unmute sur chaque entité, opacité 0.5 si muté
- `widgets/topic_chip.dart` — refactor mute topic/source (passe par `personalizationRepositoryProvider` directement, plus par `feedProvider.notifier`) + invalidation de `personalizationProvider`
- `widgets/suggestion_row.dart` — ajout mute sur les suggestions
- `config/topic_labels.dart` — ajout de nouveaux labels de topics

## Zones à risque

- **`custom_topics.py` router** : le `count` remplace un `select(UserTopicProfile)` qui retournait l'objet — vérifier qu'aucun code en aval n'utilisait `existing.topic_name` après ce bloc
- **`personalization.py` + `penalties.py`** : parsing JSON des entités dupliqué dans deux couches — si le format de `content.entities` change, les deux doivent être mis à jour
- **`theme_section.dart`** : signature de `mutedTopicSlugs` changée (`List` → `Map`) — tout callsite qui passerait une liste échouerait à la compilation (vérification statique OK via `flutter analyze`)

## Points d'attention pour le reviewer

1. **Bug B — résolution du label** : le map `mutedByTheme` est construit dans `my_interests_screen.dart` sur le snapshot courant de `topics` (avant que l'UI ait reflété le `unfollowTopic` optimiste). Cela fonctionne car le prochain rebuild recalcule le map avec les nouvelles données du provider.

2. **`unfollowTopic` dans `onMute`** : ordre `muteTopic` → `unfollowTopic` → `invalidate`. Si `unfollowTopic` échoue après que `muteTopic` a réussi, le topic sera muté backend mais encore visible dans les suivis. Pas de rollback compensatoire (cas rare, acceptable).

3. **Migration `ht01`** : uniquement `DROP INDEX`, pas d'index non-unique en remplacement. La limite à 3 est gérée applicativement via count — pas besoin d'index pour cette requête ponctuelle.

4. **Entités mutées dans le scoring** : match via `entity_names & set(context.muted_topics)` (intersection de sets lowercased). Les items non-JSON dans `content.entities` sont silencieusement ignorés.

## Ce qui N'A PAS changé (mais pourrait sembler affecté)

- `feed_provider.dart` et `collection_detail_screen.dart` sont modifiés mais ces changements appartiennent à d'autres parties de la branche (non liés aux bugs A/B/C)
- Le mute des **sources** (`muteSource`) dans `topic_chip.dart` a été refactoré pour passer par `personalizationRepositoryProvider` — comportement identique, chemin d'appel simplifié
- `pubspec.lock` : retrait de 16 lignes = nettoyage de dépendances, non lié au feature

## Comment tester

**SQL à appliquer sur Supabase avant test staging :**
```sql
DROP INDEX IF EXISTS ix_utp_unique_topic;
```

**Bug A — sujet muté disparaît des suivis :**
1. Suivre un topic custom (ex: "NBA") dans MyInterests
2. Swipe-left pour le muter → il doit disparaître de "Suivis" ET apparaître dans "Sujets masqués"

**Bug B — casse correcte :**
1. Après le test ci-dessus, vérifier que le label affiche "NBA" (pas "Nba")

**Feature C — limite 3 topics :**
1. Ajouter 3 topics dans le même thème → les 3 doivent s'enregistrer
2. Ajouter un 4e → SnackBar : `"3 sujets personnalisés maximum par thème (Sport)"`

**Entités mutées dans le scoring :**
1. Muter une entité (ex: "Emmanuel Macron") depuis l'entities sheet
2. Vérifier dans les logs de scoring que les articles contenant cette entité reçoivent un malus

**Tests automatisés :**
```bash
cd packages/api && pytest -v
cd apps/mobile && flutter test && flutter analyze
```
