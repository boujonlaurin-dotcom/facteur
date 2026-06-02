# QA Handoff — Flâner : onglets épinglés fiabilisés + modal simplifiée (v2)

> Itération v2 de la modal d'épinglage (suite PR #748). 1 bug + 3 évolutions UX
> + réduction des boutons filtre/recherche. Input de /validate-feature (Chrome 390×844).

## Feature développée
Fiabilise la barre d'onglets Flâner (les sujets/sources épinglés ne « disparaissent »
plus), supprime l'onglet « Tous », transforme le `+` en engrenage au-delà de 4 onglets,
et remplace les 2 listes « suivies » de la modal par 2 onglets (Sources / Sujets) avec
sujets à plat.

## PR associée
<!-- À compléter après /go : gh pr view --web -->

## Écrans impactés
| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Flâner (feed principal) | onglet Flâner | Modifié (barre d'onglets + boutons filtre/recherche) |
| Modal d'épinglage | `showPinSubjectsSheet` (bottom sheet) | Modifié (zone SUIVIS à 2 onglets) |

## Scénarios de test

### Scénario 1 : Happy path — épingler sources + sujets, tout reste visible
**Parcours** :
1. Ouvrir Flâner, taper l'engrenage/`+` pour ouvrir la modal.
2. Épingler 2-3 sources (onglet **Sources**) et 2-3 sujets (onglet **Sujets**).
3. Fermer la modal, observer la barre d'onglets.
**Résultat attendu** : tous les onglets épinglés (sources **et** sujets) sont visibles et
intercalés dans l'ordre, aucun ne « disparaît » derrière le fade de droite.

### Scénario 2 : Cap à 10 onglets
**Parcours** :
1. Épingler plus de 10 éléments au total (sources + sujets).
**Résultat attendu** : exactement 10 onglets dans la barre (les 10 premiers de l'ordre
utilisateur) ; le reste reste gérable dans la modal. Pas de crash.

### Scénario 3 : Tap onglet actif = retour non filtré
**Parcours** :
1. Taper un onglet **sujet** → le feed se filtre, l'onglet devient actif.
2. Re-taper l'onglet actif.
3. Idem avec un onglet **source**.
**Résultat attendu** : le feed redevient non filtré, aucun onglet n'est actif. La source
se désélectionne bien (régression historique `setSource(null)` corrigée).

### Scénario 4 : Affordance + / engrenage
**Parcours** :
1. Avec ≤ 4 onglets épinglés → observer l'icône en fin de barre.
2. Épingler jusqu'à > 4 onglets → ré-observer.
**Résultat attendu** : `+` quand ≤ 4 ; engrenage quand > 4. Dans les deux cas, le tap
ouvre la même modal d'épinglage.

### Scénario 5 : Modal — 2 onglets Sources / Sujets
**Parcours** :
1. Ouvrir la modal avec des sources suivies non épinglées **et** des sujets suivis.
2. Basculer entre les segments **Sources** et **Sujets**.
3. Taper une ligne pour l'épingler ; vérifier qu'elle remonte dans « ÉPINGLÉS ».
4. Tester la recherche (filtre l'onglet actif) et un onglet vide.
**Résultat attendu** : 2 segments fonctionnels ; sujets en liste à plat (emoji par ligne,
**plus d'en-têtes de thème**) ; épingler/dé-épingler + drag dans « ÉPINGLÉS » OK ;
placeholder muet (« Aucune source suivie » / « Aucun sujet ») si l'onglet actif est vide.

### Scénario 6 : Boutons filtre + recherche réduits
**Résultat attendu** : la loupe (recherche) et le bouton filtre sont légèrement plus petits
(34 px, icônes 16) ; l'espace horizontal libéré profite à la liste d'onglets. Aucun
chevauchement, alignement vertical correct.

## Critères d'acceptation
- [ ] N sources + M sujets (N+M ≤ 10) → tous visibles et intercalés dans l'ordre unifié.
- [ ] > 10 épinglés → exactement 10 onglets, surplus non perdu (modal).
- [ ] Aucun onglet « Tous ».
- [ ] Tap onglet actif (sujet ET source) → feed non filtré, aucun onglet actif.
- [ ] ≤ 4 onglets → `+` ; > 4 → engrenage (même action).
- [ ] Modal : 2 segments Sources/Sujets, sujets à plat, drag « ÉPINGLÉS » non régressé.
- [ ] Boutons filtre/recherche visiblement réduits, sans casser le layout.

## Zones de risque
- Cohérence **barre ↔ modal** : l'ordre des onglets doit suivre l'ordre validé par drag
  (prefs `pinned_tabs_order_v1`). Drag dans la modal → la barre reflète le même ordre.
- Réseau : `onTapActiveTab` enchaîne 4 `set*(null)` → potentiellement plusieurs refresh
  (trade-off connu, follow-up hors scope).

## Dépendances
- `tab_counts_provider`, `userInterestsProvider`, `userSourcesStateProvider`,
  `userSourcesProvider`, `tabOrderPrefsProvider` (SharedPreferences `pinned_tabs_order_v1`).
- Aucune modif backend / migration.
