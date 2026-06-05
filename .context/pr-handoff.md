feat(flux-continu): rendre le snap *lisible* — signifiants feedforward (A1+A2+A3)

## Quoi

Le scroll-snap section-par-section frustrait certains users (« coupé dans mon
geste », mouvement « subi » et imprévisible). Diagnostic : **la mécanique du snap
est bonne** — c'est un manque de *lisibilité*. On ajoute des **signifiants**, sans
toucher à la physique ni à une seule constante de tuning.

- **A1 — Feedforward pendant le drag.** Le `_SectionPassageDot` existant (déjà à
  chaque frontière, déjà porteur du pulse de validation) **grossit/brille à
  l'approche du bord**, pic pile au seuil de bascule (`kSectionEdgeMargin`). Le
  même dot fusionne désormais feedforward (avant) + feedback (pulse après) →
  lecture « j'approche un seuil → je l'ai franchi », un seul cue continu.
- **A2 — Progress track *segmenté*.** Le track 4 px passe d'un dégradé continu à
  **un pip par section** (fait rempli-désaturé / courant éclairé+glow / à venir
  gris), piloté par `activeIndex` (même source que les checks d'onglets) → modèle
  mental « pages » cohérent avec le snap discret.
- **A3 — Signifiant « carte haute = lecture libre ».** Les sections plus hautes
  que l'écran (qui autorisent un scroll libre *silencieusement*) reçoivent un
  **fade bas subtil** (`backgroundPrimary` → transparent, 24 px), peint par
  l'écran (zéro modif de signature `SectionBlock`).

## Pourquoi

Décision PO (5 juin 2026) : garder le snap, le rendre lisible — priorité au
« coupé dans mon geste ». Le défaut était l'absence de **feedforward** : tout le
feedback existant (`_SectionPassageDot`, track, haptique) était *post-hoc*.

## Comment c'est construit (anti-duplication)

- **Une seule source de vérité** : `snapPointsOf(List<SectionFrame>)` extrait de
  `resolveSnapTarget` (comportement strictement inchangé) — la rampe visuelle de
  A1 ramène donc *exactement* aux offsets où le snap commit.
- Tout s'accroche à l'infra existante : listener `_onScroll`, anchors
  `_snapAnchors`, `ValueNotifier` (rebuilds ciblés, **zéro `setState`/frame**).
- Mapping direction `ScrollDirection → ±1` factorisé (`_travelDirection`) et
  partagé entre le feedforward (A1) et la physique → impossible qu'ils
  divergent.
- Hot path propre : snap points **cachés une fois par layout** (plus de
  re-`sort()` par frame) ; lookup dot via `Map<double,int>` exact (offsets
  bit-identiques aux frame tops) ; proximity quantizée (~20 paliers) ; merged
  `Listenable` du dot mis en cache.
- **Nettoyage** : la prop `progress` continue de `StickyTabBar` + le
  `ValueNotifier _scrollProgress` (écrit chaque frame) sont supprimés — le track
  segmenté n'a besoin que de `activeIndex`.

## Comment ça a été vérifié

- [x] `flutter analyze` — **clean** (lib/features/flux_continu + tests modifiés).
- [x] `flutter test test/features/flux_continu/` — tous verts **sauf** 1 échec
      **pré-existant hors-scope** (`section_block_test.dart` ne compile pas :
      `onTapArticle: (_, __)` vs signature 1-arg de `SectionBlock`, inchangé vs
      `origin/main`, dernier touché par #785).
- [x] Tests ajoutés : `snapPointsOf()` (frames canon ⇒ `{0,300,600,1200}`,
      single-point, vide, + « tout target commit ∈ snapPointsOf ») ; les tests
      `resolveSnapTarget` existants **restent verts** (preuve de non-régression de
      la physique). Track A2 : capture image + sampling pixels (1 fait + 1
      courant remplis / 1 à venir muté ; un segment à-venir se remplit quand il
      devient courant).
- [ ] Validation device/feel : à confirmer par le PO (le « grain » du snap se
      juge sur device ; aucune constante de physique n'a bougé).

> CI = backend pytest only (pas de `flutter test`) → l'échec mobile pré-existant
> ne bloque pas la CI.

## Zones à risque

- `flux_continu_screen.dart` (Router/scroll feature, fichier central) : aucune
  modif de `_SectionSnapPhysics`, `resolveSnapTarget`, ni des constantes de
  tuning. Changements additifs (notifiers + overlay) sur l'infra existante.
- A3 (`_FreeReadEdgeFade`) = ligne de coupe nette ; son absence ne créerait
  aucune incohérence (la lecture libre est silencieuse aujourd'hui).
