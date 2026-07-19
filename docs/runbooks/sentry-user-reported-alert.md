# Runbook — Alerte Sentry « bug signalé par l'utilisateur »

> Configuration **manuelle dans Sentry** (hors code app). Complète la feature
> micro-toast « souci côté device » (device-only, cf. la bannière
> `UserFacingErrorBanner`).

## Contexte

Quand un utilisateur tape « Nous dire » sur la bannière et envoie, l'app émet :

- un event **Sentry** `Bug signalé par l'utilisateur` (`level: error`) avec les
  tags `user_reported:true`, `source:<flutter_error|http_5xx|timeout>` et un
  contexte `user_error` (`route`, `signature`, `detail`, `comment`) ;
- un event **PostHog** `user_error_reported` (funnel, propriétés `source`,
  `has_comment`).

Ces events sont le **signal fort** : ils distinguent les vrais bugs UX vécus du
bruit Sentry ambiant.

## Config de l'alerte (Sentry)

1. **Saved search** : `user_reported:true` (Issues → Custom Search → Save).
2. **Alert rule** (Alerts → Create Alert → Issues) :
   - *When* : `An event is seen`
   - *If* : `The event's tags match user_reported equals true`
   - *Threshold* : `number of events` **≥ 3 in 24h** sur la même issue.
   - *Then* : notifier le canal **Slack #ops** (ou email équipe).
3. Nommer la règle `user-reported bug spike` et l'activer sur les environnements
   `production` **et** `staging`.

## Kill-switch app

La bannière est en **dark launch** : `UserErrorBannerConstants.enabled` = `false`
par défaut. Pour l'activer, builder avec
`--dart-define=USER_ERROR_BANNER_ENABLED=true` (activation progressive : un canal
d'abord, monitorer le volume `user_reported:true` sur 48h avant généralisation).

Un vrai remote-flag PostHog remplacera ce define en suivi (choix (b) du plan V1).

## Vérif rapide

Forcer un 500 sur un appel opt-in (`extra['userFacing']`) → bannière → tap
« Nous dire » → envoi → l'event doit apparaître dans la saved search en < 1 min.
