# QA Handoff — Lettres passées à parité visuelle avec « Aujourd'hui »

> Input pour /validate-feature (Playwright Agent CLI, skill facteur-qa-web).
> Viewport mobile 390×844, sémantique activée au boot (canvas Flutter web).
> ⚠️ **Valider par HOT RESTART** (pas hot reload) : `editionEssentielProvider`
> garde `state` + `_dayCache` à travers un reload. Sinon pull-to-refresh /
> changement de sélection.

## Résumé
Les lettres passées (« Hier » = jour passé, « Cette semaine » = rétro hebdo) de
l'écran Essentiel (`FluxContinuScreen`) rendaient une lettre tronquée vs
« Aujourd'hui ». Elles adoptent maintenant la **même grammaire visuelle** en
lecture seule. Mobile-only, aucun changement backend.

Nouvelle composition d'une lettre passée (`_singleDaySlivers`) :
`héros → · → Actus → · → Bonnes Nouvelles → citation → carte de clôture`, où `·`
est un point de passage (`_SectionPassageDot`, statique en passé).

Changements clés :
1. **Bonnes Nouvelles réaffichées** (jour ET semaine) : la donnée serein
   (`dual.serein.topics`) était déjà fetchée mais jetée ; ré-exposée via
   `EditionEssentielState.bonnesTopics`.
2. **Bannières de section à parité** : « Actus » et « Bonnes Nouvelles » portent
   blurb + illustration comme la lettre du jour.
3. **Carte de clôture** : `ClosingCardV18.readOnly` (coque météo « FIN DE TOURNÉE »
   / « Tu es à jour » identique) remplace l'ancien bloc minimal. Action primaire =
   **« Revenir à aujourd'hui »** + note de contexte. Plus de « Continuer à Flâner »
   ni « Refermer » sur une lettre passée.
4. **Points de passage** entre sections (rythme visuel du jour), calmes/statiques
   en passé (pas de snap — choix délibéré, free-scroll).
5. **Lecture seule** : aucun swipe/feedback/favori/see-all (chaque `SectionBlock`
   ne reçoit que `onTapArticle`).

Limite assumée (Option A validée PO) : les sections **tournée personnalisées**
(thèmes / sources / veille) ne sont **pas** rendues en passé — flux live non
archivé par date, hors de portée d'un fix mobile.

## Écrans impactés
- `FluxContinuScreen` → `_buildPastEdition` / `_singleDaySlivers` (lettre passée).
- `ClosingCardV18` (nouvelle variante `.readOnly`).
- Provider `editionEssentielProvider` (champ `bonnesTopics`).

## Scénarios de test

### Happy path — comparer côte à côte
1. Ouvrir Essentiel → header carte « Ton Essentiel » → rewind (timeline).
2. Sélectionner **« Hier »** : vérifier la présence, dans l'ordre, de
   héros Essentiel → point de passage → section **« Actus du jour »** (bannière
   avec blurb + illustration) → point de passage → section **« Bonnes Nouvelles »**
   (bannière verte) → **citation** → carte de clôture **« FIN DE TOURNÉE » /
   « Tu es à jour »** avec bouton **« Revenir à aujourd'hui »** + note
   « Tu lis la lettre du … ».
3. Sélectionner **« Cette semaine »** : même grammaire ; label **« Actus de la
   semaine »** ; **Bonnes Nouvelles** présentes (agrégées) ; **pas de citation** ;
   même carte de clôture (note « rétro de la semaine »).
4. Repasser à **« Aujourd'hui »** : la page complète (avec sections tournée)
   revient normalement.
5. Comparaison visuelle « Aujourd'hui » vs « Hier » vs « Cette semaine » :
   cartes de section, espacements, points de passage, carte de clôture cohérents.

### Lecture seule (invariant critique)
6. Sur « Hier » / « Cette semaine », tenter un **swipe** sur une carte → **aucune
   action** (pas de feedback chips, pas de dismiss). Pas d'étoile favori active,
   pas de « voir tout ».
7. Tap sur un article → ouvre le reader normalement (seule interaction permise).
8. Bouton **« Revenir à aujourd'hui »** de la carte de clôture → resélectionne
   « Aujourd'hui ».

### Edge cases
9. **Jour stale / vide** (édition absente) : rendu = état vide `_BackToTodayBlock`
   (« Pas d'édition pour … » + « Revenir à aujourd'hui » + « Choisir un autre
   jour »). Pas de demi-lettre.
10. **Mode serein activé** puis rewind sur un jour passé : Bonnes Nouvelles
    toujours cohérentes (bonnesTopics dérivent toujours du digest serein,
    indépendamment du toggle).
11. Jour passé **sans Bonnes Nouvelles** (serein vide) : la section Bonnes est
    simplement absente, pas de bannière vide ni de point de passage orphelin.

## Critères d'acceptation
- [ ] « Hier » et « Cette semaine » lues comme « la même lettre, un autre jour ».
- [ ] Bonnes Nouvelles visibles jour + semaine.
- [ ] Carte de clôture présente (variante lecture seule, « Revenir à aujourd'hui »).
- [ ] Aucune mutation possible (swipe/feedback/favori) en passé.
- [ ] Aucune erreur console, aucun 4xx/5xx inattendu.

## Vérifs déjà faites (dev)
- `flutter analyze lib test` : 0 erreur/warning sur les fichiers touchés.
- `flutter test test/features/flux_continu/` : **360 tests verts**, dont :
  - provider `bonnesTopics` jour (serein / vide / stale) + semaine (agrégation),
  - widget `ClosingCardV18.readOnly` (coque préservée, CTA, note, tap).
- Non couvert par les tests unitaires : la **composition d'écran** (c'est l'objet
  de cette validation Playwright/device).
# QA Handoff — Paywalls Premium « Fact·eur·isse » (PR 2 mobile)

## Contexte

Implémentation de la maquette « Paywalls Premium » : écran **Soutien** (porte 1, lettre des fondateurs), **murs de feature** (porte 2 : veille plein écran + sheets sources/analyses/serein), gating client-side (cap 30 sources, veille premium, quota 1 analyse/jour, personnalisation serein), confirmation « lien envoyé ». Le CTA n'ouvre jamais un paiement : il déclenche `POST /api/checkout/send-link` (magic link Supabase par email, PR backend #954).

⚠️ **Web = état free uniquement** : RevenueCat est null sur web (`customerInfoProvider` → null → non-premium). Ne pas tester les états premium en web.

⚠️ Les photos fondateurs sont des **placeholders** (aplats de couleur) en attendant les vraies images.

## Écrans impactés

- Réglages (bottom sheet) : tuile « Nous soutenir », badge `N/30` sur Mes sources, stamp `PREMIUM` sur Ma veille/Crée ta veille, sous-row « Personnaliser mes bonnes nouvelles » (lock).
- `/soutien` : écran Soutien complet.
- `/soutien/veille-wall` : mur veille.
- `/soutien/lien-envoye` : confirmation.
- Intro veille : stamp « RÉSERVÉ AUX FACT·EUR·ISSES » + CTA verrouillé.
- Ajout de source : pill « N / 30 médias suivis ».
- Perspectives / Analyse Facteur : gate quota 1/jour (bannière quota épuisé sous le CTA en free).

## Scénarios

1. **Happy path Soutien** : Réglages → « Nous soutenir » → écran Soutien (eyebrow, headline, lettre 2 §, carte bonus avec 2 stamps BIENTÔT, 3 réassurances, prix 3 €/mois, CTA « Reçois ton lien pour nous rejoindre », disclaimer stores). Tap CTA → soit confirmation « Ton lien est en route. » (backend avec send-link), soit toast d'erreur propre, jamais de crash.
2. **Mur veille** : Réglages → « Crée ta veille » (compte free sans veille) → mur veille (3 bénéfices, MissionCard « Notre histoire → » → Soutien, prix, CTA).
3. **Intro veille gated** : deep-link `/veille/config` en free → redirection mur veille.
4. **Cap sources** : ajout de source → pill « N / 30 médias suivis » au-dessus de la recherche (absente en mode veille).
5. **Serein** : Réglages → sous-row « Personnaliser mes bonnes nouvelles » avec cadenas → tap → PaywallSheet variante serein (« Un mode serein à ton image »).
6. **Lien envoyé** : « Renvoyer le lien » 2× de suite → le second affiche « Patiente une minute avant de renvoyer. » (429) si backend actif.
7. **Console/réseau** : pas d'erreurs console inattendues, pas de 4xx/5xx hors 429 attendu.

## Critères d'acceptation

- Aucune copy avec em-dash « — ».
- Aucun crash sur images manquantes (fallback monogramme).
- Navigation retour cohérente (swipe back plein écran).
