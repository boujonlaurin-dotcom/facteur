# feat(notifs) : alerte source rare + refonte du réglage Notifications (story 30.2, Epic 30 PR 2)

Story : [`docs/stories/core/30.2.alerte-source-rare.md`](docs/stories/core/30.2.alerte-source-rare.md)
Prédécesseur : #988 (gouverneur de budget push + push « coup d'œil »)

## Ce que ça livre

Le premier vrai geste utilisateur de l'Epic 30 : **poser une cloche sur une
source rare**. C'est le cas d'usage le plus sûr — impossible à transformer en
spam par construction (source qui publie moins d'une fois par semaine, plafond
de 5 cloches) — et il installe le geste dont dépend la PR #3.

Une info = une notif claire. L'alerte est une notification distincte,
**silencieuse**, livrée au créneau de l'utilisateur. Seule la tournée sonne.

## Arbitrages PO embarqués (26/07)

1. **Exemption du cooldown rituel.** La règle des 4h du gouverneur refusait
   *toute* alerte (un kind non rituel est bloqué dès qu'un rituel est envoyé ou
   attendu à moins de 4h, or l'alerte part dans la même passe que la tournée).
   Nouveau paramètre `ritual_companion=True` : le cooldown est sauté, les
   budgets 2/24h et 6/7j restent appliqués. **Conséquence assumée** : le budget
   quotidien étant partagé avec la tournée, au plus 1 alerte par jour passe ;
   les suivantes sont `skipped` avec `daily_budget_exceeded`. C'est le garde-fou
   qui fait son travail, pas un bug.
2. **`NotifPreset.curieux` retiré de l'UI.** La pépite hebdo « Les
   Fact·eur·isses adorent cet article » était sa *seule* différence avec
   `minimaliste` (le backend stocke `preset` sans jamais le lire). Le sélecteur
   de préset est remplacé par le réglage des Alertes. Le champ `preset` reste en
   base, dans Hive et dans le DTO : **aucune migration, aucun changement d'API**.
3. **Bouton QA** pour tester la notif sur téléphone avant merge.

## Écart vs plan : 2 heads Alembic sur `main`

Le plan supposait `es01_essentiel_placement` comme head unique. `origin/main`
en portait **deux** (`pt01_contents_entities_trgm` et `rd01_ucs_completed_at`,
tous deux enfants de `181c618da382`) — un fork de merge concurrent, cas déjà
rencontré (`mg01`/`mg02`/`mg03`). Cette PR ajoute donc `mg04_merge_pt01_rd01`
(révision de merge vide) avant sa propre migration. Sans ça, `alembic upgrade
head` — rejoué au boot de **chaque** conteneur Railway par le `Dockerfile` —
échoue et plante le déploiement.

## Backend

- **Migrations** : `mg04_merge_pt01_rd01` (vide) + `sa01_user_sources_notify`
  (`ADD COLUMN notify BOOLEAN NULL` + index partiel
  `ix_user_sources_notify_source ... WHERE notify IS TRUE`). Strictement
  additive et idempotente → sûre en expand-contract sur la DB partagée
  staging/prod, lue partout comme `notify IS TRUE`.
- **`source_alert_producer.py`** : `is_rare_source(...)` pure, miroir exact de
  `publication_frequency.dart` (fenêtre 30 j clampée à l'âge réel de la source,
  pour ne pas classer « rare » une source fraîchement ingérée). `articles_30d
  == 0` n'est **pas** éligible : sans preuve qu'elle publie, la cloche ne
  sonnerait jamais. Rareté rejouée à l'activation **et** au dispatch.
- **`kind` porteur de la source** : `push_deliveries` est unique par
  `(device_id, target_date, kind)` ; deux cloches du même jour entreraient en
  collision avec un `kind` constant, et élargir la contrainte n'est pas
  expand-contract safe. D'où `source_alert:{source_id.hex[:16]}` (29 c, tient
  dans le `String(32)`). Analytics/PostHog reçoivent le `kind` propre
  `source_alert` + une propriété `source_id`.
- **`push_alert_dispatcher.py`** : réutilise les helpers de `push_dispatcher`
  rendus publics (`send_fcm`, `is_due`, `get_or_create_delivery`,
  `firebase_configured`, `is_invalid_token_error`) plutôt que de les dupliquer.
  Job `source_alert_push_dispatch` toutes les 5 min.
- **Endpoints** : `PUT /api/sources/{id}/alert` (404 / 409 `not_followed` /
  409 `alert_cap_reached` / 422 `source_not_rare` ; désactiver est toujours
  autorisé, sinon une source devenue bavarde piégerait sa propre cloche) et
  `GET /api/alerts`.

## Mobile

- Cloche sur la fiche source (éligibilité depuis `sourceProfileProvider`, déjà
  chargé → aucun appel réseau supplémentaire), mini-sheet post-« Suivre » via le
  helper unique `maybeOfferSourceAlert`, écran « Mes alertes »
  (`/settings/alerts`), canal Android `alerts_channel` silencieux, nudge
  d'intro, badge `rare` en onboarding, section « Tes alertes » dans la Tournée.
- Suppression complète de la pépite hebdo. **Piège traité** : les installations
  existantes ont déjà une notification planifiée pour le prochain vendredi
  18:00 ; supprimer le code ne l'annule pas. `cancelLegacyCommunityPick()` est
  conservée et appelée inconditionnellement en tête de `_reschedule` (qui tourne
  à chaque fetch Flux Continu) — nettoyage one-shot supprimable dans une release
  ultérieure.

## Portée honnête du bouton QA

Profil → bloc QA → « Tester une alerte source » injecte localement le payload
`data` exact qu'enverrait FCM. Ça valide le canal silencieux, la copy, les ids
de notification et le deep-link au tap. Ça ne valide **pas** le transport FCM ni
le producteur serveur — ceux-là se vérifient sur staging après merge.

## Vérification

Voir la section « Vérification » de la story.
