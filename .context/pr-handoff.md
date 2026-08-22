# PR — feat(mobile): Reader « Analyse des angles (6C) » — front (Story 35.3)

## Quoi

Le Reader câble enfin le contrat 6C livré par #1109 (`consensus` + `display`
sur `GET /contents/{id}/perspectives`), mobile-only :

- **CTA haut d'article** « Comparer les {N} angles » (nouveau
  `consensus_widgets.dart`) : pile de logos, constats du bloc `cta` (accord ✓ /
  désaccord ⇄), variantes solo / pending / bare, fade-in sans skeleton. Tap →
  scroll animé 620 ms vers la section + haptique + flash orangé one-shot.
- **Section basse refondue** : header « Analyse des angles ({qualificatif
  backend}) », ordre constats → footnote (égalité / sablier) → barre de biais →
  « {N} médias en parlent » → carrousel ; badge POLARISÉ supprimé du Reader
  (« polarisé » n'apparaît qu'une fois) ; carte « Analyse complète IA » en
  **fin** de carrousel (décision PO 22/08) ; encart solo sans cloche.
- **Data layer** : `ConsensusBlock` / `DisplayGates` (gates appliquées sans
  re-dérivation ; `hidden()` sur les chemins d'erreur → une erreur réseau ne
  produit jamais l'encart « seule rédaction » ; fallback
  `fromCoverageCount` = table backend si vieux backend) ;
  `analyzePerspectives` structuré avec `throttled` → état sheet dédié
  (message seul, sans « Réessayer »).

## Pourquoi

L'analyse LLM payée chaque matin partait dans le JSONB `daily_digest` pendant
que le Reader interrogeait une table vide. #1109 a livré la persistance et
l'exposition ; cette PR affiche enfin ces constats à l'utilisateur, selon le
design gelé « Reader consensus 6C export » (`ReaderPhone6C`).

## Comment ça a été vérifié

- [x] `flutter analyze` : 0 nouveau warning sur les fichiers touchés.
- [x] Tests ciblés : 27 parsing repo + 21 consensus_widgets + 11 états inline
      + 6 overflow + 4 intro + 3 animation + 3 sheet throttled + 3 reader
      in-app — verts.
- [x] Suite mobile complète : 2556 pass / 25 fail, tous pré-existants
      (baseline ~26-27 : stubs notification, bookmark, feed_sources…).
- [x] Contrat live `verify_consensus_contract.sh` (uvicorn + facteur_test
      54322 + compte QA) : nominal available/polarized (3 accords + 2
      désaccords), pending sans qualificatif, solo `is_solo`, stabilité cache
      x2 — OK.
- [x] `/simplify` passé (corpus refs 1x/build, param `divergenceLevel` mort retiré).
- [x] Smoke Playwright (build web local branché sur staging, compte QA,
      390x844) : article réel 13 sources → CTA haut « Comparer les 13
      angles » (pile de logos + ligne sablier pending), tap CTA → scroll
      animé jusqu'à la section ; section : footnote pending, barre de biais
      Gauche/Droite AU-DESSUS du carrousel, « 13 médias en parlent »,
      cartes ; 1 seul GET perspectives par article ; aucun 4xx/5xx ni erreur
      console imputable à la feature (404 `/veille/config` + proxys d'images
      pré-existants). Carte IA en fin + tap « Lancer » couverts par widget
      tests (drag canvas non simulable via le CLI).
- [ ] QA web complète (`/validate-feature`, handoff : `.context/qa-handoff.md`).

## Zones à risque

- `content_detail_screen.dart` (zone Router/Reader) : insertion du CTA dans
  les deux branches de layout + factorisation des deux blocs
  `PerspectivesInlineSection` — aucun appel réseau ajouté (fetch partagé).
- Cohabitation brève possible « Recherche en cours… » (partial) × footnote
  sablier (pending) — acceptée (plan §8).
- `display_domains` personnalisés par user : jamais mis en cache au-delà de la
  session (résolution à chaque build depuis la réponse).
- **Gate PO restant** : dry-run copy `scripts/dryrun_consensus.py --tag 6c-pr1`
  (~20 appels mistral-large, read-only) — non exécutable depuis ce workspace
  (pas de MISTRAL_API_KEY / DATABASE_URL applicatif). À lancer côté PO.
