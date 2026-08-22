# Story partage.2 — Attribution & partage mobile (lot viralité, hors PR1)

> **PR1 (socle web) est HORS PÉRIMÈTRE de cette story.** Elle est traitée en parallèle sur une
> autre branche : `.well-known/{apple-app-site-association,assetlinks.json}`, les `location` nginx
> de `apps/landing/nginx.conf.template`, `apps/landing/public/grille.html`, `index.html`, et le
> routeur de carte de partage `packages/api/app/routers/public_pages.py` (`facteur.app/a/<id>`).
> **Ne toucher aucun de ces fichiers ici.**

Statut : **PR A livrée** (backend attribution) — PR B (mobile) en cours.
Date : 22/08/2026. Branche : `boujonlaurin-dotcom/partage-viralite-liens`. Base : `main`.

## Objectif

Rendre le partage porteur d'état et attribuable :
- un code `ref` par utilisateur, posé en base et lu au premier lancement (install referrer Android) ;
- une share sheet native partout (grille, leaderboard, article), « Copier » en secondaire ;
- des universal / app links `https://facteur.app/grille` et `https://facteur.app/a/<id>` routés dans l'app ;
- deux CTA de partage (Notif du jour, fin de tournée) ;
- UTM systématiques `utm_source=app`, `utm_medium=partage_in_app`, `utm_content=<surface>`.

Hors périmètre : export image de la grille, « Wrapped », récompenses de parrainage, UI du compteur
« X ont rejoint ».

## Contrats hérités de PR1 (à ne pas ré-implémenter)

| Élément | Valeur figée |
|---|---|
| Lien article public | `https://facteur.app/a/<content_id>` |
| Lien grille | `https://facteur.app/grille` (déjà `GrilleConstants.shareBaseUrl`) |
| Hosts à accepter en deep link | `facteur.app`, `www.facteur.app` |

⚠️ Point de contact unique avec la branche PR1 : `packages/api/app/main.py` (les deux PRs ajoutent
un import + un `include_router`). Conflit trivial, à résoudre au rebase.

---

## PR A — Attribution backend (`/api/referral`)

### Migration `packages/api/alembic/versions/rf01_referral_tables.py`
- `down_revision = "ca01_coverage_analyses"` (head unique vérifiée le 22/08 via `alembic heads`).
- Écrite **à la main**, pas d'`--autogenerate` (l'autogenerate ramasse le drift pré-existant et
  proposerait des `DROP` sur des tables prod — cf. runbook drift Alembic).
- DDL brut `op.execute("CREATE TABLE IF NOT EXISTS …")` → migration rejouable (DB Supabase partagée
  entre `main` et `production`).
- `referral_codes` : `user_id UUID PK REFERENCES user_profiles(user_id) ON DELETE CASCADE`,
  `code VARCHAR(8) NOT NULL`, `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`,
  `CONSTRAINT uq_referral_codes_code UNIQUE (code)`.
  ⚠️ La FK cible `user_profiles(user_id)` (id Supabase), **pas** `user_profiles(id)` (PK technique).
- `referral_attributions` : `id UUID PK`, `referred_user_id UUID NOT NULL UNIQUE REFERENCES
  user_profiles(user_id) ON DELETE CASCADE` (l'unicité **est** l'idempotence), `code VARCHAR(8) NOT NULL`
  + `CREATE INDEX IF NOT EXISTS ix_referral_attributions_code`, `surface VARCHAR(40)`,
  `platform VARCHAR(16)`, `store VARCHAR(16)`, `referrer_raw TEXT`, `utm JSONB`, `created_at`.
- Verrouillage (advisor `rls_disabled_in_public`, patron `ca01` / `sec01`) : `ENABLE ROW LEVEL SECURITY`
  + `REVOKE ALL … FROM anon, authenticated` sur les deux tables (backend-only).
- `downgrade()` en `DROP … IF EXISTS`.

### Modèle & router
- `packages/api/app/models/referral.py`, **importé dans `app/models/__init__.py`** (sinon absent de
  `Base.metadata` → tests et autogenerate aveugles).
- `packages/api/app/routers/referral.py`, préfixe `/api/referral` :
  - `GET /me` (auth) → `{code, joined_count}`. Création paresseuse : 6 caractères dans
    `ABCDEFGHJKMNPQRSTVWXYZ23456789` via `secrets.choice`, insert
    `pg_insert(...).on_conflict_do_nothing(index_elements=["user_id"])` puis re-select (patron
    `feedback.py:116`), retry ×3 sur collision de `code`.
    `joined_count = COUNT(referral_attributions WHERE code = …)`.
  - `POST /attribution` (auth) `{code, surface?, platform?, store?, referrer_raw?, utm?}` →
    `{attributed: bool}`, **toujours 200** (un premier lancement ne doit jamais échouer là-dessus).
    `false` si code inconnu, auto-parrainage, ou attribution déjà posée. Sinon insert +
    `get_posthog_client().capture(user_id, "referral_attributed", …)` fire-and-forget + pose
    `acquisition_source = "referral"` dans `user_preferences` en **select-then-insert**
    (patron `admin_cohorts.py:85-100`).
    ⚠️ `user_preferences` n'a pas d'unicité `(user_id, key)` → pas d'`ON CONFLICT` ; et
    `preference_value` est `String(100)`. Ajouter `"referral"` au `Literal AcquisitionSource`
    (`admin_cohorts.py:31`) ; `acquisition_source` est déjà dans `ALLOWED_PREFERENCE_KEYS`.

### Tests PR A
`packages/api/tests/routers/test_referral.py` (11 tests) : alphabet/longueur du code, stabilité
(2 appels → même code), `joined_count` ; attribution nominale, idempotence (2e POST →
`attributed: false`, une seule ligne), auto-parrainage, code inconnu ou vide, troncature aux largeurs
de colonnes, premier lancement sans `user_profiles`, et non-écrasement d'une `acquisition_source`
plus spécifique. Override `app.dependency_overrides[get_current_user_id]`, PostHog patché au point
d'import (`app.routers.referral.get_posthog_client`).

---

## PR B — Mobile : share sheet, app links, liens porteurs d'état, CTA

### Dépendances
`share_plus` + `android_play_install_referrer` dans `apps/mobile/pubspec.yaml`.
⚠️ CI de tests en **Flutter 3.38.6** → vérifier la résolution (`flutter pub get`) avant d'aller plus loin.

### Config plateformes
- `ios/Runner/Runner.entitlements` : `com.apple.developer.associated-domains = ["applinks:facteur.app"]`.
- `ios/Runner/Info.plist` : `FlutterDeepLinkingEnabled = false` (`app_links` reste seul propriétaire du routage).
- `android/app/src/main/AndroidManifest.xml` : intent-filter `autoVerify="true"`, `scheme="https"`,
  `host="facteur.app"`, `pathPrefix="/grille"` et `/a/` + `<meta-data flutter_deeplinking_enabled=false/>`.
  ⚠️ `test/android/widget_resources_test.dart:355-388` lit ce manifest en dur → y asserter l'intent-filter.

### Deep links — élargir **les quatre** gardes de scheme
`deep_link_service.dart:414` (`parse`), `:156` (`_handle`), `:207` (`seedPending`),
`routes.dart:262` (bloc de seed du `redirect`). Un écart entre elles produit un lien seedé mais jamais
routé (ou l'inverse).
Règle commune : `scheme == 'io.supabase.facteur'` **ou** (http/https **et** host ∈ {facteur.app, www.facteur.app}).
Normalisation dans `parse` : `/grille` → `target: grille` ; `/a/<id>` → `target: article`,
route `${RoutePaths.flaner}/content/$id` ; le reste → `unhandled`.
⚠️ `main.dart:288-302` gate le seed cold-start sur `Platform.isAndroid` : sur iOS le cold start passe
par `DeepLinkService.start()` → `getInitialLink()`. À vérifier sur device réel.

### Générateur de liens — `apps/mobile/lib/core/utils/share_links.dart` (nouveau)
`buildGrilleChallengeLink({numero, score, ref})`, `buildArticleLink({contentId, ref})`,
`buildAppLink({surface, ref})` — UTM systématiques, `n` = digits extraits de `numero`
(`"N°143"` → `143`, c'est une `String` côté modèle), construction via `Uri(queryParameters:)`,
`ref` optionnel (dégradation propre hors ligne).
Provider `referralCodeProvider` : `FutureProvider` sur `GET /api/referral/me`, cache mémoire + `SharedPreferences`.

### Bascule share sheet
- `grille_share_text.dart:45-46` : `buildGrilleShareLink(today, {ref})` délègue à
  `buildGrilleChallengeLink` ; corriger le docstring périmé `:14,42-44`.
- `grille_share_screen.dart:169-191`, `grille_leaderboard_screen.dart:107-119` : `Share.share(...)`
  avec **`sharePositionOrigin`** (sinon crash iPad) ; « Copier » reste en secondaire.
- `content_detail_screen.dart:2033-2045` : partager `buildArticleLink(content.id)` + texte court, au lieu
  de copier `content.url`. Le tooltip « Lien copié » reste pour le chemin « Copier ».
- `analytics_service.dart` : `trackShare({surface, medium, contentId, numero, hasRef})` en dual-track
  (patron `trackGrilleShared:1418-1428`) ; `trackGrilleShared` délègue et reste émis une release.

### Install referrer — `install_attribution_service.dart` (nouveau)
Premier boot Android (flag `install_referrer_consumed`) : `AndroidPlayInstallReferrer.installReferrer`
→ parser `ref=…&utm_…` → pending → à la première session authentifiée,
`POST /api/referral/attribution` puis clear sur 200. Sideload beta : « feature not supported » attrapé
silencieusement. `$set_once` des UTM en person properties PostHog.
iOS : aucune capture individuelle (lecture agrégée `ct=` App Store Connect) — limite documentée.

### CTA de viralité
- **Notif du jour** : entrée de catalogue, aucun widget touché — `NotifDuJourIds.partage` +
  `case` dans `buildNotifDuJourMessage` (`PhosphorIcons.shareNetwork()`, `NotifTint.ocre`,
  `onTap` → share sheet + `trackShare`) + entrée dans `notifDuJourQueueProvider` à relevance basse
  (~0.35, sous `tournee` 0.5) ; cooldown de dismiss ~30 j inchangé.
  ⚠️ **Collision avec la PR #1021** (ouverte, stale depuis le 29/07) qui ajoute déjà un
  `NotifDuJourIds.shareApp` presse-papier à relevance 0.3, dans les mêmes fichiers → décision PO requise
  (superseder #1021 ou l'attendre et étendre).
- **Fin de tournée** : `ShareClosingCta` (`TourneeGhostButton`) dans la `Column` `secondary` de
  `ClosingCardV18` au montage `flux_continu_screen.dart:1975-2025`, aux côtés de `DailyCompletionRecap`
  et `FeedbackClosingCard`.
  ⚠️ Hauteur de `_closingKey` mesurée par `_recomputeSnapAnchors` → appeler `_scheduleAnchorRecompute`
  via `onLayoutChanged` comme `FeedbackClosingCard`, sinon le snap repousse la carte hors zone.

### Copy (placeholders à valider PO)
Sobre, sans personnification du facteur, **sans tiret cadratin** : notif
« Un ami mérite un meilleur fil d'info » / CTA « Partager Facteur » ; fin de tournée « Partager Facteur » ;
article « … vu sur Facteur ».

### Tests PR B
`test/core/services/deep_link_service_test.dart` : https `/grille`, `/a/<id>`, host `www`, query ignorées,
révision du cas « foreign scheme → unhandled » (l.142), non-régression du scheme custom et de
`login-callback`. Plus : tests `share_links` (UTM, digits, absence de `ref`), dual-track `trackShare`,
parser d'install referrer, test notif sur le patron `notif_du_jour_card_test.dart`.
Smoke `flutter build apk --debug --flavor beta` (`JAVA_HOME` openjdk@17 Intel).
Baseline connue : ~26-27 échecs mobiles pré-existants.

---

## Vérification

**PR A** — `make db-reset` (DB vide, `facteur:facteur@localhost:54322/facteur_test`) →
`alembic upgrade head` OK, **1 seule head**, `downgrade -1` puis `upgrade head` (rejouabilité) ;
`pytest tests/routers/test_referral.py -v` puis `pytest -v` ; `curl` `/api/referral/me` et
`/api/referral/attribution` **avec un JWT** (sans `SUPABASE_URL` local, tout endpoint authentifié répond 501).

**PR B** — `flutter test && flutter analyze` ; `flutter build apk --debug --flavor beta` ;
app links Android via `adb shell pm get-app-links facteur.app` sur un build **signé Play** (l'APK beta
sideloadé ne peut pas se vérifier) ; universal links iOS sur **device réel** (le simulateur ne valide pas
l'AASA de façon fiable) ; QA web Playwright pour les surfaces UI (viewport bloqué à 1680px → valider le
layout par test widget + `getRect`).

`/go` en fin de chaque PR (VERIFY → SIMPLIFY → PR `--base main`).

## Risques & étapes hors repo

1. **Capability iOS « Associated Domains »** à activer sur l'App ID `app.facteur` puis **régénérer les
   profils de provisioning**, sinon le build iOS casse à la signature (Codemagic).
2. **Séquencement release** : ne pas livrer PR B aux utilisateurs avant que (a) les placeholders
   AASA/assetlinks de PR1 soient remplis (le CDN Apple cache l'AASA ~24 h) et (b) le « Weekly Production
   Release » ait embarqué la route `/a/<id>` sur l'API **prod** — la landing déploie depuis `main`,
   l'API prod depuis `production`, sinon les liens partagés tombent en 404.
3. **Fingerprint Android** : celui de **Play App Signing**, pas de la clé d'upload.
4. Le flavor `beta` (`com.example.facteur.staging`, signé debug/upload) ne sera **jamais** vérifié pour les
   app links : QA app links uniquement sur piste de test interne Play.
