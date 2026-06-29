## Lettre du jour — timeline en overlay + ajustements PO (rewind page lettre, mode serein, simplification)

Finalisation de l'EPIC « Lettre du jour ». Deux blocs :

1. **Refonte timeline en overlay** : le **strip horizontal de pills** (permanent,
   au-dessus de l'Essentiel, dupliqué live + passé) est remplacé par un **bouton
   « rewind » compact** dans l'en-tête de la carte Essentiel, qui ouvre une
   **timeline en feuille du bas** avec un signal **lu / non-lu** honnête (réutilise
   la feature streaks, zéro back-end).
2. **4 ajustements PO** (avant ship) : simplification de la feature + rééquilibrage
   des points d'entrée + extension du rewind et d'un CTA serein à la page **Lettre
   du jour** (le rituel matinal), jusqu'ici dépourvue de ces affordances.

### Bloc 1 — timeline overlay

- **Nouveau** `widgets/edition_timeline_sheet.dart` : `EditionTimelineSheet.show`
  (calqué sur `manage_favorites_sheet`, scrim chaud, pas de `useRootNavigator`),
  `_DayRow` (icône + libellé + méta + pastille), `EditionRewindTrigger`.
- **Nouveau** `providers/edition_read_status_provider.dart` :
  `editionReadStatusProvider` (union streaks `opened` ∪ set local) +
  `editionCaughtUpProvider` (SharedPreferences, additif). Dégradation gracieuse :
  streaks off/loading/error ⇒ aucun statut affiché.
- **Modifié** `essentiel_hi_fi_card.dart` : `_Header` reçoit le déclencheur rewind.
- **Modifié** `flux_continu_screen.dart` : retrait des 2 strips ; `ref.listen`
  marquant un jour « rattrapé » quand une édition passée se charge ; action
  « Choisir un autre jour » dans l'état vide (anti-cul-de-sac).
- **Déplacé** `editionPillLabel` → `selected_edition_date_provider.dart`
  (co-localisé avec `EditionSelection`/`editionPillModel`).
- **Supprimé** `widgets/edition_date_strip.dart` (+ son test).

### Bloc 2 — ajustements PO

- **Point 1 — rewind réduit à 3 options** : `kEditionMaxPastDays` 7 → **1**
  (`selected_edition_date_provider.dart`). `editionPillModel()` ⇒
  `[Cette semaine, Aujourd'hui, Hier]` ; la timeline et le pill se réduisent
  automatiquement. **« Cette semaine » inchangé** (agrège toujours J-0…J-6 via la
  constante distincte `kEditionWeekPastDays`). **Aucun rollback back-end** : la
  garde « édition passée » de `digest_service.py` reste nécessaire (Hier + fan-out
  hebdo).
- **Point 2 — retrait du bouton « personnaliser » + grossir « GÉRER »** : le bouton
  perso de la carte Essentiel est **retiré partout** (today ET lettre passée). Point
  d'entrée préférences **unique** = l'inline « GÉRER » de `MyInterestsIntro`, rendu
  plus visible (libellé 11→13 px, fond accent doux au lieu d'un simple contour).
  Nettoyage : suppression du widget `_PersonalizeButton` + du param `onTapPersonalize`
  (`essentiel_hi_fi_card.dart`) et du param mort `interactive` (`section_block.dart`,
  call-site `flux_continu_screen.dart`).
- **Point 3 — rewind sur la page Lettre du jour (swipe horizontal riche)**
  (`morning_ritual_screen.dart`) : glisser la lettre du jour vers la **droite**
  révèle une carte « Hier » décorative parquée hors-écran gauche (liseré ~24 px au
  repos = nudge) ; commit (seuil 30 % ou fling) → sélectionne `EditionPastDay(hier)`
  + route vers le feed en lecture seule. Coexiste avec le swipe-up existant (arène de
  gestes H/V). Repli accessible : trigger « Remonter le temps » (ouvre la timeline).
  `reduceMotion` → carte statique.
- **Point 4 — CTA « mode serein »** : `_SereinCta` (ConsumerWidget privé) sous le
  bloc rewind, copie « Pas d'humeur pour les news difficiles ? » + bouton « Active ton
  mode serein » → `sereinToggleProvider.toggle()` (persiste + haptique) + snackbar de
  confirmation ; désactivé tant que `state.isLoading`.

### Tests
- `flutter analyze` : **0 issue** sur les fichiers touchés.
- MAJ/nouveaux : `selected_edition_date_provider_test` (pills 9→3),
  `edition_timeline_sheet_test` (3 lignes), `essentiel_hi_fi_card_test` (bouton perso
  retiré), `morning_ritual_content_test` (ProviderScope + serein CTA + trigger),
  `edition_read_status_provider_test` (fixtures découplées de `kEditionMaxPastDays`).
- Suite `test/features/flux_continu/` : **354 verts, 1 échec pré-existant et non lié**
  (`flux_continu_provider_test` « 10 favorites cap » — cap déjà bumpé à 13 en amont).

### Validation web (Playwright)
- QA handoff prêt (`.context/qa-handoff.md`) pour `/validate-feature` (4 scénarios PO :
  timeline 3 options, carte sans bouton perso + « GÉRER » plus grand, page Lettre du
  jour rewind, CTA serein). **Le swipe horizontal de la page Lettre du jour est validé
  par `flutter analyze` + Playwright** (pas de test widget plein-écran : le rituel monte
  des providers réseau/streak/profil ; le geste reprend le pattern éprouvé du swipe-up,
  lui-même couvert au niveau `MorningRitualContent` + QA, non par un test d'écran).

### Risque / migration
- **Aucun** changement back-end, **aucune** migration Alembic.

### Hors scope (suivi)
- Audit « santé des streaks » (frontière de jour / sémantique `opened`) :
  `.context/streaks-health-handoff.md` (read-only, ne bloque pas cette PR).
