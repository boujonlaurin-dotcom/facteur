# Essentiel — la navigation entre articles n'existe qu'après le tri

Story : `docs/stories/core/34.1.navigation-swipe-articles-section.md` § 11
(ajustement v4 de la 34.1, après la refonte « pile de tri » 33.1/33.4)

## Le problème

La navigation par swipe entre les articles d'une section (34.1) a été conçue
quand l'Essentiel était un **sommaire** : le deck reprenait
`EssentielSection.articles`. Depuis la 33.1/33.4, la carte du jour est un
**geste** — l'utilisateur compose son Essentiel carte par carte. Le deck n'avait
pas suivi :

1. **Pendant le tri**, un tap sur la carte du dessus ouvrait un deck de tout le
   slate. Le swipe horizontal — *le* geste du tri — devenait un geste de
   navigation, et on parcourait des articles sur lesquels on ne s'était pas
   encore prononcé.
2. **Après le tri**, le deck portait encore le slate entier, rejetés compris :
   glisser depuis un gardé ramenait un « pas pour moi ». Le geste défaisait la
   décision qu'on venait de prendre.

## La règle

| État de la carte du jour | Tap sur un article | Swipe dans le reader |
|---|---|---|
| Tri **en cours** (pile visible, lignes déjà gardées comprises) | ouvre l'article **seul** | aucune navigation |
| Tri **terminé** (liste « Tes articles ») | ouvre l'article dans un deck | navigue **entre les seuls gardés**, ordre du slate |
| **Lettre passée** (archive figée) | inchangé | la lettre entière (comportement 34.1) |

`later` (« Plus tard ») compte comme gardé — c'est déjà la règle de
`keptContentIds`, donc le deck est **exactement** la liste affichée sous « Tes
articles » : même contenu, même ordre, l'index d'arrivée correspond toujours à la
tuile tapée.

## Implémentation

Une seule décision, prise à l'ouverture. `_openArticle` (`flux_continu_screen`)
n'appelle plus `articleDeckFromSection` pour l'Essentiel mais
`essentielArticleDeck` (`flux_continu/utils/essentiel_deck.dart`), fonction pure
qui prend la section, l'état de tri, les articles rapatriés et `isToday` :

- `!isToday` → délègue à `articleDeckFromSection` (archive inchangée) ;
- `!triage.done` → `null` ⇒ le reader s'ouvre nu, sans `PageView`. Ce test couvre
  **deux** cas d'un coup : tri actif, et tri indéterminé au cold-boot
  (`hasStarted` faux tant que le slate n'est pas gelé — la carte rend alors sa
  silhouette, rien n'y est tappable) ;
- sinon → `articleDeckFromContents` sur `triage.keptContentIds`.

Aucune branche ajoutée dans le reader ni dans `ArticleDeckView` : « pas de
navigation » est déjà l'état que produit un payload `null` (le passe-plat de la
34.1). Le verrou vit à un seul endroit, celui qui sait ce que l'utilisateur a
choisi.

**Le pool sort de la carte.** `EssentielHiFiCard._refreshPoolMemo` composait
« slate + carrousel inédit + rapatriés » en privé ; le deck a besoin du **même**
pool pour résoudre un gardé venu de « Plus d'articles ? ». La composition passe
donc dans `essentielTriagePool`, appelée par les deux — sinon un gardé injecté via
le carrousel manquerait silencieusement à la séquence de lecture. La carte garde
son mémo et son invalidation par identité.

`section_key` de la mesure reste `essentiel_v3` : seul le contenu du deck change,
pas le vocabulaire de la dimension.

## Vérifications

- `flutter test test/features/flux_continu/utils/essentiel_deck_test.dart` — 11 ✅
  (tri en cours → pas de deck, carte du dessus **et** ligne gardée ; tri terminé →
  gardés seuls dans l'ordre du slate, rejetés exclus, `later` inclus ; gardé venu
  du carrousel / du réseau présent ; un seul gardé → pas de deck ; lettre passée →
  lettre entière).
- Régression ciblée : `test/features/detail/deck/` + `essentiel_hi_fi_card_test.dart`
  → 134 ✅.
- `flutter analyze` sur les fichiers touchés → 0 issue.
- Suite mobile complète : échecs strictement identiques à la base (goldens
  `ring_avatar`, bootstrap Supabase/Hive).

Backend : aucun changement, aucune migration.

## À valider côté PO (staging)

1. Tri en cours → tap sur la carte du dessus : l'article s'ouvre, **aucun** swipe
   inter-articles, la barre de progression du header n'est pas segmentée.
2. Tri terminé → tap sur un article de « Tes articles » : le swipe enchaîne les
   gardés, dans l'ordre de la liste, et **jamais** un rejeté.
3. « Plus d'articles ? » / « Refaire ? » relancent le tri ⇒ retour au cas 1.
4. Lettre passée (⏪) : navigation inchangée sur toute la lettre.
