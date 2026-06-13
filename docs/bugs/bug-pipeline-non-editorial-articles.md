# Bug — Articles non-éditoriaux + publicités Frandroid passent dans le top 10

## Date

2026-05-27

## Symptôme

Deux familles de faux positifs observées dans la pipeline « Actus du jour » :

1. **Bulletins / chroniques régulières** remontent comme actu du jour :
   - « Journal RTL du 25 mai 2026 » (pas catché — pattern « Le journal » exige
     l'article défini)
   - « L'émission politique de France 2 »
   - « La chronique de Nicolas »
2. **Publicités Frandroid** : « Bouygues fête ses 30 ans… » remonte parce que
   `apply_ad_filter` tolère `is_ad=NULL` (articles non encore classifiés) et
   parce que `apply_ad_filter` n'était même pas appliqué au pool `pour_vous`
   du clustering éditorial.

## Cause racine

- `NEWS_BULLETIN_PATTERNS` incomplet : 4 variantes manquantes (`Journal RTL`,
  `L'émission`, `Ma/La/Sa/Notre chronique`, `Chronique:`).
- `is_news_bulletin_title()` était **uniquement** appelé dans
  `essentiel_service.py` (les 5 cartes finales) — pas dans
  `actu_matcher.py:_find_best_article*()` qui sélectionne les actus dans le
  top 10 éditorial. Les bulletins remontaient donc dans le clustering en
  amont.
- Pool `pour_vous` de `digest_generation_job._get_global_candidates()` ne
  passait pas par `apply_ad_filter`, contrairement à `serein` qui transite
  par `apply_good_news_filter` (lequel l'inclut).

## Correctif

- `filter_presets.py` : +4 patterns ancrés début (`^\s*`), ajout
  `EDITORIAL_SOURCE_DENYLIST` (`{"frandroid"}`) + helper
  `is_denylisted_editorial_source()`.
- `actu_matcher.py` : appel de `is_news_bulletin_title()` +
  `is_denylisted_editorial_source()` dans les 3 méthodes de sélection
  (`_find_best_article`, `_find_best_article_global`,
  `_find_extra_articles_global`).
- `digest_generation_job.py` : `apply_ad_filter` appliqué au pool
  `pour_vous` dans `_get_global_candidates()`.

## Tests

- `tests/test_low_priority_cap.py::TestIsNewsBulletinTitle` — 11 nouveaux
  cas (patterns + faux positifs « Une chronique du conflit »).
- `tests/test_low_priority_cap.py::TestIsDenylistedEditorialSource` —
  5 cas (Frandroid match + variations de casse + Le Monde non bloqué).

## Vérification manuelle

Régénération de la pipeline du 27 mai 2026 après merge pour confirmer
disparition des bulletins RTL/émissions et des pubs Frandroid des actus
du jour.
