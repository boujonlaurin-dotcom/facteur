# Maintenance — Filtre Sentry pour le bruit `trafilatura`

**Date** : 2026-04-19
**Branche** : `claude/backend-stability-scalability-PAzL7`
**Décision CTO** : D1 F1 (handoff 2026-04-19)

## Symptôme

Depuis 2026-04-18 15:00 UTC, le quota du projet Sentry est **entièrement consommé**
par du bruit externe émis par la lib `trafilatura` (extraction d'articles web).
Conséquence : Sentry refuse tous les events suivants → on vole aux instruments
cassés sur la release `c2d2d802` (PR #436) déployée dans la nuit.

Volume responsable : logs `WARNING`/`ERROR` de `trafilatura.*` avec messages
contenant `"not a 200 response"` ou `"download error:"` — bruit HTTP normal
(404, timeouts, paywalls) remonté comme erreurs par `LoggingIntegration`.

## Fix

Ajout d'un `before_send` callback dans `sentry_sdk.init(...)` (fichier
`packages/api/app/main.py`). Le callback drop (retourne `None`) les events qui
matchent simultanément :

1. `logger_name` commence par `"trafilatura"` (champ `event["logger"]` posé
   par la `LoggingIntegration`)
2. ET message contient `"not a 200 response"` OU `"download error:"`
   (case-insensitive, teste `logentry.message` ET `message` top-level)

Tous les autres events passent inchangés.

## Portée volontairement étroite

Le filtre exige **les deux conditions** simultanément pour éviter de masquer
de vrais bugs :
- Si notre propre code loggait `"not a 200 response"` (ex: `app.services.fetcher`),
  il continue à remonter (logger ≠ trafilatura).
- Si trafilatura logge une vraie erreur interne inattendue (parsing, OOM),
  elle continue à remonter (message ≠ HTTP noise).

## Tests

`packages/api/tests/test_sentry_before_send.py` — 8 cas couvrant :
drop des deux signatures, passage des events trafilatura légitimes, passage
des events non-trafilatura avec messages qui matchent, tolérance events sans
`logger`, case-insensitivity, message vide.

## Rollback

Retirer l'argument `before_send=_sentry_before_send` du `sentry_sdk.init(...)`
et supprimer la fonction `_sentry_before_send`. Aucun impact schéma / DB.

## Suite (non couvert ici)

Si le bruit `trafilatura` réapparaît sous une autre signature (nouveau
message type), élargir le filtre au cas par cas — ne PAS filtrer `trafilatura.*`
entièrement : ça masquerait les vrais bugs internes de la lib.

Alternative long terme : configurer le logger `trafilatura` en `logging.CRITICAL`
côté application pour qu'il n'atteigne jamais Sentry — décision non prise
(l'équipe veut garder la trace locale des erreurs d'extraction pour debug).
