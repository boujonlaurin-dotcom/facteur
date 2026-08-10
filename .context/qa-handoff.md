# QA Handoff — Retouches carte « Ton Essentiel » triable (Story 33.1, itération PO)

> Rempli par l'agent dev. Input de /validate-feature (Playwright Agent CLI, viewport 390×844, sémantique activée).

## Feature développée
6 retouches de la carte « Ton Essentiel » triable au swipe : fix du swipe qui se
fige (priorité), carte qui épouse son contenu (fin du grand vide), images bien
plus grandes, skeleton « cartes » visible au chargement, « Plus d'articles » au
tri terminé (réinjecte le carrousel du jour), retrait de la pastille « X nouveaux
articles ». Mobile-only, aucun changement backend.

> **MAJ passe PO 09/08** — « Plus d'articles » est de nouveau **gaté**, cette fois
> à **3 gardés minimum** (`kTriageMoreArticlesMinKept`). La note « le gate a été
> retiré » qui figurait ici est annulée. S'ajoutent : la carte ne se réduit plus
> jamais à son en-tête, la pile ne tressaute plus au swipe, le pied de tri passe
> en deux boutons pleine largeur, la liste des gardés devient homogène, et la
> description de la carte change. Scénarios 16 à 20 ci-dessous.

## PR associée
À créer via /go (`--base main`).

## Écrans impactés
| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Flux Continu — carte héros « Ton Essentiel » | `/` (home) | Modifié |
| Skeleton du héros au chargement | `/` (fenêtre de loading) | Modifié |

## Scénarios de test

### Scénario 1 : Swipe increvable (happy path, PRIORITÉ)
**Parcours** :
1. Ouvrir l'app sur la Tournée du jour (carte « Ton Essentiel » en pile à trier).
2. Trier les 5 articles **au swipe seul**, rapidement, en alternant gauche/droite.
**Résultat attendu** : chaque swipe fait avancer à l'article suivant ; aucune
carte ne se fige ni ne reste « grisée » hors écran ; l'index avance à chaque
décision jusqu'à la fin du tri. Le bouton « Je garde » ne doit jamais être requis
pour « débloquer » une carte.

### Scénario 2 : Swipe pendant l'anim de sortie + swipe vs long-press
**Parcours** :
1. Glisser une carte pour la faire sortir, puis tenter un 2ᵉ geste pendant l'anim.
2. Sur une carte, faire un appui long (aperçu) puis un glissé horizontal.
**Résultat attendu** : le 2ᵉ geste pendant l'anim est ignoré (une seule décision).
L'appui long ouvre l'aperçu ; un glissé horizontal n'ouvre jamais l'aperçu sous le
doigt (l'arène départage bien swipe vs long-press).

### Scénario 3 : La carte épouse son contenu (fin du vide)
**Parcours** :
1. À « 0 sur 5 triés », observer la zone sous la barre d'actions.
2. Garder des articles un à un et observer la croissance.
**Résultat attendu** : plus de grand vide (~256px) sous « 0 sur N triés ». La
kept-list grandit **en douceur vers le bas**, sous la barre d'actions (la zone
progression + carte + actions ne saute pas sous le doigt).

### Scénario 4 : Images grandes + skeleton visible
**Parcours** :
1. Recharger avec le réseau throttlé (DevTools) pour voir la fenêtre de chargement.
2. Observer la carte une fois chargée.
**Résultat attendu** : au chargement, un skeleton en shimmer **qui lit comme des
cartes** (pile de 2 cartes décalées, grande image + lignes de titre). Une fois
chargée, l'image de chaque carte de tri est nettement plus grande (~format 16:9),
sans saut de layout à l'hydratation.

### Scénario 5 : pied de fin de tri (« Trier à nouveau » + « Plus d'articles »)
> Remplacé par les scénarios **18** et **19** (passe PO 09/08) : le pied a changé
> de forme (deux boutons pleine largeur) **et** « Plus d'articles » est gaté à 3
> gardés. Ne pas tester la version décrite ici.

### Scénario 6 : Retrait du badge
**Parcours** :
1. Sur la carte héros, chercher une pastille « X nouveaux articles » près du titre.
**Résultat attendu** : plus aucune pastille « N nouveaux articles ».

---

## Passe pré-prod « design » (07/08) — scénarios additionnels

### Scénario 7 : boot à froid, l'attente ressemble au contenu (PRIORITÉ)
**Parcours** :
1. Vider le stockage local, throttler le réseau (DevTools), recharger.
2. Observer **sans cligner** la carte « Ton Essentiel » entre le chargement et
   l'arrivée de la pile.
**Résultat attendu** : on voit la **silhouette de la pile** (progression + pile de
2 cartes + barre d'actions : 2 ronds puis une pilule large), puis **directement**
la vraie pile. À aucun moment l'ancienne liste passive (gros article + petits
titres) ne doit apparaître, même une fraction de seconde. Idem sur un rechargement
« tiède » (snapshot déjà en cache).

### Scénario 8 : la carte du dessous ne bouge plus, et n'est jamais pré-tamponnée
**Parcours** :
1. Glisser lentement la carte du dessus vers la droite, sans lâcher, puis lâcher.
2. Répéter vers la gauche.
**Résultat attendu** : la carte du dessous **grandit progressivement** pendant le
geste et est déjà à sa taille pleine quand elle devient carte du dessus (aucun
« claquement », aucune carte « légèrement décalée » qui saute). Elle n'est pas
rognée en haut ni en bas. Aucun tampon (« JE GARDE » / « PAS POUR MOI ») n'est
visible sur la carte fraîche qui arrive.

### Scénario 9 : article sans image
**Parcours** :
1. Trier jusqu'à tomber sur un article sans vignette (ou couper les images).
**Résultat attendu** : **aucun aplat gris** en tête de carte. La carte est plus
courte, son titre s'étale sur plus de lignes, et la barre d'actions **glisse**
vers le haut (transition animée), elle ne saute pas sous le pouce.

### Scénario 10 : tampons lisibles sur photo
**Parcours** :
1. Glisser une carte **avec image** dans chaque direction, mi-course.
**Résultat attendu** : le tampon est un **aplat plein** (orange « JE GARDE » /
gris très foncé « PAS POUR MOI ») avec texte **blanc**, lisible par-dessus la
photo. Plus de contour vide.

### Scénario 11 : coche « suivie » / étoile « favorite »
**Parcours** :
1. Mettre une source en favori et une autre en « suivie » depuis Mes intérêts.
2. Revenir sur la Tournée et trier jusqu'à voir ces sources.
**Résultat attendu** : à droite du nom de source, une **étoile pleine** pour un
favori, une **coche** pour une source suivie ; rien pour une source neutre. Même
signal sur les lignes des articles gardés, sous la pile.

### Scénario 12 : plus aucun compteur
**Parcours** :
1. Parcourir tout le tri, du début à la fin.
**Résultat attendu** : plus aucun libellé « N sur M trié(s) » nulle part, ni dans
la carte ni dans le squelette de chargement. La barre de progression segmentée est
le seul indicateur d'avancement.

---

## Reprise E2E PO (08/08) — scénarios additionnels

> Les trois défauts ci-dessous avaient été déclarés corrigés sur la foi de tests
> verts, alors qu'aucun ne l'était à l'écran. **À vérifier dans l'app qui
> tourne**, pas sur un test.

### Scénario 13 : la barre de progression est SOUS les boutons (PRIORITÉ)
**Parcours** :
1. Ouvrir la Tournée du jour, pile de tri active.
**Résultat attendu** : l'ordre vertical est **carte → boutons (✕ · signet · « Je
garde ») → barre de progression segmentée → articles gardés**. Plus rien
au-dessus de la carte. Même ordre pendant le chargement (silhouette).

### Scénario 14 : la carte épouse le contenu réellement affiché (PRIORITÉ)
**Parcours** :
1. Trier plusieurs articles d'affilée : alterner titres courts / longs, avec et
   sans image.
**Résultat attendu** : aucune carte ne montre de **blanc interne** entre le titre
et la ligne du bas (polarisation / « N sources ») — la méta est collée sous le
titre. Une carte à titre court est visiblement **plus basse** qu'une carte à titre
long. La barre d'actions **glisse** (transition animée) d'une hauteur à l'autre,
elle ne saute pas sous le pouce. Une carte ne dépasse jamais l'écran.

### Scénario 15 : plus jamais de carte vide (PRIORITÉ)
**Contexte** : l'aplat beige rapporté en E2E n'était pas une attente, c'était un
état cassé — le slate figé du jour désignait un article que la carte ne pouvait
plus résoudre (typiquement un article ajouté la veille par « Plus d'articles » :
le carrousel n'est pas rejoué à l'hydratation depuis le cache).

**Parcours (repro dirigée)** :
1. Trier partiellement, taper « Plus d'articles », **ne pas** finir le tri.
2. Tuer l'app, la relancer (cold boot, cache chaud).
   *Variante web* : avant rechargement, éditer dans `localStorage` la clé
   `flutter.essentiel_triage_v1_<dayKey>` et remplacer un `content_id` du
   `slate` par une valeur bidon, puis recharger.
**Résultat attendu** : **jamais** d'en-tête « Ton Essentiel » seul au-dessus d'un
aplat de fond. Au pire une **silhouette de pile** le temps d'une frame, puis le
tri reprend sur le premier article réellement disponible ; la barre de progression
ne compte plus l'article fantôme. Le tri déjà fait n'est pas perdu.

### Critères d'acceptation additionnels
- [ ] Progression rendue **sous** les boutons (pile réelle **et** silhouette).
- [ ] Aucune carte avec du blanc interne ; hauteur qui suit le contenu ;
      barre d'actions qui glisse au lieu de sauter.
- [ ] Slate périmé → silhouette puis reprise automatique, jamais de carte vide.

---

## Passe PO 09/08 — scénarios additionnels

### Scénario 16 : jamais l'en-tête seul (PRIORITÉ)
**Parcours** :
1. Vider le stockage local **et** IndexedDB, recharger, se connecter.
2. Regarder la carte « Ton Essentiel » **pendant** tout le chargement, sans
   cligner. Refaire sur un rechargement « tiède » (snapshot déjà en cache).
**Résultat attendu** : à aucun instant la carte ne se réduit à son en-tête
au-dessus du vide. On voit soit la **silhouette de la pile** (deux cartes
esquissées + barre d'actions + progression), soit du contenu. Jamais rien entre
les deux.

### Scénario 17 : la pile ne tressaute plus (PRIORITÉ)
**Parcours** :
1. Enchaîner **5 swipes** en alternant gauche/droite, en incluant au moins une
   carte **sans image** (nettement plus courte) suivie d'une carte **avec image**.
**Résultat attendu** : la carte promue ne bouge pas autrement qu'en montant en
échelle et en opacité. La barre d'actions **glisse** d'un seul mouvement continu
vers sa nouvelle position — pas de temps d'arrêt suivi d'un saut, pas de
va-et-vient. La liste des gardés grandit sans à-coup.

### Scénario 18 : gate « Plus d'articles » à 3 gardés
**Parcours** :
1. Trier les 5 articles en n'en gardant que **2** (« Je garde » ou « Plus tard »).
2. Observer le pied. Puis « Trier à nouveau » et recommencer en gardant **3**.
**Résultat attendu** : à 2 gardés, **aucun** bouton « Plus d'articles » — pas de
version grisée, pas de message d'explication ; seul « Trier à nouveau » reste. À
3 gardés, « Plus d'articles » apparaît.

### Scénario 19 : pied de tri lisible et actionnable
**Parcours** :
1. Finir un tri avec au moins 3 gardés.
2. Taper « Plus d'articles ».
**Résultat attendu** : sous la liste des gardés, **deux boutons pleine largeur**
séparés du contenu par une vraie marge : « Plus d'articles » plein orange (même
allure que « Je garde ») puis « Trier à nouveau » bordé. Le tap réinjecte le
carrousel du jour et **rouvre** la pile sur un nouvel article ; la barre de
progression s'allonge et les gardés restent en dessous.

### Scénario 20 : gardés homogènes + nouvelle description
**Parcours** :
1. Finir un tri avec 3 gardés ou plus ; observer la liste.
2. Ouvrir une **lettre passée** depuis le rewind ⏪.
**Résultat attendu** : dans la liste des gardés, toutes les lignes se
ressemblent — aucun fond teinté, aucun filet vertical orange, aucune pastille
« Actu du jour », pas de premier article mis en avant. Sur une **lettre passée**,
au contraire, le premier article garde son traitement éditorial (fond teinté,
filet, pastille). Sous le titre de la carte, la description lit **« Choisis les
articles que tu liras aujourd'hui. »**

## Critères d'acceptation
- [ ] Le tri au swipe seul va jusqu'au bout, sans carte figée/grisée.
- [ ] La carte grandit doucement sous la barre d'actions ; plus de grand vide.
- [ ] Images de tri nettement plus grandes (QA 390×844).
- [ ] Skeleton lisible « cartes » pendant le chargement.
- [ ] « Plus d'articles » (≥ 3 gardés) : injecte le carrousel + rouvre la pile.
- [ ] Plus de pastille « nouveaux articles ».
- [ ] Boot à froid : silhouette de pile → vraie pile, **sans** liste passive.
- [ ] Carte du dessous stable pendant la sortie, jamais pré-tamponnée.
- [ ] Article sans image : pas d'aplat gris, carte plus courte, barre qui glisse.
- [ ] Étoile / coche selon l'état d'intérêt de la source.
- [ ] Pied de fin : deux boutons **pleine largeur** ; « Plus d'articles » absent
      sous 3 gardés **ou** si le pool injectable est vide.
- [ ] Jamais d'en-tête « Ton Essentiel » seul : silhouette ou contenu.
- [ ] Aucun tressautement de la pile ni saut de la barre d'actions au swipe.
- [ ] Gardés tous rendus à l'identique ; lettre passée conserve son lead.
- [ ] Description « Choisis les articles que tu liras aujourd'hui. »
- [ ] Plus aucun « N sur M trié(s) » nulle part.
- [ ] Console sans erreurs ; réseau sans 4xx/5xx inattendus.

## Zones de risque
- Fluidité du swipe (le bug d'origine) : bien tester swipes rapides + interruptions.
- Croissance `AnimatedSize` : vérifier l'absence de saut au-dessus de la barre
  d'actions et la non-régression des ancres de snap du feed.
- « Voir d'autres articles » ne doit pas réinjecter deux fois les mêmes articles.

## Dépendances
Aucune modif backend. La carte lit `GET /api/essentiel` (articles + `carousel`)
déjà servi. Démarrer l'API locale si besoin (`uvicorn app.main:app --port 8080`).
