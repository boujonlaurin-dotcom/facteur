# Runbook — Configuration RevenueCat (paywall Premium V1)

> Procédure dashboard à réaliser **une fois** pour activer le paywall.
> À conserver à jour : si tu changes un identifiant ici, le code mobile et le
> webhook backend doivent suivre (`apps/mobile/lib/config/constants.dart` +
> `packages/api/app/services/subscription_service.py`).

## 1. Source de vérité

RevenueCat = source de vérité de l'entitlement `premium`.
La table `public.user_subscriptions` est un **miroir requêtable** alimenté par
le webhook ; elle ne sert qu'à l'analytics et au back-office, jamais à
décider de l'accès dans l'app.

## 2. Configuration RevenueCat — checklist

### 2.1 Entitlement

- Identifier : `premium`
- Description : Accès aux fonctionnalités Premium de Facteur

### 2.2 Produits

Créer ces produits côté Stripe (Web Billing) :

| Identifier                   | Prix       | Période  | Essai      |
|------------------------------|------------|----------|------------|
| `facteur_premium_monthly`    | 4,99 €     | 1 mois   | 7 jours    |
| `facteur_premium_annual`     | (à fixer)  | 1 an     | 7 jours    |
| `facteur_premium_founder`    | 2,99 €     | 1 mois   | 7 jours    |

Tous les produits doivent grant l'entitlement `premium`.

### 2.3 Offerings

| Offering identifier | Packages                                    | Visibilité          |
|---------------------|---------------------------------------------|---------------------|
| `default`           | `monthly` + `annual`                        | publique (landing)  |
| `founder`           | `founder` uniquement                        | accès via `/founder.html` (lien direct) |

### 2.4 Web Billing

- Activer Web Billing pour les deux offerings.
- Personnaliser les URLs de redirection : `pay.rev.cat/facteur-premium` pour
  `default`, `pay.rev.cat/facteur-founder` pour `founder`.
- Si ces URLs diffèrent, mettre à jour `packages/api/app/routers/checkout.py`
  (constantes `DEFAULT_WEB_BILLING_BASE_URL` / `FOUNDER_WEB_BILLING_BASE_URL`).

### 2.5 Webhook

- URL : `https://facteur-production.up.railway.app/api/webhooks/revenuecat`
- Auth : utiliser un secret partagé. Le code backend supporte deux formats :
  - `Authorization: Bearer <secret>` (recommandé par RC en 2026)
  - `X-RevenueCat-Signature: <hmac_sha256>` (legacy)
- Stocker le secret en variable d'env Railway : `REVENUECAT_WEBHOOK_SECRET`.

### 2.6 Clés API SDK

- Récupérer les clés iOS et Android depuis Project Settings → API Keys.
- Stocker dans le build mobile via `--dart-define` :
  - `REVENUECAT_IOS_KEY=...`
  - `REVENUECAT_ANDROID_KEY=...`

## 3. Vérification end-to-end (sandbox)

1. Configurer un user sandbox sur le dashboard RC.
2. Sur la landing locale (`apps/landing/`), saisir un email via `/premium.html`.
3. Vérifier dans les logs Railway que `POST /api/checkout/start-passwordless`
   crée bien un user Supabase et renvoie une `checkout_url`.
4. Compléter l'achat sandbox sur la page RC.
5. Vérifier dans les logs Railway le webhook `INITIAL_PURCHASE` reçu et que
   `user_subscriptions` reflète l'état (`status=trial`, `product_id` correct).
6. Ouvrir l'app mobile, se connecter avec le même email → `isPremium == true`
   doit basculer en < 1 min via `customerInfoProvider`.
7. Annuler dans le portail RC → vérifier `status=cancelled` puis `expired`
   après période.
8. Rejouer le même event webhook (curl avec même `event.id`) → la ligne ne
   doit pas être mutée (idempotence via `last_event_id`).

## 4. Points de vigilance

- **Identité unique** : l'`app_user_id` côté web ET app DOIT être le
  `user_id` Supabase. Le checkout endpoint l'enforce, le mobile fait
  `Purchases.logIn(user.id)` au signin (cf. `apps/mobile/lib/main.dart`).
- **Web Billing EUR** : vérifier que RC Web Billing supporte EUR pour
  la région cible (compte Stripe FR sous-jacent).
- **Essai 7j** : assure-toi que l'entitlement `premium` est bien actif
  *pendant* l'essai. Sinon le paywall se redéclencherait à tort.
- **Migration Alembic** : le champ `last_event_id` ajouté par
  `sub01_subscription_idempotency.py` est nullable. Aucune action manuelle
  requise en prod, le `Dockerfile` Railway exécute la migration au boot.
