# PR — Story 10.29 : Refonte Digest Journal + fixes pipeline reliability

## Quoi

Implémentation complète de la story 10.29 "Digest Journal" : toggle compact/étendu pour chaque topic, passage de 3 à 5 sujets actus, intégration des perspectives médiatiques (bias distribution, divergence analysis) en batch, nouveaux blocs UI (`DivergenceAnalysisBlock`, `PasDeReculBlock`, `SourceCoverageBadge`).
En parallèle : fix de fiabilité pipeline digest (cron 8h → 6h, watchdog 7h30, retry avec backoff, catch-up coverage-based).

## Pourquoi

Le digest éditorial manquait de hiérarchie visuelle (toutes les cartes identiques), cachait la comparaison de sources (différenciant Facteur), et ne donnait pas de sentiment de complétude (3 sujets insuffisants). Sur le backend, des digests étaient silencieusement sautés à cause d'APScheduler fragile sur Railway et d'un catch-up trop grossier.

## Fichiers modifiés

**Backend :**
- `packages/api/app/services/editorial/pipeline.py` — Étape 3C : enrichissement perspectives en batch (asyncio.gather), passage 3→5 sujets, helpers bias
- `packages/api/app/services/editorial/schemas.py` — 4 nouveaux champs sur `EditorialSubject` + helpers `compute_bias_distribution` / `compute_bias_highlights`
- `packages/api/app/services/editorial/config.py` — `subjects_count: 3 → 5`
- `packages/api/app/services/editorial/deep_matcher.py` — Seuils élargis pour le sujet "À la Une", seuil minimum absolu 0.08
- `packages/api/app/services/editorial/curation.py` — Adaptation au count dynamique
- `packages/api/app/services/digest_service.py` — Mapping des 4 champs perspectives vers `DigestTopic`
- `packages/api/app/schemas/digest.py` — Ajout champs perspectives dans le schéma API
- `packages/api/app/workers/scheduler.py` — Cron 8h→6h, watchdog 7h30 (coverage < 90%), misfire 4h, coalesce
- `packages/api/app/main.py` — Catch-up coverage-based (< 90% users)
- `packages/api/app/jobs/digest_generation_job.py` — Retry 2× avec backoff exponentiel
- `packages/api/config/editorial_config.yaml` / `editorial_prompts.yaml` — 5 sujets, prompt intro revu (2 phrases max, no mention sources)

**Mobile :**
- `apps/mobile/lib/features/digest/widgets/topic_section.dart` — Réécriture majeure : état compact (4 variantes : image/no-image × hero/standard), état étendu avec header toggle, carrousel articles, carte "De quoi on parle ?", blocs divergence/pas-de-recul
- `apps/mobile/lib/features/digest/widgets/divergence_analysis_block.dart` — Nouveau bloc : analyse médiatique avec Markdown, CTA "Comparer les sources"
- `apps/mobile/lib/features/digest/widgets/pas_de_recul_block.dart` — Nouveau bloc : article de fond
- `apps/mobile/lib/features/digest/widgets/source_coverage_badge.dart` — Nouveau badge "X sources"
- `apps/mobile/lib/features/digest/models/digest_models.dart` + `.freezed.dart` + `.g.dart` — 4 nouveaux champs `DigestTopic` + `publishedAt` sur Pepite/CoupDeCoeur
- `apps/mobile/lib/features/digest/widgets/digest_briefing_section.dart` — Retrait getter `_usesEditorial` stale
- `apps/mobile/lib/core/auth/auth_state.dart` — Fix bug : détection `isNewSignIn` avant `state.copyWith`, marquage version onboarding au dismiss

**Tests :**
- `apps/mobile/test/features/digest/widgets/divergence_analysis_block_test.dart` — 74 lignes
- `apps/mobile/test/features/digest/widgets/pas_de_recul_block_test.dart` — 70 lignes
- `apps/mobile/test/features/digest/widgets/source_coverage_badge_test.dart` — 44 lignes
- `packages/api/tests/editorial/test_schemas.py` — 142 lignes (helpers bias)
- `packages/api/tests/editorial/test_pipeline.py` / `test_curation.py` / `test_config.py` — MAJ assertions 3→5
- `packages/api/tests/workers/test_scheduler.py` — Tests watchdog + cron 6h

**Config/Docs :**
- `docs/stories/core/10.digest-central/10.29.refonte-digest-journal.story.md`
- `docs/bugs/bug-digest-pipeline-reliability.md`
- `docs/bugs/bug-digest-post-e2e-adjustments.md`

## Zones à risque

1. **`pipeline.py` Étape 3C** — `asyncio.gather` sur 5 appels `PerspectiveService` parallèles peut significativement allonger la génération digest. Le fallback est en place mais la latence est à surveiller en prod.

2. **`scheduler.py` — Watchdog 7h30** — Vérifie que `run_digest_generation()` est bien idempotent (skip les users déjà traités). Risque de double génération si non.

3. **`digest_generation_job.py` — Retry avec backoff** — Le retry est DB-based (check digest existant). Confirmer que le skip est correct avant retry pour éviter les doublons.

4. **`topic_section.dart` — 800+ lignes** — Condition `widget.editorialMode` protège les formats anciens (`topics_v1`, `flat_v1`). Bien vérifier que le toggle n'impacte pas ces formats.

5. **`auth_state.dart` — isNewSignIn** — `isNewSignIn` capturé AVANT `state = state.copyWith(...)`. Vérifier que le cas token refresh (user déjà loggé, nouveau JWT) ne déclenche pas `_checkOnboardingStatus()` par erreur.

## Points d'attention pour le reviewer

- **Backward compat API** : tous les nouveaux champs (`perspective_count`, `bias_distribution`, etc.) ont des defaults. Anciens digests en DB (JSON sans ces champs) restent lisibles côté mobile grâce aux `@Default` Freezed. Pas de migration Alembic — les champs vivent dans le JSON `topics_data` existant.

- **`compute_bias_distribution` et `compute_bias_highlights`** dans `schemas.py` : bien testés dans `test_schemas.py`. Vérifier les cas limites : liste vide, un seul biais, tous neutres.

- **Deep matcher** — `prefilter_limit ×2` et `threshold /2` pour "À la Une" peuvent faire remonter des faux positifs. À valider sur données réelles.

- **Toggle state local** — `_isExpanded` est un `StatefulWidget` local. Si l'utilisateur scrolle loin puis revient, le state est reset (tout repasse compact). Intentionnel pour l'instant ?

- **Prompt `editorial_prompts.yaml`** — L'intro ne doit plus mentionner les sources/divergences. Anciens digests avec mentions = affichage redondant mais pas cassé.

## Ce qui N'A PAS changé (mais pourrait sembler affecté)

- **Formats `topics_v1` et `flat_v1`** : `TopicSection` est paramétré par `widget.editorialMode`. Les formats anciens ne passent pas par le toggle compact/étendu.
- **`PepiteBlock` et `CoupDeCoeurBlock`** : touches mineures (ajout import), aucun changement de comportement.
- **`feed_repository.dart`** : nettoyage de code mort (`recommendation_service`, `_usesEditorial`), aucune logique business modifiée.
- **Alembic** : aucune migration. Les 4 nouveaux champs perspectives vivent dans le champ JSON `topics_data` existant.

## Comment tester

### Backend
```bash
cd packages/api
pytest tests/editorial/ -v         # Schemas, pipeline, curation, config
pytest tests/workers/test_scheduler.py -v  # Watchdog + cron timing
```

### Mobile (unitaire)
```bash
cd apps/mobile
flutter test test/features/digest/widgets/  # Nouveaux blocs
flutter analyze
```

### E2E Manuel
1. Ouvrir le digest éditorial d'un user avec digest du jour
2. Vérifier état compact par défaut : titre, logos sources, time, caret
3. Taper sur un topic → état étendu : header avec X, "De quoi on parle ?", carrousel, `DivergenceAnalysisBlock`
4. Vérifier topic `isUne` : badge "À la Une" + border left en compact
5. Vérifier topic avec `pas_de_recul` : bloc visible en état étendu
6. Vérifier formats anciens (`topics_v1`) : aucun toggle, comportement inchangé

### Pipeline reliability (staging)
- Forcer redémarrage Railway entre 6h et 10h → watchdog 7h30 doit relancer si coverage < 90%
- Vérifier logs : `digest_watchdog_check`, `digest_watchdog_low_coverage_triggering_generation`
- Vérifier catch-up au startup : log `digest_startup_catchup` si users manquants
