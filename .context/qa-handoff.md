# QA Handoff — Volet B : carrousel « sources discrètes » en dernier recours

- **Branche** : `claude/essentiel-carrousel-dernier-recours`
- **Type** : Bug (grief PO n°2, `docs/bugs/bug-curation-essentiel-personnalisation.md`)
- **Surfaces impactées** : carte « Ton Essentiel » (pile de tri) ; backend
  `GET /api/essentiel` (carrousel attaché) et `GET /api/feed/` (Phase B Flâner).

## Ce qui change pour l'utilisateur

1. Le carrousel du jour n'entre **plus** dans la pile de tri d'emblée : la
   pile ne propose que le slate du jour + les articles `/more`.
2. Il se **verse en queue** de pile seulement quand la pile est basse
   (≤ 2 restants), l'objectif de gardés non atteint, et `/more` à sec.
3. Carrousel « Tes sources discrètes » (backend) : **3 items max**, jamais un
   article déjà trié (keep/later/pass, 90 j), jamais > 30 j, sous-ensemble
   stable la journée.

## Scénarios de test (build web, viewport 390x844, compte QA en mémoire `reference_qa_staging_account`)

> ⚠️ Les scénarios 2-3 exigent un état backend difficile à mettre en scène
> (carrousel présent + `/more` épuisé). Ils sont verrouillés par widget tests
> (`essentiel_hi_fi_card_test.dart`, section « Volet B ») — la passe web peut
> se limiter aux scénarios 1 et 4 si l'état ne se présente pas.

1. **Happy path — pas de carrousel prématuré** : se connecter, ouvrir
   l'Essentiel du jour, trier quelques cartes. Vérifier qu'aucune carte
   « carrousel » (badge source discrète/reco) n'apparaît tant que la pile a
   des articles du jour, et que la pile s'allonge d'articles réseau quand elle
   descend sous 2 restants (requête `/api/essentiel/more` visible réseau).
2. **Versement dernier recours** : épuiser la pile ET `/more` (6 lots ou
   retour vide) sans atteindre l'objectif → les items carrousel apparaissent
   en fin de pile, 3 max.
3. **Pas de répétition** : trier un item carrousel, recharger le lendemain
   simulé → il ne revient pas.
4. **Non-régression fin de tri** : terminer le tri → liste « Tes articles »,
   « Plus d'articles ? » et « Refaire ? » fonctionnels ; cold-boot (reload) →
   pas de silhouette infinie, gardés intacts.

## Critères d'acceptation

- Aucune erreur console inattendue, aucun 4xx/5xx inattendu.
- La pile ne « saute » jamais : le versement du carrousel n'ajoute qu'en queue.
- `GET /api/essentiel` : `carousel.items` ≤ 3 quand type `quiet_sources`, et
  deux appels espacés dans la même journée rendent le même sous-ensemble.
