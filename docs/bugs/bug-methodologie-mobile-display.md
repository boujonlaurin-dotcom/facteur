# Bug — page `/methodologie` cassée sur mobile

## Symptômes rapportés

1. Les 3 barres "piliers" du hero (Rigueur / Transparence / Indépendance) débordent
   de leur encart, notamment les pastilles de points ("60 pts", "20 pts"...).
2. La révélation "critère par critère" (accordéon qui s'ouvre au scroll) n'est pas
   fluide sur mobile : fenêtre de lisibilité trop petite, scroll qui accompagne
   l'ouverture fait sortir le haut de la carte de l'écran.

## Contexte

La page publique `/methodologie` (PR #980, commit `20ce30ef`) est une page statique
(`apps/landing/public/methodologie.html` + `js/methodologie.js`, servie par nginx)
construite "desktop-first", très riche en effets scroll-liés. Elle n'a jamais été
adaptée au mobile : aucune media query `max-width` (juste `prefers-reduced-motion`).

## Root cause

- **Bug 1** : dans le bloc hero (`methodologie.html` lignes 93-136), les 3 lignes de
  piliers sont des flex-rows `align-items:center;gap:14px` **sans `flex-wrap`**.
  L'icône est `flex:none` (46px fixe), le libellé est `flex:1;min-width:0` (peut se
  réduire), mais la pastille de points (lignes 102, 110, 118) est en
  `white-space:nowrap` **sans `flex:none`** — contrairement à la pastille équivalente
  des cartes de critères plus bas (ex. ligne 162 `...white-space:nowrap;flex:none`)
  qui, elle, a le bon traitement. Résultat : sur mobile, la pastille se fait
  comprimer par flexbox (flex-shrink:1 par défaut) mais son texte ne peut pas
  s'enrouler (`nowrap`) → le texte déborde visuellement de sa pastille. Les 2e/3e
  barres (`width:64%`) sont en plus artificiellement plus étroites que la colonne
  parente déjà réduite sur petit viewport, ce qui aggrave le manque de place.

- **Bug 2** : `js/methodologie.js` (lignes 1-103) implémente un effet "scroll FX"
  maison en `requestAnimationFrame` + `getBoundingClientRect()` : un seul critère
  "focus" à la fois, déterminé par la distance entre le milieu de son en-tête et une
  ligne focale fixée à 42% de la hauteur de viewport, sans aucune hystérésis — dès
  qu'un autre critère devient marginalement plus proche de cette ligne, le focus
  bascule instantanément. C'est ce qui rend la fenêtre "lisible" trop petite et les
  transitions saccadées. Par ailleurs, perdre le focus déclenche l'effondrement de
  l'accordéon (`max-height:900px → 0`, ligne 53-54 du `<style>`), ce qui change
  réellement la hauteur du document ; si ça arrive alors que la carte est encore
  visible ou juste au-dessus du viewport, le contenu visible se décale brutalement
  vers le haut — c'est le "scroll automatique" ressenti par l'utilisateur.

  La page a déjà un filet de sécurité intégré : le JS n'active l'attribut
  `data-scrollfx` sur `<html>` que si `prefers-reduced-motion` n'est pas actif
  (ligne 9-10). Sans cet attribut, tout le CSS scroll-lié (lignes 47-62) ne
  s'applique pas : les critères s'affichent immédiatement, statiquement, pleinement
  dépliés et lisibles.

## Fix

### Fix 1 — barres piliers du hero (`methodologie.html`)

1. Ajouter `flex:none` aux 3 pastilles de points du hero, pour les aligner sur le
   traitement déjà correct des pastilles de critères.
2. Sortir la largeur `width:64%` des 2e/3e barres de leur `style` inline vers une
   classe `.pillar-bar--sub`, avec media query mobile qui la ramène à `100%`.

### Fix 2 — accordéon critère par critère (`js/methodologie.js`)

Désactiver l'effet scroll-lié maison sur mobile/tactile en réutilisant le filet de
sécurité déjà présent dans le code (état statique, tout déplié, sans animation) :
condition d'activation étendue avec `(pointer: fine)`, qui exclut les écrans
tactiles tout en gardant l'effet scroll-lié sur desktop/trackpad.

Fichiers modifiés : `apps/landing/public/methodologie.html`,
`apps/landing/public/js/methodologie.js` (cache-bust `?v=1` → `?v=2`).

## Vérification

Page statique sans dépendance backend pour ces sections. Vérifié via Playwright
Agent CLI en viewport mobile (390x844, émulation tactile) :

- Hero : aucun débordement horizontal / aucune pastille "pts" hors de son encart,
  aux largeurs 375px, 390px, 414px.
- Section "La grille" : `<html>` sans `data-scrollfx` en émulation tactile ; tous
  les critères (C1-C10) visibles et dépliés sans interaction de scroll.
- Non-régression desktop : viewport large + pointeur souris → `data-scrollfx`
  toujours actif, effet d'accordéon scroll-lié inchangé.
