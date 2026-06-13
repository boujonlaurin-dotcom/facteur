# QA Handoff — Modes d'affichage des articles (Story 10.1, finalisation)

> Rempli par l'agent dev. Input de /validate-feature.

## Feature développée
Différenciation réelle des 3 modes d'affichage (Normal / Minimaliste / Ludique) : le minimaliste révèle plus d'articles par section (le fit peut monter au-dessus du top 3 nominal, plafond 7) avec titres jusqu'à 5 lignes ; le ludique met l'image en élément principal (pleine largeur en haut de carte, hauteur fixe 170, fontScale 1.05, titres 3 lignes). Bonus : le CTA « Tout lire » de bas de section est remplacé par un banner cliquable (chevron accent + « +X » gris dans le titre) et les chips de thème des tuiles de l'Essentiel sont retirées.

## PR associée
À créer via /go (base main).

## Écrans impactés
| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Tournée (Flux Continu) | / (home) | Modifié (cartes, banners, fit) |
| Profil → Affichage des articles | /profile (bottom sheet) | Existant (sélecteur de mode) |
| Page thème / source (deep-dive) | /flux-continu/theme/:key | Modifié (accès via tap banner) |
| Flâner (banner large) | page Flâner | Inchangé attendu (pas de chevron) |

## Scénarios de test

### Scénario 1 : Mode minimaliste — plus d'articles
**Parcours** :
1. Profil → « Affichage des articles » → Minimaliste → valider
2. Revenir sur la Tournée
**Résultat attendu** : cartes texte seul compactes ; les sections (Bonnes Nouvelles incluse) affichent plus de 3 articles si l'écran le permet (jusqu'à 7) ; titres longs jusqu'à 5 lignes ; aucune carte ne déborde de l'écran (filet `[fit-net]` silencieux).

### Scénario 2 : Mode ludique — image en haut
**Parcours** :
1. Profil → « Affichage des articles » → Ludique → valider
2. Parcourir la Tournée
**Résultat attendu** : cartes régulières avec image pleine largeur en haut (type carrousel) et texte dessous ; textes à peine plus gros que Normal (1.05) ; titres max 3 lignes ; badge play conservé sur les vidéos ; hero Essentiel inchangé structurellement.

### Scénario 3 : Carte ludique avec image cassée (cas d'erreur)
**Parcours** :
1. En mode ludique, trouver un article dont la vignette 404 (ou couper le réseau après le 1er rendu)
**Résultat attendu** : la carte retombe sur le layout texte standard (pas d'espace vide de 170px, pas d'image grise cassée).

### Scénario 4 : Banner cliquable (Bonus 1)
**Parcours** :
1. Sur la Tournée, taper le banner d'une section thème, source, veille, Actus du jour et Bonnes Nouvelles
2. Taper l'étoile favorite d'une section favorite, puis le bouton réglages (tune) de la veille
**Résultat attendu** : tap banner → ouvre la page « tout lire » de la section ; chevron « > » fin couleur accent après le titre + « +X » gris si articles cachés ; plus aucun bouton « Tout lire » en bas de section ; l'étoile ouvre « Composer ma Tournée » (pas la navigation) ; le tune ouvre la config veille ; le banner large de la page Flâner n'a ni chevron ni tap.

### Scénario 5 : Essentiel allégé (Bonus 2)
**Parcours** :
1. Observer la carte « Ton Essentiel » (lead + médiums)
**Résultat attendu** : plus de balises de thème (« Technologie », etc.) sur les tuiles ; le badge « Actu du jour » reste sur le lead concerné ; les tuiles médiums montrent source + titre.

## Critères d'acceptation
- [ ] Minimaliste : > 3 articles/section sur écran standard ; titres 5 lignes max
- [ ] Ludique : image pleine largeur en haut, fontScale 1.05, titres 3 lignes, fallback image cassée
- [ ] Banner cliquable sur les 5 types de sections, chevron + « +X », étoile/tune indépendants
- [ ] Plus de bouton « Lire plus » en bas des sections
- [ ] Plus de chips de thème dans l'Essentiel
- [ ] Aucun débordement de carte dans les 3 modes (logs `[fit-net]` propres)

## Vérifications déjà faites (dev)
- `flutter analyze` : 0 erreur.
- `flutter test test/features/flux_continu/ test/features/settings/` : 245/245 verts.
- Suite complète : retour exact à la baseline (23 échecs pré-existants Hive/Supabase, hors périmètre).
