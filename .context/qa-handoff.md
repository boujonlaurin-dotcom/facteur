# QA Handoff — Essentiel : l'objectif devient « articles à garder »

**Story** : `docs/stories/core/33.4.essentiel-objectif-articles-gardes.md`
**Branche** : `boujonlaurin-dotcom/swipe-tri-feed-essentiel`
**Viewport** : 390×844

## Écrans impactés

Carte « Ton Essentiel » en tête du Flux Continu (`/` → Tournée du jour), dans
ses deux états : **tri en cours** (pile swipable) et **tri terminé** (liste des
gardés + pied de carte).

## Ce qui change

1. Le stepper règle désormais le **nombre d'articles à garder**, pas la taille
   de la pile : `Je veux lire [−] 5 [+] articles aujourd'hui`. Le fragment
   « · Y à trier » a disparu.
2. La pile **continue de proposer** jusqu'à ce que la cible soit atteinte : elle
   va chercher de nouveaux articles au réseau avant de sécher, sans aucune UI
   d'attente.
3. La barre segmentée compte les **gardés**, plus les triés — et elle est plus
   discrète (traits fins, espacés, sans segment épaissi).
4. Après 5 refus enchaînés, un bandeau propose d'arrêter là.
5. « Trier à nouveau » devient « Refaire ? », plus discret.
6. En fin de tri, **l'objectif n'est plus affiché**.

## Scénarios

### S1 — Tri jusqu'à la cible (happy path)

1. Ouvrir l'app sur un tri du jour non commencé.
2. Vérifier le libellé exact : `Je veux lire` `5` `articles aujourd'hui`.
   **« à trier » ne doit apparaître nulle part.**
3. Garder 5 articles d'affilée (swipe droite ou bouton « Je garde »).
4. Après chaque gardé, un segment de plus se remplit dans la barre.
5. Au 5e gardé, le tri se termine : liste « TU GARDES » + pied de carte.

**Attendu** : la pile n'a jamais été à court d'articles ; aucun spinner, aucun
clignotement, aucun saut de mise en page pendant le réapprovisionnement.

### S2 — Un refus ne rapproche pas de la cible

1. Repartir d'un tri en cours (`Refaire ?` si besoin).
2. Refuser 3 articles (swipe gauche ou ✕).
3. **La barre ne bouge pas** : aucun segment ne se remplit.
4. Garder un article : un segment se remplit.

### S3 — Nudge d'arrêt (5 refus enchaînés)

1. Refuser 5 articles d'affilée.
2. Le bandeau apparaît **sous les boutons**, au-dessus de la barre :
   « Rien ne t'accroche ? Tu peux t'arrêter là. » + `Arrêter le tri` + croix.
3. Vérifier qu'il ne recouvre ni la carte ni les boutons, et que son apparition
   est glissée (pas de saut sous le doigt).
4. **Cas A** — garder un article : le bandeau disparaît tout seul.
5. **Cas B** — taper la croix : il disparaît et **ne revient pas** de la journée
   (relancer l'app pour le confirmer), le tri continue.
6. **Cas C** — taper `Arrêter le tri` : le tri se termine sur les gardés
   obtenus. Avec 0 gardé ⇒ « Rien gardé aujourd'hui. » — vérifier qu'aucun
   message ne présente ça comme un échec, et que **l'objectif n'est pas
   affiché**.

### S4 — Stepper

1. En cours de tri, taper `+` : le chiffre monte, **la pile ne change pas**
   (même carte du dessus, même nombre de cartes).
2. Monter jusqu'à 10 : le rond `+` s'éteint et ne répond plus au tap.
3. Descendre jusqu'à 3 : le rond `−` s'éteint de même.
4. Viser le bord du rond (à ~5px du cercle) : le tap doit **quand même** passer
   (cible tactile 44px).
5. Avec 4 articles déjà gardés, régler la cible à 3 : le tri se termine
   immédiatement, sans rien perdre.

### S5 — « Plus d'articles ? » au-delà de la cible

1. Terminer un tri (cible atteinte).
2. Vérifier le pied de carte : zone pointillée « Plus d'articles ? » puis
   « Refaire ? ». **Pas de stepper.**
3. Taper « Plus d'articles ? » : la pile rouvre.
4. Recommencer jusqu'à épuisement réel du pool : le CTA reste visible et affiche
   « Pas de nouvel article pour l'instant. » — jamais un bouton qui disparaît.

### S6 — Cold-boot en cours de tri

1. Trier 2 articles, tuer l'app, la relancer.
2. La pile reprend au bon endroit, dans le même ordre, avec la même cible.
3. Aucun squelette persistant, aucune carte vide, aucun aplat de fond.

### S7 — « Refaire ? »

1. Au tri terminé, taper « Refaire ? ».
2. Le tri repart de zéro sur le même slate ; le nudge d'arrêt redevient
   possible.
3. Vérifier que le libellé « Trier à nouveau » n'existe plus nulle part.

## Critères d'acceptation

- [ ] Aucune occurrence de « à trier » ni de « Trier à nouveau ».
- [ ] La barre de progression ne se remplit **que** sur un gardé (« Je garde »,
      « Plus tard », ou retour de lecture).
- [ ] Aucun segment n'est plus épais que les autres.
- [ ] La pile ne sèche jamais tant que la cible n'est pas atteinte et que le
      backend a de la matière.
- [ ] Le nudge apparaît au 5e refus, pas au 4e.
- [ ] Fin de tri : pas de stepper, pas d'objectif chiffré.
- [ ] Console sans erreur, réseau sans 4xx/5xx inattendu (les appels
      `/api/essentiel/more` sont normaux et doivent répondre 200).

## Points de vigilance réseau

Ouvrir l'onglet réseau et vérifier, sur un tri long :

- les appels `/api/essentiel/more` partent **avant** que la pile ne sèche, par
  lots de 5 (`?limit=5`) ;
- pas plus d'un appel toutes les ~5 décisions, et **jamais** un appel par frame ;
- si un appel revient vide, le suivant n'est pas relancé immédiatement
  (cooldown de 10 min) — sauf si l'utilisateur tape « Plus d'articles ? ».
