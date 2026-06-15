feat(onboarding): refonte sources — swipe de calibration + biais « sources productives » + badge format (Story 2.8)

Refonte du parcours sources de l'onboarding, livrée en **1 PR groupée** (backend + mobile) vers `main`. Le swipe devient le cœur du parcours, la calibration agit au niveau pôle, et l'onboarding **favorise les sources productives** (volume de publication réel) tout en rendant le **format** (vidéo, podcast, Reddit) lisible d'un coup d'œil. Additif, **aucune migration Alembic** (champ `articles_30d` purement calculé).

## Ce que ça change (user-visible)

- **Tout le monde swipe.** Question d'intent « curieux / je connais » retirée. Après les sous-thèmes → directement le swipe, non skippable (set vide = auto-skip).
- **Swipe satisfaisant + cliquable.** Carte suivie au drag (rotation + translation), fling hors écran au seuil, retour élastique sinon ; tap carte → fiche source. Nudge « Touchez pour explorer » sur la 1ère carte.
- **Sources les plus actives mises en avant.** Le recommander biaise vers les sources qui publient vraiment (volume 30 j), en matched/préselection **et** dans le deck de swipe (tiebreaker volume puis audience).
- **Format visible.** Badge discret YouTube / Podcast / Vidéo / Reddit sur les cartes de swipe, les recos d'onboarding et la fiche source (jamais pour les articles, format implicite).
- **Titre + compteur humanisés.** Titre « Quels médias suivre ? » ; compteur à 3 paliers (« Premières cartes » → « On affine » → « Encore quelques-unes »).
- **« Ce qu'on retient » en bas.** Les chips du haut deviennent une phrase inline discrète sous le deck (« On retient pour ta sélection : … »), qui s'allume quand un pôle passe net-positif.
- **Calibration en direct (signal pôle).** Votes agrégés par pôle (fond / actu directe / indépendant / référence) → repondèrent toutes les sources du pôle (±2/vote, capé ±4), en plus du `+5/-4` par source swipée.

## Technique (additif, sans migration)

- **Backend** : `SourceResponse.articles_30d` (calculé, défaut 0). `SourceService` enrichit les réponses curées (`get_all_sources` + `get_curated_sources`) via **un unique GROUP BY batché** (jamais d'appel par source), réutilisant l'index composite existant `ix_contents_source_published` (source_id, published_at). Le custom reste à 0 (hors-scope). Aucune colonne DB, aucune migration, toujours 1 head Alembic.
- **Mobile** : `Source.articles30d` (porté depuis le JSON) + `Source.getTypeIcon()` ; nouveau widget partagé `SourceTypeBadge` (masqué pour les articles). Recommander : `_volumeBonus` (+2 ≥90/30j, +1 ≥20/30j, 0 sinon — sous le match thème `+3`) et tiebreaker `byVolumeThenFollowers` sur `buildSpanningSet`. `articles30d == 0` = no-op (rétro-compatible).
- Réutilise `SourceDetailModal`, `buildSpanningSet`, le scoring thème/fiabilité existant.

## Vérification

- **Backend** : `pytest` ciblé sources/onboarding → **49 passed** (dont 2 nouveaux : `articles_30d` peuplé par le GROUP BY, fenêtre 30 j, 0 sans contenu). Alembic : 1 head, aucune migration ajoutée. `ruff check` OK.
- **Mobile** : `flutter analyze` → **0 erreur** sur les fichiers touchés (warnings `withOpacity` pré-existants). `flutter test test/features/onboarding/ test/features/sources/{widgets,models}/` → **147 passed** (recommander volume + tiebreaker, badge type, compteur humanisé, phrase inline, absence des chips du haut).
- NB : suite mobile complète a ~27 échecs pré-existants (Hive/Supabase non init, hors CI) — non liés.

## Follow-up (PR2, hors scope)

- Page « Vos sources, sur mesure » : 4 blocs numérotés, 15-20 suggestions dont ~8-10 pré-cochées, « pourquoi » plus visible + tag « Similaire à », proxy volume mainstream.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
