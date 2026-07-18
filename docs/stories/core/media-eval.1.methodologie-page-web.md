# Story media-eval.1 — Page « Méthodologie » sur facteur.app + lien in-app

## Statut : Implémenté (en attente de review)

## Contexte

La méthodologie d'évaluation des médias (v1.3 : 3 axes / 10 critères / 100
points, notes A-E) devient une page publique du site facteur.app, convertie
depuis la maquette Claude Design « Méthodologie facteur.app v4.dc.html »
(projet `c0127361-ca33-4d08-9b7c-e3061b52de8f`).

## Décisions PO (validées)

- URL propre `https://facteur.app/methodologie` (règle nginx `location = /methodologie`).
- Formulaire « Rejoindre le comité de revue » branché sur `/api/waitlist`
  étendu (2 colonnes nullables `motivation` + `methode_complete`, migration
  Alembic additive `wl01`).
- Lien « Méthodologie » dans le footer **et** la nav de section de `index.html`.
- Le lien « Voir la méthodologie » de la modale source mobile devient tappable.

## Tasks

- [x] Landing : `apps/landing/public/methodologie.html` (page statique autonome,
      runtime design-canvas supprimé, fonts Google Fraunces / DM Sans / Courier
      Prime, Phosphor via CDN, logo `/favicon.png`, sans em-dash visible)
- [x] Landing : `apps/landing/public/js/methodologie.js?v=1` (scroll FX accordéon
      critères / étapes / axes + pin clic 2,5 s + formulaire comité idle/sending/ok/error)
- [x] Nginx : `location = /methodologie { try_files /methodologie.html =404; }`
      avant le `location /` générique
- [x] `index.html` : lien Méthodologie dans `footer__links` + nav de section
      (sans `data-section`, ignoré proprement par le scroll-spy)
- [x] Backend : colonnes `motivation` (Text) + `methode_complete` (Boolean)
      nullables sur `waitlist_entries` (modèle + schéma + service + router +
      properties PostHog `motivation_provided`/`methode_complete`)
- [x] Migration `wl01_waitlist_comite_fields` (additive, idempotente, chaînée
      sur `es01`, 1 seul head)
- [x] Service : sur doublon email, upsert de `motivation`/`methode_complete`
      sur la ligne existante (un inscrit waitlist peut rejoindre le comité)
- [x] Tests backend : `tests/routers/test_waitlist.py` (payload complet, payload
      legacy, doublon avec/sans champs comité)
- [x] Mobile : `LegalLinks.methodology` + « Voir la méthodologie » tappable
      (InkWell → url_launcher externe) dans `source_detail_modal.dart`
- [x] `assets/changelog.json` : entrée `unreleased` (+ réparation du JSON cassé à HEAD)

## Fichiers modifiés

- `apps/landing/public/methodologie.html` (nouveau)
- `apps/landing/public/js/methodologie.js` (nouveau)
- `apps/landing/nginx.conf.template`
- `apps/landing/public/index.html`
- `packages/api/app/models/waitlist.py`
- `packages/api/app/schemas/waitlist.py`
- `packages/api/app/services/waitlist_service.py`
- `packages/api/app/routers/waitlist.py`
- `packages/api/alembic/versions/wl01_waitlist_comite_fields.py` (nouveau)
- `packages/api/tests/routers/test_waitlist.py` (nouveau)
- `apps/mobile/lib/config/constants.dart`
- `apps/mobile/lib/features/sources/widgets/source_detail_modal.dart`
- `apps/mobile/assets/changelog.json`

## Hors périmètre

- Auto-hébergement des icônes Phosphor (CDN unpkg conservé).
- Mise à jour de `utm_campaign` sur doublon.
- Autres points d'entrée in-app vers la page.
