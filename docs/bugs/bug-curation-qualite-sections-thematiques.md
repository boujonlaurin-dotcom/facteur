# Bug — Qualité de curation des sections thématiques (Tournée du jour)

## Symptôme (PO)

Le PO reste **très insatisfait** de la qualité du contenu curé dans les sections
thématiques de la Tournée (« Technologie », « Sciences », « Environnement »…),
malgré les PR précédentes qui ont résolu la *quantité* (3 → 10+ articles) et
l'affichage du bloc de clôture.

Compte de référence : `fd6b9d0b-4c16-422b-9688-bae34d63f41c`.

## Diagnostic (deep-dive 2026-06-01)

### Cause racine : le tri chronologique pur ignore toute notion de qualité

Il existe **3 chemins** dans `RecommendationService.get_personalized_feed`
(`recommendation_service.py`) :

1. **Chrono pur** (early-return L574) — aucun scoring, aucune compression.
2. **Chrono diversifié** (L600-710) — compression lourde : diversification par
   source + `entity_regroupement` + `keyword_regroupement` + `source_safety_net`.
   C'est le feed **Flâner home**.
3. **Scoré** (L712-918) — `PillarScoringEngine` (4 piliers), tri par score,
   source-fatigue decay, `stratify_followed_first`. **Aucune compression.**

Historique :
- **Story 21.2** (`767c4023`) voulait router `personalized_theme_mode` vers le
  chemin **scoré (3)**. Mais elle a sorti le mode de l'early-return *sans*
  garder la condition L600. Les appels Tournée arrivent avec `mode=None`
  (le mobile appelle `/api/feed/?theme=X&personalized=true`, sans `mode`) →
  ils tombaient donc dans le chemin **chrono diversifié (2)** → la compression
  collapsait 40+ candidats à 2-3 articles. **Story 21.2 a routé vers la
  compression en croyant router vers le scoring.**
- **Fix 3a4ccd9c** (PR #706) a « corrigé » en remettant `personalized_theme_mode`
  dans l'early-return **chrono pur (1)** → supprime la compression **mais aussi
  tout le scoring**. La section devient un dump anti-chronologique brut.

### Conséquence mesurée sur le compte (fenêtre 24h, sources suivies)

Pool **tech** = 21 articles. En tri chronologique pur :
- **12 / 21 ont `content_quality='none'`** → non lisibles in-app (teasers
  Le Monde / BDM / Courrier Int. / Mediapart, souvent paywall). « Lire plus »
  ouvre un contenu vide.
- Un teaser Le Monde `none` + sans image se classe **au-dessus** d'articles
  Next.ink `full` + image, uniquement parce qu'il est plus récent.
- **4 brèves « ☕️ » Next.ink** (ex. « Paint.NET récupère son domaine ») au même
  niveau que les articles de fond.
- Un **post Reddit en anglais** (« I fired my SEO agency ») dans la section FR.
- **Theme bleed** : Mediapart « blanchiment 500 M€ » et Le Monde « encyclique du
  pape sur l'IA » classés `tech` ; Le Monde « guerre de l'IA sur France 5 » =
  grille TV.

Le **boost subtopic** (seul levier de perso restant) est **quasi inerte** :
presque tous les articles tech ont `ai`/`tech` dans `topics`, et le user a
`tech=3.0`, `ai=2.89` → l'`overlap` est `True` presque partout → dégénère en
chronologique pur. Le boost est binaire (match / pas match), pas pondéré.

### Le problème généralise à tous les thèmes (24h, sources suivies)

| thème | candidats | `full` lisible | `none` teaser | sans image |
|---|---|---|---|---|
| society | 36 | 6 | 29 | 19 |
| international | 35 | 5 | 30 | 21 |
| tech | 21 | 9 | 12 | 6 |
| culture | 20 | 3 | 16 | 13 |
| economy | 20 | 3 | 17 | 15 |
| environment | 12 | 5 | 5 | 2 |
| **science** | **4** | **0** | 3 | 3 |

Deux problèmes distincts :
- **(A) Ranking** — partout, la majorité des candidats sont des teasers
  `none` non lisibles, noyant les rares articles riches. Le chrono pur ne
  les distingue pas.
- **(B) Rareté** — pour les thèmes à faible fréquence (science : 4 candidats,
  0 lisible), 24h + sources-suivies-seulement donne une section quasi vide.
  Les sources science du user (Hygiène Mentale, Science Étonnante… = chaînes
  YouTube) publient peu par jour. Perçu comme « mauvaise curation » alors que
  c'est une rareté de contenu.

### Bonus : mauvais classements source-level (upstream)

Au passage : Fireship / Underscore_ / Cybernetica (contenu tech) sont rangés
`theme='society'` ; Socialter (société/environnement) est rangé `theme='tech'`.
Ça pollue le matching source-level de `apply_theme_focus_filter` (Path 2).
Hors-scope code, mais à corriger côté données sources.

## Plan technique proposé

### Fix #1 (PRIMAIRE, fort impact, faible risque) — Router vers le PillarScoringEngine

Faire ce que Story 21.2 **voulait** faire, correctement :

1. `recommendation_service.py` — retirer `personalized_theme_mode` de la
   condition d'early-return chrono pur (L574-581).
2. Ajouter le garde manquant à L600 :
   `if (mode is None or mode == FeedFilterMode.CHRONOLOGICAL) and not personalized_theme_mode:`
   → les sections thématiques **sautent la compression** et tombent dans le
   chemin **scoré (3)**.
3. **Neutraliser le source-fatigue decay agressif** (`decay_factor=0.70`,
   L832) pour `personalized_theme_mode` : sur une section mono-thème où le user
   suit délibérément ~10 sources, 0.70^n enterre ses meilleures sources
   (Next.ink = 7/21 articles tech → 0.70^6 ≈ 0.12×). Remplacer par un
   **interleaving doux** (réutiliser `_apply_source_interleaving`, L650 — pas de
   pénalité de score, évite juste les murs de même source).

Effet : la section est classée par les 4 piliers déjà éprouvés sur POUR_VOUS :
- **Qualité (15%)** : `content_quality=full` (+10) + thumbnail (+12) + curated
  (+10) → lève les articles riches au-dessus des teasers `none`. **Le plus gros
  gain** vu la table ci-dessus.
- **Source (25%)** : sources suivies + curated/reliability + **affinity apprise**
  + **priority_multiplier** (préférences « plus/moins » du user) → Next.ink /
  Le Monde > Reddit / BDM.
- **Pertinence (40%)** : matching subtopic **pondéré** (`user_subtopic_weights`)
  au lieu du boost binaire actuel → un article `ai`+`tech` passe devant un
  `religion`.
- **Fraîcheur (20%)** : récence, bornée par la fenêtre 24h.

Réutilise tout le système de scoring testé. Randomisation déjà désactivée pour
`personalized_theme_mode` (L850) → pagination stable. `stratify_followed_first`
devient un no-op (tous les candidats sont déjà des sources suivies).

### Fix #2 (SECONDAIRE, rareté — décision PO requise) — Fenêtre adaptative

Quand le pool 24h + sources-suivies est sous un seuil (ex. `< 8`), élargir la
fenêtre à 48h (puis 72h) **avant** de tomber sur la section quasi vide. Garde le
« frais d'abord » mais évite la section science à 4 items. **Touche la règle
« rester <24h » → à valider avec le PO** avant implémentation.

### Hors-scope / follow-ups notés

- Détection des brèves « ☕️ » (pas de signal propre aujourd'hui).
- Filtre langue : le post Reddit EN passe (`language=null`) — pré-existant.
- Theme bleed (classification ML) + mauvais `theme` source-level → côté données.

## Vérification prévue (phase CODE)

- **Preuve empirique avant/après** : script one-off qui fait tourner le vrai
  `PillarScoringEngine` sur les 21 candidats tech du compte fd6b9d0b et imprime
  le reclassement (articles `full` remontés, teasers `none` descendus, Reddit EN
  en bas).
- `pytest` : nouveau test « personalized_theme_mode → chemin scoré, pas de
  compression, decay neutralisé ».
- Tests de non-régression existants (`test_personalized_theme_mode.py`).
- Comparaison cardinalité : la section doit garder ~10 items/page (pas de
  ré-introduction de la compression).

## Résultats (phase CODE — 2026-06-01)

### Fixes implémentés

- [x] **Fix #1** — `personalized_theme_mode` routé vers le PillarScoringEngine :
  - retiré de l'early-return chrono pur (gardé par `and not personalized_theme_mode`) ;
  - garde ajouté sur la branche chrono-diversifié → saute la compression ;
  - source-fatigue decay `0.70` neutralisé pour ce mode, remplacé par
    `_apply_source_interleaving` (interleaving doux, sans pénalité de score).
- [x] **Fix #2** — fenêtre de fraîcheur adaptative dans `_get_candidates` :
  24h → 48h → 72h, n'élargit que si le pool < `THEMATIC_MIN_POOL_SIZE` (8) ;
  ne relance la requête que si nécessaire. Constantes nommées dans
  `ScoringWeights` (`THEMATIC_WINDOW_TIERS_HOURS`, `THEMATIC_MIN_POOL_SIZE`).

### Fichiers modifiés

- `packages/api/app/services/recommendation_service.py`
- `packages/api/app/services/recommendation/scoring_config.py`
- `packages/api/tests/test_thematic_curation.py` (nouveau — Fix #1 + Fix #2)
- `packages/api/tests/test_personalized_theme_mode.py` (commentaires/docstrings MAJ)
- `packages/api/scripts/prove_thematic_scoring.py` (nouveau — preuve empirique)

### Preuve empirique (vrai PillarScoringEngine, 20 candidats tech réels)

`PYTHONPATH=. python scripts/prove_thematic_scoring.py`

```
full+image — rang moyen : 8.5 → 7.6  (plus bas = mieux)
full+image dans le top 5 : 2 → 3 / 5
teasers 'none' — rang moyen : 11.2 → 13.1  (plus haut = mieux)
teasers 'none' dans le top 5 : 3 → 1 / 5
post Reddit EN — rang : [19] → [5]  (sur 20)
```

- L'article riche **« Génération IA » (Le Grand Continent, favori, full+image)**
  passe du rang **16 → 1**.
- Les **4 teasers `none` de Le Monde** (priority_multiplier 0.2) tombent tous en
  bas (rangs **17-20**).
- Les teasers `none` dans le top 5 passent de **3 → 1**.

> ⚠️ **Écart vs attente PO sur le post Reddit EN.** Le post EN « I fired my SEO
> agency » **remonte** (19 → 5) au lieu de tomber, parce que le compte a mis
> `priority_multiplier = 2.0` **et une souscription** sur la source
> « Reddit's Startup Community ». Le scoring honore légitimement ces signaux
> explicites de l'utilisateur (pilier Source). Le démoter relève du **filtre
> langue** (hors-scope, déjà noté en follow-up) ou d'un ajustement de préférence
> de cette source par le PO — pas du routage scoring de cette PR.

### Tests

- Suite backend complète : **1315 passed**, 1 skipped (le seul échec,
  `test_notification_preferences::test_patch_increments_refusal_count`, est
  pré-existant et environnemental — sérialisation TZ `+02:00` ; échoue aussi sur
  `origin/main`, hors-scope).
- `test_thematic_curation.py` : fenêtre adaptative (élargit / reste 24h) +
  scoring qualité (full+image > teaser none) — vert.
- `test_personalized_theme_mode.py` (11 tests) : vert.
- Cardinalité : aucune compression réintroduite (le chemin scoré ne compresse
  pas) → la section garde son volume de candidats.
