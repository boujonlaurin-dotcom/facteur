# Paywalls Premium « Fact·eur·isse » — implémentation de la maquette

## Context

La maquette Claude Design **Paywalls Premium.dc.html** (projet 81284798) définit le système de monétisation UX de Facteur : un seul abonnement à 3 €/mois, deux portes d'entrée (écran **Soutien** incarné par les fondateurs, et **murs de feature** utilitaires), zéro urgence/culpabilisation. Le CTA n'ouvre jamais un paiement in-app : le Facteur envoie le lien de checkout **par email** (règles stores).

État du code : RevenueCat est branché (PR #597 : entitlement `premium`, `isPremiumProvider`, purchase natif dormant), un ancien `PaywallScreen` existe mais n'est atteignable nulle part, et **aucun gating de feature n'existe** (pas de cap 30 sources, pas de gate veille, pas de quota analyses, pas de personnalisation serein). Le backend n'a **aucun envoi d'email** ; `/api/checkout/start-passwordless` construit déjà l'URL Web Billing (`_build_checkout_url` → `https://pay.rev.cat/facteur-premium?app_user_id=<id>`).

### Décisions utilisateur (bloquantes)
- CTA = **lien par email** via **magic-link Supabase Auth** (`POST /auth/v1/otp`, `redirect_to` → URL checkout). Le purchase natif PR #597 reste dormant. Zéro nouveau secret.
- Gating = **client-side mobile uniquement** (pas d'enforcement backend).
- Réglages **reste une bottom sheet** (`settings_sheet.dart`), on y ajoute les entrées/badges.
- Photos fondateurs : à télécharger depuis le projet design. **⚠️ Les prénoms de la maquette sont inversés** : la photo étiquetée DJANGO dans la maquette est Laurin, et vice versa. Convention : sauvegarder `django_crop.jpg` (source) → `assets/images/founders/laurin.jpg` et `laurin_crop.jpg` → `django.jpg`, pour que nom de fichier = vraie personne ; les labels affichés suivent le nom de fichier. Commenter le swap dans le widget.

Maquette complète sauvegardée : `/Users/laurinboujon/.claude/projects/-Users-laurinboujon-conductor-workspaces-facteur-algiers-v3/cf23ca91-e5aa-40d0-b614-05bea5c5b046/tool-results/toolu_01HB3b6GVEkvTcPfPjPQhu2Q.txt` (JSON-wrapped, lignes très longues → lire par `cut -c`).

---

## PR 1 — Backend : `POST /api/checkout/send-link`

Dans `packages/api/app/routers/checkout.py` (router déjà monté `/api/checkout`) :

1. Nouveau helper `_supabase_admin_get_user_email(user_id)` → `GET {supabase_url}/auth/v1/admin/users/{user_id}` (mêmes headers service-role que `_supabase_admin_lookup_user_by_email`).
2. Endpoint authentifié (`Depends(get_current_user_id)`) :
   - construit l'URL via `_build_checkout_url(offering, user_id)` (existant) ;
   - envoie le magic link : `POST {supabase_url}/auth/v1/otp` body `{"email", "create_user": false}` + `redirect_to=<checkout_url>`, header `apikey: settings.supabase_anon_key` — Supabase envoie l'email lui-même ;
   - `_get_or_create_subscription(user_id)` + commit (parité avec `start_passwordless`) ;
   - PostHog `checkout_link_sent {offering, resend}` ;
   - 429 Supabase (rate-limit OTP ~1/min) → propagé proprement.
3. Schemas `packages/api/app/schemas/checkout.py` : `CheckoutSendLinkRequest(offering="default", resend=False)`, `CheckoutSendLinkResponse(sent, email)`.
4. **Aucune migration Alembic** (aucune table touchée).
5. Tests `packages/api/tests/routers/test_checkout_send_link.py` — calqués sur `test_checkout_start_passwordless.py` (overrides `get_db`/`get_current_user_id`, patch des helpers) : happy path (redirect_to contient app_user_id), email introuvable, 429, flag resend.

**Étape manuelle (PO)** : ajouter l'URL de redirect à l'allow-list Supabase Auth. Option A : `https://pay.rev.cat/*`. Option B (fallback) : page statique `checkout-redirect.html` sur la landing (qui a déjà `premium.html` + `js/checkout.js`) qui forwarde vers pay.rev.cat.

## PR 2 — Mobile : feature `lib/features/soutien/`

### Nouveaux fichiers
- `soutien_copy.dart` — toutes les strings (copy verbatim maquette, **em-dashes « — » remplacés** par `,` / `·` / `:` conformément à la règle projet ; ex. « Deviens Fact·eur·isse · 3 €/mois », « honnêtement, sans te manipuler »).
- `providers/checkout_link_provider.dart` — `checkoutLinkProvider` (AsyncNotifier), `sendLink({resend})` → POST `/checkout/send-link` via l'ApiClient Dio existant (`core/api/`) ; erreurs → `NotificationService.showError`.
- `providers/analyse_quota_provider.dart` — quota local 1/jour : SharedPreferences clé `analyse_quota_YYYY-MM-DD` (reset minuit, purge des clés stales) ; `canLaunch` (premium → toujours true), `recordUse()`.
- `providers/premium_gate_provider.dart` — façade `PremiumGate { isPremium, followedSourcesCount, sourceCapReached (>=30), canCreateVeille, canCustomizeSerein }` dérivée de `isPremiumProvider` + `userSourcesProvider` (`sources_providers.dart:176` — **vérifier** que sa longueur = « médias suivis »). Plus `premiumSinceProvider` depuis `customerInfoProvider` → `entitlements.active['premium'].originalPurchaseDate` (nullable → masquer la ligne « depuis … »).
- `screens/soutien_screen.dart` — porte 1 : eyebrow mono « UNE LETTRE DE DJANGO & LAURIN », headline Fraunces « Une info qui ne te manipule pas, ça se finance autrement. », collage fondateurs (photos rotées, clip organique via `ClipRRect` radii asymétriques), lettre 2 §, signature, carte bonus (4 features + 2 stamps `BIENTÔT` via `FacteurStamp`), 3 réassurances, prix « 3 € /mois », CTA « Reçois ton lien pour nous rejoindre », disclaimer stores.
- `screens/veille_wall_screen.dart` — porte 2 : `facteur_veille.png` (déjà bundlé), 3 bénéfices, `MissionCard` avec « Notre histoire → » → Soutien, prix, CTA « Reçois ton lien pour débloquer ».
- `screens/link_sent_screen.dart` — enveloppe + cachet « ENVOYÉ / <date> » (`DateFormat('d MMM yyyy','fr')`, anim scale easeOutBack gated `MediaQuery.disableAnimations`), « Ton lien est en route. », `PrimaryButton` « Retour à ma lecture », secondaire « Renvoyer le lien » → `sendLink(resend:true)` + toast (429 → « Patiente une minute avant de renvoyer »).
- `widgets/founder_photos.dart` (`FounderCollage` + `FounderMiniDuo`), `widgets/mission_card.dart`, `widgets/price_row.dart`, `widgets/checkout_cta_button.dart` (wrappe `PrimaryButton` existant, icône enveloppe, loading depuis `checkoutLinkProvider`, succès → LinkSent ; depuis une sheet : pop puis push), `widgets/paywall_sheet.dart` (`PaywallSheet.show(context, PaywallWallVariant.{sources|analyses|serein})`, pattern `showModalBottomSheet` de `FeedbackModal`).

### Routes (`config/routes.dart`)
`soutien` → `/soutien`, `veilleWall` → `/soutien/veille-wall`, `soutienLinkSent` → `/soutien/lien-envoye` (FullSwipeCupertinoPage, root navigator).

### `settings_sheet.dart` (modifs)
1. `_ProfileBlock` : premium → `FacteurStamp('FACT·EUR·ISSE')` + « depuis <mois année> » ; free → grade actuel.
2. Nouvelle `_SoutienTile` (entre profil et serein) : `FounderMiniDuo` ; free → « Nous soutenir / Deviens Fact·eur·isse · 3 €/mois » → push Soutien ; premium → « Ton soutien / 3 €/mois · gérer mon abonnement » → `RouteNames.subscriptions`.
3. `_SereinSwitchTile` : sous-row « Personnaliser mes bonnes nouvelles » ; free → lock + `PaywallSheet(serein)` ; premium → toast « Bientôt disponible » (écran hors scope).
4. `_ContentShortcuts` : « Mes sources » badge mono `N/30` si free (primary à 30/30) ; « Ma veille » stamp `PREMIUM` si free, tap free sans veille → `veilleWall`. `_ShortcutTile` gagne un param `trailing`.

### Gates aux touchpoints
- **Veille intro** (`veille_intro_screen.dart` + garde deep-link dans `veille_config_screen.dart`) : free → stamp « RÉSERVÉ AUX FACT·EUR·ISSES », CTA lock « Créer ma première veille » → `veilleWall`.
- **Add source** (`source_add_panel.dart`) : pill « N / 30 médias suivis » (free) vs pill verte « Sources illimitées · Fact·eur·isse » (premium) ; dans `_addSource` (~l.175) : cap atteint → `PaywallSheet(sources)` et return.
- **Analyse IA** : garde dans `content_detail_screen.dart` `_openPerspectivesAnalysis` (~l.1853) et `perspectives_bottom_sheet.dart` `_requestAnalysis` (l.386) : `!canLaunch` → `PaywallSheet(analyses)` ; `recordUse()` uniquement sur lancement frais (state idle, pas la réouverture d'une analyse cachée). Surfaces : bannière « Ton analyse offerte du jour a été utilisée. Reviens demain, ou passe en illimité. » (free, quota épuisé) / pill « Analyses illimitées · Fact·eur·isse » (premium). `topic_section.dart` affiche du pré-calculé → non gaté.

### Assets
Télécharger via DesignSync `get_file` : `assets/django_crop.jpg` → `apps/mobile/assets/images/founders/laurin.jpg`, `assets/laurin_crop.jpg` → `.../django.jpg` (swap voulu). Ajouter `- assets/images/founders/` au pubspec (le glob actuel ne récurse pas). Si le binaire ressort corrompu du get_file, demander les fichiers à l'utilisateur.

### Artefacts process (CLAUDE.md)
- Story doc `docs/stories/core/premium.1.paywalls-facteurisse.md` (plan + tasks).
- `apps/mobile/assets/changelog.json` (unreleased) : `{ "tag": "Soutien", "summary": "Deviens Fact·eur·isse et débloque veille, sources illimitées, analyses et mode serein sur mesure." }`

## Vérification
- Backend : `cd packages/api && pytest -v` ; uvicorn local + curl `POST /api/checkout/send-link` (JWT test) → vérifier l'appel OTP mocké/réel et le 429.
- Mobile : `flutter test && flutter analyze` ; tests widgets : settings_sheet (états free/premium via overrides `isPremiumProvider`/`customerInfoProvider`/`userSourcesProvider`), `analyse_quota_provider_test` (rollover jour, bypass premium), `paywall_sheet_test` (3 variantes), smoke Soutien/LinkSent, cap 30 dans `source_add_panel`, gate veille intro.
- E2E visuel : Playwright Agent CLI sur build web (skill `facteur-qa-web`, viewport 390x844) — parcours Réglages → Soutien → CTA → confirmation ; toggle premium impossible en web (RevenueCat null) → vérifier surtout l'état free. QA handoff `.context/qa-handoff.md` puis `/validate-feature`, puis `/go` (PR `--base main`).
- Smoke APK : `flutter build apk --debug --flavor staging`.

## Risques / points ouverts
1. Allow-list redirect Supabase = étape manuelle dashboard (option B landing en fallback). Vérifier le template email magic-link (wording « connexion »).
2. Rate-limit OTP ~1/min → gérer le 429 sur « Renvoyer ».
3. Identité RC : le web checkout key l'entitlement sur l'id Supabase — `Purchases.logIn` est déjà appelé au login (`main.dart:367`), OK.
4. Quota analyses local au device (reset à la réinstall) — accepté.
5. Vérifier sémantique `userSourcesProvider` avant de câbler le cap 30.
6. Ancien `paywall_screen.dart` : suppression en follow-up.
