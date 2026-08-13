# Bug — des blocs favoris n'apparaissent pas dans L'Essentiel

**Type** : Bug
**Statut** : corrigé (mobile)
**Signalé par** : PO (Laurin), 2026-08-13
**Zone** : `apps/mobile/lib/features/flux_continu/providers/flux_continu_provider.dart`

---

## Symptôme

L'utilisateur a rangé ses favoris dans « Mes favoris » (modal *Préparer sa
tournée*) : **7 blocs** dans sa page L'Essentiel — Actus & Mot du jour, Bonnes
Nouvelles, International, **Technologie**, **Environnement**, Ma veille,
Politique.

Le matin, Technologie et Environnement **n'apparaissent nulle part** dans
L'Essentiel : ni bloc, ni empty-state (« Rien de neuf récemment sur … »), ni
onglet dans le header sticky. Le feed passe directement d'International à
« Ma veille ».

Ce n'est pas une pénurie d'articles : les articles tech et climat étaient bien
présents ce matin-là, dans le héros / la pile de tri de l'Essentiel — et
plusieurs sources de l'utilisateur couvrent ces thèmes.

## Invariant produit (PO)

> Un bloc que l'utilisateur a placé dans son Essentiel **apparaît toujours**.
> S'il est pauvre, il le dit (badge « Peu d'articles », empty-state) — il ne
> disparaît jamais en silence.

## Cause racine

Deux mécanismes indépendants, tous deux dans la composition de la Tournée, qui
se combinent exactement dans le scénario rapporté.

### 1. Le score de bloc punit les blocs dont le héros a pris les articles

`_classifyFavoriteSections` calcule `blockScores` (somme des 3 meilleurs
`scoreTotal`, cf. `section_score_order.dart`) **après**
`_dedupeSectionsInOrder` — donc sur les seuls articles **survivants** à la dédup
inter-sections.

Or la dédup retire d'un bloc tout article déjà rendu plus haut : héros
« Ton Essentiel » (5 articles), Actus du jour, blocs précédents. Un thème dont
les meilleurs articles du jour sont montés dans la pile de tri se retrouve donc
vidé, score ≈ 0 → `rankKeysByBlockScore` le fait **couler en bas de Tournée**.

Effet pervers : plus un thème est pertinent le matin même (ses articles sont
sélectionnés pour le héros), plus son bloc coule. C'est littéralement le cas
rapporté — « j'ai eu des articles tech et climat dans ma pile de tri, et je n'ai
pas vu ces sections ».

### 2. Le cap d'affichage coupait des blocs choisis au profit de suggestions

`_orderedTourneeKeys` plafonne la Tournée à `kTourneeVisibleCap = 13` clés avec
un `take(cap)` **aveugle**, appliqué *après* que le tri par score
(`applyScoreOrder`) a classé favoris et sections « Choisie pour vous » dans un
**même** pool. Une suggestion bien scorée passait donc devant un favori, qui
tombait sous le cap.

Le quota Story 22.6 aggravait la chose : il *réservait* jusqu'à
`kTourneeSuggestQuota = 3` slots aux suggestions en tronquant les blocs choisis
à `cap - quota` — une éviction de favoris explicitement codée.

Les volumes rendent la saturation atteignable sans configuration extrême :
`FAVORITE_CAP = 7` favoris backend + Actus + Grille + Bonnes = 10, plus
`TOURNEE_SUGGEST_FLOOR = 4` à `TOURNEE_SUGGEST_SUBCAP = 5` suggestions servies
quel que soit le nombre de favoris ⇒ **jusqu'à 15 clés pour 13 slots**.

Un bloc coupé par le cap ne laisse **aucune trace** : pas d'empty-state, pas de
badge « Peu d'articles ». Indistinguable d'un bug côté utilisateur.

## Correctif

`apps/mobile/lib/features/flux_continu/providers/flux_continu_provider.dart`

1. **`_classifyFavoriteSections`** — le score d'un bloc se calcule sur les
   articles que le backend a **servis** pour ce bloc (survivants + retirés par
   la dédup), plus sur ses seuls survivants. La dédup n'arbitre plus le
   classement : un article partagé compte pour chacune des sections qui l'a
   servi.
   La **maigreur** (`thinKeys`), elle, continue de se mesurer sur les survivants
   — elle décrit ce qui sera *affiché* et pilote le backfill + le badge « Peu
   d'articles ». Inchangée.

2. **`_orderedTourneeKeys`** — le cap ne coupe **jamais** un bloc choisi par
   l'utilisateur (cartes éditoriales + favoris thème/source/veille) au profit
   d'une « Choisie pour vous ». Les blocs choisis prennent leurs slots en
   premier ; les suggestions occupent ceux qui restent, dans l'ordre
   d'affichage (une suggestion intercalée par le score reste à sa place, elle
   n'est pas reléguée en queue). Si l'utilisateur a lui-même plus de blocs que
   le cap, c'est la queue de **son** ordre qui tombe.

3. **`kTourneeSuggestQuota` retiré** (`tournee_order_prefs_provider.dart`) : la
   réservation de slots aux suggestions par éviction de favoris disparaît avec
   le point 2. L'intention de la Story 22.6 (ne pas voir *moins* de suggestions
   parce qu'on a personnalisé) tient toujours dans le cas nominal — ≤ 7 favoris
   + 3 cartes éditoriales = 10 sur 13, il reste des slots. Seul un compte qui a
   lui-même rempli le cap de blocs choisis n'a plus de place pour une
   suggestion : c'est son choix, pas un arbitrage de la Tournée.

Aucun changement backend, aucune migration.

## Tests

- `flux_continu_block_score_order_test.dart` — « un bloc dépouillé par la dédup
  garde son rang » : trois thèmes dont le 2ᵉ sert les mêmes articles que le 1ᵉʳ
  (donc vidé par la dédup) + un article faible à lui. Avant : il coulait sous le
  3ᵉ. Après : il tient son rang.
- `flux_continu_tournee_order_test.dart` — groupe des suggestions sous le cap
  réécrit sur le nouvel invariant : cap plein de favoris ⇒ aucun favori évincé
  et zéro suggestion ; un favori masqué rend son slot à la meilleure suggestion.

## Vérification

⚠️ Le SDK Flutter n'est pas installé dans l'environnement d'exécution distant de
cette session : `flutter test` / `flutter analyze` n'ont **pas** pu être lancés
ici. La suite mobile doit être rejouée en local (ou en CI) avant merge.

---

## Itération 2 — l'ordre composé n'était toujours pas celui rendu

**Retour PO après déploiement du 1ᵉʳ correctif** : l'ordre des blocs dans « Mes
favoris » (Actus, Environnement, International, Technologie, Politique, Bonnes,
Ma veille) ne correspond pas à l'ordre rendu dans la Tournée, et Technologie
reste introuvable dans le feed.

### Cause (ordre)

`_orderedTourneeKeys` applique `applyScoreOrder` **après** `applyOrder` : le tri
par score du jour repositionne donc les blocs que l'utilisateur a lui-même
rangés. C'était un arbitrage explicite de PR-4 (« le score l'emporte sur l'ordre
manuel quand il départage »), testé comme tel — mais il rend la modal « Mes
favoris » mensongère : on y compose un ordre qui n'est pas celui affiché.

Aggravant : l'ordre trié est **gelé pour la journée tournée** (frontière 07h30
Paris). Un réordre fait le soir n'a donc aucun effet visible avant le lendemain,
même sur les blocs que le tri aurait laissés en place.

### Correctif

Une clé présente dans `order` (l'ordre composé dans « Mes favoris ») n'entre plus
dans le tri du jour : son rang est un choix, pas une estimation. Le tri conserve
tout son rôle sur les blocs que l'utilisateur n'a **pas** placés — sections
« Choisie pour vous », favori tout juste ajouté — qui sont classés entre eux dans
les slots laissés libres.

Conséquence assumée sur la Story 10.2 : la clé `source:<id>` d'une source
favorite sert **aussi** de marqueur de mode (« Essentiel » ⟺ clé dans
`tournee_order_v1`), donc une source favorite est toujours « placée » et suit
l'ordre composé. C'est cohérent avec `applyOrder`, qui traitait déjà `order`
comme un arrangement (les clés ordonnées passent devant les non-ordonnées).

### Non élucidé à ce stade

L'**absence** de la section Technologie n'est pas expliquée par ce correctif et
ne l'était pas non plus par ceux de l'itération 1 : aucun chemin de composition
lu jusqu'ici ne retire une `FeedThemeSection` favorite (ni `_filterSections`, ni
`_dedupeSectionsInOrder`, ni `_dropEmptySuggested`, ni `_capSectionsToFit`), et
une section favorite vide se rend en empty-state visible. Deux pistes restent à
départager côté terrain, cf. la PR.
