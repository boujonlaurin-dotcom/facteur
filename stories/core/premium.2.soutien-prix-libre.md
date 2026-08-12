# premium.2 — Soutien à prix libre (page web propre + Stripe + Premium in-app)

> Type : **Feature**. Base de toutes les PR : `main` (staging continu).
> Arbitrage store-review retenu par le PO : **option (c)** (cf. plus bas).

## Objectif

Remplacer le détour « magic-link brut Supabase -> RevenueCat Web Billing prix
fixe » par :

1. Une **page web Facteur propre** (`/soutenir`) présentant la mission (info de
   qualité, indépendante, sans peur ni urgence).
2. Un **abonnement à prix libre** (montant choisi par l'utilisateur, mensuel)
   via **Stripe en direct**.
3. Une reconnaissance **Premium automatique dans l'app** dès paiement validé, via
   un **entitlement RevenueCat « promotionnel »** posé par le backend -> zéro
   changement du gating mobile (`isPremiumProvider` lit déjà l'entitlement
   `premium` du SDK).

## Arbitrage store-review : OPTION (c) — validée PO

App Store 3.1.1 (et équivalent Google Play) interdit d'ouvrir un paiement externe
pour débloquer du contenu premium. Le parcours email existait précisément pour
l'éviter. **Décision : (c) on garde le flux magic-link email** (l'app ne pointe
jamais directement vers un paiement), **mais** :

- Le **template email Supabase par défaut** (« Follow this link to login ») est
  remplacé par un **email propre, à notre ton** (source de vérité versionnée :
  `apps/landing/emails/soutien-magic-link.html`, collée dans Supabase Auth ->
  Email Templates -> Magic Link).
- Le magic link **redirige désormais vers `/soutenir`** (prix libre Stripe) au
  lieu de `pay.rev.cat` (prix fixe RevenueCat).

Conséquence sur le découpage : **PR4 (mobile) conserve `send-link` +
`link_sent_screen`** (pas de suppression, pas d'ouverture directe de paiement) ;
seules la copy/le CTA et le refresh premium au retour changent. **PR5** se limite
à retirer les bouts RevenueCat Web Billing (`*_WEB_BILLING_BASE_URL`, page-pont
`checkout-redirect.html`, `_build_bridge_url`), pas le canal email.

## État de l'existant réutilisé

- Premium = entitlement RevenueCat `premium`, lu par le SDK mobile
  (`premium_provider.dart`). `user_subscriptions` = miroir analytics (webhook).
- Couplage identité : `main.dart:378` `Purchases.logIn(userId)` avec user_id
  Supabase = app_user_id RevenueCat -> un paiement web est reconnu dans l'app.
- `SubscriptionService` : pattern idempotent (`last_event_id`,
  `_is_duplicate_event`), `_get_or_create_subscription` -> étendu pour Stripe.
- `checkout.py` : `_supabase_admin_*` + `_supabase_send_magic_link` +
  `_build_bridge_url` -> réutilisés (magic link conservé, redirect_to changé).
- In-app browser store-safe déjà en place (`LaunchMode.inAppBrowserView`), JWT
  Bearer attaché à toutes les requêtes Dio.
- Landing = nginx statique `apps/landing/public/` ; modèle de ton =
  `methodologie.html` (Fraunces + palette crème/orange).

## Corrections d'hypothèses (importantes)

- Stripe `custom_unit_amount` NE marche PAS en subscription : montant saisi sur
  la page, **validé serveur** (min/max), passé en `unit_amount` fixe dans un
  `price_data` récurrent inline.
- Head Alembic réel = `sa02_alerts_v2` -> `st01_stripe_support` chaîne dessus
  (**vérifié : `alembic heads` == 1**).
- `stripe` n'était pas une dépendance (ajoutée PR1). `revenuecat_api_key`
  (config) inutilisé ; le grant promotionnel exige une **clé secrète v1 RC**
  dédiée (`revenuecat_rest_api_key`).
- Ne PAS réutiliser `supabase_jwt_secret` pour le lien signé -> secret dédié
  `checkout_link_secret` (HS256).
- Bug latent hors scope (à ne PAS corriger ici) : `subscription.py:38` (test)
  appelle `service.sync_with_revenuecat(...)` inexistant.

## Découpage en PR (chacune `--base main`)

### PR1 — Fondations (migration additive + config + dépendance) — LIVRÉE ✅
- `alembic/versions/st01_stripe_support_columns.py` (`down_revision="sa02_alerts_v2"`,
  additif/nullable) : colonnes `stripe_customer_id`, `stripe_subscription_id`,
  `support_amount_cents`, `provider` sur `user_subscriptions` + index sur les 2
  ids Stripe ; table `stripe_events(event_id PK, event_type, received_at)`.
- `app/models/subscription.py` : 4 colonnes nullable + modèle `StripeEvent`.
- `app/config.py` : `stripe_secret_key`, `stripe_webhook_secret`,
  `stripe_support_product_id`, `stripe_currency="eur"`,
  `stripe_support_min_cents=200`, `stripe_support_max_cents=10000`,
  `checkout_link_secret`, `revenuecat_rest_api_key`,
  `revenuecat_entitlement_id="premium"`, `public_web_base_url`.
- `requirements.txt` : `stripe==11.4.1`.
- **Vérifié** : `alembic heads` == `st01_stripe_support` ; upgrade+downgrade+re-upgrade
  contre une DB vide OK ; 47 tests subscription/checkout verts.

### PR2 — Backend Stripe (env-gated : 503 si `stripe_secret_key` vide) — LIVRÉE ✅
> Fait : `checkout_token.py`, `revenuecat_grant_service.py`, `stripe_service.py`
> (appels SDK bloquants en threadpool), handlers Stripe dans
> `subscription_service.py` (grant tz-safe : bug d'offset UTC corrigé),
> `create-stripe-session` + cutover env-gated de `send-link`, routeur
> `stripe_webhooks.py` (idempotence `stripe_events` = INSERT/ON CONFLICT dans la
> même tx, rollback re-traitable). 24 tests neufs + 10 subscription verts, ruff OK.

- `services/checkout_token.py` : `mint`/`verify` HS256 (`checkout_link_secret`),
  claims `{sub,email,aud:"soutenir",iat,exp}`.
- `services/revenuecat_grant_service.py` : `grant_premium(app_user_id,end_time_ms)`
  / `revoke_premium(app_user_id)` (REST v1 promotional / revoke_promotionals).
- `services/stripe_service.py` : `create_support_subscription_session(...)`
  (mode=subscription, price_data inline récurrent, validation min/max,
  idempotency_key) + `construct_event(payload,sig)`.
- `subscription_service.py` : handlers `checkout.session.completed` /
  `invoice.paid` (-> `grant_premium`, end_time = period_end + 3 j) /
  `customer.subscription.deleted` (-> `revoke_premium`) /
  `invoice.payment_failed` (-> `past_due`), idempotents via `stripe_events`.
- `routers/checkout.py` : `POST /create-stripe-session` (non-auth ; branche
  token OU email passwordless) -> `{url}`.
- **Option (c)** : `send-link` **conservé**, mais `redirect_to` devient
  `{public_web_base_url}/soutenir?t=<checkout_token>` (plus RevenueCat).
- `routers/stripe_webhooks.py` (monté `/api/webhooks/stripe`, clone de
  `webhooks.py`) : `construct_event` (401 si invalide), idempotence
  `stripe_events` (ON CONFLICT DO NOTHING), dispatch, 200 systématique.

### PR3 — Page web — LIVRÉE ✅
> Fait : `soutenir.html` (design manifeste, copy sobre, module prix libre
> 3/5/10 EUR + custom borné 2/100, fallback email si pas de `?t=`),
> `js/soutenir.js` (token vs email, validation bornes, POST create-stripe-session
> -> redirect), `soutenir-merci.html`, routes nginx `/soutenir` + `/soutenir-merci`,
> lien « Soutenir » dans le footer `index.html`. Validé au navigateur : rendu OK,
> toggle montant, garde bornes (pas de fetch si invalide), payload correct vers
> l'endpoint, redirect succès. Page autonome inline -> pas de bump `?v=` global.

- `apps/landing/public/soutenir.html` + `js/soutenir.js` + `soutenir-merci.html`
  (design manifeste `methodologie.html`). Module prix libre (3/5/10 EUR + custom,
  bornes 2 EUR/100 EUR alignées `stripe_support_*_cents`, « par mois »),
  réassurance, fallback email si pas de `?t=`.
- `nginx.conf.template` : `location = /soutenir` + `= /soutenir-merci`. Lien
  « Soutenir » de `index.html` -> `/soutenir`.

### PR4 — Mobile (option c) — LIVRÉE ✅
> Fait : `send-link` + `link_sent_screen` **conservés** (store-safe, aucune
> ouverture de paiement in-app). La copy/CTA existantes sont déjà sobres et
> compatibles prix libre (PriceRow sans montant, note « tu soutiens quand tu
> veux ») -> pas de churn inutile. Ajout : helper `premium_refresh.dart`
> (`refreshPremiumAfterCheckout` = invalidate cache RC + poll 1/2/4 s +
> invalidate `customerInfoProvider`) ; `SoutienScreen` passé en
> `ConsumerStatefulWidget` avec `AppLifecycleListener` -> refresh premium au
> `resume` (guardé si déjà premium). `flutter analyze` OK. Test unitaire du
> helper non pertinent (wrapper sur singleton natif RC, no-op hors config) ;
> validation réelle = smoke device (APK non buildable ici, pas de JDK).

### PR4 (plan initial) — Mobile
- `send-link` + `link_sent_screen` **conservés** (store-safe).
- Copy/CTA soutien alignés « prix libre » ; icône `heart`/`handHeart`.
- Refresh premium au retour : `SoutienScreen` -> `AppLifecycleListener`, sur
  `resumed` `refreshPremiumAfterCheckout()` = `invalidateCustomerInfoCache()` +
  `getCustomerInfo()` avec poll court (3 essais 1/2/4 s).

### PR5 — Nettoyage (après validation prod Stripe)
- Retirer `*_WEB_BILLING_BASE_URL`, `_build_bridge_url`,
  `checkout-redirect.html`, page-pont. **Conserver** `send-link` /
  `_supabase_send_magic_link` (canal email = mitigation store).

## Email « Magic Link » (option c) — livrable clé PO

`apps/landing/emails/soutien-magic-link.html` (source versionnée, à coller dans
Supabase). Objet suggéré : « Merci pour ta demande de soutien ». Ton **sobre**
(copy validée PO : pas de fausse lettre personnifiée, argument coût/indépendance,
signé « Django & Laurin » sans fioriture), palette crème/orange, Fraunces->Georgia,
sans em-dash, `{{ .ConfirmationURL }}`.

## Mot de soutien (mur public modéré) — LIVRÉE ✅
Le soutien peut laisser un « mot » optionnel sur `/soutenir` (280 car. max).
Pipeline : champ web -> `create-stripe-session {message}` -> metadata de session
Stripe -> persisté au webhook `checkout.session.completed` dans
`supporter_messages` (migration **st02**, `down_revision="st01_stripe_support"`),
**`published=false` par défaut = modération avant tout affichage public**.
Lecture publique : `GET /api/checkout/support-messages` (uniquement `published`).
Affichage : section « Ils soutiennent Facteur » sur `/soutenir`, **masquée tant
qu'aucun message publié** (rendu `textContent` = pas d'injection HTML).

> ⚠️ **Décision PO en attente** : (a) garder la modération manuelle (aucun outil
> d'admin pour l'instant : publier = passer `published=true` en base), ou (b)
> auto-publier (risque spam/PII/abus sur une surface publique). Défaut retenu :
> modéré. Placement du mur (page `/soutenir` vs page dédiée vs `index`) à confirmer.

## Config & étapes manuelles PO

1. Stripe : Product « Soutien Facteur » -> `stripe_support_product_id` ; clés
   `sk_...` (test + live).
2. Webhook Stripe -> `https://facteur-production.up.railway.app/api/webhooks/stripe`
   (4 events) -> `whsec_...`.
3. RevenueCat : clé API **secrète v1** ; vérifier entitlement `premium`.
4. `checkout_link_secret` aléatoire fort.
5. Env vars sur Railway **staging ET prod**.
6. Configurer Resend côté Railway : `RESEND_API_KEY`, `RESEND_FROM_EMAIL`,
   `RESEND_WEBHOOK_SECRET`, puis le webhook `/api/webhooks/resend` pour les six
   événements de livraison. Le lien de soutien est envoyé directement par l'API
   et suivi jusqu'à la remise : aucun template Magic Link Supabase n'est requis.

## Tests & vérif

- pytest : `test_checkout_stripe.py`, `test_stripe_webhooks.py`,
  `test_revenuecat_grant_service.py` (cf. plan).
- flutter : provider refresh premium (poll), copy/CTA.
- E2E : `stripe listen` + carte test 4242, vérifier grant/revoke + idempotence.

## Pièges

- Grant : `end_time_ms = period_end + 3 j`, re-grant à chaque `invoice.paid`,
  `revoke_promotionals` sur `subscription.deleted`. Webhook manqué -> retries
  Stripe.
- Propagation grant -> SDK : `invalidateCustomerInfoCache` + poll.
- Sécurité : token `exp` court + `aud`, jamais loggé, absent du success_url ;
  seul `amount_cents` vient du user et est borné ; `construct_event` anti-forge.
- Migration DB partagée : additif nullable + table neuve ; PR1 avant tout code
  lisant ces colonnes ; `alembic heads` == 1.
- Clé RC bien **secrète v1** (clé SDK publique -> 401 sur `/promotional`).
