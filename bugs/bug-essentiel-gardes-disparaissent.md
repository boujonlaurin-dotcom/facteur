# Bug — Les articles gardés disparaissent de l'Essentiel (et reviennent au refresh)

**Type** : Bug · **Surface** : mobile (carte « Ton Essentiel », pile de tri 33.1→33.4)
**Statut** : corrigé

## Symptôme (PO)

> « J'ai trié cinq articles, je les ai lus, j'ai fermé l'app et je l'ai killée sur
> Android. Je suis revenu : il ne restait que **trois** de mes articles, deux
> avaient disparu. J'en ai ajouté deux nouveaux, je les ai lus, kill à nouveau —
> et à nouveau il en manquait. Ensuite j'ai fait un pull-to-refresh et **un
> article est réapparu comme par magie au milieu de la liste** : c'était un de
> ceux que j'avais mis de côté, bien marqué comme gardé. »

Règle produit attendue : **un article gardé est gardé pour toute la journée. Il
ne bouge pas, ni au kill de l'app, ni au refresh.**

## Répro

1. Trier le slate du jour, garder N articles (« Je garde » ou « Plus tard »).
2. Ouvrir et **lire** les articles gardés.
3. Attendre > 30 min (`ESSENTIEL_READ_EVICTION_GRACE`), tuer l'app, la rouvrir.
4. La liste des gardés ne contient plus que les gardés **non lus** (ou lus dans
   les 30 dernières minutes).
5. Pull-to-refresh ⇒ certains gardés réapparaissent, à leur place d'origine dans
   la liste (« au milieu »).

## Cause racine — la liste des gardés est un **jeu d'ids résolu contre un pool volatil**

Le tri persiste **des `contentId`, jamais les articles**
(`essentiel_triage_provider.dart` : `slate` + `decisions`, blob jour
`essentiel_triage_v2_<dayKey>`). Le rendu, lui, résout ces ids contre le pool
*courant* de la carte et **saute silencieusement** ce qu'il ne trouve pas :

```dart
// essentiel_hi_fi_card.dart (tri terminé)
final byId = {for (final a in pool) a.contentId: a};
passiveArticles = [
  for (final id in triage.keptContentIds)
    if (byId[id] != null) byId[id]!,   // ← un gardé introuvable est jeté
];
// essentiel_triage_stack.dart (kept-list pendant le tri) : même `if (byId[id] != null)`
```

Or ce pool — `articles` (`GET /api/essentiel`) + items du carrousel du jour +
articles rapatriés par `/more` — **n'est pas stable sur la journée** :

| Composante du pool | Stabilité | Ce qui la casse |
|---|---|---|
| `GET /api/essentiel` | ❌ | « Essentiel vivant » (story 9.8) **évince activement les articles lus** et les remplace par du frais, cap 5 (`build_essentiel_response_with_supplements`, `_W_READ_PENALTY`, `ESSENTIEL_READ_EVICTION_GRACE = 30 min`) |
| items du carrousel | ❌ | jamais persistés — absents de l'hydratation au cold-boot |
| `/more` (`essentielExtraArticlesProvider`) | ✅ | payloads bruts persistés dans `essentiel_extra_v1_<dayKey>` |

D'où **exactement** les trois observations du PO :

1. **« deux ont disparu »** — les gardés que l'utilisateur a *lus* sortent de la
   réponse `/essentiel` passée la grâce de 30 min. La décision `keep` est
   toujours en base locale (`pruneUnavailable` conserve explicitement les ids
   décidés), mais plus rien ne peut la **rendre** : l'article est jeté au build.
   Ce sont donc précisément les articles lus qui s'évaporent — ceux auxquels
   l'utilisateur tenait le plus.
2. **« encore après avoir ajouté deux articles »** — les deux nouveaux venaient
   de `/more` (persistés, donc survivants) ; ce qui manquait à nouveau, c'était
   la fraction lue du slate initial. Même mécanisme.
3. **« un article réapparu par magie au milieu »** — le blend live a re-servi cet
   id dans la réponse suivante ; il redevient résolvable, et `keptContentIds`
   itérant le **slate gelé**, il se réinsère à sa place d'origine, donc au milieu
   de la liste. La « magie » est le symptôme miroir du même défaut.

En une phrase : **le tri persiste une décision sans persister son objet.** La
carte a un contrat de stabilité à la journée, adossé à une source de vérité qui
tourne à chaque requête.

## Correctif — archiver le **payload** des gardés pour la journée

Nouveau `essentielKeptArticlesProvider`
(`providers/essentiel_kept_articles_provider.dart`) : une **archive jour** des
articles gardés, clé `essentiel_kept_v1_<dayKey>`, purgée comme les autres blobs
jour (`TourneeProgressService.purgeDatedPrefsKeys`). Elle reprend le patron déjà
éprouvé de `essentielExtraArticlesProvider` — persister le payload, pas l'id.

- **Capture** : à chaque build, la carte confie à l'archive les gardés que le
  pool sait encore résoudre (`sync`). Un article ne peut être gardé que s'il est
  en haut de pile, donc dans le pool à cet instant : la capture est garantie, et
  elle se **rafraîchit** tant que l'article reste servi (état de lecture, saved,
  couverture à jour).
- **Résolution** : le rendu résout désormais contre `pool ∪ archive`, le pool
  gagnant quand il porte l'article (payload le plus frais). Un gardé évincé par
  le blend live retombe sur son archive au lieu d'être jeté.
- **Bornage** : `sync` reçoit aussi l'ensemble des ids réellement gardés et
  **retire** de l'archive tout le reste — « Refaire ? » (`restart()`) et un
  `pass` après coup nettoient donc derrière eux. L'archive ne peut pas grossir
  au-delà du nombre de gardés du jour.
- **Sûreté d'hydratation** : tant que l'archive n'est pas relue
  (`hydrated == false`), elle n'élague rien — sans quoi le premier build après un
  cold-boot effacerait ce qu'on vient d'écrire la veille au soir.

Mobile-only : aucune migration, aucun changement de contrat d'API.

### Ce que le correctif ne change délibérément pas

- **Le blend live reste vivant.** Évincer un article lu de la réponse est le
  comportement voulu par la story 9.8 : la carte doit se regarnir au fil de la
  journée. Le défaut n'était pas l'éviction, c'était que la **liste des gardés**
  en dépende.
- **`pruneUnavailable` reste en place** : il protège la *pile* (haut de pile
  irrésolvable ⇒ carte figée) et ne touche déjà pas aux ids décidés.
- **La durabilité s'arrête au device**, comme tout le reste de l'état de tri
  (slate, décisions, objectif). Une réinstallation en cours de journée repart à
  zéro. Rendre les gardés portables demanderait de relire
  `essentiel_triage_decisions` dans `GET /api/essentiel` et d'y épingler les
  gardés — ce serait une story, pas un fix de bug ; noté comme suite possible.

## Fichiers

- **Nouveau** : `apps/mobile/lib/features/flux_continu/providers/essentiel_kept_articles_provider.dart`
- `apps/mobile/lib/features/flux_continu/widgets/essentiel_hi_fi_card.dart`
- **Nouveau** : `apps/mobile/test/features/flux_continu/providers/essentiel_kept_articles_provider_test.dart`
- `apps/mobile/test/features/flux_continu/widgets/essentiel_hi_fi_card_test.dart`

## Vérification

- Test provider : capture, rafraîchissement du payload, éviction hors gardés,
  survie au cold-boot, purge des jours passés, pas d'élagage avant hydratation.
- Test carte : un gardé **absent du pool** (le cas « lu puis évincé ») est rendu
  depuis l'archive après redémarrage ; l'ordre du slate est conservé.
- `flutter test` + `flutter analyze` verts.
