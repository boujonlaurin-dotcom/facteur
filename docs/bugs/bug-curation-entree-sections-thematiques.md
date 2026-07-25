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

## Plan technique proposé

### Lot 1 — Volume (Partie 1)

| # | Fichier | Changement | Risque |
|---|---|---|---|
| 1.1 | `scoring_config.py` | `THEMATIC_MIN_POOL_SIZE` 8 → 30 (> page size, avec marge dédup) ; ajouter un palier `168 h` à `THEMATIC_WINDOW_TIERS_HOURS` | faible — n'élargit que quand c'est maigre |
| 1.2 | `recommendation_service.py` | Fenêtre indexée sur l'offset : une page N>1 part directement au palier le plus large (le « frais d'abord » n'a de sens que sur la page 1) | faible |
| 1.3 | `flux_continu_provider.dart` | `_kThemeSectionPageLimit` 10 → 20 (parité Flâner) | faible ; à valider vs le temps de cold-open (~10 appels parallèles) |
| 1.4 | `flux_continu_provider.dart` | `_themeHasMore` → `hasNext && itemCount > 0` (parité Flâner) | **fort gain**, faible risque |
| 1.5 | `flux_continu_provider.dart` | Sur-fetch anti-dédup : demander `limit + marge` et/ou étendre le backfill (`kThinSectionMaxItems` 1 → 4, cible `kRichSectionMinItems` → taille de page) pour compenser ce que la dédup retire | moyen — touche la composition de la Tournée |

Le point **1.4** seul débloque déjà le scroll infini sur les sections maigres.
Les points **1.1 + 1.3** sont ceux qui rapprochent le volume de Flâner.

### Lot 2 — Dépriorisation « non-actualité » (Partie 2)

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
3. **Périmètre** — décision PO requise : malus dans tout le scoring piliers
   (donc aussi « Pour vous » / Flâner scoré) ou restreint à
   `personalized_theme_mode` ? Recommandation : **tout le scoring piliers**, le
   signal est vrai partout et un malus de −6 est sans danger.

### Hors-scope, à noter

- **Doublons d'ingestion** : 171 groupes `(source_id, title)` en double sur 7 j
  (197 lignes en trop, ~1,3 % du corpus) — ex. « Et si nous vivions dans une
  simulation 3/3 » présent 2×. Consomme des slots de section. À traiter dans un
  ticket dédié (dédup RSS sur `guid`/titre).

## Vérification prévue (phase CODE)

- Script one-off : pool par thème **avant/après** Lot 1 (24 h / adaptatif /
  post-dédup simulée), sur le compte de référence, serein ON et OFF.
- Tests unitaires `serial_episode_signal` : les 7 titres feuilletons relevés
  → `True` ; les 3 titres datés JJ/MM → `False`.
- Test scoring : à pertinence/source/fraîcheur/qualité égales, un titre
  feuilleton se classe sous un titre d'actu, sans jamais sortir du pool.
- `pytest -v` backend + `flutter test` + `flutter analyze`.
- QA Playwright : ouvrir Technologie et Environnement, compter les articles
  avant/après, vérifier que le scroll infini de la page dédiée ne se coupe plus.

## Tasks

- [ ] GO PO sur le plan (arbitrages : 1.3, 1.5, périmètre Lot 2)
- [ ] Lot 1 — backend (1.1, 1.2)
- [ ] Lot 1 — mobile (1.3, 1.4, 1.5)
- [ ] Lot 2 — `serial_episode_signal` + `PenaltyPass`
- [ ] Preuve empirique avant/après
- [ ] Suite de tests complète
