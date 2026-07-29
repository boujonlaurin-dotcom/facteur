# feat(feedback): invitation « un café en visio » visible, humaine et actionnable (story 13.3)

Base `main`. **Aucune migration.**

L'invitation à un call qualitatif (Epic 13) ne convertissait pas : **jamais vue**,
**lien de booking mort**, ton froid, et une carte de clôture qui dépassait l'écran.
Cette PR la remet en état de marche.

## Ce qui n'allait pas (vérifié dans le code)

| # | Symptôme | Cause racine |
|---|---|---|
| 1 | Invitation jamais vue | Le teaser vivait dans la **toute dernière boîte de la page** (`ClosingCardV18.secondary`), sous le vote emoji et sous `DailyCompletionRecap`. Il fallait scroller jusqu'au bout **puis** taper pour révéler la modale. |
| 2 | 0 RDV pris | `ExternalLinks.calendlyUrl` était un placeholder jamais remplacé, avec son `TODO(laurin)`. Lien mort. |
| 3 | Ton froid | Avatar = `CircleAvatar('👋')`, copy signée « Laurin » seul, ask à « 15 min ». |
| 4 | Carte trop haute | La résolution de l'invite ajoutait Divider + teaser (~+90 px) dans une boîte déjà chargée → hors budget `section_fit`. |
| 5 | Deux boutons redondants | « 15 min, je suis curieux » et « J'ai un truc précis à te dire » appelaient **tous les deux** `_accept`. |
| 6 | Compteur d'affichages faussé | `markInviteShown()` partait au **build** de la carte de clôture : le cap `MAX_SHOWS=2` se consommait sur des affichages que personne n'avait vus. |

## Ce que fait la PR

**Placement (le vrai fix du #1).** L'invitation quitte la carte de clôture et
devient une entrée slim (`CallInviteEntry`) ancrée **2 sections avant la fin** de
la Tournée : `inviteTargetIndex = max(1, sections.length - 3)`, jamais sur le hero
Essentiel. Elle est rendue **dans le `KeyedSubtree` de sa section** (pattern de
`MyInterestsIntro`) : un sliver autonome serait orphelin entre deux ancres de snap.
Le micro-vote emoji, lui, reste en fin de Tournée (c'est une note *sur* la tournée).

**Auto-déploiement une fois.** À la première exposition **réellement visible**
(`VisibilityDetector` ≥ 50 %, pas au build), la modale s'ouvre seule, gardée par
`NudgeIds.feedbackCallAutoModal` (`frequency: once`). Ensuite, seule l'entrée
inline subsiste et le tap la rouvre. `markInviteShown()` migre sur cette même
garde de visibilité (fix #6).

**Modale humaine.** `FounderCollage` (nos deux vraies photos) + tampon
« TON AVIS COMPTE » + copy dans le ton « Nous soutenir », signée « Django &
Laurin, tes facteurs ». Ask ramené de 15 min à « un café en visio, 5 minutes ».
Toute la copy vit dans un `FeedbackCallCopy` unique (modèle `SoutienCopy`), zéro
em-dash. Titre unique tous segments, deux corps seulement (`active` vs
« Tu ouvres parfois Facteur » pour `low_active`/`returning`).

**Trois sorties nettes** (fin du #5) : « Prendre un café » (`accepted` + ouverture
du **vrai** lien Google Agenda), « Plus tard » (`declined`, snooze 21 j), et
**« On l'a déjà fait »** (`already_done`, nouveau statut terminal côté backend).
Après une sortie, `inviteStatusProvider` est invalidé : l'entrée disparaît tout de
suite au lieu de laisser traîner un CTA qu'on vient d'écarter.

**Carte de clôture compactée** (#4) : le départ de l'invitation libère ~125 px, et
le micro-vote est resserré (emoji 30 → 24, gaps et paddings réduits) pour ~45 px de
plus. `FeedbackClosingCard` redevient un `StatelessWidget` ; le tampon dupliqué
entre carte et modale est extrait en `FeedbackStamp`.

**Funnel analytics** (il n'y en avait aucun) : `feedback_invite_shown` /
`_opened` (origin `auto`|`tap`) / `_booked` / `_snoozed` / `_already_done`, avec
`segment`, en `_logEvent` + `_capturePostHog`.

## Backend

Nouvelle action terminale `already_done` dans `submit_invite_action`, ajoutée au
set des statuts terminaux de `get_invite_status`, autorisée par le pattern du
schéma. Gating inchangé (`classify_segment`, `SNOOZE_DAYS`, `MAX_SHOWS`) : le
problème n'était pas le gating.

**Aucune migration Alembic** : `FeedbackInvite.status` est un `String(20)` libre,
pas une enum PG. 1 head, inchangé.

## Vérification

- `pytest tests/test_feedback_router.py` → **22 passed** (2 tests ajoutés :
  `already_done` terminal côté GET et côté POST, sans snooze résiduel).
- Suite backend complète : 1996 passed. Le 1 failed + 554 errors sont tous des
  `OperationalError`/`InterfaceError` sur `localhost:54322` (DB de test locale
  éteinte), faux négatif documenté, aucun lié à cette story.
- `ruff check` / `ruff format` OK sur les 4 fichiers Python touchés.
- `flutter analyze` → **0 erreur**. `flutter test` → **1857 passed / 27 failed**,
  soit exactement la baseline pré-existante du repo. Run ciblé
  `feedback` + `flux_continu` + `soutien` → **496 passed**, aucun échec.
- 14 tests sur la feature, dont 4 nouveaux sur `CallInviteEntry` (non éligible =
  rien rendu ; entrée + `markInviteShown` sur visibilité ; auto-ouverture **une
  seule fois** ; tap rouvre).
- Passe `simplify` : `_trackFeedbackInvite` prend un `extra` (les 4 wrappers
  d'event redeviennent des one-liners) et les 3 sorties passent par un seul
  `trackFeedbackInviteAction(action)` piloté par la table
  action → event ; `TERMINAL_ACTIONS` / `TERMINAL_STATUSES` remplacent les
  tuples de statuts recopiés dans le routeur ; `entryCta` fusionné dans
  `ctaBook`. Tests re-passés après coup.

### Gotcha noté pour la suite

`addPostFrameCallback` posé **depuis** le callback de `VisibilityDetector` ne se
rejoue jamais (aucune frame supplémentaire n'est planifiée) : rien ne partait, y
compris en test. `Future.microtask` sort de la passe de rendu sans dépendre d'une
frame.

### Reste à faire avant merge

**Non joué faute d'environnement** (Docker indisponible sur la machine, donc pas
de DB de test locale sur `localhost:54322` ni d'API locale à interroger) :

- `uvicorn` + `curl` sur `POST /feedback/invite/action {"action":"already_done"}`
  puis `GET /feedback/invite`. Couvert en tests unitaires (2 tests dédiés), pas
  en bout-en-bout HTTP.
- Passe Playwright (`facteur-qa-web`, 390x844) : entrée visible sans scroller
  jusqu'au bout, auto-ouverture unique, photos rendues, ouverture du lien Google
  Agenda, carte de clôture sans overflow. Scénarios détaillés dans
  `.context/qa-handoff.md` → lancer `/validate-feature` depuis une machine avec
  Docker.

Story : `docs/stories/core/13.3.invitation-feedback-humaine.story.md`
