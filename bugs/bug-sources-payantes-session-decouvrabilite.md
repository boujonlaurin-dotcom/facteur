# Bug Report: Sources payantes — session non persistée + découvrabilité cassée

**Status:** PRÊT POUR REVIEW — backend découvrabilité + session persistante + UI
(une seule PR, décision PO du 2026-06-08 : « lancer les 2 en même temps »).
Validation device (cookies natifs) restant à faire manuellement.
**Severity:** HIGH (lecture des sources payantes inutilisable + CTA invisible)
**Created:** 2026-06-08
**Branch:** `boujonlaurin-dotcom/webview-credentials-not-saving`
**Plan source:** `.context/attachments/J6NgmX/plan.md` (validé PO)

---

## Symptômes

| # | Problème | Symptôme | Cause racine |
|---|----------|----------|--------------|
| #1 | Session non persistée | L'utilisateur doit se reconnecter au média **à chaque article** | `webview_flutter` n'expose pas les cookies ; controllers WebView jetables ; aucun store partagé ni capture/réinjection |
| #2 | CTA d'abonnement invisible | La modal d'une source n'affiche **jamais** "Connecter mon abonnement" | Sur 377 sources, `premium_connection_config` renseigné = **0** → `from_config` renvoie toujours `None` → CTA gated sur `premiumConnection != null` jamais vrai |
| #3 | 400 actif en prod | `premium_sources_sheet.dart` appelle `connectSubscription` quand `premiumConnection == null` → backend lève `PremiumConnectionNotEnabled` (400) | Conséquence directe de #2 |

---

## Décisions (validées PO)

- **Session = A+B** : migrer le flow premium sur `flutter_inappwebview` (store persistant
  partagé) + capture/réinjection explicite des cookies via `flutter_secure_storage`.
- **Bug + découvrabilité traités ensemble.**
- **Découvrabilité = config curée quand on l'a + fallback générique sinon** + point
  d'entrée global « Mes abonnements ».

---

## PR 1 — Backend découvrabilité (CI-couverte, débloque PR 2) — ✅ implémentée

Chokepoint unique : toute la résolution config→réponse passe par
`PremiumConnectionResponse` + le helper de source. Effet immédiat : le CTA réapparaît
partout et le 400 disparaît, **sans migration Alembic** (zéro dépendance d'id, conforme
« 1 head » / pas de SQL manuel).

**Fichiers**
- `packages/api/app/services/premium_curated_sources.py` (nouveau) — `PREMIUM_CURATED_MAP`
  (keyé eTLD+1), `domain_key(url)`, `is_paywalled_source(source)`.
- `packages/api/app/schemas/source.py` — `PremiumConnectionResponse.is_generic`,
  classmethod `from_source(source, *, curated_map)` (config > map curée > générique > None) ;
  `SourceResponse.has_paywall`.
- `packages/api/app/services/source_service.py` — `_premium_connection` délègue à
  `from_source` ; `_has_paywall` ; `has_paywall` câblé sur les 3 builders.
- `packages/api/app/routers/sources.py` + `packages/api/app/services/pepite_service.py` —
  2 builders inline alignés (`from_source` + `has_paywall`).
- Mobile minimal : `apps/mobile/lib/features/sources/models/source_model.dart` —
  `PremiumConnection.isGeneric` + `Source.hasPaywall` (parsing).
- Tests : `packages/api/tests/test_premium_discoverability.py` (domain_key, from_source
  a/b/c/d, has_paywall, 400 levé→résolu en générique) ;
  `apps/mobile/test/features/sources/models/source_model_test.dart` (is_generic/has_paywall).

**Signal « source payante » (`has_paywall`)** : `paywall_config is not None` **ou** domaine
dans `PREMIUM_CURATED_MAP`. On n'utilise **pas** `source_tier` (faux signal).

**Vérification** : `pytest` complet **1564 passed / 0 failed** ; mobile model tests verts ;
`ruff`/`flutter analyze` propres.

---

## PR 2 — Session persistante + UI — ✅ implémentée

**Session (A+B) — mobile**
- `apps/mobile/lib/features/sources/services/premium_session_store.dart` (nouveau) —
  `PremiumSessionStore` (capture/restore/clear/hasSession) adossé à `CookieManager`
  (inappwebview) + `FlutterSecureStorage`, via abstractions `PremiumCookieJar` /
  `SecureKeyValueStore` (testabilité). Clé `premium_session::<sourceId>::<eTLD+1>` ;
  `premiumDomainKey` miroir Dart de `domain_key`.
- `apps/mobile/lib/features/sources/widgets/premium_web_view.dart` (nouveau) —
  `InAppWebView` calqué sur `youtube_player_widget.dart` (UA Chrome, `incognito:false`,
  `clearCache:false`, store partagé). `onWebViewCreated → await restore → loadUrl`.
  ScrollBridge porté (`callHandler` au lieu de `postMessage`, messages identiques) ;
  sonde paywall (mots-clés FR) → `PaywallDetected`.
- Providers : `premiumSessionStoreProvider`, `subscribedSourcesProvider`
  (`sources_providers.dart`).
- Flow de connexion (`premium_source_connection.dart`) → `ConsumerStatefulWidget` +
  `PremiumWebView` ; capture au `_confirm()` (`captureForSource(testUrl)`). Hooks de test
  `webViewBuilder`/`openExternal` conservés.
- Reader (`content_detail_screen.dart`) : **seul** le chemin premium migre
  (`InAppWebViewController? _premiumWebController` + `PremiumWebView`) ; le scroll-to-site
  gratuit reste sur `webview_flutter`. Progression partagée (`_applyWebReadingProgress`).
  Paywall détecté → bandeau non-bloquant « Session expirée — Reconnecter » (jamais de
  dissociation auto).

**Découvrabilité — UI**
- `apps/mobile/lib/features/settings/screens/subscriptions_screen.dart` (nouveau) +
  route `/settings/subscriptions` + carte « ABONNEMENTS » sur le Compte. Par source :
  logo, statut session (`hasSession`), Reconnecter / Dissocier (`+ clearForSource`).
- CTA reader « Lire avec mon abonnement » (source payante non connectée).
- CTA modal proéminent (primary + en tête quand `hasPaywall`) ; label par état
  (Reconnecter / Associer générique / Connecter curé).
- `premium_sources_sheet.dart` : branche `connectSubscription` directe supprimée (le 400).

**Tests mobile (verts)** : `premium_session_store_test.dart` (capture→restore→clear,
domain key), `premium_source_connection_test.dart` (PremiumWebView injecté + capture au
confirm), `subscriptions_screen_test.dart`, `source_model_test.dart`. `flutter analyze` :
0 erreur / 0 warning introduits.

**Validation device (non testable Playwright/CI)** : connecter Le Monde → autre article LM
→ kill+relance app → toujours connecté → Dissocier → paywall revient. iOS **et** Android
(WKWebView vs Android WebView diffèrent sur les cookies de session).
