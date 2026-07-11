# PR — 2 fixes UX/UI : carte de source + notifs inlines

Deux irritants UX signalés par le PO, regroupés en une seule PR (`--base main`).
Pas de migration, pas de DDL → aucune contrainte expand-contract.

## Partie 1 — Carte de source (`SourceDetailModal`)

- **1a — Priorité + Abonnement remontés quand la source est suivie.** Dans
  `_FsBody._assemble`, quand `display.isTrusted`, `_FsSettings` (priorité dans
  le flux) **et** `_FsManage` (connexion abonnement) passent juste sous
  `_FsEval`, avant la couverture / les derniers articles. Source non suivie :
  `_FsManage` reste le CTA de découverte (paywall) sous le contenu, `_FsSettings`
  masqué (gate `isTrusted` inchangé).
- **1b — « Lire plus » sur Derniers articles (3 → 10, sans requête réseau).**
  - Backend `sources.py:get_source_profile` : `recent_articles` limite `3 → 10`
    (additif, pas de rupture de contrat ; anciens clients prennent 3 via
    `.take(3)`). Docstring MAJ.
  - Mobile `_FsArticlesSection` → `StatefulWidget` : replié = `take(3)`, déplié =
    `take(10)`, bouton discret « Lire plus » / « Réduire » (idiome
    `_ExpandableDescription`) si `articles.length > 3`. Aucune requête : les 10
    articles sont déjà dans le payload profil.
  - Hors scope (noté) : mode smart-search (`_ArticlesContent`) et
    `recent_articles_list.dart` restent à 3 (autre chemin de préchargement).

## Partie 2 — Notifs inlines (« Notif du jour »)

- **2a — Cooldown durable au dismiss (~30j).** Nouveau store
  `notif_du_jour_dismissal_store.dart` (clé `notif_du_jour_dismissals_v1`, JSON
  `{ id: 'YYYY-MM-DD' }`, `kNotifDismissCooldownDays = 30`, clock injectable).
  `notifDuJourQueueProvider` filtre les `activeCooldownIds(now)` (même clé jour
  que le day store). Le cooldown se pose **au dismiss (croix) uniquement**
  (`_CloseButton` → `recordDismissed`), jamais au tap. Anti-flash : la carte
  gate désormais sur `day.loaded` **et** `dismissalStore.loaded`.
- **2b — « Mode serein » remonte.** Relevance `0.4 → 0.55` (au-dessus de
  `tournee` 0.5, sous les prompts temps-sensibles). Combiné au cooldown, serein
  émerge une fois les autres messages profil dismissés.
- **2c — Sondage « bien informé » non tronqué.** Titre `maxLines: 1 →
  hasCustomBody ? 2 : 1` (la question s'affiche en entier au-dessus de la
  rangée NPS ; une ligne, sans impact sur les autres messages).

## Tests

- Backend `test_source_profile.py` : happy path aligné (4 contents ≤ 10) +
  nouveau `test_profile_recent_articles_capped_at_10` (14 contents → 10).
  **7 passed** (`DATABASE_URL=postgresql+psycopg://facteur:facteur@localhost:54322/facteur_test`).
- Mobile : nouveau `notif_du_jour_dismissal_store_test.dart` (record + cooldown
  30j + expiration + date illisible) ; `notif_du_jour_provider_test.dart` étendu
  (id en cooldown filtré, cooldown expiré, serein remonte quand les autres sont
  en cooldown) ; `notif_du_jour_card_test.dart` (titre 2 lignes hasCustomBody,
  1 ligne standard) ; `source_detail_modal_test.dart` (ordre Priorité/Abonnement
  au-dessus des articles si suivie / paywall dessous si non suivie ; « Lire plus »
  déroule à 10 puis « Réduire » ; pas de bouton si ≤ 3). **76 passed.**
- `flutter analyze` sur les fichiers touchés : **No issues found.**

## Changelog

2 entrées `unreleased` : « Sources » (réglages en tête + Lire plus) + « Feed »
(notifs moins insistantes).
