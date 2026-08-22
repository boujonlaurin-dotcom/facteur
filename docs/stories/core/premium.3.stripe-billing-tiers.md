# premium.3 — Stripe Billing (vraies formules premium) + hardening

> Type : **Feature**. Base de toutes les PR : `main` (staging continu).
> Plan généré via `stripe_implementation_planner` (MCP Stripe) le 2026-08-22,
> croisé avec la skill `stripe-best-practices` et l'existant [[premium.2]].

## Contexte

[[premium.2]] a livré un abonnement Stripe à **prix libre** (« Soutien »), sans
lien avec le gating Premium réel (RevenueCat = seule source de vérité de
l'entitlement `premium`, alimenté par l'App Store / Play Billing côté mobile).
Cette story couvre deux choses distinctes :

1. **Hardening de l'existant** (livré dans cette story, cf. PR1 ci-dessous) —
   deux corrections identifiées en revue, indépendantes de toute décision
   produit.
2. **Plan cible pour de vraies formules Stripe Billing** (web) — dépend de
   décisions PO non encore prises (tiers, prix). Documenté ici, **pas encore
   codé**.

## PR1 — Hardening `stripe_service.py` — LIVRÉE ✅

Deux corrections identifiées en revue de code, sans impact produit :

- **Client Stripe non-global** : `stripe.api_key = ...` (mutation globale
  partagée entre requêtes concurrentes) remplacé par `stripe.StripeClient(...)`
  instancié par appel, aligné sur `stripe.checkout.sessions.create(params=...,
  options=...)` et `client.construct_event(...)` (vérifié contre la version
  réellement pinnée, `stripe==11.4.1` — pas de namespace `.v1.*`, qui n'existe
  que dans une version plus récente du SDK que celle du repo).
- **Clé d'idempotence stable** : `idempotency_key=str(uuid4())` généré à
  chaque appel ne protégeait jamais rien (deux appels identiques obtenaient
  toujours des clés différentes). Remplacé par `_support_session_idempotency_key`,
  dérivée de `(user_id, amount_cents, message)` + une fenêtre de 5 min — un
  double-clic/retry réseau à quelques secondes d'intervalle réutilise
  désormais la même session Stripe.
- Fichiers : `app/services/stripe_service.py`,
  `tests/services/test_stripe_service.py` (11 tests, dont 2 nouveaux sur la
  stabilité de la clé d'idempotence).
- **Vérifié** : suite complète `pytest -q` → 3247 passed, 21 skipped, 2 xfailed,
  0 failed (DB test locale `facteur:facteur@localhost:54322/facteur_test`,
  cf. [[project_local_backend_test_db]]). `ruff check`/`ruff format` clean sur
  les 2 fichiers touchés.

## Plan cible — vraies formules Stripe Billing (web) — NON codé, attend PO

Généré via le planner Stripe (compte `acct_1U7DBfCBSGC5BRJ7`, decision trees
`optimize_subscriptions`) à partir du contexte : B2C, digest média, mobile
reste sur RevenueCat/IAP store, Stripe = surface web uniquement.

| Axe | Recommandation retenue |
|---|---|
| Checkout | Stripe-hosted Checkout, redirect (`checkout_type: hosted`) — même pattern que l'existant |
| Mobile | Reste sur RevenueCat / App Store / Play IAP (politique store) ; Stripe = web only |
| Pricing | Flat-rate, **1 Product Stripe par tier** (jamais 2 tiers sur 1 Product), Prices séparés mensuel/annuel |
| Essai | Free trial avec carte enregistrée (miroir du `TRIAL_DAYS = 7` RevenueCat) |
| Self-service | Stripe Customer Portal (upgrade/downgrade/annulation/moyen de paiement) — **gap actuel**, aucun code existant |
| Recouvrement impayés | Smart Retries + emails automatiques (config Dashboard, zéro code) |
| Invoicing (produit Stripe) | **Non retenu.** Le planner classe ça sous « automate AR / cash flow » (B2B, facturation manuelle/AR) — hors sujet pour un abonnement B2C auto-débité. Les factures/reçus sont déjà auto-générées par Billing (`invoice.paid`, déjà géré). |
| Taxe EU/CH | Ne pas activer `automatic_tax` sans registration active (sinon Stripe collecte 0 taxe silencieusement). Suisse hors OSS/VAT-MOSS UE → registration séparée. Éligibilité **Managed Payments** (Stripe = merchant of record) à vérifier séparément — non tranché ici. |

### Bloqué en attente de décisions PO

- Nombre de tiers, noms, prix (mensuel/annuel) → conditionne la création des
  Products/Prices Stripe (test **et** live).
- Le flux « Soutien à prix libre » ([[premium.2]]) reste-t-il en parallèle des
  formules payantes, ou devient-il caduc ?
- Registration Stripe Tax (pays/seuils) — décision hors scope agent (fiscal).
- Éligibilité Managed Payments (digital-goods-only, direct account, single
  processor) à vérifier avant de trancher le flux de taxe.

**Prochaine étape** : dès ces décisions prises, découper une PR2
(Products/Prices + endpoint checkout tiers + webhook `customer.subscription.updated`
pour les changements de plan) et une PR3 (Customer Portal), sur le modèle du
découpage [[premium.2]].

## Pièges (hérités de [[premium.2]], toujours valables)

- `custom_unit_amount` Stripe ne marche pas en mode subscription (`price_data`
  inline avec `unit_amount` fixe).
- Store review : jamais de paiement direct ouvert depuis l'app mobile (App
  Store 3.1.1 / Google Play équivalent) → toute formule Stripe payée doit
  rester un parcours web (email/lien), pas un bouton in-app.
- Migration DB partagée staging/prod : toute colonne/table nouvelle pour les
  tiers doit être additive/nullable (cf. [[project_env_split_staging_prod]]).
