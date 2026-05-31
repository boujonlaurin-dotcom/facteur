# Veille — curation premium + config liée aux angles + fix navigation

Refonte de la **veille** sur 3 axes (par impact) : curation par score (le « 90 % »), config où chaque angle porte sa grappe de mots-clés, et fix du bug « Créer ma veille » → feed.

## Part A — Curation premium (cœur)
Remplace le filtre `OR` (où le **thème** suffisait à faire entrer tout l'article) par un pipeline **prefilter SQL axes forts → scoring piliers → seuil → tri par score**, en réutilisant le moteur de la Tournée (`PillarScoringEngine`).
- `feed_filter.py` : `build_strong_predicate` (topics/sources/mots-clés ; **thème retiré du prédicat**) + fenêtre récence 168h + `CANDIDATE_CAP` 300 + `_score_and_rank` (seuil + tri score/récence). `matched_on` ne qualifie plus via `theme`.
- `scoring_context.py` (nouveau) : adaptateur `VeilleAngleTopic` (duck-type de `_score_custom_topics`) + `build_veille_scoring_context` — thème = signal **faible** (`user_interests`), topics → `user_subtopics` (+45), angles → `user_custom_topics` (+25), sources → `followed_source_ids` (+35).
- `scoring_config.py` : `VEILLE_RELEVANCE_THRESHOLD=40`, `VEILLE_CANDIDATE_CAP=300`, `VEILLE_RECENCY_HOURS=168` + log structuré (`max_score`/`pass_count`/`candidate_count`) pour calibrer en prod.

## Part B — Modèle : angle = sujet + grappe
- `VeilleKeyword.veille_topic_id` (FK `veille_topics`, nullable = mot-clé global), index `ix_veille_keywords_topic`, unique relâché en `(config, topic_id, keyword)`.
- Migration `vk01_link_keywords_to_topics` (`down_revision = dd01_franceinfo_dedup`, 1 head, downgrade symétrique).

## Part C — Config enrichie
- `schemas` + `routers/veille.py` : `VeilleTopicSelection.keywords` persisté lié à l'angle ; `_hydrate_response` round-trip (grappes nichées, globaux à plat).
- `angle_suggester.py` : prompt **8-12 angles** (au lieu de 5-8), `max_tokens` 2000, fallback étendu.
- Sources : `/presets` 6 → 12 ; `_fetch_source_examples` **préfère** les articles matchant les mots-clés de la veille active (sinon récence brute).
- Mobile : DTO round-trip des grappes ; brief introduit **une fois** au Step 1 (suppression du doublon Step 2).

## Part D — Fix navigation « Créer ma veille » → feed (2 leviers)
- `veille_config_provider.submit()` : `invalidate(userInterestsProvider)` après hydratation (lever racine).
- `my_interests_screen.dart` : CTA masqué si veille active connue **ET** pas de `VeilleFavoriteRef` (défense en profondeur).

## Tests / VERIFY
- Backend complet : **1408 passed, 1 skipped, 2 xfailed** (0 régression). Veille : 65 passed (scoring, thème-seul exclu, topic>keyword, source/keyword, frontière seuil, exclusions hidden/seen/inactive, pagination, persistance grappes round-trip, unique triplet).
- Alembic : 1 head ; `upgrade head` + `downgrade -1` + re-upgrade OK sur DB **vide**.
- Mobile : `flutter analyze` → 0 erreur (548 infos préexistantes).

## Hors-scope (suite)
Le fetch LLM `/suggest/angles` n'est pas encore branché dans l'écran suggestions mobile (il consomme aujourd'hui les preset topics statiques) ; le backend + le round-trip DTO sont prêts à l'accueillir → l'affichage éditable des chips de mots-clés par angle (C3 UI) suivra dans une PR mobile dédiée.
