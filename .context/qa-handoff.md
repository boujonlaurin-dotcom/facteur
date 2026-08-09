# QA Handoff — Navigation par swipe entre les articles d'une section (Story 34.1)

> Story : `docs/stories/core/34.1.navigation-swipe-articles-section.md`

## Feature développée

Depuis un article ouvert, glisser vers la gauche mène à l'article **suivant** de
la section, vers la droite au **précédent**, sans repasser par la liste. Le deck
porte la **liste complète** de la section (pas l'aperçu borné par
`coreVisibleCount`) : depuis la 2ᵉ carte affichée sur la Tournée, le swipe atteint
le 3ᵉ article, celui qui n'était visible qu'en passant par « Tout lire ».

## PR associée

[#1067](https://github.com/boujonlaurin-dotcom/facteur/pull/1067) → `main`

## Preview web

**https://boujonlaurin-dotcom.github.io/facteur/preview/swipe-nav/**

Build de la branche sur l'API staging, publié par `deploy-web-preview.yml` à
chaque push. La démo de `main` (`/facteur/`) n'est pas affectée : publication
additive (`destination_dir` + `keep_files`). La preview disparaît au prochain
push sur `main`, qui republie la racine sans `keep_files`.

## Écrans impactés

| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Deck d'articles (hôte du reader) | `/flux-continu/content/:id`, `/flaner/content/:id` | Nouveau (passe-plat si 1 seul article) |
| Reader | idem | Modifié (aperçu d'arrivée, barre segmentée, verrou WebView) |
| L'Essentiel (Tournée) | `/flux-continu` | Modifié (passe la section au tap) |
| Page section thème / sujet / veille | `/flux-continu/theme/:key` | Modifié |
| Page section source | `/flux-continu/source/:id` | Modifié |
| Page section digest | `/flux-continu/section/:key` | Modifié |
| Flâner | `/flaner` | Modifié (deck **sans** repère de position) |

## Scénarios de test

### Scénario 1 : Happy path — enchaîner la lecture d'une section
1. Ouvrir **L'Essentiel**, repérer une section qui n'affiche que 2 cartes et
   porte un « Tout lire ».
2. Taper la **2ᵉ** carte.
3. Glisser l'article vers la **gauche**.

**Résultat attendu** : on arrive sur le **3ᵉ** article de la section — celui qui
n'était pas affiché sur la Tournée. La transition suit le doigt : l'article
quitté part moins vite (parallaxe), s'assombrit et se rétrécit légèrement ;
l'article qui arrive glisse par-dessus avec des coins arrondis et une ombre
d'arête pendant le seul mouvement.

### Scénario 2 : Bornes de la séquence
1. Depuis le **1ᵉʳ** article d'une section, glisser vers la **droite**.
2. Depuis le **dernier**, glisser vers la **gauche**.

**Résultat attendu** :
- 1ᵉʳ article, tirage court → rebond, l'article revient en place.
- 1ᵉʳ article, tirage franc (> ~56 px de course) → une affordance
  « ← {nom de la section} » se révèle à gauche puis on **revient à la section**.
- Dernier article → la pile **résiste** : elle suit d'abord le doigt puis freine
  de plus en plus, plafonne à ~32 px de course, vibre au passage
  (`lightImpact`) et revient. Insister ne fait plus rien avancer — on reste sur
  le dernier article. **Jamais d'écran noir** : la bande découverte est le fond
  crème de l'app. Repère de recette : 40 px de doigt → ~8 px de décalage,
  320 px → ~28 px. Si la pile se **fige d'un coup**, c'est la régression.

### Scénario 3 : Repère de position (barre segmentée)
1. Ouvrir un article depuis une section de N articles.

**Résultat attendu** : la barre du header est découpée en **N segments** — les
articles déjà passés pleins (vert atténué), le courant **plein lui aussi** d'un
aplat clair que la progression de lecture vient assombrir, les suivants creux.
Sur **Flâner**, la barre reste la barre classique (non segmentée) : le feed est
ouvert, il n'y a pas de total à annoncer.

2. Aller jusqu'au **dernier** article de la section.

**Résultat attendu** : **plus aucun segment vide** — la barre est pleine de bout
en bout. C'est le signal de fin de séquence ; s'il reste une case creuse, c'est
le bug corrigé en v2.

### Scénario 4 : Un article entrevu n'est pas un article lu
1. Depuis un article, commencer un glissement vers la gauche **à mi-course**,
   puis relâcher pour revenir en arrière.
2. Revenir à la Tournée.

**Résultat attendu** : l'article voisin **n'est pas marqué « Lu »** et son
compteur d'ouverture n'a pas bougé. Pendant le geste, le voisin s'affiche en
« aperçu d'arrivée » (header + vignette + titre + squelette de corps).

### Scénario 5 : Retour et geste de bord
1. Depuis un article de deck, glisser vers la droite **depuis le bord gauche**
   (~24 px).
2. Taper la flèche ← du header.

**Résultat attendu** : les deux ramènent à la section. Attention : la zone de
swipe-back large (35 %) est volontairement réduite à la bande de bord sur les
articles ouverts en deck — c'est le prix du geste « précédent ».

### Scénario 6 : Lecture sur le site
1. Sur un article, scroller jusqu'à révéler la page du site (scroll-to-site).
2. Tenter de glisser horizontalement.

**Résultat attendu** : le swipe du deck est **gelé** — le geste horizontal
appartient à la page distante. Sortir du site (← du header) le réactive.

### Scénario 7 : Non-régression des ouvertures hors section
1. Ouvrir un article depuis une notification push / un deep link.
2. Ouvrir un article depuis **Sauvegardés** et depuis la modal Source.

**Résultat attendu** : reader **identique à avant** — pas de swipe horizontal,
barre de progression classique, swipe-back large (35 %) conservé.

### Scénario 8 : Flâner — retrouver le feed où la lecture s'est arrêtée
1. Dans **Flâner**, descendre de quelques cartes, en ouvrir une.
2. Enchaîner 3 ou 4 articles au swipe vers la gauche.
3. Sortir (flèche ← du header, geste de bord, ou back système).

**Résultat attendu** : le feed rouvre **sur l'article qu'on vient de lire**,
calé en haut de l'écran — pas sur celui qu'on avait tapé. Aucune animation de
défilement : la position est rendue, pas rejouée.

Cas limites à couvrir :
- sortir **sans avoir swipé** → le feed ne bouge pas d'un pixel ;
- revenir en arrière dans le deck jusqu'à l'article de départ, puis sortir → le
  feed ne bouge pas non plus ;
- article d'arrivée très bas dans le feed (6-8 swipes) → il doit quand même être
  atteint (la liste est paresseuse, l'app va le construire en descendant) ;
- ouvrir depuis un **carrousel** ou depuis « Explorer de nouvelles sources » →
  comportement inchangé, aucun repositionnement (ces cartes n'ont pas de place
  propre dans le fil).

## Critères d'acceptation

- [ ] Glisser à gauche → article suivant de la section ; à droite → précédent
- [ ] Le deck parcourt la liste **complète** (au-delà des cartes affichées)
- [ ] 1ᵉʳ article : seul le suivant est atteignable ; tirage franc à droite = retour
- [ ] Dernier article : seul le précédent est atteignable ; la pile résiste
      progressivement (pas de blocage sec), vibre, revient, sans écran noir
- [ ] Flâner : sortir du deck rouvre le feed sur l'article où la lecture s'est
      arrêtée ; sans swipe, le feed ne bouge pas
- [ ] Dernier article : la barre segmentée est pleine, aucun segment vide
- [ ] Transition fluide, sans saccade, sur une section de 8 articles
- [ ] Barre segmentée sur les sections, absente sur Flâner
- [ ] Un article entrevu n'est ni marqué « Lu » ni compté comme ouvert
- [ ] Aucune régression sur les ouvertures sans section

## Zones de risque

- **Arène de gestes** : deux recognizers horizontaux coexistent (bande de retour
  de la route + `PageView` du deck). Couvert par un test
  (`swipe_back_page_test.dart`), mais à revérifier au doigt sur device.
- **Fluidité du drag** : la page voisine est volontairement un aperçu léger, pas
  le reader complet. Si une saccade apparaît, c'est là qu'il faut regarder.
- **Android / platform views** : sur un article sans contenu in-app (webview
  pleine page), le platform view passe sous la transformation du deck. À vérifier
  visuellement sur Android.
- **Flutter web : le deck ne se glisse PAS à la souris.** Les `dragDevices` par
  défaut d'un `Scrollable` Flutter excluent `PointerDeviceKind.mouse` et l'app
  ne surcharge pas `ScrollBehavior` — un drag souris (réel ou Playwright) ne
  déplace donc jamais le `PageView`. C'est une limite du **rendu web**, pas un
  bug du deck : sur mobile (le vrai support) le geste est tactile.
  Pour tester la preview au navigateur, deux voies :
  1. **DevTools → Device toolbar** (mode responsive) : active l'émulation
     tactile, le glissement fonctionne à la souris ;
  2. **Playwright** : émuler le tactile puis envoyer les événements en CDP —
     `Emulation.setTouchEmulationEnabled` puis `Input.dispatchTouchEvent`
     (`touchStart` / `touchMove` × N avec ~16 ms entre chaque / `touchEnd`).
     Un `page.mouse.down()/move()` ne suffit pas.
  Autre piège : **ne pas activer la sémantique** avant de glisser — les nœuds
  DOM d'accessibilité posés au-dessus du canvas absorbent le geste. Sémantique
  pour lire l'écran (`snapshot`), rechargement sans sémantique pour gester.

## Dépendances

Aucune. Zéro changement backend, zéro migration Alembic. Un seul nouvel event
analytics : `article_swipe_nav`.
