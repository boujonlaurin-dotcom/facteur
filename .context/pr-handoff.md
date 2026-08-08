# fix(essentiel): pile de tri — progression sous les boutons, carte au contenu, plus de carte vide

Reprise E2E de la story 33.1 : le PO a **infirmé** trois correctifs de la passe
design. Mobile-only, aucune migration, aucun endpoint touché.

## La root cause du défaut « aucun squelette pendant le chargement » n'était pas la bonne

Le hand-off d'entrée attribuait l'aplat beige à « la vraie carte rendue avec
`articles` vide ». **Ce chemin n'existe pas** : `_buildEssentielSection` renvoie
`null` sur liste vide (la section n'est alors pas dans le feed, donc pas
d'en-tête), et l'état squelette explicite rend `_HeroSkeleton`, du shimmer — or
la capture PO montre le **vrai texte** de l'en-tête.

La vraie cause : `EssentielTriageStack` sortait en `SizedBox.shrink()` quand
l'article du haut du **slate figé** ne se résolvait plus dans le pool. En-tête
rendu, corps de **0 px**, et c'est **persistant**, pas transitoire. Reproduit en
test : slate `['x-99','c-1']` + pool `[c-1,c-2]` ⇒ hauteur de la pile = `0.0`.

Comment on y arrive en vrai : « Plus d'articles » (`extendSlate`) persiste dans
le slate des `contentId` **du carrousel du jour** ; au cold-boot suivant,
l'hydratation depuis le cache ne rejoue pas le carrousel → l'id du haut de pile
est introuvable. (Idem blend live story 9.8, ou tous les articles masqués.)

## Ce que fait la PR

**#4 — plus jamais de carte vide**
- Haut de pile irrésolvable ⇒ la pile rend la **silhouette** partagée
  (`TriageStackSkeleton`), jamais un corps vide.
- `EssentielTriageNotifier.pruneUnavailable(poolIds)` retire du slate les ids
  **non décidés** absents du pool (les décidés restent : leur décision est
  partie). Strictement décroissant ⇒ pas de boucle. Posté après la frame par la
  carte, et **uniquement** quand le haut de pile est irrésolvable — jamais sur
  le chemin nominal.
- Piège trouvé en relecture, corrigé et testé : un slate *entièrement*
  introuvable se vide, or le gel du slate (`_scheduleStart`) est verrouillé une
  fois par montage → la carte serait restée sur sa silhouette. Le verrou est
  levé après la réparation.

**#3 — la carte épouse le contenu réellement affiché**
Renversement assumé des « deux hauteurs discrètes » : le titre était un
`Expanded` dans un slot de 360 px, donc un titre court **étirait du vide** et
repoussait la méta en bas. Désormais `mainAxisSize: min` de bout en bout, plus
d'`Expanded`, et le slot n'impose plus de hauteur (`SizedBox(height:)` retiré de
la pile **et** de `TriageSwipeCard`). L'`AnimatedSize` déjà en place fait
**glisser** la barre d'actions d'une hauteur à l'autre au lieu de la faire
sauter. Hauteur bornée par construction (bandeau 180 fixe + `maxLines`), donc
pas de plafond ajouté. La carte du dessous est ancrée en haut sans hauteur
imposée — en `Positioned.fill` elle débordait dès qu'elle était la plus grande
des deux (test dédié).

**#2 — progression sous les boutons**
`_ProgressBar` passe après `_ActionBar` : `carte → actions → progression →
gardés`, répercuté à l'identique dans la silhouette (sinon saut à
l'hydratation).

**Ménage** : `kTriageCardTextOnlyHeight` et `triageCardHeightFor` retirés (plus
d'appelant) ; `kTriageCardHeight` redocumenté — il ne sert plus qu'à la réserve
du squelette.

## Vérification

- `flutter analyze lib/features/flux_continu` : **0 issue**.
- `flutter test test/features/flux_continu` : **619 passés, 1 échec** —
  `theme_section_screen_test` (`Expected: <0.6> / Actual: <0.8>`), échec de
  baseline documenté, hors scope. Le 2ᵉ échec de baseline (purge cross-day)
  passe aujourd'hui : il dépend de la frontière de date.
- Tests neufs : 7 sur `pruneUnavailable`, 6 sur la carte (ordre
  progression/actions, fit court vs long, méta collée au titre, carte du dessous
  plus haute sans débordement, slate irrésolvable → silhouette puis reprise,
  slate entièrement introuvable → re-gel), 1 sur l'ordre de la silhouette.
  Les deux tests de piège ont été **vérifiés rouges** sans leur correctif.

## ⚠️ Ce qui reste à faire avant merge

Le hand-off exige une repro **dans l'app qui tourne** (build web + Playwright).
Elle **n'a pas été faite** : le build web public est celui de `main`, donc il
faut builder cette branche en local et se connecter à l'API staging — ce qui
demande un compte de test que je n'ai pas. Scénarios prêts dans
`.context/qa-handoff.md` (13, 14, 15). Donne-moi des credentials et je fais la
passe.
