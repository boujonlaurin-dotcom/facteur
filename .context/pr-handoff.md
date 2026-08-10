# fix(essentiel): pile de tri — en-tête nu, tressautement, pied de tri, gate à 3 gardés

Passe PO du 09/08 sur la story 33.1 : **trois régressions visuelles** encore
présentes après une passe déclarée terminée sur des tests verts, et **trois
demandes produit**. Mobile-only, aucune migration, aucun endpoint touché.

Règle de cette passe : **rien n'est coché sans preuve visuelle**. Un test widget
ne voit ni un placeholder manquant, ni un bouton mal posé, ni un tressautement de
deux frames. Tout ce qui suit a été reproduit puis vérifié sur le build web
release (flavor staging, API `api-staging-40d3`), viewport 390×844, sémantique
activée, compte QA. Traces et captures dans `.context/evidence-33.1/`.

## A1 — la carte se réduisait à son en-tête

Reproduit **au premier boot** (`a1-avant-entete-nu.png`), puis instrumenté.

`_buildSkeletonState` laisse dans le notifier une coquille
`EssentielSection(articles: [])`. Elle **échappe au squelette d'écran** parce que
`_reconcilePlacementThenSync` publie un `_compose()` **non-squelette** pendant le
bootstrap — il n'est délibérément pas gardé par `_bootstrapping`, c'est le
correctif « race 1 » de « Sources favorites absentes ». La trace le nomme :

```
[A1] _buildSkeletonState -> EssentielSection(articles: [])
[A1] reconcile -> _refetchSourcesOnly (bootstrapping=true picked=4)
[A1] screen isSkeleton=false ... sections=1 essentielArticles=[0]
[A1] card articles=0 ... triagePending=false     ← ni pile, ni silhouette, ni tuile
```

`articles.isEmpty` ⇒ `triagePending` était faux (il exigeait `articles.isNotEmpty`)
⇒ la colonne s'arrêtait à `_Header` + `SizedBox(6)`.

C'est le chemin que la passe du 08/08 avait déclaré inexistant (« Ce chemin
n'existe pas »). **Cette affirmation était fausse** ; la story la corrige.

**Correctifs**
- `triagePending` → `contentPending`, qui couvre aussi `articles.isEmpty` :
  garde-fou terminal, la carte rend la silhouette quelle que soit la cause amont.
- Convention du héros écrite des deux côtés : `_essentiel == null` ⇒ *résolu à
  rien* (aucune carte) ; `EssentielSection` **vide** ⇒ *pas encore résolu*
  (silhouette). Les deux ne sont pas fusionnées parce qu'elles ne décrivent pas le
  même état : fusionner ferait soit disparaître la carte pendant le fan-out (saut
  de mise en page), soit laisser une silhouette éternelle sur un Essentiel
  réellement vide.
- `essentiel_triage_stack.dart` : `currentId == null` rend la silhouette au lieu
  de `SizedBox.shrink()` (parité avec son cas frère).

`_reconcilePlacementThenSync` n'est **pas** touché : le rendre silencieux pendant
le bootstrap rouvrirait la race qu'il existe pour fermer.

Écarté par la mesure : la piste « silhouette rendue mais invisible » — la sonde
donne `TriageStackSkeleton(standalone: true)` à `Size(332.8, 438.0)`.

## A3 — la pile tressautait au swipe

Sonde de géométrie **par frame** (`Ticker` : les `AnimatedSize` animent sans
reconstruire leur sous-arbre, une sonde branchée sur le build ne verrait rien).
Position de la barre d'actions au changement de carte :

```
607.3 → 572.2 → 542.9 → 518.8 → 485.3 → 474.0
 pas :  35.1    29.3    24.1    33.5*   11.3      (*) rebond
```

Une easeOutCubic a des pas monotones décroissants. **Cause : deux `AnimatedSize`
imbriqués animant la même hauteur.** Celui de la colonne avait pour enfant une
colonne dont la hauteur bougeait à chaque frame ; `RenderAnimatedSize` bascule
alors en état `unstable`, **cesse d'animer** et se cale sur son enfant, après une
frame de stalle et un saut de re-ciblage.

**Correctif** : les deux `AnimatedSize` deviennent **frères**, sur des hauteurs
disjointes — l'un autour du slot de carte (la barre glisse d'une carte à
l'autre), l'autre autour de la seule liste des gardés (elle grandit vers le bas).

**Écarté par la mesure** : la remise à zéro de `_promotion` dans
`_completeExit()`. Le banc qui lit l'échelle **rendue** de la carte du dessous
frame par frame montre que la baisse 1.0 → 0.96 tombe exactement sur la frame de
promotion. `_completeExit()` et les deux `didUpdateWidget` ne sont pas touchés.

Après : `324 → 281 → 265 → 256 → 248 → 246` (43, 16, 9, 8, 2) — monotone.

## B1 — « Plus d'articles » gaté à 3 gardés

`kTriageMoreArticlesMinKept = 3`, accroché sur le calcul d'`injectableIds` : sous
le seuil la liste est vide, donc le bouton est **absent** — pas désactivé, pas
remplacé par un message (décision PO). Aucun second gate.
`keptCount` = « Je garde » **+** « Plus tard » (définition conservée).
`extendSlate` n'a qu'un seul appelant en production, ce bouton.

Les docs qui portaient l'inverse depuis `9cad0816` / `019f7058` sont corrigées.

## A2 — le carrousel était bien servi ; c'est le pied qui manquait

`curl /api/essentiel` (JWT compte QA) : 5 articles **et** un `carousel` de 5 items
distincts. Instrumentée, la chaîne mobile les porte jusqu'au bout
(`carouselMemo=5`, `carouselItems=5`, `injectable=5`). **Aucun bug mobile** — donc
aucun correctif spéculatif.

L'hypothèse « le chemin SWR in-day remet `_essentielCarousel` à `null` » est
exacte mais **inoffensive** : ce chemin ne s'exécute qu'à la première peinture,
avant tout fetch, alors que le champ vaut déjà `null` ; `refresh()` passe par
`_fetchAll`, qui porte toujours le carrousel. Laissé tel quel.

Ce qui manquait, c'était la présentation. `_TriageDoneActions` passe de deux
`TextButton` inline collés à gauche à **deux boutons pleine largeur empilés**,
avec une vraie respiration au-dessus :
- « Plus d'articles » → primaire, plein `colors.primary`, rayon `pill`, hauteur
  `kTriageActionButtonSize` — l'idiome de « Je garde » ;
- « Trier à nouveau » → `OutlinedButton` (thème), remis en rayon `pill`.

## B2 — liste des gardés homogène

Au tri terminé, **tous** les gardés sont des tuiles sobres, le premier compris :
plus de fond teinté, plus de filet gauche, plus de pastille « Actu du jour ». Une
**lettre passée** garde son rendu éditorial — `_LeadTile`, `_ActuBadge` et
`_accentFor` restent vivants, la bascule se fait sur `triageDone`.

## B3 — description de la carte

« 5 articles du jour, basé sur tes intérêts » → **« Choisis les articles que tu
liras aujourd'hui. »** L'ancienne devenait fausse dès « Plus d'articles ».
Répercuté dans `changelog.json`.

## Signalé, non touché

`_fitHeroSection` est un no-op ; `fitHeroCount`, `kHeroLeadHeight` et
`kHeroMediumHeight` n'ont plus d'appelant hors `section_fit_test.dart`. Nettoyage
laissé à une passe dédiée plutôt que mêlé à des correctifs visuels.

## Vérifications

- `flutter analyze lib test` : **0 erreur**, 0 warning (527 `info`, tous des
  `deprecated_member_use` pré-existants hors périmètre).
- `flutter test` : **2110 passés / 26 échecs**, contre **2104 / 26** en baseline
  sur `4128d429` — **exactement le même jeu d'échecs** (bookmark, feed_sources,
  topic chips, notifications, premium, perspectives, smoke,
  `theme_section_screen_test`), tous hors périmètre. Aucun nouvel échec ; les 6
  tests en plus sont ceux ajoutés par cette passe.
- `pytest` backend : **aucun fichier de `packages/api` n'est touché** par cette
  PR (`git diff origin/main...HEAD --name-only` → 0). Le run local s'arrête sur
  692 erreurs de connexion à la base de test, non provisionnée dans ce
  workspace ; c'est la CI qui fait foi pour le backend.
- Aucune migration Alembic.
- E2E Playwright (390×844, sémantique activée, compte QA) rejoué **sur le build
  livré**, instrumentation retirée : A1 avant/après, trace A3 avant/après, pied
  de tri, gate à 2 gardés, « Plus d'articles » qui rouvre la pile, nouvelle
  description, GIF de 5 swipes. Les fichiers sont dans le workspace, sous
  `.context/evidence-33.1/` (répertoire gitignoré, non poussé) ; les chiffres qui
  tranchent sont recopiés dans la story et ci-dessus.
- Console : aucune erreur applicative. Les seuls 4xx sont pré-existants et hors
  périmètre — `/api/veille/config` 404 (le compte QA n'a pas de veille
  configurée) et `/api/images/proxy` 400/404 sur des favicons de sources morts.

`CLAUDE.md` porte en plus un pointeur (déjà présent dans l'arbre de travail) vers
le compte QA staging conservé hors dépôt.
