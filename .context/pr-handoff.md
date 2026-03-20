# PR — Souscription entités + Serene mode rethink + Feed interest filter

## Quoi
Branche combinée couvrant 3 chantiers majeurs :
1. **Serene mode rethink** — Les modes digest (Serein, Perspective, Theme Focus) sont remplacés par un toggle global ON/OFF "Rester serein" dans le header Digest. Double génération digest (normal + serein) pour switch instantané. Classification `is_serene` via Mistral sur chaque article.
2. **Entity subscription schema** (WS1) — Migration Alembic ajoutant `Content.entities` (ARRAY Text), `UserTopicProfile.entity_type` + `canonical_name`. Contrainte unique remplacée par deux index partiels.
3. **Mobile entity surfaces** (WS3/WS4 — WIP non committé) — Chip "Mes intérêts" dans le feed filter bar, modal entités dans le detail article, bouton "Ajouter un sujet niche" dans Mes Intérêts, entités populaires dans l'onboarding.

## Pourquoi
- **Serene** : Les utilisateurs ne comprenaient pas les modes de digest et voulaient switcher selon l'humeur du jour → toggle binaire simple.
- **Entités** : Permettre de suivre des personnes/orgs/événements au même niveau que les topics. Le scoring par keyword substring ("IA" matchait "chainsaw") est remplacé par du word-boundary matching + entity matching précis.
- **Feed filter** : Les utilisateurs n'avaient aucun moyen de filtrer le feed par sujet suivi.

## Fichiers modifiés

### Backend — Serene mode
- `packages/api/app/services/ml/classification_service.py` — Prompt Mistral étendu (entités + sérénité)
- `packages/api/app/services/digest_service.py` — Double génération digest (normal + serein)
- `packages/api/app/services/digest_selector.py` — Filtre pool serein
- `packages/api/app/jobs/digest_generation_job.py` — Job double génération
- `packages/api/app/routers/digest.py` — Endpoint toggle serein
- `packages/api/app/models/daily_digest.py` — Colonne `is_serene`
- `packages/api/app/services/editorial/writer.py` — Ton éditorial serein
- `packages/api/config/editorial_prompts.yaml` — Prompts serein

### Backend — Entity schema (WS1)
- `packages/api/alembic/versions/ts01_entity_schema_foundation.py` — Migration entities + entity_type + canonical_name
- `packages/api/alembic/versions/merge_sm01_ts01.py` — Merge heads Alembic
- `packages/api/app/models/content.py` — Colonne `entities` réactivée
- `packages/api/app/models/user_topic_profile.py` — Colonnes entity_type, canonical_name
- `packages/api/app/schemas/content.py` — entities + theme dans ContentResponse/DetailResponse
- `packages/api/app/routers/custom_topics.py` — Endpoint popular-entities + extend create avec entity_type
- `packages/api/app/routers/feed.py` — Param entity filter
- `packages/api/app/services/recommendation/layers/user_custom_topics.py` — Word-boundary fix + entity scoring
- `packages/api/app/services/ml/topic_enrichment_service.py` — Détection type entité

### Mobile — Serene mode
- `apps/mobile/lib/features/digest/screens/digest_screen.dart` — Suppression modes, ajout toggle serein
- `apps/mobile/lib/features/digest/widgets/serein_toggle_chip.dart` — Nouveau widget toggle
- `apps/mobile/lib/features/digest/providers/serein_toggle_provider.dart` — Provider toggle
- `apps/mobile/lib/features/digest/widgets/digest_briefing_section.dart` — Prop `isSerein` remplace `mode`
- Fichiers supprimés : `digest_mode.dart`, `digest_mode_provider.dart`, `digest_mode_card.dart`, `digest_mode_tab_selector.dart`, `digest_settings_screen.dart`

### Mobile — Feed filter + Entity surfaces (WIP)
- `apps/mobile/lib/features/feed/widgets/interest_filter_chip.dart` — Chip "Mes intérêts" (nouveau)
- `apps/mobile/lib/features/feed/widgets/interest_filter_sheet.dart` — Modal sélection sujet (nouveau)
- `apps/mobile/lib/features/feed/widgets/filter_bar.dart` — Slot chip intérêts
- `apps/mobile/lib/features/feed/models/content_model.dart` — ContentEntity class + entities field
- `apps/mobile/lib/features/detail/screens/content_detail_screen.dart` — Chip entités header
- `apps/mobile/lib/features/detail/widgets/article_entities_sheet.dart` — Modal entités article (nouveau)
- `apps/mobile/lib/features/custom_topics/widgets/entity_add_sheet.dart` — Modal ajout sujet niche (nouveau)
- `apps/mobile/lib/features/custom_topics/widgets/theme_section.dart` — Bouton inline "+ Ajouter un sujet niche"
- `apps/mobile/lib/features/custom_topics/models/topic_models.dart` — entityType + canonicalName (Freezed)
- `apps/mobile/lib/features/custom_topics/repositories/topic_repository.dart` — getPopularEntities, followEntity
- `apps/mobile/lib/features/onboarding/widgets/theme_with_subtopics.dart` — Entités populaires dans onboarding

## Zones à risque

1. **Migration Alembic `ts01_entity_schema_foundation.py`** — Remplacement de la contrainte unique `uq_user_topic_user_slug(user_id, slug_parent)` par deux index partiels. Opération délicate en prod : l'ancien index doit être dropé AVANT de créer les nouveaux. Le SQL brut doit être exécuté manuellement dans Supabase SQL Editor (Guardrail #4).

2. **`merge_sm01_ts01.py`** — Merge de deux heads Alembic (serene mode + entity schema). Vérifier qu'il n'y a qu'un seul head après merge.

3. **`digest_generation_job.py`** — Double génération digest (normal + serein). Impact perf : 2x les appels Mistral pour l'éditorial. Le fallback si le pool serein est insuffisant doit être robuste.

4. **`user_custom_topics.py` — word-boundary regex** — Le `re.search(r'\b...\b')` peut avoir des edge cases avec les accents français et les mots courts. Tester avec "IA", "UE", "ONU".

5. **Fichiers WIP non commités** (11 fichiers modifiés + 2 nouveaux) — Code potentiellement incomplet ou non testé. Le reviewer doit distinguer le code commité (fonctionnel) du WIP.

## Points d'attention pour le reviewer

1. **Suppression fichiers serene mode** — `digest_mode.dart`, `digest_mode_provider.dart`, `digest_settings_screen.dart` etc. sont supprimés. Vérifier qu'aucun import résiduel ne les référence (flutter analyze devrait catch ça).

2. **Contrainte unique UserTopicProfile** — L'ancienne contrainte `UNIQUE(user_id, slug_parent)` limitait à 1 topic par thème. La nouvelle permet plusieurs entités par thème via `UNIQUE(user_id, canonical_name) WHERE canonical_name IS NOT NULL`. Vérifier que les endpoints CRUD dans `custom_topics.py` gèrent correctement la logique de doublon pour les deux cas (topic classique vs entité).

3. **ContentEntity.fromJson** — Le field est `text` + `label` côté Dart mais `name` + `type` côté API. Vérifier la correspondance dans le parsing.

4. **Prompt Mistral** — Le prompt étendu demande à la fois topics, serene, ET entities. Vérifier que `max_tokens` est suffisant et que le parsing est robuste aux réponses partielles/malformées.

5. **`interest_filter_sheet.dart`** — 385 lignes, c'est le plus gros fichier nouveau. Pattern répliqué de `source_filter_sheet.dart` — vérifier la cohérence UX.

## Ce qui N'A PAS changé (mais pourrait sembler affecté)

- **`recommendation_service.py`** — Seul un param `entity` est ajouté au feed filter. Le scoring engine, les autres layers, et le feed generation flow sont inchangés.
- **`classification_worker.py`** — Seul le passage de `entities` à `mark_completed_with_entities()` change. Le flow de retry, batch, et queue est identique.
- **`source_filter_chip.dart` / `source_filter_sheet.dart`** — Non modifiés. Le nouveau interest filter est un clone indépendant, pas une modification de l'existant.
- **Routes / navigation** — `routes.dart` supprime la route `digestSettings` (écran supprimé), mais aucune autre route n'est affectée.

## Comment tester

### Serene mode
1. Ouvrir le digest → vérifier la présence du toggle "Rester serein" dans le header
2. Activer le toggle → le digest doit switcher instantanément (pas de rechargement API)
3. Vérifier que l'écran "Réglages Digest" / "Mon Essentiel" n'est plus accessible (route supprimée)

### Entity schema
```bash
cd packages/api && source venv/bin/activate
# Vérifier 1 seul Alembic head
python3 -c "
import re; from pathlib import Path
d = Path('alembic/versions'); revs={}; refs=set()
for f in d.glob('*.py'):
    c=f.read_text()
    r=re.search(r\"^revision\s*(?::\s*str)?\s*=\s*['\\\"]([^'\\\"]+)['\\\"]\", c, re.M)
    dn=re.search(r\"^down_revision\s*(?:[^=]+)?\s*=\s*(.+?)\$\", c, re.M|re.S)
    if r:
        revs[r.group(1)]=[]; refs.update(re.findall(r\"['\\\"]([^'\\\"]+)['\\\"]\", dn.group(1)) if dn else [])
print('HEADS:', [h for h in revs if h not in refs])
"
# Résultat attendu : HEADS: ['<un_seul_id>']
```

### Feed interest filter
1. Ouvrir le feed → vérifier la présence du chip "Mes intérêts" dans la filter bar
2. Tap chip → modal bottom sheet avec liste des sujets suivis
3. Sélectionner un sujet → feed filtré → chip actif avec nom + ×
4. Tap × → filtre retiré → retour au feed complet

### Content detail entities
1. Ouvrir un article → vérifier chip "[N sujets +]" dans le header
2. Tap → modal avec entités de l'article + boutons Suivre/Suivi
3. Suivre une entité → chip se met à jour ("+" → "✓" si toutes suivies)

### Onboarding
1. Lancer l'onboarding → étape thèmes → sélectionner un thème
2. Vérifier que des entités populaires apparaissent sous les subtopics
