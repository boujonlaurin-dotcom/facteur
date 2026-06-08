# Bug Report: Sources payantes — session non persistée + découvrabilité cassée

**Status:** EN COURS — PR 1 (backend découvrabilité) prête ; PR 2 (session + UI) à suivre
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

## PR 2 — Session persistante + UI (après merge PR 1) — ⏳ à faire

`premium_session_store.dart` (CookieManager + secure storage), `premium_web_view.dart`
(InAppWebView calqué sur `youtube_player_widget.dart`, ScrollBridge porté), migration du
flow de connexion + du chemin premium du reader, détection paywall/expiration → bandeau
« Reconnecter », écran « Mes abonnements » (+ route + carte Compte), CTA reader, proéminence
CTA modal, nettoyage `premium_sources_sheet.dart`, tests mobile.

**Validation device (non testable Playwright)** : connecter Le Monde → autre article LM →
kill+relance app → toujours connecté → Dissocier → paywall revient. iOS **et** Android
(WKWebView vs Android WebView diffèrent sur les cookies de session).
