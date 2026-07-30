# QA Handoff — Couverture multi-sources sur les cartes (story 32.2)

> Rempli par l'agent dev. Input de /validate-feature. Story :
> `docs/stories/core/32.2.couverture-multi-sources-cartes.md`.

## Feature développée

Le signal « ce sujet est couvert par N rédactions », jusqu'ici confiné au bloc
« Actus du jour », devient visible sur les cartes : pastille de sous-thème ML
retirée du footer, remplacée par une puce de couverture (avatars des rédactions
+ « N sources »), affichée dès **2 sources**. Propagée jusqu'à la carte hi-fi de
l'onglet L'Essentiel. En prime, trois correctifs sur le nudge « comparaison ».

## PR associée

https://github.com/boujonlaurin-dotcom/facteur/pull/1041 — CI verte.

## Écrans impactés

| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Tournée / Flux Continu (cartes d'article) | `/flux` | Modifié (footer) |
| Carte hi-fi « Ton Essentiel » | `/flux` (en tête) | Modifié (puce ajoutée) |
| Page dédiée d'une section | `/flux/section/:key` | Modifié (footer) |
| Lecteur d'article (nudge « comparaison ») | `/flaner/content/:id` | Modifié |

## Scénarios de test

### Scénario 1 : happy path — la puce est là où le sujet est couvert
**Parcours** :
1. Ouvrir la Tournée (viewport 390x844, sémantique activée au boot).
2. Repérer une carte d'un sujet traité par plusieurs rédactions.

**Résultat attendu** : le footer lit `source · heure … [avatars] N sources`.
Aucune pastille de sous-thème (« Cybersécurité », « Immobilier », « LGBTQ+ »…)
nulle part. Au plus **3 avatars**, même si le sujet a 6 sources.

### Scénario 2 : edge case — seuil et budget horizontal
**Parcours** :
1. Trouver une carte dont le sujet n'a qu'**une** source.
2. Trouver une carte à nom de source long (« Le Monde Diplomatique », « Le
   Journal du Dimanche ») **qui porte aussi** la puce, et si possible le badge
   de divergence (icône).

**Résultat attendu** : aucune puce sous le seuil de 2. Sur le nom long, c'est le
**nom qui s'ellipse** (« Le Monde Diplo… »), jamais la puce qui est tronquée ou
poussée hors écran. Aucun bandeau jaune/noir de débordement.

### Scénario 3 : L'Essentiel
**Parcours** :
1. Rester sur la carte hi-fi en tête de Tournée.
2. Comparer la tuile lead et les tuiles médiums.

**Résultat attendu** : la puce apparaît sur les tuiles dont le sujet est couvert,
sans casser la ligne de source ni la coche de lecture. **Mesurer le temps
d'affichage de l'onglet** (contrainte PO n°1) : il ne doit pas bouger.

### Scénario 4 : nudge « comparaison » (commit 3, le plus à risque)
**Parcours** :
1. Ouvrir depuis le feed un article à **≥ 3 perspectives**, rester immobile en
   haut de l'article. Chronométrer l'apparition du nudge.
2. Recommencer via un **deeplink** (notification / lien externe).
3. Rouvrir un autre article dans la même journée.

**Résultat attendu** : le nudge apparaît dans **les deux** chemins, plus vite
qu'avant (le délai de 1,5 s court désormais en parallèle du réseau, plus après).
Il ne réapparaît pas une 2ᵉ fois dans la journée pour une même cible.

## Critères d'acceptation

- [ ] Puce de couverture visible sur les cartes à ≥ 2 sources, absente à 1.
- [ ] Les deux formes sont là : avatars **et** « N sources » en texte.
- [ ] Plus aucune pastille de sous-thème dans les footers de carte.
- [ ] Jamais plus de 3 avatars.
- [ ] Aucun débordement horizontal en 390 px, nom de source long inclus.
- [ ] Puce présente sur la carte hi-fi de L'Essentiel.
- [ ] Temps d'affichage de L'Essentiel inchangé.
- [ ] Nudge « comparaison » visible depuis le feed **et** depuis un deeplink.
- [ ] Console sans erreur, réseau sans 4xx/5xx inattendu.
- [ ] Screenshots avant/après sur les deux surfaces.

## Zones de risque

- **Le nudge (commit 3)** touche une machine à états sans test automatisé
  possible (état privé d'un widget de ~5 000 lignes). Seul commit à risque de
  régression ; révocable seul.
- **Le budget horizontal du footer** : un débordement réel de 37 px a été trouvé
  et corrigé (le `Spacer` se partageait l'espace libre avec le nom de source, qui
  ne rétrécissait donc qu'à moitié). Deux tests de garde couvrent le cas en
  390 px, mais la vérification visuelle reste utile — les métriques de police en
  test ne sont pas celles du rendu réel.
- **Cache Hive** : ouvrir l'app avec un snapshot écrit par la version précédente
  (sans `perspective_sources`) ne doit pas casser le parse — affichage dégradé
  (pas de puce) jusqu'au refetch, pas de crash.

## Dépendances

- `GET /api/essentiel` — deux champs ajoutés (`source_count` et
  `perspective_sources`, ce dernier tronqué à 3 côté serveur). Pas de nouvelle
  requête DB, pas de cache à invalider, pas de migration.
- Backend de staging à jour requis pour voir la puce sur L'Essentiel ; les cartes
  du flux, elles, n'ont besoin d'aucun backend neuf.
