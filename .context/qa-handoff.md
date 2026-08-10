# QA Handoff — Essentiel v2 : pile de tri au design 2A + carte cliquable (Story 33.2)

> Rempli par l'agent dev. Input de /validate-feature (agent QA).
> ⚠️ QA web : viewport 390x844, sémantique activée au boot (skill `facteur-qa-web`).
> Compte de test : entrée mémoire `reference_qa_staging_account` (jamais créer de compte).

## Feature développée

La carte « Ton Essentiel » passe au design 2A « Le jour décide, la pile compte » :
contrôle « − N à lire aujourd'hui · Y à trier + » sous les boutons (cible
persistée par jour, plus de segments), balises de pied de carte (1 avec image /
2 sans), en-tête « TU
GARDES » sur la liste des gardés, pied de tri terminé en zone pointillée
« Plus d'articles ? » + ligne « Trier à nouveau ». Et, indépendant du design :
**la carte du dessus est cliquable** — un tap ouvre l'article sans rien
décider ; au retour, si l'article a été effectivement lu, il compte comme
gardé (décision `keep`, modalité `read`) avec le marquage de lecture habituel.

## PR associée

À créer via /go après validation QA (`--base main`).

## Écrans impactés

| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Feed (carte « Ton Essentiel », pile de tri) | `/` (Flux Continu, héros) | Modifié |
| Lettres passées (carte figée) | timeline overlay depuis l'en-tête | Non-régression |

## Scénarios de test

### Scénario 1 : stepper — régler la cible du jour
**Parcours** :
1. Ouvrir le feed sur un compte avec un Essentiel du jour non trié.
2. Repérer sous les boutons le contrôle « − 5 à lire aujourd'hui · 5 à trier + ».
3. Taper « + » jusqu'à la borne haute, puis « − » jusqu'à la borne basse (3).
**Résultat attendu** : le nombre suit chaque tap ; la ligne de progression suit
(« 0 sur N triés ») ; à chaque borne le rond concerné est estompé et inerte.
La borne haute = slate + articles du carrousel du jour ; la basse = 3.

### Scénario 2 : la cible survit au jour (persistance)
**Parcours** :
1. Régler la cible à 3 (ou 7 si le pool le permet).
2. Trier 1 article, tuer l'app, relancer.
**Résultat attendu** : la pile revient avec la même cible et la décision déjà
prise ; aucune décision perdue, pas de re-mélange de l'ordre. Si le carrousel
arrive après le héros, la cible complète se restaure dès son retour.

### Scénario 3 : baisser la cible ne perd JAMAIS une décision
**Parcours** :
1. Cible à 5 ; trier 4 articles (mélange garde/passe).
2. Baisser la cible à 3.
**Résultat attendu** : le compteur affiche la taille réelle (il ne peut retirer
que des non-décidés en fin de pile) — avec 4 décidés, la cible s'arrête à 4,
jamais en dessous du nombre de décisions prises. Rien ne disparaît de la liste
des gardés.

### Scénario 4 : tap sur la carte → l'article s'ouvre, AUCUNE décision
**Parcours** :
1. Sur la pile, taper (tap court) la carte du dessus.
**Résultat attendu** : l'article s'ouvre (reader). Revenir immédiatement SANS
lire : la même carte est toujours en haut de pile, la progression n'a pas
bougé, l'article n'est pas dans les gardés.

### Scénario 5 : lecture effective au retour = gardé (modalité `read`)
**Parcours** :
1. Taper la carte du dessus, lire l'article (rester dedans, scroller un peu).
2. Revenir au feed.
**Résultat attendu** : l'article a quitté la pile et apparaît dans « TU
GARDES » **avec sa coche de lecture** (pastille verte) et l'opacité grisée ;
le compteur avance (« 1 sur N triés · 1 gardé ») ; la carte suivante est en
haut de pile.

### Scénario 6 : un article lu ailleurs n'est PAS auto-gardé
**Parcours** :
1. Cold-boot avec un slate persisté contenant un article déjà lu la veille
   (ou lu depuis une autre section du feed, pas depuis la pile).
**Résultat attendu** : cet article reste dans la pile, à trier normalement.
Seul un article **ouvert depuis la pile** (tap) est auto-gardé au retour.

### Scénario 7 : progression en ligne, plus de segments
**Parcours** :
1. Trier au swipe et aux boutons, en alternant.
**Résultat attendu** : sous la barre d'actions, une seule ligne
« N à lire aujourd'hui · Y à trier » ; `Y` diminue à chaque décision et aucun
segment de progression n'est rendu.

### Scénario 8 : balises du pied de carte (règle 1 avec image / 2 sans)
**Parcours** :
1. Observer une carte **avec** image portant couverture/polarisation.
2. Observer une carte **sans** image.
**Résultat attendu** : avec image → **une seule** balise (la pilule
couverture/polarisation si dispo, sinon thème ou fraîcheur « Il y a Xh »).
Sans image → jusqu'à **deux** balises, titre plus grand (22) et padding plus
généreux. Jamais de débordement à droite, les libellés s'élident.

### Scénario 9 : « TU GARDES »
**Parcours** :
1. Garder un premier article.
**Résultat attendu** : l'en-tête « TU GARDES » (petites capitales, filet, puis
le compte en accent orange) apparaît **avec** la première ligne gardée, jamais
seul, et le compte suit les gardés suivants.

### Scénario 10 : tri terminé — pied 2A
**Parcours** :
1. Finir le tri avec le carrousel du jour non épuisé.
**Résultat attendu** : zone à **bord pointillé** « Plus d'articles ? / Deux de
plus, tirés du même Essentiel » avec « + » orange, puis ligne discrète « Trier
à nouveau » (icône flèche circulaire). Taper la zone rouvre la pile avec 2
articles de plus ; le contrôle sous les actions reste visible et l'augmenter
rouvre aussi la pile. Sans carrousel restant, seule la ligne « Trier à nouveau »
apparaît.

### Scénario 11 : lettre passée = rien de tout ça
**Parcours** :
1. Ouvrir une édition passée via le rewind de l'en-tête.
**Résultat attendu** : ni stepper, ni pile, ni « TU GARDES » — la lettre
passée garde son rendu éditorial figé (lead teinté + mediums).

## Critères d'acceptation

- [ ] Contrôle cible/statut sous les boutons, uniquement aujourd'hui, bornes `[3, pool]`
- [ ] Cible persistée par jour (cold-boot), baisse sans perte de décision
- [ ] Tap carte → ouvre sans décider ; lecture au retour → gardé + coche
- [ ] Ligne « N à lire aujourd'hui · Y à trier » sous les boutons, plus de segments
- [ ] Balises : 1 avec image / 2 sans ; pilule couverture réutilise les
      pastilles existantes
- [ ] « TU GARDES » + filet + compte accent au-dessus des gardés
- [ ] Tri terminé : zone pointillée « Plus d'articles ? » + ligne « Trier à
      nouveau »
- [ ] Aucune erreur console, aucun 4xx/5xx inattendu (le POST triage porte
      `decided_via: "read"` pour les gardés par lecture)

## Zones de risque

- **Auto-keep** : le filtre « ouvert depuis la pile » est le garde-fou contre
  l'auto-garde massive au cold-boot (hydratation serveur des lus). Scénario 6
  est le test clé.
- **Silhouette** : la ligne de progression a changé de hauteur (14 → 26 px) ;
  vérifier qu'aucun saut de layout n'apparaît à l'hydratation de la pile.
  Limite connue : le stepper (34 px) n'a pas de silhouette — un léger
  décalage de 34 px peut apparaître 1-3 frames à l'hydratation du tri.
- **QA web** : le viewport reste bloqué à 1680px (mémoire
  `project_qa_web_viewport_stuck_use_widget_getrect`) — valider les layouts
  par getRect si besoin.
- Les balises `newsource` / `social` / `durée de lecture` du design n'ont pas
  de signal côté données : absentes, c'est voulu (hors périmètre 33.2).

## Dépendances

- `POST /api/essentiel/triage` accepte `decided_via: "read"` (migration
  `tr02_widen_triage_via`, CHECK élargi — déployée avec la PR).
- `GET /api/essentiel` inchangé (slate + carrousel = pool du stepper).
