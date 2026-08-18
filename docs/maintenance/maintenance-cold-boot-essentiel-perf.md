# Maintenance : cold boot de l'Essentiel — latence et attente lisible

**Date :** 2026-08-15
**Classification :** MAINTENANCE
**Branche :** `claude/facteur-article-loading-perf-ioi7t4`

---

## Problème

Remonté par plusieurs utilisateurs : à la première ouverture de l'app,
l'Essentiel s'affiche mais **la pile d'articles met 10 à 20 s à se charger**.
Pendant tout ce temps l'écran montre une carte blanche — pas un chargement, une
carte vide. Deux problèmes distincts, traités séparément ici :

1. **la latence** elle-même (objectif : < 5 s, idéalement 2-3 s) ;
2. **le ressenti** de l'attente (objectif : une attente lisible et calme).

---

## Diagnostic

### 1. Le héros attendait le plus lourd des trois appels de base

`FluxContinuNotifier._fetchAll` tirait ses trois appels de base dans un
`Future.wait` unique :

| Appel | Sert à |
|---|---|
| `GET /api/digest/both` | « Actus du jour » + « Bonnes Nouvelles » |
| `GET /api/flux/top-themes` | l'ordre des sections aval |
| `GET /api/essentiel` | **la pile d'articles du héros** |

La première peinture de contenu (« Phase 1 ») n'arrivait qu'**après les trois**.
Or la pile ne dépend que de `/api/essentiel`, de loin le plus léger : elle
attendait `/api/digest/both` sans en avoir besoin.

### 2. `/api/digest/both` pèse ~1 Mo, non compressé

Mesuré via `tests/perf_probe_digest_payload.py` (probe jetable, supprimée) sur
un digest `editorial_v1` réaliste — 6 sujets × 3 articles, corps d'article
~12 KB, prose à entropie réaliste :

```
  ONE digest payload      : 467 KB
    of which html_content : 436 KB (93%)
    without html_content  :  31 KB
  /digest/both (x2)       : 934 KB
  gzip(level 6)           : 179 KB  (5.2x)
```

Trois multiplicateurs se composent :

- `html_content` (le **texte intégral** de l'article, colonne `Text`, sans
  aucun plafond à l'écriture) est sérialisé pour chaque article ;
- chaque article est sérialisé **deux fois** par digest — une fois dans
  `topics[]`, une fois dans le `items[]` plat legacy ;
- `/digest/both` renvoie **deux** digests (normal + serein).

Et surtout : **aucune compression n'était activée**. Pas de `GZipMiddleware`
dans `app/main.py` — les ~934 KB partaient en clair. Le même `html_content` est
sérialisé par `ContentResponse` (`app/schemas/content.py`), donc par les
**~14 appels `/api/feed`** du fan-out de la Tournée : le cold boot téléchargeait
plusieurs Mo, sur un seul worker uvicorn (`Dockerfile`, pas de `--workers`).

### 3. L'attente ne se lisait pas comme une attente

`_HeroSkeleton` et `TriageStackSkeleton` dessinent une silhouette correcte, mais
avec `textTertiary` à **alpha 0.10** (sweep à 0.04) sur une `surface` crème
`#FDFBF7`. À ce contraste, les barres sont à la limite du perceptible : d'où la
« carte blanche » du rapport utilisateur. La capture jointe au ticket le montre
bien — on devine à peine les placeholders.

---

## Ce que fait cette PR

### Backend — `app/main.py`

Ajout de `GZipMiddleware(minimum_size=1000)`. Une ligne, aucun changement de
contrat : Starlette ne compresse que si le client envoie `Accept-Encoding:
gzip`, ce que Dio fait par défaut et décompresse de façon transparente.

Posé **avant** `RequestContextMiddleware`/CORS dans l'ordre `add_middleware`
(qui est inverse — dernier ajouté = outermost), donc gzip reste *sous* CORS et
ne touche jamais aux réponses de préflight.

Porte sur **tous** les endpoints de lecture, pas seulement le digest :
`/api/feed` (×14 au cold boot), `/api/contents/{id}`, `/api/essentiel`.

`tests/test_gzip_compression.py` épingle la présence du middleware
(structurellement — httpx décode en transparence, un test de réponse seul
passerait encore si le middleware disparaissait), l'ordre vis-à-vis de CORS, le
gain réel mesuré sur `Content-Length`, et le fallback `identity`.

### Mobile — `flux_continu_provider.dart`

Le héros ne dépend que de `/api/essentiel` : on l'émet **dès que cet appel
atterrit**, sans attendre le digest. Les trois futures sont désormais démarrées
séparément (elles partent toujours en parallèle, comme avant) et un `.then` sur
l'Essentiel publie la pile en avance.

L'émission anticipée reste un **squelette** (`_composeSkeleton`,
`isSkeleton: true`) : seul le héros s'hydrate, les sections aval gardent leurs
placeholders. C'est ce qui préserve l'invariant existant — `emitProgressive`
teste `mounted.isSkeleton` pour décider d'émettre la Phase 1, et un état
non-squelette ici l'aurait désarmé, figeant tout le haut de page.

Garde-fous : `_disposed`, liste d'articles vide ignorée, et un test
`state.isSkeleton` qui empêche d'écraser un état déjà hydraté si l'Essentiel
répond en dernier.

### Mobile — l'attente

- **`facteurSkeletonBase` / `facteurSkeletonHighlight`** (`config/theme.dart`) :
  la recette shimmer devient un token partagé, remontée à alpha **0.20 / 0.07**.
  Appliquée aux trois silhouettes du cold boot (`_HeroSkeleton`,
  `TriageStackSkeleton`, `SectionSkeletonCard`) — elle était copiée-collée dans
  chacune, donc elles pouvaient diverger.
- **`FacteurBikeLoader`** (`shared/widgets/loaders/facteur_bike_loader.dart`) :
  l'en-tête du héros troque ses barres grises contre le facteur en tournée.
  L'asset `assets/notifications/facteur_bike.png` existait déjà (carte de
  clôture, modale notifications) — c'est une **image plate**, pas une
  composition à calques, donc les roues ne peuvent pas tourner : le mouvement
  est porté par la scène (tangage doux + route qui défile). Respecte
  `MediaQuery.disableAnimations`.
- **`_LoadingHintText`** : rotation lente (2,6 s, fondu croisé) des
  `LoaderStrings.longLoadingHints` existants — « Le facteur prend la côte… »,
  « Secouage des sacoches… ». Un texte figé sur une attente longue se lit comme
  un écran bloqué.

L'en-tête garde sa hauteur réservée de 140 px (celle de la pastille date/météo
de `EssentielHiFiCard`) : aucun saut de layout à l'hydratation.

---

## Effet attendu

| | Avant | Après |
|---|---|---|
| `/api/digest/both` sur le fil | 934 KB | ~179 KB |
| Temps jusqu'à la pile d'articles | max(digest, essentiel, topThemes) | `/api/essentiel` seul |
| Pendant l'attente | carte blanche | facteur + silhouette lisible |

Les deux leviers sont indépendants et se composent : gzip réduit *tous* les
appels du cold boot, le découplage sort le plus lourd du chemin critique du
héros.

---

## Décisions : ce qui ne change PAS, et pourquoi

### Retirer ou tronquer `html_content` des payloads de liste : **hors PR**

C'est le gain restant le plus gros (934 KB → 62 KB avant gzip, soit ~15× de
plus que ce que gzip seul obtient). Écarté ici parce que le champ n'est pas
mort : `DigestItemPreview.toPreviewContent()` s'en sert pour peindre le corps de
l'article **sans shimmer** à l'ouverture du lecteur, et le lecteur refetch de
toute façon via `getContent` puis fusionne au plus long (`_pickLongest`).

Le tronquer (~2000 car.) préserverait la première peinture, mais
`isPartialContent` (seuil 500 car., `core/utils/html_utils.dart`) et la
qualification *scroll-to-site* dépendent de la **longueur** du texte : un
extrait basculerait ces heuristiques pendant la fenêtre qui précède le merge, et
fausserait `articleCharCount` en analytics. Ça mérite sa propre PR, avec un
passage QA sur le lecteur — pas un effet de bord d'une PR perf.

À rouvrir si les mesures post-déploiement ne suffisent pas.

### Paralléliser les deux `read_digest_or_fallback` de `/digest/both` : **non**

Les deux appels sont séquentiels dans le endpoint et partagent la **même**
`AsyncSession`. Un `asyncio.gather` dessus est incorrect (une `AsyncSession`
n'est pas concurrente) ; le faire proprement demanderait deux sessions
indépendantes, donc deux connexions par requête — précisément la zone des fuites
`idle-in-transaction` qui a fait repasser le healthcheck Railway en liveness
probe (cf. `railway.toml`, incident 2026-04-28).

Sans intérêt de toute façon ici : avec gzip **et** le découplage du héros,
`/digest/both` n'est plus sur le chemin critique de la pile d'articles.

### `--workers 2` : **non**

Inchangé depuis `maintenance-essentiel-loading-speed.md` : le cache feed est
in-process et `invalidate` est process-local ⇒ un article masqué réapparaîtrait.

---

## Vérification

Backend, contre une DB locale :

```bash
cd packages/api && pytest -v          # 3104 passed, 33 skipped (base : 3099 + 5)
pytest tests/test_gzip_compression.py -q
```

Mobile :

```bash
cd apps/mobile && flutter analyze && flutter test
```

Sur staging après déploiement :

1. `curl -H 'Accept-Encoding: gzip' -sI .../api/digest/both` → `content-encoding: gzip`.
2. Cold boot compte neuf, réseau bridé 4G → chrono jusqu'à la pile d'articles.
3. Vérifier dans les logs `digest_both_retrieved` que `elapsed_ms` est stable
   (gzip déplace du temps CPU sur le worker : il compresse, mais ~5× moins
   d'octets à écrire sur la socket).
4. Ouvrir un article depuis la pile → le lecteur peint toujours le corps sans
   shimmer (garde-fou du `html_content` conservé).
