# PR — fix: harden serein filter + add user feedback CTA

## Quoi
1. Réécriture du prompt LLM de classification sérénité pour couvrir les catégories manquantes (trafic humain, extrémisme, discrimination, pandémie, etc.) + extension des mots-clés fallback.
2. Nouveau CTA "Pas serein" dans Digest et Feed : quand le mode Serein est actif, le bouton "Pas pour moi" est remplacé par un bouton shieldWarning qui signale l'article au backend → reclassification immédiate `is_serene=False`.

## Pourquoi
Des articles clairement anxiogènes passaient à travers le filtre Serein (ex: "trafic d'êtres humains", "montée de l'extrême droite"). Le prompt Mistral ne listait que 8 catégories pour `serene=false` et le LLM traitait la liste comme exhaustive. Aucun mécanisme de feedback utilisateur n'existait pour corriger les faux positifs.

## Fichiers modifiés

### Backend
- `packages/api/app/services/ml/classification_service.py` — Section SÉRÉNITÉ du prompt : ajout "liste NON exhaustive" + 11 catégories manquantes + règle "même partiellement anxiogène → false"
- `packages/api/app/services/recommendation/filter_presets.py` — 19 nouveaux mots-clés dans `SEREIN_KEYWORDS` (fallback pour articles `is_serene=NULL`)
- `packages/api/app/models/serene_report.py` — **Nouveau fichier** : modèle `SereneReport` (table `serene_reports`, contrainte unique user+content)
- `packages/api/app/models/__init__.py` — Enregistrement du nouveau modèle
- `packages/api/app/routers/contents.py` — Endpoint `POST /contents/{id}/report-not-serene` : upsert idempotent + flip immédiat `is_serene=False`
- `packages/api/alembic/versions/sr01_create_serene_reports.py` — **Nouveau fichier** : migration (table + index + unique constraint). Head unique confirmée : `merge01 → sr01`

### Mobile
- `apps/mobile/lib/features/digest/widgets/article_action_bar.dart` — Nouveau param `isSerene`, 4è bouton conditionnel : eyeSlash/"Pas pour moi" → shieldWarning/"Pas serein"
- `apps/mobile/lib/features/digest/widgets/digest_card.dart` — Passe `isSerene` à `ArticleActionBar` (1 ligne)
- `apps/mobile/lib/features/digest/repositories/digest_repository.dart` — Méthode `reportNotSerene(contentId)`
- `apps/mobile/lib/features/digest/providers/digest_provider.dart` — Intercepte action `report_not_serene` en haut de `applyAction()`, appel API séparé + snackbar "Merci"
- `apps/mobile/lib/features/feed/widgets/feed_card.dart` — Nouveaux params `isSerene` + `onReportNotSerene`, bouton conditionnel shieldWarning avant eyeSlash
- `apps/mobile/lib/features/feed/screens/feed_screen.dart` — Lit `sereinToggleProvider.enabled`, passe `isSerene` + callback `onReportNotSerene` au `FeedCard`
- `apps/mobile/lib/features/feed/repositories/feed_repository.dart` — Méthode `reportNotSerene(contentId)`

## Zones à risque
- **`classification_service.py`** : le prompt élargi pourrait théoriquement être plus conservateur et classer certains articles légitimement neutres comme non-sereins. C'est le trade-off voulu (faux négatifs > faux positifs pour le mode Serein).
- **`contents.py` endpoint** : le flip `is_serene=False` est immédiat (seuil=1). Risque d'abus théorique si un user signale tout, mais accepté par le product owner pour cette phase.
- **`digest_provider.dart`** : le `report_not_serene` est intercepté AVANT le flow normal `applyAction` (early return). Pas d'optimistic UI update — le bouton n'a pas d'état "actif" persistant. Vérifier qu'il ne court-circuite pas d'autre logique.

## Points d'attention pour le reviewer
1. **Prompt LLM** : vérifier que la formulation "liste NON exhaustive" + "même partiellement anxiogène" donne bien le comportement attendu avec Mistral. Pas de test automatisé possible (classification LLM).
2. **`PhosphorIcons.shieldWarning()`** : confirmé existant dans phosphor_flutter 2.1+ (même famille que `shieldCheck` déjà utilisé). Pas de compilation error sur `flutter analyze`.
3. **Endpoint upsert** : utilise `on_conflict_do_nothing` (pas `do_update`) car il n'y a rien à update — le signalement existe ou pas. Le flip `is_serene` se fait via `db.get(Content, content_id)` dans la même transaction.
4. **Feed vs Digest** : le Feed n'a pas de `onNotInterested` callback passé (le swipe-dismiss le gère). Le bouton "Pas serein" apparaît dans le même slot mais via `isSerene && onReportNotSerene != null` qui est une condition différente — pas de conflit.

## Ce qui N'A PAS changé (mais pourrait sembler affecté)
- `SEREIN_EXCLUDED_THEMES` n'a pas été modifié (toujours 4 thèmes : society, international, economy, politics). Les nouveaux mots-clés sont dans `SEREIN_KEYWORDS` uniquement.
- `apply_serein_filter()` n'a pas changé de logique — la stratégie 3 tiers (True/False/NULL→keywords) est identique. Seule la liste de keywords a grandi.
- `is_cluster_serein_compatible()` utilise aussi `SEREIN_KEYWORDS` et bénéficie donc automatiquement des nouveaux mots-clés.

## Comment tester
1. **Prompt** : reclassifier manuellement quelques articles problématiques avec le nouveau prompt via Mistral API directement (titre: "Trafic d'êtres humains en Méditerranée") → vérifier `serene=false`
2. **Keywords** : `pytest tests/test_serein_filter.py -v` — les tests existants couvrent la logique True/False/NULL, pas le contenu exact de la liste
3. **CTA Digest** : lancer l'app en mode Serein, vérifier que le 4è bouton est bien shieldWarning/"Pas serein", taper → snackbar "Merci" + check réseau que `POST /contents/{id}/report-not-serene` part
4. **CTA Feed** : même vérification dans le Feed en mode Serein (toggle via le chip header)
5. **Backend** : `curl -X POST localhost:8080/api/contents/{content_id}/report-not-serene -H "Authorization: Bearer ..."` → 200 + vérifier que `is_serene` est flippé en DB
6. **Migration** : vérifier head unique Alembic (`HEADS: ['sr01']` ✅ déjà confirmé)
