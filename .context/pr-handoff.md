# feat(mobile): « Notif du jour » — bandeau agrégateur quotidien en tête de l'Essentiel

## Quoi

Une **ligne de notification unique** en tête du feed Essentiel (sous le bandeau Lettres) : chaque jour, le Facteur met en avant une fonctionnalité peu vue, choisie selon le profil. Un seul message à la fois, **jusqu'à 3/jour** (le suivant après action ou dismiss), rotation quotidienne déterministe.

Story : `docs/stories/core/23.1.notif-du-jour.md`.

## Moteur

- **File** : `notifDuJourQueueProvider` trie les messages éligibles par `relevance(profil) + jitter(jour, id)` (ε = 0.15, hash FNV `id#jour` → stable intra-jour, permute inter-jour pour les pertinences proches uniquement).
- **9 messages** : 6 profil (serein, source, tournée, veille, premium, recommencer-fallback) + **3 nudges absorbés** (renudge notif 0.9, well-informed NPS 0.85 en rendu custom, géoloc 0.7) — leurs `*ShouldShowProvider` et caps existants sont réutilisés tels quels (avancés à la consommation).
- **Day store** : `notif_du_jour_state_v1` (SharedPreferences), `{day, consumed[]}`, reset à minuit, cap 3.
- **Rendu hifi** : surface, radius 14, ombre 0x14, carré icône 34 teinté (ocre/green/steel), DM Sans 13.5, CTA-lien + flèche, croix 30 ; repli AnimatedSize + fondu + translation 300ms, reduced-motion instantané, press scale + haptique.

## Dépréciations (PR 1)

- Supprimés : `NotificationRenudgeBanner`, `WellInformedPrompt`, `GeolocPromptBanner` (widgets standalone) + leurs 3 slivers du feed.
- `FirstImpressionSlot` réduit aux modales (`iosAddToHome`, `notifModal`) ; la carte cède aussi au bandeau Lettres (`lettresBannerVisibleThisSessionProvider`). Lettres → PR 3.

## Fix CTA (décision PO « taps propres »)

- Source → `RouteNames.addSource` (panneau d'ajout direct).
- Premium → `/settings/subscriptions?add=1` : `SubscriptionsScreen` auto-ouvre la feuille d'ajout.
- « Config » sorti de la rotation → tuile « Ma configuration » (barre de progression onboarding) dans `profile_screen.dart`.

## Tests

35 nouveaux (`test/features/notif_du_jour/`) : sélecteur (déterminisme, rotation bornée à ε, fallback), éligibilité par message, day store (reset minuit, cap, idempotence), widget (anti-flash, un-à-la-fois, X → persist + suivant, cap 3, reduced motion, tap Serein in-place, NPS custom, gates). Zones impactées : 446 verts (lettres, flux_continu, well_informed, notifications, settings).

Aucune migration / changement backend. Changelog `unreleased` ajouté (« Notif du jour »).

## Reste hors PR

- Validation on-device Android des demandes OS (renudge/géoloc) via la file.
- Calibration relevance/ε avec le PO ; PR 3 Lettres.
