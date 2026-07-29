# Maintenance : vitesse de chargement de l'Essentiel (Tournée du jour)

**Date :** 2026-07-29
**Classification :** MAINTENANCE
**Branche :** `boujonlaurin-dotcom/essentiel-loading-speed`

---

## Problème

L'écran Essentiel est lent à l'ouverture. Chaque cold-open déclenche un fan-out
client de 10 à 14 `GET /api/feed?personalized=true` (une par section), chacun
payant le pipeline de scoring complet sur **1 seul worker uvicorn**.

Un cache applicatif existe pourtant (`app/services/feed_cache.py`, clé
`(user, variant)`, TTL 60 s pour les variantes personnalisées) — mais il était
**neutralisé en pratique** :

- `invalidate(user_id)` purge *tous* les variants du user, et il était appelé
  depuis 36 sites d'écriture ;
- or l'écriture dominante est `POST /contents/{id}/status` en `SEEN`, émise **à
  chaque scroll**.

Autrement dit : scroller trois articles suffisait à annihiler le cache des
~12 sections de la Tournée, donc le cache ne servait quasiment jamais.

---

## Découpage

| PR | Périmètre | État |
|---|---|---|
| PR 1 (`e8c9fbaa`) | Sections « Sources favorites » toujours rendues + attente lisible (shimmer) | mergée |
| **PR 2 (ce doc)** | Backend : cache feed observable, correct sous écriture concurrente, et invalidation ciblée | cette PR |
| PR 3 | SWR client par section (hydratation) — voir « Périmètre réel de PR 3 » plus bas | à faire |

PR 2 et PR 3 restent séparées : zéro fichier et zéro test en commun, cycles de
validation disjoints (backend = redéploiement Railway 2 min ; mobile = QA device
réel puis build), et surtout **la mesure doit précéder le jugement** — il faut
lire le hit rate réel sur staging avant de décider du TTL et de l'ampleur du
volet client.

---

## Ce que fait PR 2

### 1. Observabilité (la baseline)

- **`app/routers/feed.py`** — un log structlog `feed_request` par requête :
  `cache=hit|miss|bypass`, `variant_class=default|personalized|none`,
  `duration_ms`, `items`. Avant, `feed_total` n'était émis que par
  `_compute_feed` : **un hit ne produisait aucun log**, le hit rate était
  invisible. `items` n'est renseigné que sur miss/bypass (le compter sur un hit
  imposerait un `json.loads` du payload sur le chemin rapide).
  `variant_class` seulement, pas le variant complet : bruit.
- **`app/main.py`** — `GET /api/health/feed-cache`, calqué sur
  `/api/health/pool`, avec deux écarts assumés :
  - **gate par header `X-Health-Token`** (comparaison `hmac.compare_digest`)
    quand le secret `HEALTH_METRICS_TOKEN` est configuré — déclaré comme
    `health_metrics_token` dans `Settings` (`app/config.py`), à côté de
    `admin_api_token`. `size` est un proxy du nombre d'users actifs. Sans le
    secret (staging), l'endpoint reste ouvert : fail-**open** assumé, à
    l'inverse de `require_admin_token` qui est fail-closed ;
  - `uptime_seconds` ajouté à `stats()` : les compteurs sont cumulatifs depuis
    le boot, donc le hit rate se lisse et masquerait une régression. La QA prend
    **deux échantillons et calcule le delta**.

### 2. Correction : les générations (bug pré-existant)

Sous le lock single-flight, `_compute_feed` prend 1,5 à 5 s puis `put()`
écrivait **inconditionnellement**. Une `invalidate` arrivant dans cette fenêtre
était écrasée ⇒ **un article masqué pouvait réapparaître** jusqu'à expiration du
TTL.

Le bug existait déjà, mais l'invalidation ciblée l'aggraverait (elle inspecte le
payload *en cache*, l'ancien, alors que le payload *en cours de calcul* contient
l'article ⇒ faux négatif systématique dans la fenêtre), et un TTL plus long
multiplierait la durée du symptôme.

Fix : `generation(user_id)` renvoie le couple `(compteur du user, compteur
global)` — le second sert aux invalidations cross-user, dont le rayon d'action
inclut des users sans entrée en cache. Le endpoint le capture **juste avant**
`_compute_feed` et le repasse à `put()`, qui droppe l'écriture si le couple a
bougé. Un compteur global seul aurait laissé l'écriture d'un user annuler le
`put()` en vol de tous les autres — soit, avec le SEEN à chaque scroll, en
permanence.

### 3. Invalidation content-scoped, limitée aux sites prouvés sûrs

`FeedPageCache.invalidate_content(user_id, content_id)` ne purge que les
variants du user **dont le payload contient l'id**.

> **Pourquoi un scan d'octets plutôt qu'un `frozenset` d'ids capturé au `put()`**
> — le set exigerait un walk qui connaît le schéma (`items`,
> `carousels[].items`, `clusters[]…`) et **manquerait silencieusement** les items
> imbriqués ⇒ faux négatifs (contenu périmé servi après écriture). Le scan est
> agnostique du schéma, son seul mode d'échec est le faux positif (une purge en
> trop, inoffensive), et il coûte ~50 µs pour 12 variants. Le risque réel (une
> évolution de sérialisation qui casserait le match en silence) est couvert par
> `test_cached_payload_item_ids_match_str_uuid`, qui épingle l'invariant : les
> ids apparaissent verbatim dans le payload caché.

**Périmètre — le point critique.** Vérifié dans `content_service.py` :
**like (l. 476), save (l. 514), hide (l. 562), note upsert (l. 646) et la
transition CONSUMED (l. 187) mutent `UserSubtopic.weight` et
`UserEntityAffinity.affinity`**, qui alimentent le scoring de *toutes* les
sections. Les scoper laisserait un **classement** périmé partout. On ne les
touche donc pas.

| Site | Après |
|---|---|
| `update_content_status` **sans** transition consumed (SEEN au scroll) | `invalidate_content` ← **le gain principal** |
| `impress_content` (n'écrit que `manually_impressed`/`last_impressed_at`) | `invalidate_content` |
| `unsave_content` (`set_save_status(False)` ⇒ aucun poids ajusté) | `invalidate_content` |
| `unhide_content` (`unset_hide_status` ⇒ idem) | `invalidate_content` |
| `delete_note` — **n'invalidait rien** | `invalidate_content` (bug fix) |
| like/unlike, save, hide, feedback, status→CONSUMED | `invalidate()` inchangé |
| `upsert_note` — **n'invalidait rien** | `invalidate()` (bug fix ; il boost les poids) |
| `report_not_serene` — **n'invalidait rien**, et le flip `is_serene=False` est **global cross-user** | `invalidate_content_global(content_id)` (bug fix) |
| les 27 autres sites (mute, follow, prefs, custom topics, refresh…) | inchangés |

`update_content_status` avait déjà le discriminant en main : il renvoie
`(updated_status, transitioned_to_consumed)`.

**Faux négatif résiduel, borné par le TTL** : le payload caché est une tranche
top-N ; une action sur un article hors-tranche ne purge pas la variante — ce qui
est correct, cet article n'était pas affiché.

**Ne pas purger `_locks` dans `invalidate*`** : retirer un `Lock` détenu par des
waiters casserait le single-flight (le thundering herd que ce cache existe pour
éviter). C'est écrit en commentaire dans le code et gardé par
`test_invalidate_keeps_locks_alive`.

Aucune migration DB.

---

## Décisions : ce qui ne change PAS, et pourquoi

### `--workers 2` : non — décision de correction, pas de perf

Le cache est in-process et `invalidate` est process-local : avec 2 workers, un
`POST /hide` traité par le worker A ne purge pas le cache du worker B ⇒
**l'article masqué réapparaît**. Idem pour `_analysis_cache` /
`_perspectives_cache` (`contents.py`). C'est incompatible avec la stratégie même
qu'on renforce ici.

**Condition de réouverture** : une invalidation partagée (Redis pub/sub). Et si
le besoin est du parallélisme CPU pour le scoring, la vraie réponse est de sortir
le scoring du chemin requête, pas d'ajouter des workers.

*Décidé le 2026-07-29.*

### `FEED_CACHE_PERSONALIZED_TTL_SECONDS=300` : hors PR

Étape ops Railway staging, à faire **après** lecture du hit rate réel, et jamais
avant que les générations soient déployées. Le défaut code reste 60 s.
Réversible sans build.

### `degraded_fallback` dans `FeedResponse` : abandonné

Le fallback timeout→curé ne concerne que la vue par défaut, pas les sections. Un
champ de schéma additif sans consommateur UI est du poids mort ; le log
`feed_request` couvre le besoin d'observabilité.

### `profile_feed_latency.py` : pas réécrit

Il bypasse le endpoint *et* le cache (et contient un `NameError`,
`briefing_rows`) — il ne peut pas mesurer ce qu'on change. Le log `feed_request`
et `/api/health/feed-cache` sont les instruments.

---

## Vérification sur staging (après déploiement)

1. Deux lectures de `/api/health/feed-cache` encadrant une ouverture d'app →
   hit rate calculé **sur le delta**, pas sur le cumul.
2. `grep 'feed_request'` dans les logs Railway sur 5 min d'usage réel.
3. **Scroller 3 articles puis rouvrir la Tournée < 60 s** → les sections doivent
   être servies du cache (c'est le scénario que cette PR débloque).
4. `hide` un article visible dans une section + pull-to-refresh immédiat → il ne
   revient **pas** (test des générations, cas intermittent d'aujourd'hui).
5. `like` un article → cœur toujours plein après aller-retour d'onglet.
6. Deux comptes en mode serein : A signale non-serein, B pull-to-refresh →
   l'article disparaît chez B.

Puis seulement : poser `FEED_CACHE_PERSONALIZED_TTL_SECONDS=300` sur staging et
re-mesurer.

---

## Suite : périmètre réel de PR 3 (SWR client par section)

Le SWR client par section reste le vrai gain **perçu** : aujourd'hui, à une
réouverture in-day, `_buildStateFromPayload(fetchThemes: false)` seed des
**coquilles vides** et retourne sans fan-out — le digest est instantané, les
12 sections restent vides jusqu'à la fin du fan-out complet.

Mais trois bloquants la précèdent, tous vérifiés dans le code
(`apps/mobile/lib/providers/flux_continu_provider.dart` sauf mention) :

- **Le reseed nu détruirait l'hydratation, visiblement.**
  `_buildStateFromPayload` fait `_themes = _shellThemeSections(...)` (pas
  `_reseedShells`) + `_resolvedSectionKeys.clear()`, et `sectionTask` appelle
  `emit()` **inconditionnellement**, hors de la garde `emitProgressive`.
  Aujourd'hui inoffensif (coquilles → coquilles) ; avec l'hydratation, c'est un
  flash contenu → vide → contenu sur toute la page. Le commentaire en place
  promet déjà l'inverse : **le code ne tient pas ce que son commentaire dit**.
  À corriger en commit séparé, *avant* toute hydratation (corrige aussi le
  pull-to-refresh).
- **Les sections source ne s'hydrateraient pas.** Le chemin `fetchThemes: false`
  retourne **avant** `_ensureSourceCatalog` ; `userSourcesProvider` est lazy ⇒
  `if (src == null) continue`. Idem pour les custom topics (label) et la veille
  (`veilleActiveConfigProvider` non résolu ⇒ section absente). Il faut persister
  l'en-tête minimal (label, logo) à côté du raw.
- **Un article balayé réapparaîtrait.** `_dismissedIds` est en mémoire seule.
  Invisible aujourd'hui ; avec l'hydratation, c'est le pire ressenti possible.
  À persister par jour.

Points à ne pas redécouvrir :

- ne **pas** hydrater `_resolvedSectionKeys` (pilote `demote`/`underfilled` ⇒
  saut d'ordre des sections au boot) ;
- ne **pas** hydrater les suggestions « Choisie pour vous » (`onEmpty` retire la
  coquille ⇒ disparition sous le doigt) ;
- `getVeilleFeedItems` (`flux_continu_repository.dart`) **avale les
  DioException** et renvoie un feed vide ⇒ on persisterait une section vide
  comme légitime ;
- le snapshot passerait de ~80 KB à ~600 KB, or `patchContentConsumed` fait
  decode + walk + encode du **snapshot entier sur le thread UI au retour de
  WebView** (`read_sync_service.dart`) ⇒ éclater en clés Hive `section:<key>`
  plutôt qu'un map imbriqué.
