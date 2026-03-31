# PR — Digest UI polish: editorial badge chips, article thumbs feedback, palette refresh

## Quoi
Refonte visuelle du digest : les badges éditoriaux passent de labels inline (dans le FeedCard footer) à des **chips colorés** au-dessus de chaque carte. Ajout d'un **feedback thumbs up/down par article** (nouveau widget + endpoint API + table DB). Rafraîchissement de la palette Serein/Normal vers "Terre & Sauge". Ajustements UI divers (ombres cartes, opacités gradient light mode, closure CTA).

## Pourquoi
- Les badges éditoriaux inline étaient peu visibles → les chips colorés ajoutent du contexte éditorial avant la lecture.
- Le feedback par article permet de collecter des signaux de pertinence pour ajuster les poids subtopics du moteur de recommandation (+0.15 / -0.15).
- La palette actuelle (orange vif + vert vif) était trop saturée → tons plus doux "Terre & Sauge".

## Fichiers modifiés

### Backend (5 fichiers)
- `packages/api/app/routers/contents.py` — Nouvel endpoint `POST /{content_id}/feedback` (upsert idempotent, ajuste subtopic weights)
- `packages/api/app/schemas/content.py` — `ArticleFeedbackRequest` schema
- `packages/api/app/models/article_feedback.py` — **Nouveau** modèle SQLAlchemy `article_feedback`
- `packages/api/alembic/versions/fb01_create_article_feedback.py` — **Nouvelle** migration Alembic
- `packages/api/config/editorial_prompts.yaml` — Clarification prompt pépite (anti meta-commentaire)

### Mobile (13 fichiers)
- `apps/mobile/lib/features/digest/widgets/article_thumbs_feedback.dart` — **Nouveau** widget thumbs up/down avec chips raisons + auto-submit 2s
- `apps/mobile/lib/features/digest/widgets/editorial_badge.dart` — Ajout `EditorialBadge.chip()` (widget coloré) en plus de `labelFor()`
- `apps/mobile/lib/features/digest/widgets/topic_section.dart` — Badge chip au-dessus des cartes, `editorialBadgeLabel` retiré, thumbs feedback ajouté
- `apps/mobile/lib/features/digest/widgets/coup_de_coeur_block.dart` — Badge chip + intro text + thumbs, suppression "Gardé par X lecteurs"
- `apps/mobile/lib/features/digest/widgets/pepite_block.dart` — Badge chip + thumbs feedback
- `apps/mobile/lib/features/digest/widgets/closure_block.dart` — CTA simplifié, haptic feedback, nouvelle icône
- `apps/mobile/lib/features/digest/widgets/digest_briefing_section.dart` — Ombres cartes + opacités gradient light mode réduites
- `apps/mobile/lib/features/digest/widgets/feedback_bottom_sheet.dart` — ConsumerStatefulWidget, navigation ClosureScreen après submit
- `apps/mobile/lib/features/digest/widgets/transition_text.dart` — Font size 13→14, couleur ajustée
- `apps/mobile/lib/features/digest/repositories/digest_repository.dart` — `submitArticleFeedback()` (fail-silent)
- `apps/mobile/lib/features/digest/screens/digest_screen.dart` — Passe `editorialBadge` au Content model
- `apps/mobile/lib/features/detail/screens/content_detail_screen.dart` — Badge chip au-dessus du titre écran détail
- `apps/mobile/lib/features/feed/models/content_model.dart` — Nouveau champ `editorialBadge` + copyWith
- `apps/mobile/lib/config/serein_colors.dart` — Nouvelle palette "Terre & Sauge"

## Zones à risque

1. **`contents.py` — accès à `service._adjust_subtopic_weights()`** : méthode privée de ContentService. Si renommée côté service, ça casse silencieusement. Anti-pattern assumé.
2. **Migration Alembic `fb01`** — `down_revision` pointe sur `z1a2b3c4d5e6`. Vérifier que c'est le dernier head. Exécuter via Supabase SQL Editor (pas CLI).
3. **`FeedbackBottomSheet` → `context.go(RoutePaths.digestClosure)`** : si cette route n'existe pas ou attend un format différent pour `extra`, crash.
4. **Palette Serein** : toutes les couleurs changent. Vérifier contraste dark + light mode.

## Points d'attention pour le reviewer

- **`editorialBadgeLabel` supprimé des FeedCards** : passé à `null` ou retiré dans topic_section, coup_de_coeur_block, pepite_block. Vérifier que FeedCard gère `null` proprement.
- **Auto-submit timer (2s)** dans `ArticleThumbsFeedback` : le feedback négatif part après 2s d'inactivité. Si l'utilisateur sélectionne encore des raisons, feedback partiel envoyé. Acceptable car upsert côté API.
- **`print()` dans `digest_repository.dart`** : le catch de `submitArticleFeedback` utilise `print()` au lieu du logger. V1 acceptable mais à upgrader.
- **Unicode escapes** dans `editorial_badge.dart` : emojis en `\u{XXXX}` au lieu de littéraux. Fonctionnel mais moins lisible.

## Ce qui N'A PAS changé (mais pourrait sembler affecté)

- **`FeedCard`** : aucune modification. Les changements sont dans les appelants.
- **`digest_models.dart`** : le champ `badge` sur DigestItem existait déjà.
- **Les routes** : pas de nouvelle route. `RoutePaths.digestClosure` pré-existant.
- **`ScoringWeights`** : constantes `LIKE_TOPIC_BOOST` / `DISMISS_TOPIC_PENALTY` inchangées.

## Comment tester

### Backend
```bash
cd packages/api && pytest tests/ -x -q

# Test endpoint :
curl -X POST http://localhost:8080/contents/<uuid>/feedback \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"sentiment": "positive"}'
# → {"status": "ok", "sentiment": "positive"}
# 2e appel = upsert, pas d'erreur
```

### Mobile
```bash
cd apps/mobile && flutter analyze
cd apps/mobile && flutter test
```

### Visuel (device/simulator)
1. Ouvrir le digest → chips colorés au-dessus des cartes (actu=primary, pas_de_recul=info, pepite/coup_de_coeur=success)
2. Thumbs up sur un article → icône remplie, pas de chips
3. Thumbs down → chips raisons apparaissent, sélectionner 1-2, attendre 2s → soumission auto
4. Dark mode + light mode (palette Terre & Sauge, contraste lisible)
5. Ouvrir un article depuis digest → badge chip visible au-dessus du titre
6. Closure → CTA "Essentiel terminé — Un avis ?" → bottom sheet → submit → navigation ClosureScreen

### Migration
- Exécuter le SQL de `fb01` via Supabase SQL Editor
- Vérifier table `article_feedback` avec un INSERT test
