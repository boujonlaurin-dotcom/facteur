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
