# Bug — Curation « en entrée » des sections thématiques (Tournée du jour)

> Suite de `bug-curation-qualite-sections-thematiques.md` (2026-06-01), qui avait
> traité le **ranking** (routage vers le PillarScoringEngine) et la **rareté**
> (fenêtre adaptative). Ce document traite ce qui n'avait pas été vu : le
> **volume réellement affiché** et le **signal « ça ne ressemble pas à de l'actu »**.

Branche : `claude/tournee-jour-curation-issue-ou0gi5` (repartie de `main` @ f4fb305a).

## Symptôme (PO)

1. Une section thème de la Tournée (Technologie, Environnement…) plafonne à
   **6-7 articles**, alors que le même thème filtré dans **Flâner** en donne
   **15+**, depuis les **mêmes sources suivies**.
2. Les **3 articles previewés** en tête de bloc sont souvent les moins
   intéressants : épisodes de podcasts et feuilletons (« … 4/7 : … ») occupent
   des slots que l'actualité devrait avoir.

---

## Partie 1 — Pourquoi 6-7 et pas 15+

### Le contenu existe : ce n'est pas un problème de pool

Mesuré sur `fd6b9d0b-4c16-422b-9688-bae34d63f41c` (72 sources suivies), articles
des **sources suivies uniquement**, mutes + articles masqués déduits :

| thème | 24 h | 48 h | 7 j |
|---|---|---|---|
| tech | 29 | 68 | 226 |
| environment | 50 | 103 | 283 |

Le backend a donc largement de quoi remplir. La perte est **en aval**, dans une
cascade de 5 étranglements dont aucun n'existe côté Flâner.

### ⚠️ Révision après précision PO (2026-07-25)

Le PO précise : **pas de mode serein**, et dans les **deux** vues il compare des
articles **publiés dans les dernières 24 h**, tous de sources suivies.

Cela **invalide les étranglements A et E** comme explication du symptôme (la
fenêtre 24 h contient déjà 29-50 articles, largement de quoi remplir). La cause
racine est **l'étranglement C**, et elle est plus précise que décrit ci-dessous :
voir « Cause racine confirmée » plus bas. Les sections A/E restent documentées
comme dette technique réelle mais hors du chemin critique.

### Étranglement A — fenêtre de fraîcheur 24 h, quasi jamais élargie

`recommendation_service.py::_get_candidates` (branche `personalized_theme_mode`)
part à 24 h et n'élargit à 48 h puis 72 h que si le pool tombe sous
`ScoringWeights.THEMATIC_MIN_POOL_SIZE = 8`.

Deux problèmes :
- **Le seuil (8) est sous la taille de page (10).** Un pool de 9 satisfait le
  seuil, ne déclenche aucun élargissement, et ne remplit pourtant même pas la
  première page.
- **Flâner n'a aucune fenêtre.** La branche `followed_only`
  (`recommendation_service.py:2785`) ne pose aucun prédicat `published_at`.
  D'où 226 candidats côté Flâner vs 29 côté Tournée sur `tech`. **C'est la
  source principale de l'asymétrie perçue.**

### Étranglement B — taille de page 10 vs 20

`flux_continu_provider.dart:96` : `_kThemeSectionPageLimit = 10`.
`feed_provider.dart:169` (Flâner) : `_limit = 20`.

### Étranglement C — dédup inter-sections (le chaînon manquant du « 6-7 »)

`flux_continu_provider.dart::_dedupeSectionsInOrder` (L1230) retire de chaque
section tout article **déjà rendu plus haut** dans la Tournée : Essentiel (5
articles), Actus du jour, Bonnes Nouvelles, et les sections thème précédentes.

C'est une règle produit légitime (pas de doublon dans une même page), mais elle
s'applique **après** le fetch, sans compensation : la section demande 10, en
perd 3-4 au profit des sections amont, et **affiche 6-7**. Flâner n'a aucune
dédup de ce type.

Le rattrapage existant (`_backfillThinSections`, L950) ne se déclenche que pour
les sections tombées à **≤ 1** article (`kThinSectionMaxItems = 1`) et ne remonte
qu'à **2** (`kRichSectionMinItems`). Une section qui passe de 10 à 6 n'est jamais
rattrapée.

### Étranglement D — verrou de pagination

`flux_continu_provider.dart:1563` :

```dart
bool _themeHasMore(bool hasNext, int itemCount) =>
    hasNext && itemCount >= _kThemeSectionPageLimit;   // ≥ 10
```

Flâner (`feed_provider.dart:730`) : `hasNext && items.isNotEmpty`.

Conséquence : dès que le backend renvoie une page **incomplète** alors qu'il
reste des candidats (`has_next: true`), le scroll infini de la page dédiée est
**définitivement** coupé. Ce cas se produit réellement : `total_candidates` est
figé **avant** les post-filtres Python (entités mutées, filtre entité —
`recommendation_service.py:576` puis L579-631), donc `has_next` peut être vrai
avec une page courte.

### Étranglement E — mode serein (amplificateur)

Si le mode serein est actif, `apply_serein_filter` coupe sur `is_serene` :

| thème | 24 h total | `is_serene = true` |
|---|---|---|
| environment | 56 | **12** (−79 %) |
| tech | 39 | 24 (−38 %) |

Sur Environnement en serein, le pool 24 h tombe à ~12, puis mutes + dédup
inter-sections → **6-7 affichés, et `hasMore = false`**. Le compte est bon.

---

## Cause racine confirmée — l'exclusion digest serveur est morte, la dédup client encaisse tout

### Le mécanisme, bout à bout

`recommendation_service.py:468-482` (Story 10.20) doit exclure du feed les
articles du digest du jour :

```python
items_raw = digest_row.items          # attendu : list[{content_id: ...}]
if isinstance(items_raw, str): items_raw = json.loads(items_raw)
if items_raw:
    digest_content_ids = [
        UUID(item["content_id"])
        for item in items_raw
        if isinstance(item, dict) and item.get("content_id")
    ]
```

Or `daily_digest.items` est en `format_version = "editorial_v3"` : un **objet**
`{mode, metadata, subjects[]}`, pas une liste plate. Itérer un dict renvoie ses
**clés** (`"mode"`, `"metadata"`, `"subjects"`) → `isinstance(item, dict)` est
faux pour chacune → `digest_content_ids = []`, **sans exception donc sans
warning Sentry**. L'exclusion serveur est un **no-op silencieux** depuis le
passage à `editorial_v3`. Les `content_id` y vivent sous
`subjects[].representative_content_id`, `subjects[].actu_article.content_id` et
`subjects[].extra_actu_articles[].content_id`.

Conséquence : la section thème reçoit ses 10 articles **digest inclus**, puis le
client (`_dedupeSectionsInOrder`) les retire parce que l'Essentiel et Actus du
jour les ont déjà rendus plus haut. **La dédup s'applique après le slice de
pagination : ce qui est retiré n'est jamais remplacé.**

Et l'overlap n'est pas accidentel : la section thème est classée par le
PillarScoringEngine, le digest sélectionne les meilleurs articles du jour — les
deux convergent structurellement sur les mêmes têtes de liste.

### Vérification chiffrée (digest `pour_vous` du 2026-07-25, compte de référence)

| mesure | valeur |
|---|---|
| articles distincts rendus par le digest | 14 |
| dont publiés < 24 h | **14 / 14** |
| dont `theme = environment` | **4** |
| dont `theme = tech` | 0 (ce jour-là) |

Section Environnement : **10 demandés − 4 retirés par la dédup = 6 affichés.**
C'est exactement le symptôme. Flâner, qui n'a aucune dédup inter-sections et
demande 20 par page, en montre 15-20 sur le même pool de 24 h.

---

## Partie 2 — Les articles « pas de l'actu » en tête de bloc

### Le signal existe déjà mais n'est pas branché sur le feed

`recommendation/filter_presets.py::is_news_bulletin_title` (L515) porte déjà
`NEWS_BULLETIN_PATTERNS` — JT, revues de presse, chroniques, et **un** pattern
de feuilleton : `\(\s*\d{1,2}\s?/\s?\d{1,2}\s*\)\s*$` (compteur parenthésé en
fin de titre).

Il n'est appelé que par `essentiel_service`, `editorial/actu_matcher` et
`editorial/pipeline` — **jamais** par le scoring piliers qui classe les sections
thématiques. Aucun pilier (`pertinence`, `source`, `fraicheur`, `qualite`) ni
`PenaltyPass` ne regarde le titre.

### Ce que le pattern actuel rate (relevé réel, 7 derniers jours)

Le compteur de série est presque toujours **non parenthésé et au milieu du
titre**, donc non détecté :

- `Les sciences dans le règne animal 4/4 : Emotions des cétacés…` (La Science CQFD)
- `Et si nous vivions dans une simulation 3/3 : Ce qu'on gagne à interroger…` (Le Code a changé)
- `La révolution numérique 2/10 : 1942-1946, l'ENIAC…` (France Culture)
- `La mémoire des vaincus… 13/25 : On l'appelait La Pastora` (France Culture)
- `Les cosmologies, mythes et sciences du monde 4/22 : L'Inde` (France Culture)
- `#IA (7/10). Société : le grand effritement` (Sismique)
- `QSPTAG #332 — 24 juillet 2026` (La Quadrature du Net)

### Le piège à éviter : les dates JJ/MM

Un `\d{1,2}/\d{1,2}` naïf attrape aussi de la **vraie actu** :

- `Édition spéciale : feu en Gironde, 3 400 hectares brûlés - 23/07`
- `BFM Conso : Incendies, ce qu'ils coutent (vraiment) à la France - 24/07`
- `intensité du feu en gironde par vue satellite le 24/07`

Deux discriminants suffisent et couvrent 100 % de l'échantillon relevé :
1. **`N ≤ M`** — un compteur de série a son index sous son total (`4/22`,
   `13/25`, `3/3`) ; une date a `JJ > MM` 11 mois sur 12 (`24/07`).
2. **Suivi de `:` ou entre parenthèses** — le compteur de série introduit un
   sous-titre (`4/4 : …`, `(7/10).`) ; la date termine le titre.

### Volume (garde-fou anti-sur-déclenchement)

Sur 14 660 articles des 7 derniers jours :

| motif | matches |
|---|---|
| `N/M` brut (dates incluses) | 143 (1,0 %) |
| `épisode N` | 5 |
| `#NNN` | 38 |
| `SxxEyy` | 0 |
| `partie N` / `volet N` | 1 |

Après application des deux discriminants : **~70-80 titres/semaine**, soit
~0,5 % du corpus. Périmètre étroit et sûr.

---

## Plan technique retenu (arbitrages PO du 2026-07-25)

Décisions PO : **taille de page maintenue à 10** + lazy loading ; **éviter les
régressions** (choix technique délégué) ; **malus feuilleton limité à la
Tournée**. Fenêtre 24 h et mode serein : hors scope (non impliqués).

### Lot 1 — Volume

| # | Fichier | Changement | Risque |
|---|---|---|---|
| 1.1 | `recommendation_service.py` | Extraire correctement les `content_id` du format `editorial_v3` (`subjects[].representative_content_id` + `actu_article` + `extra_actu_articles`), en gardant le chemin `flat_v1`. Helper dédié + test sur les deux formats. | faible |
| 1.2 | `recommendation_service.py` | N'appliquer l'exclusion digest **que** si `personalized_theme_mode` — Flâner garde son volume actuel (il n'a pas de dédup client, exclure côté serveur l'amputerait). | faible, ciblé |
| 1.3 | `flux_continu_provider.dart` | `_themeHasMore` → `hasNext && itemCount > 0` (parité `feed_provider.dart:730`) | faible |
| 1.4 | `theme_section_screen.dart` | Top-up post-frame : si `items.length < _kThemeSectionPageLimit && hasMore`, déclencher `loadMoreTheme` sans attendre le scroll. Borné à 2 tours. | faible, page dédiée uniquement |
| 1.5 | `flux_continu_provider.dart` | `loadMoreTheme` : dédupliquer les items appendés contre `renderedContentIds` (aujourd'hui il n'appende que contre les items de sa propre section → une page 2 peut ré-afficher un article déjà rendu par l'Essentiel). | faible |

**1.1 + 1.2 sont le cœur** : la section demande 10 et reçoit 10 articles qui
survivront à la dédup client → 10 affichés au lieu de 6. La dédup passe
d'« après le slice » (destructrice) à « avant le slice » (compensée), sans
toucher aux règles de composition de la Tournée — c'est le chemin à plus faible
surface de régression.

**1.3 + 1.4** couvrent le cas résiduel (thème réellement pauvre) : le lazy
loading ne se coupe plus et se déclenche sans exiger que l'utilisateur scrolle
jusque sous les carrousels / « Explorer plus ».

Écartés : taille de page 20 (choix PO), élargissement de la fenêtre, extension
de `_backfillThinSections` (touche la composition → risque de régression).

### Lot 2 — Dépriorisation « non-actualité » (Partie 2), **Tournée uniquement**

1. **`filter_presets.py`** — nouvelle fonction `serial_episode_signal(title)`,
   distincte de `is_news_bulletin_title` (qui sert à **exclure** de l'Essentiel ;
   ici on veut seulement **déprioriser**). Patterns :
   - `N/M` avec `N ≤ M` **et** suivi de `:` / `.` / fin, ou entre parenthèses
   - `épisode|ép.|ep. N`, `SxxEyy`, `partie N`, `volet N`, `#NNN`
   - garde explicite anti-date : rejet si `N > M` ou si `M ≤ 12` et le motif
     termine le titre sans sous-titre
2. **`pillars/penalties.py`** — `PenaltyPass` applique un malus **absolu et
   léger** sur le score composite (échelle 0-100) :
   `SERIAL_TITLE_MALUS = -6.0` (à calibrer). À comparer aux malus existants
   (source mutée −80, thème muté −40) : c'est bien « un cran plus bas », pas une
   exclusion. Contribution exposée dans le `recommendation_reason`
   (« Épisode d'une série ») pour rester explicable.
3. **Périmètre — tranché PO : Tournée uniquement.** `PenaltyPass` ne connaît pas
   le mode aujourd'hui ; on ajoute un champ `personalized_theme_mode: bool` à
   `ScoringContext` (comme `cluster_source_counts` qui porte déjà un état
   spécifique au mode thématique) et le malus n'est appliqué que s'il est vrai.
   « Pour vous », Flâner et le digest sont inchangés.

### Hors-scope, à noter

- **Doublons d'ingestion** : 171 groupes `(source_id, title)` en double sur 7 j
  (197 lignes en trop, ~1,3 % du corpus) — ex. « Et si nous vivions dans une
  simulation 3/3 » présent 2×. Consomme des slots de section. À traiter dans un
  ticket dédié (dédup RSS sur `guid`/titre).

## Vérification prévue (phase CODE)

- Test unitaire d'extraction digest sur les **deux** formats (`flat_v1`,
  `editorial_v3`) — le no-op silencieux actuel doit devenir un échec de test.
- Script one-off sur le compte de référence : nombre d'articles servis par la
  section `environment` **avant/après**, et taille de l'intersection avec les
  articles du digest du jour (doit passer de 4 à 0).
- Test de non-régression Flâner : `followed_only` ne doit **pas** hériter de
  l'exclusion digest (volume inchangé).
- Tests unitaires `serial_episode_signal` : les 7 titres feuilletons relevés
  → `True` ; les 3 titres datés JJ/MM → `False`.
- Test scoring : à pertinence/source/fraîcheur/qualité égales, un titre
  feuilleton se classe sous un titre d'actu en `personalized_theme_mode`, et
  **pas** de changement de classement hors de ce mode.
- `pytest -v` backend + `flutter test` + `flutter analyze`.
- QA Playwright : ouvrir Technologie et Environnement, compter les articles,
  vérifier que le lazy loading ne se coupe plus.

## Résultats (phase CODE — 2026-07-26)

### Implémenté

- [x] **1.1** — extraction déléguée à `extract_content_ids` (helper partagé,
  connaît `flat_v1` / `topics_v1` / `editorial_v*`). Pur Python sur une ligne
  déjà chargée en phase 1.
- [x] **1.1 bis** — `extract_content_ids` récupère aussi
  `subjects[].representative_content_id`. Le pivot diffère d'`actu_article` sur
  **3 sujets sur 6** dans le digest de référence ; il était donc invisible à la
  fois pour l'exclusion feed **et** pour le storage cleanup, qui pouvait
  supprimer la ligne dont dépend le bottom sheet Perspectives.
- [x] **1.1 ter** — `digest_stmt` filtre sur `is_serene`. Sans ce prédicat, un
  compte disposant des deux digests du jour en tirait un **au hasard**
  (`session.scalar` ne lève pas sur plusieurs lignes) : l'exclusion pouvait
  porter sur les articles de l'autre digest.
- [x] **1.2** — exclusion restreinte à `personalized_theme_mode`.
- [x] **1.3** — `_themeHasMore` aligné sur Flâner (`hasNext && itemCount > 0`).
- [x] **1.4** — top-up post-frame sur la page dédiée, borné à 2 tours.
- [x] **1.5** — `loadMoreTheme` déduplique contre toute la Tournée
  (`renderedContentIds`), plus seulement contre sa propre section.
- [x] **Terminateur** — une page non vide dont aucun item ne survit à la dédup
  passe `hasMore=false`. Remplace, en plus précis, l'ancienne règle « page
  incomplète ⇒ fin » : sans lui, `_themeHasMore` assoupli laissait tourner
  l'indicateur de chargement et rendait la carte de clôture inatteignable.
- [x] **Lot 2** — `is_serial_episode_title` + `SERIAL_EPISODE_MALUS = -6.0`
  dans `PenaltyPass`, gaté par `ScoringContext.personalized_theme_mode`.

Écartés comme prévu : page à 20, élargissement de fenêtre, extension de
`_backfillThinSections`.

### Coût — exigence PO « n'alourdir aucune requête »

`EXPLAIN` sur la prod, section `environment`, 24 h, sources suivies :

| | coût estimé |
|---|---|
| sans le `NOT IN` | 735.15 |
| avec le `NOT IN` (14 UUID) | 739.58 |

**Plan identique**, au nœud près. Postgres compile le `NOT IN` en
`id <> ALL (…)` évalué en filtre sur les lignes déjà remontées par
`ix_contents_source_published` — aucun accès index ou table supplémentaire.
**+0,6 %**, et **0 requête ajoutée** (le prédicat `is_serene` s'ajoute à une
requête déjà exécutée ; l'extraction est du Python sur une ligne en mémoire).

Le check regex ne tourne que sur les candidats d'une section de la Tournée
(gate `personalized_theme_mode`), 4 regex compilées sur un titre ≤ 500 car.

### Preuve empirique

Digest `pour_vous` du jour, compte de référence : **14 articles distincts
rendus, tous publiés < 24 h, dont 4 en `theme=environment`** — soit les 4
articles que la dédup client retirait de la section Environnement (10 − 4 = 6,
le symptôme exact). Ils sont désormais exclus **avant** le slice : la section
sert 10 articles réellement affichables.

Précision d'honnêteté : la part du digest dans le pool varie d'un jour à
l'autre (relevé du lendemain : 2 sur 39 pour `environment`, 0 sur 25 pour
`tech`). L'overlap n'est pas uniforme dans le pool — il se **concentre en tête
de classement**, puisque la section est triée par le PillarScoringEngine et que
le digest sélectionne les meilleurs articles du jour. C'est précisément la
tranche que le slice de 10 prélève. Le reste de la perte (chevauchement avec
une autre section thème rendue plus haut) est couvert par 1.3 + 1.4.

Signal feuilleton — volume sur les sources suivies du compte, 72 h : **3
titres flaggés** (2 `tech`, 1 `culture`). Faible par construction (~0,5 % du
corpus) : l'objectif n'est pas le volume mais d'empêcher qu'une série qui
tombe en rafale (un 4/4, une série en 22 épisodes) ne monopolise les 3 slots
previewés.

### Tests

- Backend : **2516 passed, 30 skipped**, 0 échec (suite complète).
- `ruff check app/` : clean. `ruff format --check app/` : clean (un échec
  pré-existant hérité de `main` sur `app/utils/time.py` a été repris dans un
  commit `style:` distinct — il rendait la CI rouge indépendamment de cette PR).
- Nouveaux : `tests/test_serial_episode_signal.py` (23 cas — 9 feuilletons
  réels détectés, 9 actualités datées JJ/MM épargnées, gate Tournée,
  calibration du malus), 2 cas dans `tests/test_thematic_curation.py`
  (exclusion appliquée en Tournée / **non** appliquée en Flâner), 1 cas dans
  `tests/test_digest_content_refs.py` (pivot extrait).
- Mobile : test de pagination réécrit (une page courte ne coupe plus la
  pagination) + nouveau test du terminateur « page entièrement dédupliquée ».

### ⚠️ Limite de vérification

`flutter test` et `flutter analyze` **n'ont pas pu être exécutés** : aucun SDK
Flutter/Dart n'est installé dans cet environnement d'exécution. Les
modifications Dart ont été relues à la main et l'impact sur les tests existants
tracé un par un (les stubs `hasNext: false` des autres suites sont inertes
sous la nouvelle règle ; `_LoadingFluxNotifier` court-circuite le top-up via
`state.valueOrNull == null`). **La CI ou un run local doit valider le mobile
avant merge.**

## Tasks

- [x] GO PO sur le plan révisé
- [x] Lot 1 — backend (1.1, 1.2)
- [x] Lot 1 — mobile (1.3, 1.4, 1.5)
- [x] Lot 2 — `serial_episode_signal` + `PenaltyPass` gaté Tournée
- [x] Preuve empirique avant/après
- [x] Suite de tests backend complète
- [ ] `flutter test` + `flutter analyze` (bloqués — pas de SDK ici, à valider en CI)
