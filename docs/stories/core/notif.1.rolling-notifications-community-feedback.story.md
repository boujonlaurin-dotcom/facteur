# Story: Notif du jour — 4 nouveaux messages (feedback, WhatsApp, partage, café Laurin)

## Contexte

Demande utilisateur (2026-07-28) : ajouter 4 nouveaux messages à la file rotative
« Notif du jour » (bandeau en tête de l'Essentiel, `apps/mobile/lib/features/notif_du_jour/`) :

1. Inviter à envoyer un retour par mail à Laurin.
2. Inviter à rejoindre la communauté WhatsApp.
3. Inviter à partager l'app à ses proches (dispo sur les stores).
4. Proposer un café/discussion informelle avec Laurin.

Mécanique existante (`notif_du_jour_provider.dart` + `notif_du_jour_message.dart`) : un
catalogue de `NotifDuJourMessage` (id stable, icône, teinte, titre, CTA, `onTap`/`onDismissed`),
une file de candidats classés par pertinence + jitter quotidien déterministe, consommée un par un
(cap 3/jour, cooldown 30j au dismiss) par `NotifDuJourCard`.

## Décisions

- 4 nouveaux ids stables dans `NotifDuJourIds` : `feedbackMail`, `whatsappCommunity`, `shareApp`,
  `coffeeLaurin`. Persistance day-store/dismissal-store : ids jamais renommés après merge.
- Liens/contacts réutilisés depuis `config/constants.dart` (déjà présents, pas de nouveau secret) :
  - `LaurinContact.email` → mailto (mail retours).
  - `ExternalLinks.whatsappGroupUrl` → communauté WhatsApp.
  - `LaurinContact.whatsappE164` → wa.me prérempli « café » (même pattern que `feedback_modal.dart`).
  - Partage app : pas de lien App Store statique dans le repo (l'URL iOS est résolue dynamiquement
    côté remote config pour l'update gate) → on ne fabrique pas d'URL de store. On réutilise le
    pattern **clipboard** déjà en place (`grille_share_screen.dart`, aucune dépendance `share_plus`)
    avec un texte de partage pointant vers `https://facteur.app` (déjà utilisé comme domaine
    landing/legal dans le repo).
- Pertinence/rotation : les 4 nouveaux messages sont des candidats "toujours éligibles" (pas de
  condition de profil), avec une pertinence basse-moyenne pour ne pas dominer les messages
  fonctionnels existants (renudge, geoloc, well-informed, source, premium, veille, tournee, serein) :
  - `feedbackMail` : 0.35
  - `whatsappCommunity` : 0.3
  - `shareApp` : 0.3
  - `coffeeLaurin` : 0.25
  (valeurs calibrables avec le PO, cohérentes avec l'échelle existante 0.1–0.9)
- Dismiss (croix) : pas d'effet de bord métier (pas de nudge à faire progresser), juste le
  cooldown standard 30j déjà géré par le widget — pas besoin de `onDismissed` custom.
- Analytics : ajout de 4 events `trackNotifDuJourCta(id: ...)` génériques si un hook analytics
  existe déjà pour la file ; sinon skip (pas de tracking dédié actuellement sur les autres ids
  fonctionnels hors renudge/geoloc/well-informed qui ont leurs providers propres).

## Fichiers modifiés

- `apps/mobile/lib/features/notif_du_jour/models/notif_du_jour_message.dart`
  - 4 nouveaux ids + 4 nouveaux cases dans `buildNotifDuJourMessage`.
- `apps/mobile/lib/features/notif_du_jour/providers/notif_du_jour_provider.dart`
  - 4 nouveaux `NotifCandidate` toujours ajoutés à la file (pas de condition profil).
- `apps/mobile/test/features/notif_du_jour/` (tests existants à étendre si présents) :
  - catalogue retourne un message non-null pour les 4 nouveaux ids.
  - provider : les 4 ids apparaissent dans `notifDuJourQueueProvider`.

## Tâches

- [ ] Ajouter les 4 ids + messages au catalogue (icônes Phosphor : `envelopeSimple`,
      `whatsappLogo`, `shareNetwork`, `coffee`).
- [ ] Ajouter les 4 candidats à `notifDuJourQueueProvider`.
- [ ] Action `shareApp` : copie presse-papier + `SnackBar` de confirmation (pattern
      `grille_share_screen.dart`).
- [ ] Actions `feedbackMail`/`whatsappCommunity`/`coffeeLaurin` : `url_launcher` (pattern
      `feedback_modal.dart`).
- [ ] Tests unitaires catalogue + provider.
- [ ] `flutter test` + `flutter analyze`.
