# Bug: Curation Essentiels — doublons de sujet + sections thématiques hors-sujet

**Date de découverte** : 2026-05-31 (prod / `main`)
**Sévérité** : 🔥 CRITICAL (prod)
**Status** : ✅ Corrigé (fix #1 + fix #2 implémentés + tests) — en attente CI/review
**Surfaces** : Carte « L'Essentiel du jour », sections thématiques « Tournée du jour »

---

## Symptômes (rapportés + screenshots)

1. **Bug 1 — même sujet 3× dans la carte Essentiel.** Le sujet « météore explose
   au-dessus des États-Unis » apparaît 3 fois : Actu du jour (Home Fil actu) +
   Ouest-France + Le Figaro.
2. **Bug 2 — articles hors-thème dans le top 3 des sections.** Sous « Technologie »
   **et** sous « Science », on retrouve les mêmes 2 articles Le Monde sans rapport :
   « guerre en Ukraine : 229 drones » et « baleine échouée à l'île de Ré » (badgés
   « Géopolitique »).

---

## Cause racine #1 — Doublons de sujet (PAS un bug de clustering)

Le clustering **fonctionne** : les 3 articles météore partagent le même
`content.cluster_id` (`a309ac1c-…`) et `content.theme = science` (vérifié en prod).

Le défaut est dans la **projection Essentiel** :
`app/services/essentiel_service.py` → `_pick_transversal_articles()`.

L'Essentiel doit être « 5 articles **transversaux** » = 1 article max par sujet.
Or la contrainte « 1 article par topic » n'est appliquée **qu'au Round 1
(diversité)** :

- **Slot lead Actu** (l.485-495) : pose l'article Actu en rank 1, marque le topic.
- **Round 1 diversité** (l.513-518) : `if topic.topic_id in used_topics: continue` ✅
- **Round 2 remplissage** (l.520-535) : appelle `_try_pick()` **sans** vérifier
  `used_topics`. `_try_pick` ne contrôle que `content_id` (dédup) + max 2/source.

Conséquence : quand un topic « revue de presse » contient plusieurs articles du
**même** sujet (météore : 3 sources distinctes), le Round 2 ré-injecte les autres
articles du topic déjà servi en lead → le même sujet ressort 2-3×.

> Le filtre `ESSENTIEL_MAX_PER_SOURCE = 2` ne protège pas : les 3 articles
> viennent de **sources différentes**.

## Cause racine #2 — Sections thématiques hors-sujet

Endpoint : `GET /api/feed?theme=<slug>&personalized=true` →
`recommendation_service._get_candidates()` → `apply_theme_focus_filter()`
(`app/services/recommendation/filter_presets.py` l.305-336).

Le filtre admet un article via **2 chemins** :

```python
or_(
    Content.theme == theme_slug,                       # (1) classifié ML
    and_(
        Content.source_id.in_(                          # (2) "bénéfice du doute"
            sources WHERE source.theme == slug
                 OR source.secondary_themes ANY slug),
        Content.theme.is_(None),                        #     non encore classifié
    ),
)
```

Le **chemin (2)** est la fuite. Vérifié en prod :

- Les 2 articles incriminés (Ukraine 229 drones 07h11, baleine 06h48) sont des
  articles **Le Monde frais, non encore classifiés** : `content.theme = NULL`,
  `topics = []`.
- `Le Monde` : `theme = "international"`, `secondary_themes =
  ["society","politics","economy","culture","tech","science"]`.

Donc un article Le Monde non classifié matche le chemin (2) pour **tech ET
science** (présents dans `secondary_themes`) → il apparaît dans la section
Technologie **et** Science. Le badge affiché vient de `source.theme`
(`international`) → « Géopolitique ». D'où l'effet « hors-sujet partout ».

> Les articles classifiés (149/162 chez Le Monde sur 48 h) passent correctement
> par le chemin (1). La fuite ne concerne que les articles **frais non classifiés**
> de **sources généralistes à `secondary_themes` larges** — précisément la fenêtre
> 24 h de la Tournée.

---

## Plan de correction (structurel, anti-overfitting)

### Fix #1 — Invariant « 1 sujet max » dans l'Essentiel
`app/services/essentiel_service.py` :
1. Appliquer le guard `used_topics` au **Round 2** (remplissage), pas seulement
   au Round 1 → un topic déjà représenté ne peut plus ré-entrer.
2. Filet de sécurité **anti-doublon de titre** (couvre les clusters scindés et le
   couple actu/deep d'un même sujet en format éditorial) : avant de retenir un
   article, l'écarter si son titre normalisé a une similarité Jaccard ≥
   `TOPIC_CLUSTER_THRESHOLD` avec un article déjà retenu. Réutilise
   `app/services/text_similarity.py` (aucune nouvelle dépendance).
3. Conséquence assumée : s'il existe < 5 sujets distincts, l'Essentiel rend < 5
   articles plutôt que de dupliquer un sujet (cohérent avec « transversaux »).

### Fix #2 — Resserrer le filtre thématique pour les articles non classifiés
`app/services/recommendation/filter_presets.py` → `apply_theme_focus_filter()` :
- Pour le chemin « bénéfice du doute » (`Content.theme IS NULL`), restreindre au
  **thème principal** de la source (`Source.theme == theme_slug`) et **ne plus**
  s'appuyer sur `secondary_themes`.
- Rationale : `secondary_themes` n'a de sens que pour les articles classifiés —
  or ceux-ci passent déjà par le chemin (1) via `content.theme`. S'appuyer sur
  les `secondary_themes` larges des sources généralistes pour des articles **non
  classifiés** est précisément ce qui déverse Le Monde dans toutes les sections.
- Effet : un article Le Monde non classifié n'apparaît plus que dans sa section
  principale (international/Géopolitique) jusqu'à classification ML (latence
  courte). Aucune régression sur les articles classifiés.

### Tests
- `tests/test_essentiel_endpoint.py` : cas « 1 topic multi-sources (3 articles) →
  le sujet n'apparaît qu'1 fois » + cas « 2 titres quasi-identiques sur 2 topics →
  1 seul retenu ».
- `tests/test_personalized_theme_mode.py` : cas « article `theme=NULL` d'une source
  généraliste (`secondary_themes` contient le slug, mais `source.theme` ≠ slug) →
  exclu de la section » + non-régression « article classifié → inclus ».
- Test unitaire direct sur `apply_theme_focus_filter` (SQL compilé / fixtures).

### Hors-scope (noté, non traité ici)
- Latence de classification ML (déclencheur sous-jacent du bug 2) : le fix #2
  corrige la **frontière** de manière défensive sans dépendre du timing ML.
- Refonte de l'algo de clustering : inutile, le clustering regroupe correctement.

---

## Fichiers impactés
- `app/services/essentiel_service.py` (fix #1)
- `app/services/recommendation/filter_presets.py` (fix #2)
- `tests/test_essentiel_endpoint.py`, `tests/test_personalized_theme_mode.py` (+ test filtre)

## Preuves prod (read-only, Supabase)
- 3 articles météore → même `cluster_id`, `theme=science`.
- Ukraine/baleine → `content.theme=NULL`, `topics=[]`, `source.theme=international`.
- `Le Monde.secondary_themes` ⊇ {tech, science}.
- Tous les digests du jour : `format_version = editorial_v1`.

## Note de branche
Bugs présents sur `main` (feature « Tournée du jour » absente de `staging`). La
branche de travail `claude/essentials-curation-bugs-ebgnc` a été rebasée sur
`origin/main` (elle était une copie de `staging`, sans commit propre).
