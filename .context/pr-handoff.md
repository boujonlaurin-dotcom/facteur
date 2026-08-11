# Essentiel — l'objectif devient « articles à garder », la pile alimente jusqu'à la cible

Story : `docs/stories/core/33.4.essentiel-objectif-articles-gardes.md`
(suit 33.3, même branche)

## Le problème

Le stepper `[−] N [+] articles à lire aujourd'hui` réglait en réalité **la
taille du slate à trier**. Pour l'utilisateur ça n'a aucun sens : il annonce
« je veux lire 5 articles », on lui en présente 5, il en refuse 3, il termine sa
journée avec 2.

## 1. `target` (taille du slate) → `goal` (nombre de gardés)

`essentiel_triage_provider.dart` — c'est le cœur du lot.

`effectiveTriageTarget(target, poolLength)` **disparaît** : la cible ne dépend
plus du pool. C'est cette dépendance qui rendait le slate et l'objectif
indissociables.

| Avant | Après |
|---|---|
| `startIfNeeded(pool)` — gèle `pool.take(cible)` + branche de réconciliation cold-boot | `syncSlate(pool)` — gèle l'ordre au 1er appel, puis **append en queue**. Plus de `take`, plus de réordonnancement. La réconciliation devient sans objet |
| `setTarget(n, pool)` — allonge/raccourcit le slate | `setGoal(n)` — ne touche **plus au slate**. Baisser la cible ne détruit donc plus rien, et « ne jamais perdre une décision » devient structurellement impossible à violer |
| — | `extendGoal(delta)` (le CTA, sans plafond haut), `stopTriage()`, `dismissStopNudge()` |

`done = stopped || goalReached || poolExhausted`. `later` continue de compter
comme gardé (décision PO reconduite), et l'auto-keep lecture aussi.

`consecutivePassCount` est un **getter dérivé du slate**, sans champ persisté :
il se réinitialise seul dès qu'un article est gardé et survit au cold-boot.

**Bump de clé `essentiel_triage_v2_`** + purge one-shot des clés `v1` : leur
champ `target` était une taille de slate ; le relire comme un objectif donnerait
« garde 7 articles » à qui avait demandé une pile de 7. Coût assumé : un tri en
cours le jour du déploiement repart à zéro.

## 2. [Le point critique] La pile peut réellement délivrer plus d'articles

Sans ça, « N articles à garder » n'aurait été qu'une promesse.

**Mobile** — `/more` n'était appelé que par le tap sur « Plus d'articles ? ». Il
part maintenant **avant** que la pile ne sèche : moins de 2 articles à proposer
+ cible non atteinte ⇒ lot de 5, posté après la frame, **aucune UI d'attente**.
Trois gardes cumulées contre la boucle réseau : `_inFlight`, cooldown
d'épuisement de 10 min (en mémoire, forcé par un geste utilisateur), plafond de
6 prefetchs. Un échec réseau n'est **pas** un épuisement : une coupure de 3 s ne
doit pas figer la pile 10 min.

**Backend** (read-only, aucune migration) :

1. **Les exclusions partent dans le SQL, avant le `LIMIT`.** C'est la correction
   la plus rentable du lot : les ids déjà détenus par le client étaient filtrés
   en Python *après* le cap de 30 candidats, donc ils consommaient les slots et
   la fenêtre utile rétrécissait à chaque tour — au bout de deux
   élargissements, « Plus d'articles ? » ne trouvait plus rien alors que la base
   en avait. Test : 40 articles dont 35 exclus (et les plus frais) ⇒ les 5
   restants sortent quand même.
2. Cap de candidats dédié `ESSENTIEL_MORE_CANDIDATE_CAP = 80` (le blend digest
   garde ses 30).
3. Fenêtre en paliers `24h → 48h → 72h`, qui s'arrête dès que `limit` est tenu.
   L'`ORDER BY published_at DESC` garde la fraîcheur en tête.

**Bornes de schéma élargies — jamais resserrées** (compat prod, DB partagée) :

| Champ | Avant | Après | Pourquoi |
|---|---|---|---|
| `EssentielArticle.rank` | `le=5` | `le=50` | avec `limit=10`, les rangs 6..10 levaient une `ValidationError` **en production** (piège n°3 de la 33.3, rejoué) |
| `TriageBatchRequest.slate_size` | `le=20` | `le=200` | le slate n'est plus borné par la cible ; le routeur valide `rank <= slate_size` ⇒ 422 en pleine session |
| `MAX_MORE_EXCLUDE_IDS` | 100 | 300 | la troncature `split(",")[:N]` est silencieuse : au-delà, on reproposait des articles déjà écartés |
| `/more?limit=` | `le=5` | `le=10` | lots de prefetch |

## 3. UI

- **Barre de progression** → compte les **gardés**, pas les triés. Plus de
  segment « courant » : la progression n'est plus positionnelle, elle est
  cumulative. Tokens plus discrets (segment 4→2, slot 8→4, écart 3→4,
  remplissage `alpha 0.7`) — des traits fins et espacés se lisent comme un
  repère, pas comme une jauge de jeu. Le chiffre passe dans la sémantique
  (« Articles gardés : 2 sur 5 »).
- **Stepper** → `Je veux lire [−] N [+] articles aujourd'hui`. Bornes
  `[3, 10]`, plus aucune dépendance au pool (`poolIds` sort de la signature).
  Le fragment `· Y à trier` **disparaît** : le reste à trier n'est plus
  déterminé, l'afficher mentirait.
- **« Trier à nouveau » → « Refaire ? »**, 12/w500/`textTertiary`, hauteur
  34→28. La sémantique reste « Refaire le tri » (« Refaire ? » seul est trop
  pauvre pour un lecteur d'écran).
- **Fin de tri : l'objectif n'est plus affiché.** Un tri qui s'arrête en deçà de
  la cible ne doit jamais se lire comme un échec.
- **CTA « Plus d'articles ? »** simplifié : plus de branche « réserve locale vs
  réseau » (le slate porte déjà tout le pool local), juste `extendGoal(2)` ; si
  le slate est épuisé, un `fetchMore(force: true)`. `injectableIds` devient mort
  et est retiré.

## 4. Nudge « tu peux t'arrêter là »

5 refus enchaînés (décision PO) ⇒ bandeau inline sous la barre d'actions :
« Rien ne t'accroche ? Tu peux t'arrêter là. » + « Arrêter le tri » + croix.

Réutilise `NudgeInlineBanner` **sans passer par `NudgeCoordinator`** : son
cooldown global de 24 h et son budget de session sont faits pour des
sollicitations transverses, pas pour un signal contextuel intra-session qui doit
apparaître au moment exact où l'utilisateur s'entête. Même justification que
`preview_nudge_scheduler.dart`.

Il disparaît de lui-même dès qu'un article est gardé — aucun code de nettoyage,
le getter repart à 0.

## 5. Analytics

- `essentiel_triage_decision` : + `goal`. ⚠️ `slate_size` garde son nom mais
  change de sens (taille du pool proposé, **croissante**) — documenté dans le
  docstring pour les requêtes historiques.
- `essentiel_triage_session` : + `goal`, `goal_reached`, `ended_by`
  (`goal` | `exhausted` | `stopped`), `auto_fetches`. **C'est la mesure du
  lot** : la part de `exhausted` dira si la pile sèche encore avant la cible,
  donc si l'élargissement du pool a suffi.
- nouvel event `essentiel_triage_stop_nudge` (`shown` / `accepted` /
  `dismissed`) : le ratio accepted/shown dira si le seuil de 5 est le bon.

## Vérification

- `pytest -q` → **3084 passed**, 21 skipped, 2 xfailed. Dont 8 tests neufs :
  exclusions poussées en SQL, paliers 24/48/72 h, rangs 1..10 sérialisés,
  `limit=10` accepté / `limit=11` rejeté, 250 exclusions non tronquées,
  `slate_size=60` + `rank=57` ⇒ 200.
- `flutter test` sur le périmètre : `essentiel_triage_provider_test` **54
  passed** (groupe « cible du jour » réécrit en entier), `essentiel_hi_fi_card_test`
  **83 passed**, `essentiel_extra_articles_provider_test` **14 passed**,
  `section_fit_test` + squelette OK.
- `flutter test` complet : 2268 passed / **26 échecs pré-existants**, tous hors
  périmètre (settings, custom_topics, digest bookmarks, feed, notification,
  `widget_test` — Hive/Supabase non initialisés). Aucun échec dans
  `flux_continu/{widgets,providers,utils}`.
- `flutter analyze` → **0 erreur**, aucun warning sur les fichiers touchés.

## Migration

Aucun DDL, aucune migration Alembic. Le backend est read-only et toutes les
bornes de schéma sont **élargies**, jamais resserrées ⇒ l'ancien backend `prod`
continue d'accepter les payloads de l'ancien mobile pendant la semaine de
décalage (règle expand-contract, DB Supabase partagée).

## Limite connue, hors scope

Un utilisateur sans source suivie ni thème apprécié fait sortir
`_fetch_live_supplements` sur `return [], 0` : pool vide quoi qu'on élargisse.
La pile se termine alors proprement sur `poolExhausted`, et comme la fin de tri
n'affiche plus l'objectif, rien ne se lit comme un échec. À traiter dans un lot
« pool de repli » séparé.
