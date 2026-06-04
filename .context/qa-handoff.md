# QA Handoff — Polish UX/UI « l'Essentiel » (Flux Continu)

> Rempli par l'agent dev. Input de `/validate-feature` (Chrome 390×844).

Branche : `boujonlaurin-dotcom/essentiel-ux-scroll-haptics`
Écran : **l'Essentiel** (Flux Continu) — `apps/mobile/lib/features/flux_continu/`

3 ajustements UX/UI livrés en une PR. **Point 1 (haptique/snap) = validation device réel
obligatoire** (non simulable en web). Points 2 & 3 testables via Chrome (viewport 390×844).

---

## Point 1 — Snap « jamais sauter une section » (one-step cap)

**Changement** : `resolveSnapTarget` (`utils/section_snap.dart`) borne désormais la cible du snap
au **point d'ancrage adjacent à la position de lever de doigt** (`currentPixels`), plus au
*naturalLanding* du fling. Quelle que soit la force du geste, on n'avance/recule que d'**une**
section → un seul flip d'onglet actif → **un seul haptique** par pas.

### Scénarios (device réel)
- **Happy path** : scroller fort vers le bas → on ne descend que d'**une** section à la fois ;
  enchaîner des scrolls rapides descend toute la tournée, un buzz net par pas.
- Idem vers le haut (remonter une section par geste).
- **Lecture libre conservée** : au milieu d'une section plus haute que l'écran, le scroll reste
  libre (pas de snap), snap uniquement aux bords (haut/bas de section).
- **Edge** : fling très violent depuis le haut → ne saute pas 2-3 sections, s'arrête à la suivante.
- **Edge** : petit nudge (< 120 px d'inertie) → re-cadre la section courante (pull-back), pas de
  switch.
- **Edge bas de tournée** : sous « Fin de tournée », le rebond natif iOS reste propre (pas de
  rebonds étagés / buzz répétés).

> Si un fling très fort vers une cible proche dépasse légèrement : 1er levier = `kSectionEdgeMargin`
> (120 px) ; 2e levier = caper la `velocity` transmise au spring dans `_SectionSnapPhysics`.

## Point 2 — Désaturation de la progress bar (sticky header)

**Changement** : `sticky_tab_bar.dart` — les 4 stops du dégradé saturés (rouge/orange/bleu/teal)
remplacés par des tons **neutres/pastel** (rose poussiéreux → ocre doux → bleu ardoise → sauge) ;
halo passé de alpha 0.35 → 0.10.

### Scénarios (Chrome 390×844)
- Scroller jusqu'à révéler le sticky header → la barre de progression doit être **nettement plus
  discrète** (ne tire plus l'œil), tons neutres.
- Vérifier la progression (le remplissage suit toujours le scroll, valeur inchangée).
- Comparer light/dark si possible.
- *(Valeurs facilement ajustables si encore trop/pas assez visibles.)*

## Point 3 — Suppression complète du fold

**Changement** : retrait total de la mécanique de repli des sections (repli auto scroll-past +
chevrons manuels). Fichier `folded_section_card.dart` supprimé ; champs `folded`/
`markedForNextSession` retirés du state ; chevron `expand_less` retiré de la bannière.

### Scénarios (Chrome 390×844)
- Plus **aucun chevron** de repli sur les bannières de section.
- Les sections restent **toujours déployées**, même après avoir tout lu / scrollé au-delà /
  rouvert l'écran.
- **Non-régression à vérifier intactes** :
  - « Voir plus » / « Voir tout » (overflow des sections) fonctionne.
  - Carte de clôture « Fin de tournée » présente et ses CTA (Continuer / Refermer).
  - Swipe-dismiss d'un article + feedback inline.
  - Étoile favori (bannières thème) + bouton réglages (section veille) toujours tappables.

---

## Critères d'acceptation
- [ ] (device) 1 geste = 1 section + 1 haptique, dans les deux sens ; lecture libre intra-section OK.
- [ ] Progress bar désaturée, discrète, progression correcte.
- [ ] Zéro chevron / repli ; sections toujours ouvertes ; « Voir plus » + clôture + swipe intacts.
- [ ] Console sans erreurs, réseau sans 4xx/5xx inattendus.

## État technique
- `flutter analyze` : propre sur flux_continu.
- Tests unitaires : `section_snap_test` (15/15), `flux_continu_models_test`,
  `section_banner_favorite_test` verts. `flux_continu_provider_test` échoue en local
  (Hive/Supabase non-init — pré-existant) ; pas de régression (baseline 25 échecs, idem env).
- Build APK debug : OK.
