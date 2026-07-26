# QA Handoff — Recherche universelle (Story 30.1)

> Rempli par l'agent dev. Input de /validate-feature. Story :
> `docs/stories/core/30.1.recherche-universelle.md`.

## Feature développée

La loupe de Flâner devient une **recherche universelle** : un seul champ pour retrouver un
article, une source (suivie ou à ajouter), un sujet suivi ou un thème. Quand la requête ne
donne rien, l'écran propose des rattrapages au lieu d'un écran blanc. Le point d'entrée
migre dans le **header partagé** (visible sur les deux onglets).

## PR associée
À créer (`/go`) vers `main`.

## Écrans impactés
| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Header partagé (2 onglets) | `/flux-continu` et `/flaner` | Modifié — nouvelle loupe à gauche de l'avatar |
| Sheet de recherche | modale | Réécrite |
| Flâner | `/flaner` | Modifié — état vide + bandeau « élargir » |
| Barre de filtres | `/flaner` et Explorer de L'Essentiel | Modifié — la loupe devient une pill d'état |
| Ajouter une source | `/settings/sources/add` | Modifié — accepte une requête pré-remplie |

## Scénarios de test

### Scénario 1 : Happy path — filtrer sur une source suivie
1. Depuis Flâner, taper la loupe du header.
2. Saisir le début du nom d'une source suivie (ex. « media »).
3. Taper le résultat sous « TES SOURCES ».

**Attendu** : la sheet se ferme, le flux est filtré sur cette source, la barre de filtres
affiche la chip source active.

### Scénario 2 : Source absente du compte → ajout en 1 tap
1. Ouvrir la recherche, saisir le nom d'une source du catalogue **non suivie**.
2. Vérifier qu'elle apparaît sous « AJOUTER UNE SOURCE » avec le sous-titre
   « Pas encore dans tes sources » et un bouton **Ajouter**.
3. Taper **Ajouter**.

**Attendu** : spinner sur la ligne, toast « … ajoutée à tes sources », sheet fermée, flux
filtré sur la nouvelle source. La source apparaît ensuite dans Réglages → Sources.

### Scénario 3 : Source inconnue → pont vers la recherche intelligente
1. Ouvrir la recherche, saisir un nom absent du catalogue (ex. « gazette de saint-flour »).
2. Taper « Chercher « … » sur le web ».

**Attendu** : navigation vers l'écran **Ajouter une source** avec le champ **déjà rempli**
et la recherche **déjà lancée** (résultats ou skeleton visibles, pas d'écran d'accueil vide).

### Scénario 4 : Recherche bredouille → rattrapages
1. Ouvrir la recherche, saisir un mot-clé sans résultat dans les sources suivies.
2. Valider au clavier (action « rechercher »).

**Attendu** : Flâner affiche l'état vide 🔍 « Rien sur « … » » avec, dans l'ordre :
« Élargir à toutes les sources », « Ajouter « … » comme source », « Suivre « … » comme
sujet », « Revenir au feed ». **Pas** de carte « Pour ne rien rater sur … » en doublon.

### Scénario 5 : Élargissement
1. Depuis l'état vide, taper « Élargir à toutes les sources ».

**Attendu** : le flux se recharge en incluant les sources non suivies ; la pill de la barre
de filtres affiche « mot-clé · toutes sources » ; le CTA « Élargir » disparaît de l'état
vide s'il reste vide.

### Scénario 6 : Récolte maigre
1. Chercher un mot-clé qui ramène entre 1 et 4 articles.

**Attendu** : un bandeau discret « N résultats dans tes sources » + bouton « Élargir »
s'intercale sous la barre de filtres. Il disparaît à 5 résultats ou plus, et une fois élargi.

### Scénario 7 : Recherche depuis L'Essentiel
1. Aller sur l'onglet L'Essentiel.
2. Taper la loupe du header, saisir un thème (ex. « environnement »), taper le résultat.

**Attendu** : bascule automatique sur l'onglet **Flâner** avec le filtre thème appliqué.

### Scénario 8 : Intention source vs mot-clé
1. Saisir exactement le nom d'une source suivie (ex. « Mediapart »).
2. Puis saisir un domaine (ex. « lemonde.fr »).

**Attendu** : dans les deux cas, la section source / « Ajouter une source » passe **devant**
« ARTICLES », qui est relégué en fin de liste.

### Scénario 9 : Accents et casse
1. Saisir « ecolo » (sans accent) alors qu'un sujet « Écologie » est suivi.

**Attendu** : le sujet remonte sous « SUJETS SUIVIS ».

### Scénario 10 : État initial et historique
1. Ouvrir la recherche sans rien saisir.

**Attendu** : recherches récentes (si historique), sources favorites (si favoris), sujets du
moment. Aucune section de résultats. Le champ prend le focus automatiquement.

## Critères d'acceptation

- [ ] La loupe du header est visible et cliquable sur les **deux** onglets.
- [ ] La loupe passe en couleur accent quand une recherche est active.
- [ ] Aucune loupe résiduelle dans la barre de filtres quand aucune recherche n'est active.
- [ ] Toute recherche bredouille propose au moins un rattrapage (jamais d'écran blanc).
- [ ] Le pont vers l'ajout de source arrive avec la recherche **déjà lancée**.
- [ ] Console sans erreur, réseau sans 4xx/5xx inattendu.

## Points d'attention

- Le calcul des résultats est **100 % local** (aucun appel réseau pendant la frappe) : si un
  résultat attendu manque, vérifier que `userSourcesProvider` / `customTopicsProvider` sont
  bien chargés avant d'ouvrir la sheet.
- Une source **mise en sourdine** ne doit jamais être reproposée à l'ajout.
- ⚠️ Flutter web = canvas : activer la sémantique au boot avant tout `snapshot`
  (cf. skill `facteur-qa-web`).
