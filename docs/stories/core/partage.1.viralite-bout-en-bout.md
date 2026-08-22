# Story partage.1 — Partage bout-en-bout & viralité

**Type** : Feature · **Statut** : PR 1 implémentée (aucun bloquant externe restant) · **Épic** : partage (boucle virale)

## Contexte

Le parcours de partage était cassé à quatre endroits :

1. `https://facteur.app/grille` servait la home (nginx n'avait pas de `location = /grille`) ;
2. la page-pont `grille.html` pointait vers des URLs stores placeholders (404) et n'avait
   aucune balise Open Graph ;
3. aucun universal link / app link n'était configuré (redirect JS aveugle, timeout 1,5 s) ;
4. tout le partage passait par le presse-papier, sans share sheet native.

S'y ajoutent : lien de défi identique pour tous (aucune attribution), partage d'article
copiant l'URL brute de l'éditeur, et absence de tout système de parrainage.

**Objectif (périmètre validé PO)** : boucle virale complète — socle universal links +
pages-pont réparées, Défi porteur d'état, CTA de partage in-app, page article publique
`facteur.app/a/<id>` (carte riche OG, pas d'iframe), share sheet native partout avec
« Copier » en secondaire, attribution par code `ref` par utilisateur + UTM alignés sur la
convention Notion (`utm_source=app&utm_medium=partage_in_app&utm_content=<surface>`).

**Hors périmètre (lots suivants)** : export image de la grille, récap « Wrapped »,
récompenses de parrainage, UI du compteur « X ont rejoint » (l'endpoint le servira déjà).

## Découpage

```
PR1 (socle web)  ──►  PR3 (mobile socle partage)  ──►  PR4 (CTA viralité)
PR2 (attribution backend)  ──►  PR3
```

PR1 et PR2 sont indépendantes et shippables seules.

---

## PR 1 — Socle web : `.well-known`, pages-pont, page article publique

### Faits d'infra vérifiés (corrigent le plan initial)

| Fait | Valeur vérifiée | Impact |
|------|-----------------|--------|
| Domaine API prod | `facteur-production.up.railway.app` (service Railway **WEB**, branche `production`) | **`api.facteur.app` n'existe pas** (NXDOMAIN). Le `proxy_pass` vise le domaine Railway. |
| Branche du service **Landing Page** | `main`, rootDirectory `/apps/landing`, custom domain `facteur.app` | La landing se déploie **dès le merge sur `main`**, alors que l'API prod n'avance qu'au release hebdo. |
| Bundle id iOS | `app.facteur` (`project.pbxproj`) | AASA = `<TEAM_ID>.app.facteur`. |
| applicationId Android | `facteur.app` (flavor `playstore`), `com.example.facteur.staging` (flavor `beta`) | Deux entrées `assetlinks.json`. |
| Deep link article existant | `io.supabase.facteur://feed/content/<id>` → `/flaner/content/<id>` (`deep_link_service.dart:466`) | Le CTA « Lire dans Facteur » marche **sur le parc déjà installé**, sans attendre PR3. |
| `nginx.conf.template` | copié dans `/etc/nginx/templates/default.conf.template` → rendu dans `conf.d/` (niveau `http`) | Les directives http-level (`map`, `proxy_cache_path`, `limit_req_zone`) se posent en tête de fichier. |

> ⚠️ **Fenêtre de 404 assumée sur `/a/<id>`.** La landing (branche `main`) proxie vers l'API
> **prod** (branche `production`). Entre le merge de PR1 et le prochain « Weekly Production
> Release », `facteur.app/a/<id>` renverra 404. C'est sans conséquence : aucun lien `/a/` n'existe
> encore dans la nature (les CTA de partage arrivent en PR3/PR4, donc après). Ne pas merger PR3
> avant que la release hebdo ait embarqué `public_pages.py`.

### Fichiers

- **`apps/landing/public/.well-known/apple-app-site-association`** (sans extension) — `applinks`
  sur `/grille` et `/a/*`, `appIDs: ["YSV9476793.app.facteur"]`.
- **`apps/landing/public/.well-known/assetlinks.json`** — `facteur.app` (empreinte = clé **App
  Signing gérée par Google**, Play Console → Intégrité de l'app, *pas* le keystore local) et
  `com.example.facteur.staging` (keystore release local + keystore debug).
- **`apps/landing/nginx.conf.template`** :
  - en tête (avant `server {`) : `proxy_cache_path … keys_zone=article_pages`, `map` extrayant
    la 1ʳᵉ IP de `X-Forwarded-For`, `limit_req_zone … zone=pages_rl rate=10r/s` ;
  - `location = /grille` → `grille.html` ;
  - `location = /.well-known/apple-app-site-association` (+ alias legacy `/apple-app-site-association`)
    avec `default_type application/json` ; `location = /.well-known/assetlinks.json` ;
  - `location /a/` → `proxy_pass https://facteur-production.up.railway.app/api/pages/a/` avec
    `Host` upstream forcé (routage edge Railway), `proxy_ssl_server_name on`, cache 10 min (200) /
    1 min (404), `limit_req`.
- **`packages/api/app/routers/public_pages.py`** (nouveau) — `GET /api/pages/a/{content_id}`,
  `HTMLResponse`, sans auth, monté dans `main.py` sous le préfixe `/api/pages`. Pattern
  `youtube_player.py` (template Python en dur).
- **`packages/api/tests/test_public_pages.py`** — tests.
- **`apps/landing/public/grille.html`** — réparée.

### Page article — décisions

- **`content_id` typé `str`** (pas `UUID`) dans la signature : un id non-UUID doit rendre la
  page 404 HTML, pas un 422 JSON FastAPI.
- **Sécurité XSS** — seule surface d'injection du chantier. Tout champ interpolé passe par
  `html.escape()`. La `description` est d'abord `html.unescape()` → strip des balises → collapse
  des espaces → tronquée (~200 car.) → `html.escape()` (ordre sûr et idempotent). L'`id` réinjecté
  dans le JS est validé UUID en amont, donc `[0-9a-f-]` uniquement.
- **`og:image`** : `thumbnail_url` n'est utilisée que si son schéma est **https** (URL absolue
  exigée par les crawlers). Tout le reste (`http:`, `javascript:`, `data:`, relatif, vide) →
  **balise omise** et `twitter:card` bascule de `summary_large_image` à `summary`.
  > Écart assumé vs le plan (« fallback via `/api/images/proxy?url=` ») : ce proxy **rejette les
  > URLs http** (`images.py` exige `scheme == "https"`), le fallback aurait donc rendu 404 —
  > une image cassée au lieu d'une carte texte propre. Il n'existe par ailleurs aucun visuel
  > 1200×630 de marque dans le dépôt (`/images/og-image.jpg`, référencé par `index.html`, **est
  > manquant** — bug pré-existant hors périmètre).
  > **À faire PO** : fournir un `og-article-fallback.jpg` 1200×630 ; le brancher est un one-liner.
- **`robots: noindex, follow`** : la page n'a pas de contenu original (titre + extrait 200 car. +
  lien sortant) ; l'indexer exposerait à du duplicate/thin content. Les crawlers sociaux
  (Facebook, X, WhatsApp, iMessage) ignorent `robots` et lisent l'OG normalement. Décision
  réversible en une ligne.
- **CTA « Lire dans Facteur »** : tente `io.supabase.facteur://feed/content/<id>` puis retombe sur
  les stores après ~1,5 s. C'est bien le **scheme custom**, pas l'universal link : un tap
  *intra-page* ne redéclenche pas l'universal link (iOS le court-circuite volontairement une fois
  l'utilisateur arrivé sur le domaine). L'universal link joue **en amont**, quand l'app est
  installée et que la page n'est jamais chargée.
- **Attribution** : `?ref=<code>` accepté et validé (`^[A-Za-z0-9_-]{1,32}$`, ignoré sinon) puis
  reporté dans les liens stores. La clé de cache nginx inclut la query → un `ref` par entrée.
- **Analytics** : GA4 seul sur les pages-pont (pas de `posthog-js`). Le funnel PostHog se
  reconstitue côté serveur via `referral_attributed` (PR2).

### Copy

Tous les textes user-facing sont **des placeholders à valider PO**. Contraintes respectées :
pas de tiret cadratin « — » dans la copy visible, ton sobre, aucune personnification du facteur.

### Tests

`packages/api/tests/test_public_pages.py` — 200 avec OG complet ; échappement (`<script>` dans le
titre, guillemets dans la description) ; 404 id inconnu ; 404 id non-UUID (et pas 422) ; en-têtes
de cache ; `thumbnail_url` en `javascript:` / `http:` → pas d'`og:image` + `twitter:card=summary` ;
`ref` valide reporté / `ref` invalide ignoré.

### Vérifications effectuées en local

- `pytest tests/test_public_pages.py` : **17 passés**. Suite complète : **3262 passés**, 21 skipped,
  2 xfailed, 0 échec. `ruff check` + `ruff format` propres. 1 seule head Alembic (`ca01_coverage_analyses`),
  aucune migration ajoutée.
- **Image landing buildée avec Docker** (`nginx -t` OK) puis servie : `/grille` 200 `text/html`,
  `/.well-known/apple-app-site-association` et `/apple-app-site-association` 200 `application/json`,
  `/.well-known/assetlinks.json` 200 `application/json`, `/` toujours 200.
- **Chaîne de proxy `/a/` vérifiée de bout en bout** contre un `uvicorn` local (variante temporaire du
  template pointant sur `host.docker.internal`) : réécriture de chemin OK, query `?ref=` transmise,
  `X-Cache-Status: MISS` puis `HIT` au 2ᵉ appel, et `MISS` pour un `ref` différent (clé de cache par query).
  Contre l'upstream réel `facteur-production.up.railway.app`, la requête atteint bien FastAPI (404
  `{"detail":"Not Found"}` = route pas encore déployée sur `production`, fenêtre documentée ci-dessus).
- **`curl` sur l'endpoint réel** : 200 + `cache-control: public, max-age=600`, OG complet, titre
  `Smoke "test" <b>local</b>` rendu échappé (`&quot;` / `&lt;b&gt;`), description RSS HTML nettoyée en
  texte, `ct=partage_article_laurin_42`, `referrer=utm_source%3Dapp%26…%26ref%3Dlaurin_42`.
  404 HTML pour un id inconnu **et** pour `pas-un-uuid`.
- **Rendu navigateur** (Chrome, 420×900) de `/a/<id>` : carte propre (kicker source, titre, extrait,
  CTA, lien sortant, bloc stores), **zéro erreur console**, titre d'onglet affichant le HTML injecté
  en texte littéral.
- **`grille.html` : script inline réellement exécuté** contre un DOM stub (Node `vm`), 3 scénarios :
  - `?n=N°143&s=3/6&ref=laurin_42` sur iOS → « Quelqu'un a fait 3/6 au Mot du jour N°143 », liens
    stores attribués, `facteur_attrib_v1` persisté, deep link déclenché ;
  - sans params sur desktop → titre générique, stores affichés directement, **pas** de tentative de
    deep link (le scheme custom ne mène nulle part hors mobile), pas d'attribution ;
  - params hostiles (`n=<script>alert(1)</script>`, `s=999/999`, `ref=" onerror="`) → score et `ref`
    rejetés par les regex, aucune injection (tout passe par `textContent`).
  Zéro erreur console sur `/grille`.

### Passe `simplify` (4 axes : réutilisation, simplification, efficacité, altitude)

**Appliqué**

- `SITE_ORIGIN` supprimée au profit de `get_settings().public_web_base_url` (`config.py:92`,
  déjà consommée par `stripe_service` et `support_link_email`) : plus de 4ᵉ littéral
  `https://facteur.app` figé, et l'origine redevient pilotable par env comme dans le reste
  de l'app. `_safe_link_url` prend son repli en paramètre.
- `_TAG_RE`/`_WS_RE` remplacées par `strip_html()` (`services/content_quality.py:9`), qui
  faisait déjà exactement ce couple de regex.
- La requête ne charge plus l'entité `Content` mais les 4 colonnes utilisées : la table porte
  un `html_content` (corps complet de l'article) qui traversait le réseau à chaque miss de cache.
- `proxy_cache_key` restreinte à `$uri|$arg_ref`. La clé par défaut inclut **toute** la query :
  Facebook/Instagram/X collant un `fbclid`/`igshid` différent à chaque clic, presque chaque
  visite aurait été une entrée unique et le cache n'aurait quasiment jamais servi.
- Balise CSS extraite en constante unique `_LANDING_CSS_TAG`, figée dans les deux templates à
  l'import (la substitution par requête reste réservée aux données utilisateur, en une passe).
  Voir le couplage inter-trains ci-dessous.
- Nettoyages locaux : repli inatteignable dans la troncature, `image_url`/`escaped_image`
  fusionnées, `raw.strip()` calculé une fois par helper.
- Test ajouté : aucun `__TOKEN__` ne survit au rendu (page 200 **et** page 404). Un token
  ajouté au HTML mais oublié dans le dict se rendait littéralement sans casser aucune
  assertion ciblée.

**⚠️ Couplage inter-trains sur `/css/style.css?v=6`**

La carte de partage emprunte la CSS de la landing (son header réutilise `container` /
`section-nav__item`), mais elle est déployée par le service **API** (branche `production`)
alors que la CSS l'est par la **landing** (branche `main`). Le `?v=` est la clé de cache-bust
partagée par toutes les pages de la landing : **quand elle est bumpée là-bas,
`_LANDING_CSS_TAG` doit suivre**, sinon la carte reste épinglée sur une version périmée.
D'où la constante unique et greppable plutôt que deux littéraux noyés dans les templates.

**Écarté, avec la raison**

| Proposition | Pourquoi non |
|---|---|
| Extraire un `js/share-bridge.js` partagé entre `grille.html` et la page article (~35 lignes de JS dupliquées, précédent `consent.js`) | Ajouterait une **dépendance inter-trains** de plus, sur du JS cette fois — exactement le problème que le point CSS ci-dessus documente. À faire quand PR3/PR4 ajouteront une 3ᵉ surface : la règle de trois arbitrera, et les deux surfaces vivront alors du même côté. |
| Fusionner les trois `location =` `.well-known` en un bloc préfixe/regex | `location =` est la forme la plus rapide **et** la plus auditable ; ces fichiers sont mis en cache ~24 h par le CDN Apple, un `default_type application/json` élargi à tout `/.well-known/` toucherait aussi les futurs `acme-challenge`/`security.txt`. Explicite > court. |
| `${API_UPSTREAM_HOST}` au lieu du host Railway répété 3× | `envsubst` ne gère pas de valeur par défaut : variable non définie sur le service Railway ⇒ config nginx invalide ⇒ **landing par terre**. Demande de poser la variable côté Railway d'abord ; à traiter séparément. |
| Bloc `upstream` + `keepalive` pour économiser les handshakes TLS | Un bloc `upstream` sans `resolver` résout le DNS **une seule fois au chargement** : l'IP de l'edge Railway serait figée pour la durée de vie du process. Gain modeste (chemin déjà caché) contre un risque de panne silencieuse. |
| `location / { try_files $uri $uri.html … }` pour supprimer les 4 blocs pretty-URL | Change le routage de **tout** le site, très au-delà de cette PR. |
| Fusionner `_safe_link_url` et `_safe_image_url` en un `_safe_url(schemes, fallback)` | Surface d'injection : deux fonctions courtes, chacune avec la raison de son jeu de schémas en docstring, s'auditent mieux que 10 lignes économisées. |
| Retirer le paramètre `surface` (une seule valeur aujourd'hui) | PR3/PR4 en ajoutent d'autres ; le retirer pour le remettre est de la turbulence. |
| Retirer `persistAttribution()` / `facteur_attrib_v1` (write-only) | Comportement voulu et documenté : PR2 en est le lecteur. |
| Tronquer la description à ~2000 car. avant le strip des balises | Couperait potentiellement au milieu d'une balise, que `_TAG_RE` ne retirerait plus : fragment de markup visible dans l'extrait (échappé, donc sans risque XSS, mais laid) pour un gain négligeable sur un chemin déjà caché. |
| Promouvoir la troncature au mot dans `app/utils/` (3ᵉ copie : `grille_matcher`, `consensus`) | Vraie dette, mais le correctif touche deux modules hors périmètre. À traiter dans sa propre passe. |
| Réutiliser la fixture `test_source` de `conftest.py` | La fabrique locale expose `source_name` en override, dont un test a besoin ; basculer sur la fixture partagée scinderait les tests en deux régimes pour ~11 lignes. |

### Vérifications post-deploy (à faire après merge)

- [ ] `curl -sI https://facteur.app/grille` → 200 `text/html` (et non la home).
- [ ] `curl -s https://facteur.app/.well-known/apple-app-site-association` → JSON, `content-type: application/json`.
- [ ] Validateur AASA Apple + `https://digitalassetlinks.googleapis.com/v1/statements:list?source.web.site=https://facteur.app&relation=delegate_permission/common.handle_all_urls`.
- [ ] `adb shell pm get-app-links facteur.app` → `verified` (après PR3, qui ajoute les intent-filters).
- [ ] `curl -s https://facteur.app/a/<uuid>` → 200 après la release hebdo (404 attendu avant).

> ⏱ **Le CDN Apple met en cache l'AASA jusqu'à ~24 h.** Merger PR1 nettement avant la QA mobile
> de PR3, et **remplir les empreintes avant le merge** pour ne pas empoisonner ce cache.

### Valeurs hors dépôt (résolues)

Les quatre empreintes/identifiants sont désormais renseignés dans
`apple-app-site-association` et `assetlinks.json`. Provenance, pour pouvoir les
re-vérifier ou les faire tourner :

| Valeur | Renseignée | Source |
|--------|-----------|--------|
| Team ID Apple | `YSV9476793` (→ `YSV9476793.app.facteur`) | Fourni par le PO (Apple Developer → Membership). |
| Empreinte Play App Signing (`facteur.app`) | `25:23:0E:70:…:C4:00:FE` | Fournie par le PO (Play Console → Intégrité de l'app → **Certificat de clé de signature d'application**, pas le certificat d'importation). |
| Empreinte release beta (`com.example.facteur.staging`) | `D8:36:07:10:…:A4:E9:CF` | Extraite de l'APK beta publié : `apksigner verify --print-certs Facteur-beta-20260822-1311.apk` (DN `CN=Boujon Laurin, OU=Facteur`). C'est le keystore CI `KEYSTORE_BASE64` — l'APK signé en est la source de vérité, le keystore n'a pas besoin de sortir de la CI. |
| Empreinte debug (`com.example.facteur.staging`) | `64:D8:59:57:…:B7:6D:AE` | `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android`. |

> ⚠️ **L'empreinte debug est celle d'une seule machine.** Le keystore debug Android est
> généré aléatoirement par poste. Elle ne fait donc vérifier les app links que pour les
> builds debug de ce poste-là ; sur un autre poste (ou un runner CI), un build debug ne
> vérifiera pas et retombera sur le scheme custom. Ajouter d'autres empreintes debug au
> tableau `sha256_cert_fingerprints` si besoin — c'est additif et sans risque.

> ⏱ **Rappel cache CDN Apple ~24 h** : les valeurs étant renseignées *avant* le merge, le
> premier fetch du CDN servira un AASA correct. Toute correction ultérieure du Team ID
> resterait en cache une journée.

> ⚠️ **Les builds iOS beta (AltStore) ne vérifieront pas les universal links.**
> `build-ipa.yml` produit une IPA `--no-codesign` que les testeurs installent via AltStore, qui
> la **re-signe avec leur propre équipe Apple**. L'`appID` effectif devient alors
> `<team_du_testeur>.app.facteur`, qui ne correspond pas à `YSV9476793.app.facteur`. Les
> universal links ne se vérifieront donc que sur les builds signés par l'équipe Facteur
> (TestFlight / App Store, ou build Xcode local). Sur AltStore, le parcours retombe sur le
> scheme custom `io.supabase.facteur://` — que la re-signature ne casse pas (les URL schemes
> vivent dans l'`Info.plist`). **À anticiper pour la QA iOS de PR3** : un universal link qui ne
> s'ouvre pas dans l'app sur un iPhone de testeur beta n'est pas un bug de PR1.

Reste optionnel, non bloquant : `pt=` (App Store Connect → Analytics → Campagnes). Les liens
stores fonctionnent sans (`ct=` seul suffit à tracer).

---

## PR 2 — Attribution backend (à venir)

Table dédiée pour les codes `ref` par utilisateur (`user_preferences` est un key-value
`String(100)`, inadapté), endpoint d'attribution + compteur « X ont rejoint ».

## PR 3 — Mobile : socle partage (à venir)

Universal links / app links (intent-filters + entitlements ; `app_links ^6.3.2` déjà présent,
config seule), extension de `routes.dart` bloc 1 (`:262`) et de `DeepLinkService.parse` (`:414`)
au scheme `https`, share sheet native avec « Copier » en secondaire.

## PR 4 — CTA viralité (à venir)

Défi porteur d'état (`GrilleTodayResponse.numero` est une `String` « N°143 » → extraire les
chiffres pour `n=`), CTA Notif du jour + fin de tournée.
