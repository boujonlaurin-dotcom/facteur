# PR1 — Refonte « Ton Essentiel » : lettre du jour (backend) — Story 9.6

## Quoi

Remplace (à terme) la carte 5 articles par un **digest rédigé à références
inline** (maquettes 3a+3b). Cette PR livre tout le backend ; le mobile (PR2)
rendra la lettre quand `letter != null` et garde la carte actuelle en fallback.

- **Plan déterministe serveur** (`build_letter_plan`) : chapô = rank 1 (+2 si
  ≥4 picks) + picks sans thème ; rubriques = picks restants groupés par thème
  (max 3 × 1-2 picks, cas mono-thème multi-picks) ; footer = thèmes suivis non
  couverts (cap 4). Invariant : chaque pick référencé exactement une fois.
- **LLM** : `mistral-small-latest` (temp 0.35, max_tokens 700) via
  `EditorialLLMClient.chat_json(call_site="essentiel_letter")` — le LLM ne
  rédige que la prose avec marqueurs `[[n]]`.
- **Validation serveur** : comptage des marqueurs par bloc, pas de 1re
  personne, em-dash auto-réparé silencieusement, caps longueurs
  (chapô 120-360c, rubrique 60-200c, total ≤1000), pas de
  markdown/URL/emoji/`!`, pas de nom de source verbatim. 1 retry max avec bloc
  « CORRECTIONS OBLIGATOIRES », sinon pas de stockage.
- **Stockage** : table `essentiel_letters` (migration additive `el01`,
  idempotente, RLS deny-all pattern sec02, `UNIQUE(user_id, target_date,
  is_serene)`). La lettre stocke son snapshot des 5 picks ; seuls les flags
  is_read/is_saved/is_liked/is_dismissed sont réhydratés au serve (1 SELECT).
- **Router `/api/essentiel`** : lettre stockée → **servie en court-circuit**
  (le rebuild digest/re-rank/suppléments est entièrement sauté sur le chemin
  nominal post-08h ; 1 seul SELECT de statuts pour réhydrater le snapshot) ;
  absente et date du jour (hors fallback stale) → génération on-demand bornée
  8 s (seul l'appel LLM est sous timeout) ; dates passées lecture seule ;
  serein = variante on-demand cachée `(user, date, true)` ; tout échec →
  `letter=null`, réponse actuelle inchangée. Pas de feature flag.
- **Job nocturne 08h00 Paris** (digest 07h30, watchdog 08h15) : population =
  tous les UserProfile, variante pour_vous only, sessions courtes
  `safe_async_session`, `Semaphore(4)`, jamais de session ouverte pendant le
  LLM, purge 30 j, idempotent (skip si ligne existante), log résumé.

## Vérifié

- `pytest` : suite complète verte (dont 43 nouveaux tests lettre).
- `alembic upgrade head` sur DB vide : OK, exactement 1 head
  (`el01_essentiel_letters`), RLS activé vérifié via psql.
- uvicorn local : OpenAPI expose `EssentielLetter` + `letter` nullable dans
  `EssentielResponse` ; route protégée (403 sans token).
- ruff check + format sur tous les fichiers touchés.
- /simplify passé (4 agents) : court-circuit chemin chaud quand lettre stockée,
  helpers partagés extraits (`get_batch_action_states` digest↔lettre,
  `get_active_user_ids` digest↔lettre, `followed_themes_by_weight()` router↔job) ;
  re-run suite complète après refactor.

## ⚠️ Gate PO avant merge

Harnais d'éval : `cd packages/api && python scripts/eval_essentiel_letter.py
--runs 3` (nécessite `MISTRAL_API_KEY`, absent de ce workspace). Cible ≥95 %
pass après retry ; sinon escalade `model: mistral-large-latest` = 1 ligne
YAML. Relecture humaine du ton par Laurin sur les lettres imprimées par le
harnais.

## Hors scope (PR2 mobile, à suivre)

Modèles Dart + `EssentielLetterCard` (_SourcePill logo+↗ reader, _ThemePill
couleur+↘ scroll section avec garde-fou section absente, skeleton), fallback
`letter == null` → `EssentielHiFiCard`, changelog.json (l'impact user-visible
arrive avec PR2).
