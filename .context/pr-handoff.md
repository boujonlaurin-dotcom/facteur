# perf(essentiel): cold start « héros d'abord » — ordre de chargement revu

## Contexte

Suite de #1097 (gzip + émission anticipée du héros + loader vélo). Demande PO :
un diagramme vulgarisé du cold boot (diagnostic) + revoir l'ordre des appels
pour privilégier au maximum la carte « Ton Essentiel » (elle retient désormais
l'utilisateur 15-20 s de tri → le reste a un budget de temps naturel), et rendre
smooth le chargement des cartes suivantes quand un utilisateur « rush » la carte
héros sans trier.

Doc (diagnostic + diagrammes avant/après + protocole de mesure) :
`docs/maintenance/maintenance-cold-start-load-order.md`.

## Ce que fait la PR

- **Instrumentation `[PERF]`** : `gate_ms`, `essentiel_dispatch/resolved_ms`,
  `hero_emit_ms`, `phase1_ms`, `fanout_done_ms tasks=N dropped=M` (provider) +
  `hero_paint_ms` (écran, LA métrique avant/après).
- **B0** — le squelette rend la **vraie carte héros interactive** (triable) dès
  que `/api/essentiel` répond, au lieu d'un placeholder statique qui attendait
  la Phase 1 (= `/api/digest/both`, le plus lourd des 3 appels de base).
- **C1** — squelette **scrollable** (clamping, sans snap), contrôleur partagé :
  le flip Phase 1 conserve l'offset d'un « rusher ».
- **B1** — `_fetchAll` en **3 vagues** : `/api/essentiel` seul (vague 1) →
  digest/both + top-thèmes + kick des providers de coquilles à
  `min(essentiel résolu, 600 ms)` (vague 2) → listeners réseau différés +
  réconciliation de placement après la Phase 1 (vague 3, avec filet dans le
  `finally` de `build()` pour le chemin d'erreur, et armement post-gate sur le
  chemin warm).
- **B2** — fin des **initialisations furtives** : `_peekValue`
  (`ref.exists` + `read`) aux sites de composition squelette/compose ; attente
  bornée (2 s) des prérequis avant le seed des coquilles — corrige la course
  silencieuse de `_pickFavorites`.
- **B3** — fan-out Phase 2 dans l'**ordre d'affichage** (ordre custom sticky,
  biais thème suivi, ordre par score gelé, quota) ; suggestions hors du cap
  affiché **non fetchées** (+1 de réserve pour `dismissSuggestion`).

Mobile only — aucune migration, aucun backend.

## Coût assumé

`phase1_ms` peut prendre jusqu'à +600 ms (tête d'avance du héros), pendant
lesquels l'utilisateur a déjà sa carte à trier.

## Tests

- Nouveaux : `flux_continu_cold_start_waves_test.dart` (séquence des vagues,
  annexes jamais initialisés en vague 1, tête d'avance bornée à 600 ms, ordre
  de fetch = ordre d'affichage, cap suggestions +1 réserve),
  `flux_continu_skeleton_hero_test.dart` (contrat B0/C1 du squelette).
- MAJ : `flux_continu_provider_test.dart` (la structure du squelette arrive au
  seed Phase 1, plus à la 1ʳᵉ peinture), helper `settle` (le bootstrap contient
  désormais de vrais timers → attente temps réel bornée).
- Intouchés et verts : `flux_continu_block_score_order_test.dart`,
  `essentiel_placement_sync_test.dart`, `flux_continu_hero_skeleton_test.dart`.

## Étape droppée

Étape 5 du plan (cache local des noms de coquilles, marquée optionnelle) :
non implémentée — le squelette d'avant-gate reste générique chez un utilisateur
aux providers non résolus, comme le cold start historique.
