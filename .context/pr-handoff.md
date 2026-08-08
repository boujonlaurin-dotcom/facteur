# fix(essentiel) : la pile de tri passe la revue design — itération PO + passe pré-prod (33.1)

Base `main`. **Mobile-only, aucune migration, aucun changement backend.**
Suite de la PR #1051 (« le tri dans le feed »), déjà mergée.
Story : `docs/stories/core/33.1.tri-dans-le-feed.md`.

## Quoi

Sur la pile livrée en #1051, le PO a relevé deux séries de défauts — une
itération de fond sur capture, puis une passe de finition bloquante pour la mise
en prod. Les deux sont ici.

**Itération PO — 6 retouches**

1. **Le swipe se figeait.** Un unique `TriageSwipeCardState` (réutilisé via
   `GlobalKey`) laissait fuir l'état de drag d'un article sur le suivant, et
   l'index n'avançait que dans le `.then()` de l'anim de sortie — piégé si
   l'anim était interrompue. Fix : jeton `articleId` + reset complet dans
   `didUpdateWidget`, avancée garantie par un `_completeExit` idempotent doublé
   d'un Timer garde-fou, `onHorizontalDragCancel` pour la perte d'arène.
2. **La carte épouse son contenu** — fin du vide de ~256 px sous la pile. La
   kept-list grandit sous la barre d'actions (`AnimatedSize` aligné en haut), la
   zone d'action reste figée, le feed ne saute pas.
3. **Images beaucoup plus grandes** : bandeau 96 → 180 (format ~16:9), carte
   272 → 360.
4. **Squelette de pile réellement visible** : deux cartes décalées avec image et
   lignes de titre, et réserve de la hauteur d'ouverture plutôt que du pic.
5. **« Plus d'articles »** (passe de « hors scope V0 » à livré) : au tri
   terminé, réinjecte le carrousel du jour **déjà chargé** dans la pile via
   `extendSlate` (borné +5), sans réseau. Le slate reste figé — on allonge la
   queue, `decide()` envoie le `slate_size` étendu donc `rank ≤ slate_size`.
6. **Retrait de la pastille « X nouveaux articles »**.

**Passe pré-prod — 7 défauts de finition**

- **Le squelette n'était jamais vu.** Sur un boot tiède (snapshot Hive frais ⇒
  jamais de squelette d'écran), la carte rendait l'ancienne liste passive
  pendant l'hydratation SharedPreferences, puis la pile. Nouvel état
  `triagePending` + silhouette extraite dans `TriageStackSkeleton`, **partagée**
  avec `_HeroSkeleton` : une seule définition, les deux attentes ne peuvent plus
  diverger de la vraie pile.
- **Promotion continue** de la carte du dessous (`onGestureProgress` →
  `ValueNotifier`), clés de `Stack` stables, slot arrière toujours rendu :
  l'appariement se fait par clé, jamais par position.
- **Tampon gaté sur un geste réel** : un `effectiveDx` résiduel tamponnait la
  carte fraîche le temps d'une frame, qui se lisait « déjà décidée ».
- **Pas de placeholder sans image** (décision PO) : deux hauteurs discrètes
  (360 avec image / 240 sans), titre sur 6 lignes, décidées à la composition.
- **Coche « suivie » / étoile « favorite »** près du nom de source, sur la carte
  et les lignes gardées (`InterestStateVisuals` réutilisé).
- **Tampon plain** (fond plein + blanc) : il se pose sur une photo.
- **`_TriageDoneActions`** (« Trier à nouveau » + « Plus d'articles ») remplace
  l'encart conditionnel ; **compteur « N sur M » retiré**.

## Pourquoi

La V0 reste en **collecte seule** : chaque décision est enregistrée avec son
rang dans le slate figé, **aucun poids de reco ne bouge**. Ce que ces retouches
protègent, c'est la qualité du signal — un swipe qui se fige ou une carte qui se
lit comme « déjà décidée » produit des décisions fausses, pas juste une mauvaise
impression.

## Comment ça a été vérifié

- [x] **`flutter test`** — suite complète relancée après la passe `/simplify`.
      Les échecs restants sont **strictement ceux de `main`** (vérifiés dans un
      worktree sur `origin/main` pour le seul qui touchait un fichier partagé :
      `theme_section_screen_test` échoue à l'identique, `Expected: <0.6> /
      Actual: <0.8>`). Aucun échec dans le périmètre touché.
- [x] **`flutter analyze`** — **0 erreur, 0 warning neuf**, total identique à la
      baseline. Zéro issue dans les fichiers neufs/modifiés de la pile.
- [x] **Tests neufs** : `triage_swipe_card_test.dart` (geste, tampons, avancée),
      `flux_continu_hero_skeleton_test.dart` (groupe `TriageStackSkeleton`),
      `essentiel_hi_fi_card_test.dart` (harnais refait + états `triagePending` /
      tri terminé / « Plus d'articles »), `flux_continu_models_test.dart`
      (`EssentielArticle.fromContent`), `essentiel_triage_provider_test.dart`
      (`extendSlate`), `section_fit_test.dart` (géométrie partagée).
- [x] **`/simplify`** — 4 relectures parallèles, findings convergents appliqués
      (commit dédié, détail dans son message).
- [x] **Alembic** — sans objet : aucune migration, aucun fichier `packages/api`
      touché.
- [ ] **Playwright / `/validate-feature`** — **non exécuté** : chaque scénario
      de tri exige un compte connecté avec un digest du jour, et je n'ai pas de
      credentials. `.context/qa-handoff.md` est à jour ; à lancer avant merge.

## Zones à risque

- **Chemin de geste.** C'est le cœur du correctif n°1 et il concentre trois
  mécanismes qui se recouvrent (jeton `articleId`, `_completeExit` idempotent,
  Timer garde-fou). Volontaire — chacun couvre un chemin que les autres ne
  couvrent pas — mais c'est la zone à relire en priorité.
- **Budget de hauteur.** La carte avec image passe à 360 px. Elle n'est plus
  bornée par une réserve : le repli n'est plus « rétrécir » mais « ne pas
  dépasser le viewport ». À vérifier à 390×844 pendant la QA.
- **Squelette partagé.** `TriageStackSkeleton` sert **deux** points de
  branchement (écran + carte). Une régression de silhouette se voit aux deux
  endroits à la fois — c'est le but, mais ça double la surface d'un défaut.
- **Aucune migration, aucun backend** ⇒ rien à craindre côté DB partagée
  staging/prod ni côté backend `production` de la semaine en cours.

## Suites identifiées (pas dans cette PR)

Remontées par la passe `/simplify`, volontairement laissées de côté parce que
leur correctif restructure le chemin de geste ou touche des surfaces hors diff :

- **Clé par article** (`GlobalObjectKey(currentId)`) au lieu du `GlobalKey`
  unique : rendrait structurellement impossible la fuite d'état entre cartes et
  déposerait ~25 lignes de garde. À faire avec une passe QA du swipe.
- **Sortie animée portée par la pile** plutôt que par la carte : le notifier
  avancerait immédiatement, le Timer garde-fou disparaîtrait.
- **`hasImage` figé à la composition** : il dérive aujourd'hui de
  `FacteurThumbnail.failedUrls`, un set statique mutable écrit pendant le paint.
  L'invariant « jamais au milieu du geste » est en prose, pas en structure.
- **Shimmer partagé** (`FacteurShimmer` + `SkeletonBar`) : la recette
  `textTertiary @10 % / @4 %` est recopiée dans trois squelettes indépendants.
- **`triageCardHasImage`** est la 3ᵉ copie du prédicat « cette image va-t-elle
  rendre ? » ; sa place est sur `FacteurThumbnail`, qui revendique déjà la
  propriété de la politique d'éviction.
