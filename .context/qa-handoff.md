# QA Handoff — Alerte source rare (story 30.2, Epic 30 PR 2)

> Rempli par l'agent dev. Input de /validate-feature. Story :
> `docs/stories/core/30.2.alerte-source-rare.md`.

## Feature développée

Une cloche « alerte » posable sur une source qui publie **moins d'une fois par
semaine** : Facteur prévient à chaque parution, par une notification
**silencieuse** livrée au créneau de l'utilisateur. Plafond de 5 cloches.
Embarque deux nettoyages PO : le sélecteur de préset Notifications est remplacé
par le réglage des Alertes, et la notif hebdo « Les Fact·eur·isses adorent cet
article » est supprimée.

## PR associée

À compléter après ouverture.

## Écrans impactés

| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Mes alertes | `/settings/alerts` | **Nouveau** |
| Notifications | `/settings/notifications` | Modifié (section « Rythme » → « Alertes ») |
| Mes intérêts | `/settings/interests` | Modifié (ligne « Mes alertes · x/5 ») |
| Fiche source (modale) | overlay | Modifié (bloc « 📯 Activer la cloche ») |
| Modale d'activation notifs | overlay | Modifié (preset retiré, `ActivationTrigger.alert`) |
| Tournée du jour | `/` | Modifié (section « Tes alertes » quand du neuf) |
| Profil | `/settings/profile` | Modifié (bouton QA, visible en beta/debug seulement) |

## Scénarios de test

### Scénario 1 : Happy path — poser une cloche sur une source rare
1. Ouvrir la fiche d'une source qui publie rarement (chip horloge
   « quelques articles par mois »), déjà suivie.
2. Section « Réglages de suivi » → le bloc « 📯 Activer la cloche » est **au-dessus**
   de « Priorité dans ton flux ».
3. Basculer le switch.
**Résultat attendu** : switch actif, sous-texte « Cette source publie environ une
fois par mois. Tu seras prévenu à chaque parution. ». La cloche apparaît dans
`/settings/alerts` avec le compteur « 1 / 5 ».

### Scénario 2 : Source trop bavarde
1. Ouvrir la fiche d'une source quotidienne (ex. un grand quotidien), suivie.
**Résultat attendu** : le switch est **grisé/inactif**, le sous-texte dit
« Cette source publie trop souvent pour une alerte. », et une ligne cliquable
« Suis plutôt ce sujet. » ouvre la feuille d'ajout de sujet.

### Scénario 3 : Plafond de 5 atteint
1. Poser 5 cloches, puis tenter une 6ᵉ sur une source rare éligible.
**Résultat attendu** : SnackBar « Tu as déjà 5 alertes. Désactives-en une dans
Mes alertes. » avec une action « Voir » qui pousse `/settings/alerts`. Le switch
retombe à off (pas d'optimisme trompeur).

### Scénario 4 : Mini-sheet post-« Suivre » (moment chaud)
1. Depuis le catalogue ou une feuille de perspectives, suivre une source rare
   non encore suivie.
**Résultat attendu** : après le toast de succès, une feuille basse propose
« 📯 Ne rate pas sa prochaine parution » / [Activer la cloche] [Plus tard].
Elle ne doit **jamais** apparaître pour une source bavarde, ni pendant
l'onboarding (le suivi y est différé au submit).

### Scénario 5 : Écran « Mes alertes » — le silence comme preuve
1. Ouvrir `/settings/alerts` avec au moins une cloche.
**Résultat attendu** : en-tête « x / 5 alertes actives » ; une carte par cloche
avec logo + nom, une ligne d'état dérivée de la dernière parution réelle
(« Rien de neuf depuis 3 semaines, et c'est vérifié. »), le réglage « Quand me
prévenir » avec « Récap hebdo » **grisé** (V1, aucun producteur derrière), et
« Désactiver l'alerte ». État vide : explication du geste + « Voir mes sources ».

### Scénario 6 : Réglages Notifications
1. Ouvrir `/settings/notifications`.
**Résultat attendu** : **plus aucun** sélecteur Minimaliste/Curieux. À la place
une section « Alertes » → « Mes alertes · x/5 ». La section « Horaire » et le
toggle « Bonnes nouvelles » sont inchangés. La phrase de description ne mentionne
plus le vendredi 18:00.

### Scénario 7 : Notification sur téléphone (le point de la demande)
1. Installer l'APK staging de la branche.
2. Profil → bloc QA → « Tester une alerte source ».
**Résultat attendu** : notification **sans son ni vibration**, titre
`📯 Alerte : … vient de publier`, corps = titre d'article, déplié = corps + la
ligne de rareté. Tap → ouverture du bon article.
Vérifier aussi dans les réglages Android que le canal **« Alertes »** existe,
distinct de « Digest quotidien ».

## Critères d'acceptation

- [ ] La cloche n'est proposée que sur des sources < 1 article/semaine
- [ ] Plafond de 5 respecté, avec message et chemin de sortie
- [ ] Désactiver une cloche marche même si la source est devenue bavarde
- [ ] La notification d'alerte est silencieuse (canal dédié), la tournée reste sonore
- [ ] `/settings/alerts` rend le silence lisible (dernière parution réelle)
- [ ] Le sélecteur de préset a disparu partout
- [ ] Aucune trace de « Les Fact·eur·isses adorent cet article »

## Zones de risque

- **Canal Android** : Android ignore tout changement de son/importance sur un
  canal **existant**. D'où un id neuf (`alerts_channel`). Vérifier sur un device
  qui avait déjà l'app installée que le nouveau canal apparaît bien.
- **Purge de la pépite hebdo** : les installations existantes ont déjà une
  notification planifiée pour le prochain vendredi 18:00. Le code appelle
  `cancelLegacyCommunityPick()` inconditionnellement dans `_reschedule`, qui
  tourne à chaque fetch Flux Continu. À vérifier sur un device mis à jour depuis
  une version antérieure : **aucune** notif ne doit tomber le vendredi 18:00.
- **Ids de notification** : deux alertes de sources différentes ne doivent pas
  s'écraser mutuellement dans le tiroir.
- **Budget partagé** : au plus 1 alerte/jour passe une fois la tournée envoyée.
  C'est **voulu**. Ne pas le remonter comme un bug.

## Dépendances

- `PUT /api/sources/{source_id}/alert` — body `{enabled: bool}` →
  `{enabled, active_count, cap}`. Erreurs : 404, 409 `not_followed`,
  409 `alert_cap_reached`, 422 `source_not_rare`.
- `GET /api/alerts` → `{cap, active_count, items[]}`.
- Job serveur `source_alert_push_dispatch` (toutes les 5 min) — **prod/staging
  seulement**, nécessite Firebase configuré. Le bouton QA ne le sollicite pas.
