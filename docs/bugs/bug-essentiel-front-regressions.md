# Bug — Régressions front Story 9.2 (PR #650)

**Date** : 2026-05-23
**Auteur** : Laurin (PO)
**Branch** : `boujonlaurin-dotcom/hotfix-essentiel-front-regressions`

## Symptômes (3 régressions remontées par le PO)

1. **Sticky bar** : PR #650 a remplacé la `StickyTabBar` à onglets (puce + label par section + soulignement + barre de progression dégradée) par un `StickyThreeStateBar` à 3 macro-blocs. Le PO veut la bar à onglets d'origine, mais avec une **icône check** à la place du `lineThrough` quand l'onglet est `isDone`.
2. **« Actus du jour » supprimée** : PR #650 a remplacé la `DigestTopicSection(kind: essentiel)` legacy par la nouvelle carte hi-fi `EssentielSection`. Le PO voulait **garder les deux** — la carte hi-fi prend désormais le nom « L'Essentiel du jour », et la section legacy est renommée « Actus du jour » et placée juste en dessous.
3. **UI de la carte hi-fi** : noms des thématiques vides (`article.sectionLabel == ""` côté backend), cachet de date trop discret, dividers trop sombres, fond du lead pas assez subtil.

## Plan de correction (1 PR vers `main`)

### Régression 1 — Sticky
- Restaurer `StickyTabBar` + `StickyHead` + `_TabsRow` + `_ProgressPainter` depuis `d1463c05:apps/mobile/lib/features/flux_continu/widgets/sticky_tab_bar.dart`.
- Modifier `_Tab` : remplacer `decoration: TextDecoration.lineThrough` (quand `isDone`) par une `Icon(Icons.check, size: 12)` à droite du label.
- Supprimer `StickyMacroBloc` enum, `StickyThreeStateBar`, `_currentMacroBloc`, `_updateMacroBloc`, `_onTapStickyBar` dans `flux_continu_screen.dart`.
- Restaurer `_tabsScroll`, `_isInExploreMode`, `_updateExploreMode`, `_alignTabsToActive`, `_scrollToSection` (gère `_explorerKey` comme dernier tab virtuel).
- Restaurer `_StickyHostOverlay` original (tabs + `tabsController` + `isInExploreMode` + `showFilterBar`).
- Retirer la `FeedFilterBar` injectée dans le scroll sous le banner Explorer (PR #650) : elle reprend sa place dans la sticky via `showFilterBar: true`.

### Régression 2 — « Actus du jour »
- Restaurer la constante `_kEssentielAccent` + nouveau champ `_actusDuJour` dans `FluxContinuNotifier`.
- Construire `_actusDuJour` via `_buildDigestSection(... kind: SectionKind.essentiel, label: "Actus du jour" ...)`.
- Ordre dans `_compose` (normal) : `_essentiel` (hi-fi) → `_actusDuJour` (legacy) → thèmes → `_bonnes`. Mode sérène : `_bonnes` → thèmes → `_essentiel` → `_actusDuJour`.
- **Collision de clé** : étendre `sectionKey()` pour matcher `EssentielSection` → `'essentiel_v3'` ; `DigestTopicSection(kind: essentiel)` reste sur `'essentiel'` (préserve les prefs `flux_continu_folded_*` existantes du PO).
- Test provider : vérifier que `_essentiel` (hi-fi) et `_actusDuJour` (legacy) coexistent quand les deux payloads sont présents.

### Régression 3 — Carte hi-fi
- a. **Fallback theme label** : dans `essentiel_hi_fi_card.dart`, remplacer les usages de `article.sectionLabel` par `_sectionLabelFor(article)` qui retombe sur `themeMap[article.theme]?.label ?? 'Actus'` quand le backend renvoie vide.
- b. **Pastille date** : diamètre 64 px, texte 2 lignes ("23" gros / "MAI" petit), fond `accent.withValues(alpha: 0.16)`, bordure 1.6 px.
- c. **Dividers** : `_Hairline` et `_DottedDivider` → `colors.border.withValues(alpha: 0.35)`.
- d. **Lead background** : `themeAccent.withValues(alpha: 0.06)`, bord gauche 3 px solide confirmé.
- e. **Overflow safety** : ellipsis garantie sur les noms de sources / titres déjà couverts.

> Bug backend séparé (à ouvrir) : `topic.label = ""` est rempli **après** la boucle dans `digest_selector.py:_build_topic_groups`. Tant qu'il n'est pas corrigé, le fallback front absorbe la régression visible.

## Validation
- `flutter pub get && flutter analyze` (0 erreur nouvelle).
- `flutter test test/features/flux_continu/` vert (test étendu pour `Actus du jour`).
- PR vers `main` avec body listant les 3 fixes.

---

## Vague 2 — 2026-05-23

Nouvelle remontée PO après le merge du hotfix #652 : l'UI reste éloignée de la maquette cible (`.context/attachments/ncGCVx/image.png`). Voir captures `.context/attachments/uzpxjS/image.png` (actuel) vs `.context/attachments/ncGCVx/image.png` (cible).

### Symptômes

1. Bandeau gris « ÉDITION DU [DAY] · 5 ACTUS À SUIVRE » au-dessus du titre — PO veut le remplacer par un sous-titre descriptif sous le titre.
2. Pastille de date inclinée (-0.05 rad) — la maquette la montre droite.
3. Fond du lead pris sur la couleur du THÈME de l'article (violet/bleu/etc selon le thème) — PO veut un ocre Essentiel uniforme.
4. Filets (`_Hairline`, `_DottedDivider`) toujours trop visibles à 0.35 alpha.
5. Noms thématiques absents ou parasités quand le backend renvoie un `section_label` non canonique (e.g. nom de source).
6. Bouton « Tout explorer » présent dans la maquette mais invisible (callback non câblé dans `section_block.dart`).

### Plan de correction (1 PR vers `main`)

- a. **Header** (`_Header`) : supprimer le texte gris `ÉDITION DU $dayLabel · 5 ACTUS À SUIVRE`. Ajouter sous le titre un sous-titre `Les 5 articles à ne pas manquer aujourd'hui, issus de tes préférences` (`FacteurTypography.bodySmall` sur `textSecondary`, `height: 1.35`, max 2 lignes). Nettoyer `_formatDayName()` devenu inutile.
- b. **Pastille date** (`_DateStamp`) : retirer `Transform.rotate(angle: -0.05, …)`. Le reste (diamètre 64, Courier Prime, 2 lignes, fond `accent@0.16`, bordure 1.6 px) reste identique.
- c. **Lead background** (`_LeadTile`) : le fond et le bord gauche utilisent `accent` (`colors.sectionEssentiel` ocre uniforme) au lieu de `themeAccent`. La `_SectionChip` conserve `themeAccent` pour rester thématique.
- d. **Dividers** (`_Hairline`, `_DottedDivider`) : opacité 0.35 → 0.20.
- e. **Fallback label** (`_sectionLabelFor`) : priorité inversée — `themeMap[article.theme]?.label` d'abord, puis `article.sectionLabel.trim()` non-vide, puis `'Actus'`. Garantit que les noms thématiques (Technologie, Environnement…) s'affichent dès que le slug `theme` est reconnu, même si le backend renvoie un label parasite.
- f. **Bouton « Tout explorer »** :
  - `section_block.dart` : nouveau paramètre `onTapExploreAll: VoidCallback?`, passé au constructeur de `EssentielHiFiCard` (lignes ~111-116).
  - `flux_continu_screen.dart` : nouvelle méthode `_exploreAllEssentiel(EssentielSection, int)` qui appelle `notifier.foldLocally(essentiel)` puis `_scrollToSection(essentielIndex + 1)` après un délai de 50 ms (laisse le fold se rendre). Wiring : `onTapExploreAll: section is EssentielSection ? () => _exploreAllEssentiel(section, i) : null`.

### Validation
- `flutter analyze` (0 warning nouveau).
- `flutter test test/features/flux_continu/` vert (les tests #652 ne doivent pas casser).
- E2E manuel Playwright MCP (390×844) : tap « Tout explorer » plie la carte ET scrolle vers « Actus du jour » ; tap « Passer » plie sans scroller.

### Hors scope (toujours)
- Backend `topic.label = ""` — fix backend séparé.
- Page dédiée full-screen Essentiel — non retenue, scroll vers Actus du jour préféré par le PO.
