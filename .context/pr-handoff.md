feat(onboarding): swipe de calibration inconditionnel + signal pôle généralisé (Story 2.8 suite)

Le swipe devient le **cœur** du parcours sources : tout le monde swipe, la physique est satisfaisante, les cartes sont cliquables, et le signal calibre **pour de vrai** (au niveau pôle, pas juste les cartes swipées). La question d'intent « curieux / je connais » disparaît. Additif, **aucune migration**.

## Ce que ça change (user-visible)

- **Tout le monde swipe.** Question d'intent retirée. Après les sous-thèmes → directement le swipe, **non skippable** (dégrade gracieusement : set vide = auto-skip).
- **Swipe satisfaisant + cliquable.** Carte custom suivie au drag (rotation + translation), **fling** hors écran au-delà du seuil, **retour élastique** sinon. Boutons d'action = même fling programmatique. Tap carte → fiche source (`SourceDetailModal`). Nudge « Touchez pour explorer » sur la 1ère carte. Badges LIKE / NON pendant le drag.
- **Calibration en direct.** ~8-10 cartes (2 par pôle, round-robin) au lieu de 5. Rangée de chips « On retient : » qui s'allume quand un pôle passe net-positif.
- **Signal pôle → recommander (calibration *vraie*).** Votes agrégés par pôle (fond / actu directe / indépendant / référence) → repondèrent **toutes** les sources du pôle (±2 par vote net, capé ±4), en plus du `+5/-4` par source swipée. Aimer une source de fond booste désormais toutes les sources de fond.
- **Copy Indépendance recadrée** (moins biaisée) : « Les grands médias institutionnels » / « Installés, connus de tous » vs « Des médias plus spécialisés » / « Moins connus, souvent indépendants ».
- **Page sources** simplifiée à une variante unique (branche « knows » retirée).

## Technique (additif, sans migration)

- `sourcesIntent` conservé dans le modèle (compat reprise Hive, figé `curious`, hors `toJson()`). **Bump Hive `_currentVersion` 6 → 7** (réindexation enum Section 3 → wipe des positions sauvegardées).
- **Aucun changement DB / Alembic / endpoint** — tout est calculé côté Flutter.
- Réutilise `SourceDetailModal`, `buildSpanningSet`, le scoring thème/fiabilité existant. Nettoyage : strings d'intent morts + `trackOnboardingSourcesIntent` retirés.

## Vérification

- `flutter analyze` : **0 erreur** sur les fichiers touchés (warnings `withOpacity` pré-existants, style aligné).
- `flutter test test/features/onboarding/` → **55 passed** (provider, swipe, sources, recommender, signal pôle).
- NB : suite mobile complète a ~27 échecs pré-existants (Hive/Supabase non init, hors CI) — non liés.

## Follow-up (PR2, hors scope)

- Page « Vos sources, sur mesure » : 4 blocs numérotés, 15-20 suggestions dont ~8-10 pré-cochées, « pourquoi » plus visible + tag « Similaire à », proxy volume mainstream.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
