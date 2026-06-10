# QA Handoff — Sources payantes : session persistante + découvrabilité

> Bug doc : `docs/bugs/bug-sources-payantes-session-decouvrabilite.md`
> Branche : `boujonlaurin-dotcom/webview-credentials-not-saving`. Base **main**.

## ⚠️ Portée de la validation web (Chrome / `/validate-feature`)

La **persistance de session** (capture/réinjection des cookies natifs WKWebView /
Android WebView) **n'est pas testable sur le web** — elle requiert un device iOS **et**
Android (cf. plan → Vérification → Device). La validation web couvre **la découvrabilité
UI** uniquement.

## Écrans impactés

| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Fiche source (`SourceDetailModal`) | overlay | Modifié (CTA proéminent) |
| Compte (`AccountScreen`) | `/settings/account` | Modifié (carte « ABONNEMENTS ») |
| Mes abonnements (`SubscriptionsScreen`) | `/settings/subscriptions` | **Nouveau** |
| Reader (`ContentDetailScreen`) | `/content/:id` | Modifié (CTA paywall) |

## Scénarios (viewport mobile 390×844)

### 1. CTA modal réapparaît (cœur du fix #2)
Ouvrir la fiche d'un média payant (Le Monde, Mediapart, Le Figaro, L'Équipe, Libération,
Les Échos, Télérama). **Attendu** : un CTA **primary en tête** :
- jamais abonné, config curée → « Connecter mon abonnement »
- jamais abonné, config générique → « Associer mon abonnement »
- déjà abonné → « Reconnecter cet abonnement »

*(Avant : aucun CTA — `premium_connection_config` = 0/377 sources.)*

### 2. Mes abonnements
Compte → carte « ABONNEMENTS » → « Mes abonnements ».
- Sans abonnement : état vide « Aucun abonnement connecté ».
- Avec abonnement : carte par source (logo, nom, statut session, Reconnecter / Dissocier).

### 3. Dissocier
Depuis « Mes abonnements » ou la fiche → la source quitte la liste / le badge abonné tombe.

## Edge cases
- Source **gratuite** : **aucun** CTA abonnement, **aucune** entrée « Mes abonnements ».
- Onboarding `PremiumSourcesSheet` : « Connecter » ouvre le flow (plus de 400
  `PremiumConnectionNotEnabled`).

## Critères d'acceptation (web)
- [ ] CTA visible, libellé correct selon l'état, primary quand source payante.
- [ ] `/settings/subscriptions` accessible depuis le Compte ; état vide + liste OK.
- [ ] Aucune erreur console / 4xx-5xx inattendu sur les toggles d'abonnement.

## Critères d'acceptation (device — manuel, hors Chrome)
- [ ] Connecter Le Monde → ouvrir un autre article LM → **kill + relance** → toujours
      connecté (pas de re-login). → valide le bug principal #1.
- [ ] Dissocier → le paywall réapparaît.
- [ ] Répéter **iOS et Android**.

## Dépendances
Backend : PR 1 incluse dans la même branche (fallback générique `from_source` +
`has_paywall`, pas de migration Alembic). `pytest` complet vert (1564).
