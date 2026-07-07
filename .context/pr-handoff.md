# Veille — PR 1 « Quick wins » : re-corréler le feed au sujet configuré

Backend-only, **0 migration DB**. Chaque levier est un bouton réglable/réversible
par constante. Motivé par l'audit du 07/07 (`.context/veille-curation-mecanique.html`,
memory `project_veille_curation_audit_decorrelation`) : le feed Veille était
décorrélé de l'intention (topic axis mort 97 %, kw LLM génériques = 31 % du corpus,
seuil posé sur le composite ⇒ ~60 % hors-sujet, anti-starvation qui réadmet le bruit).

## Commit 1 — Mécanique scoring & pool (`feed_filter.py`, `scoring_context.py`, `scoring_config.py`)

- **Constantes** : `VEILLE_PERTINENCE_GATE=20`, `VEILLE_FLOOR_MIN_KEYWORD_HITS=2`,
  `VEILLE_BLOCK_A_PER_SOURCE_CANDIDATES=30`, `VEILLE_BLOCK_B_LANGUAGE_FILTER=True` ;
  suppression de `VEILLE_MIN_FEED_SIZE` (anti-starvation). Seuil composite **48 inchangé**.
- **E — plus de tokenisation des `why`** : `_tokenize_intent` + l'angle « Intention »
  retirés. `why` reste en DB / endpoint config (badge santé inchangé).
- **G2 — slugs non canoniques ignorés** : un `topic_id` hors des 50 slugs canoniques
  (`SUBTOPIC_LABELS`) est neutralisé en `""` → sort du prédicat SQL, de `matched_on`
  et de `user_subtopics` (le floor redevient honnête). Ses mots-clés survivent.
- **B — floor durci** : un keyword-only ne qualifie que sur **≥ 2 hits distincts** ou
  **1 hit fort** (mot-clé multi-mots, p.ex. « coupe du monde »). `_matched_axes` renvoie
  désormais `(axes, floor_qualified)`. `matched_on` (front) inchangé.
- **A — gate pertinence** : en plus du seuil composite, on exige pertinence normalisée
  ≥ 20 quand la config porte un axe topic/mot-clé (le composite offre ~37-40 pts d'office
  via source+fraîcheur+qualité). Nouveau compteur `gate_pruned_count` au log
  `veille.feed_scored`.
- **C — anti-starvation supprimée** : aucun candidat sous le seuil n'est réadmis
  (feed court honnête). Revert = un bloc isolé.
- **D — pool Bloc A équitable par source** : `row_number() OVER (PARTITION BY source_id
  ORDER BY published_at DESC)` borne chaque source à N=30 avant le cap externe 300 — une
  source dense n'affame plus les discrètes. `_base_query` refactoré en
  `_apply_common_filters` (réutilisé par la sous-requête d'ids). Le point incertain du
  plan (`apply_serein_filter` sur select non-entité) fonctionne — pas de plan B.
- **G1 — filtre langue Bloc B** : langues des sources configurées ∪ `{fr}`,
  `Content.language IS NULL` toléré. Bloc A non filtré. Kill-switch.

## Commit 2 — F : mots-clés LLM discriminants (`llm/angle_suggester.py`)

- `_SYSTEM_PROMPT` durci : noms propres / entités datées, **≥ 2 expressions multi-mots
  par angle**, denylist explicite du vocabulaire de discours, règle d'or (« un article
  qui contient ce mot-clé parle presque certainement de ce sujet ») ; « Pense large »
  retiré.
- Filtre post-parse `_filter_generic_keywords` : denylist `_GENERIC_KEYWORDS` (~65
  unigrammes) + `FRENCH_STOP_WORDS`, jamais les multi-mots ; angle vidé → écarté ; log
  `angle_suggester.keywords_filtered`.
- `_fallback_angles` 8 → 3, expressions multi-mots ancrées au thème.
- Cache TTL 24 h inchangé : d'anciennes suggestions génériques peuvent coexister ≤ 24 h
  post-deploy.

## Effet produit assumé

Les feeds des configs **existantes** (kw génériques + slugs morts toujours en base) vont
**fortement raccourcir** — 0-10 items honnêtes au lieu de dizaines majoritairement
hors-sujet. C'est le comportement voulu. Le vrai remède (régénération des configs) est un
agent suivant. Boutons de détente si trop agressif : `VEILLE_FLOOR_MIN_KEYWORD_HITS`
(2→1) et `VEILLE_PERTINENCE_GATE` (20→25/0), via les logs prod
(`floor_pruned_count` / `gate_pruned_count` / `threshold_pruned_count`).

## Harness d'audit mis à jour

`scripts/evaluate_veille_curation.py` (l'outil qui a produit l'audit) est adapté à la
nouvelle porte : `source_intents` retiré, tuple `_matched_axes` déballé, nouvelles raisons
de rejet `floor_weak_keyword` (keyword-only sous le min de hits) et `gate_pertinence`.

## Vérification

- Suites veille + harness : **98 passed** (`test_veille_curation`, `test_veille_scoring`,
  `test_veille_routes`, `test_angle_suggester`, `test_evaluate_veille_curation`).
- Suite backend complète : **2034 passed**, 2 échecs pré-existants sans lien (artefacts
  de fuseau `+02:00` sur le Postgres local, `test_notification_preferences` /
  `test_sources_recent_items` — verts en CI UTC).
- `ruff check` + `ruff format` OK sur tout le code modifié.
- Nouveaux tests ciblés : floor durci (1 hit → pruned, 2 hits / multi-mots → passe),
  gate (2 hits sans source coupés, +source passe), C (aucune réadmission), D (source
  discrète non affamée sous cap serré), G1 (article `en` écarté, `NULL` passe, langue
  d'une source configurée autorisée).

## Hors périmètre (agents suivants)

Réutilisation du brief éditorial au scoring, régénération/migration des configs existantes
(95 slugs morts + kw génériques restent en base), dédup d'angles, preview du feed à la
config, état vide UI mobile.

## À valider post-merge (logs prod)

Mesure ex-ante non réalisée (part du corpus FR 7 j matchant ≥ 2 kw distincts de
« Présidentielle 2027 ») : à confirmer via les logs `veille.feed_scored` en staging pour
calibrer `VEILLE_FLOOR_MIN_KEYWORD_HITS` (2→3 si le feed reste bruité).
