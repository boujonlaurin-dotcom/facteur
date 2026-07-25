# Epic 30 — La lecture aboutie

> **Type** : Feature · **Cible** : `main` · **Statut** : **CODE+TEST — lots 0 à 3 implémentés**
> **Date** : 24/07/2026 · **Méthode** : ronde 1 de design BMAD (UX / PM / Architecte), arbitrée sur données prod

---

## 1. La demande

> « Rendre plus satisfaisante la lecture d'un article jusqu'au bout : coche verte dans l'article, carte
> légèrement verte dans le feed. Réutiliser le système de notifs in-app pour un mini-objectif journalier
> (lire 5 articles jusqu'au bout), tagline "Moins d'info, plus de compréhension", qui renforcerait les
> flammes journalières (double flamme ?). Sans alourdir l'expérience calme. »

## 2. Ce que l'analyse a changé — 5 faits qui commandent le plan

### F1 — Le moment de fin d'article existe déjà. Il n'est ni récompensé, ni enregistré.

`content_detail_screen.dart:2194` — `_footerPermanent` bascule à 98 % du scroll et déclenche **déjà**
`HapticFeedback.selectionClick()` + un pulse de scale 280 ms. Le CTA passe alors en **ocre `#D35400`**
(`colors.primary`), alors que le vert `colors.success` est la convention « lu » sur toutes les cartes.
`grep colors.success` dans le reader → **0 occurrence**. C'est le seul écran qui ne suit pas la convention
du produit.

### F2 — `reading_progress` ne mesure pas la lecture. Il mesure le type d'article.

Deux calculs cohabitent sur des dénominateurs différents (`:2185-2210`) :

```dart
final rawProgress = metrics.pixels / metrics.maxScrollExtent;   // scroll ENTIER (article + perspectives)
if (!_footerPermanent.value && !_ctaTapped && rawProgress >= 0.98) { _footerPermanent.value = true; }

final barProgress = metrics.pixels / articleExtent;             // extent ARTICLE seul
final capped = _isPartialContent ? (barProgress * 0.25).clamp(0.0, 0.25) : barProgress.clamp(0.0, 1.0);
_maxReadingProgress = max(_maxReadingProgress, capped);         // ← seule valeur persistée
```

Distribution réelle en base (30 j, `consumed`, progress > 0) :

| valeur | occurrences | ce que c'est |
|---|---|---|
| **exactement 25** | **272** (~36 %) | valeur **sentinelle** du plafond `_isPartialContent` |
| exactement 100 | 53 | 53 des 65 lignes ≥ 90 |
| tout le reste | traîne diffuse | max 11 occurrences par valeur |

Et `isPartialContent` (`html_utils.dart:159-164`) déclenche sous 500 caractères :
**26 383 / 29 358 contenus publiés sur 14 j = 89,9 % du catalogue.**

⇒ **`reading_progress ≥ 90` est inatteignable pour ~90 % des articles, quel que soit le comportement réel.**
Conséquence directe déjà en prod : un utilisateur qui lit **intégralement** un article partiel est étiqueté
**« Parcouru »** (`content_model.dart:209-228`, il est à 25). *On démotive activement le comportement qu'on
veut encourager.*

### F3 — L'objectif « 5 » est mathématiquement hors d'atteinte

Sur 270 jours-utilisateur actifs (30 j) : **3,95 articles ouverts** par jour actif. Taux de finition estimé
~32 %. Atteindre 5 fins/jour demanderait **~16 ouvertures/jour**, soit ×4 le volume actuel — dans une app
dont la promesse est « moins d'info ».

Recalibré sur un signal honnête (les 272 + les 65) : **≈ 1,2 fin de lecture par jour actif.**
Temps médian par article : **20 s**.

### F4 — La « double flamme » afficherait zéro

`closure_streak` est calculé et stocké mais **jamais affiché** — et il est **quasi vide** :
**14 utilisateurs sur 121** l'ont jamais eu > 0 (moyenne 0,16, max 4).
La flamme actuelle, elle, ne récompense que **`session_start`** — ouvrir l'app, aucune lecture — et n'a
**aucun palier, aucun message, aucune récompense**. Les seuls paliers du repo (1/7/30) dorment dans
`digest_service.py:2958-2967` sans jamais remonter en UI.

### F5 — La lecture d'article est invisible dans l'analytics

`article_read` / `article_completed` : **0 événement sur 30 jours**, ni dans PostHog ni dans la table backend
`analytics_events` — alors que `perspectives_opened` (1139 évts / 42 users) part du même écran.

Deux causes cumulées, la seconde certaine :
1. L'unique point d'émission est dans `dispose()` (`content_detail_screen.dart:1701-1703`), dans un
   `try/catch` fourre-tout qui `debugPrint` et avale tout (`:1682-1707`). *Ce bug a déjà été corrigé une fois
   dans ce fichier* — commit `81c6a505` (PR #413, « ref.read() after dispose »).
2. **`article_completed` n'est émis que si `timeSpentSeconds >= 30`** (`analytics_service.dart:244`), alors
   que la médiane est de 20 s. Même pipeline réparé, l'événement sous-compterait — et définirait « terminé »
   par une durée, ce qui contredit la définition produit qu'on construit.

**Aucun chiffrage d'objectif ne peut être arrêté avant ce fix + 2 semaines de collecte.**
Le nombre est une **sortie** du lot 0, pas une entrée de la spec.

---

## 3. Le plan — 5 lots

| Lot | Contenu | Backend | Mobile | Migration | Statut |
|---|---|---|---|---|---|
| **0** | Rendre le succès mesurable | ✅ | ✅ | ❌ | ✅ fait |
| **1** | Le contrat de données | ✅ | ✅ | ✅ *(la seule)* | ✅ fait |
| **2** | L'état visuel — **la demande initiale** | ❌ | ✅ | ❌ | ✅ fait |
| **3** | L'objectif du jour | ✅ lecture | ✅ | ❌ | ✅ fait |
| **4** | Flamme — anneau des jours refermés | ❌ | ✅ | ❌ | ✅ fait (replié dans le lot 3) |

> **Déploiement du schéma.** Contrairement à ce qu'indiquait la ronde 1 d'architecture,
> **aucun SQL manuel n'est à passer dans le Supabase SQL Editor** : `CLAUDE.md` en fait
> explicitement l'anti-pattern à l'origine du drift d'avril 2026. Le `Dockerfile`
> (`packages/api/Dockerfile:40`) joue `alembic upgrade head` au boot de chaque conteneur
> Railway — la migration `rd01_ucs_completed_at` s'applique donc **seule** au déploiement.
>
> **Expand-contract respecté** : la migration est purement additive (2 colonnes nullables
> + 1 index partiel), donc inoffensive pour le backend `production` qui tourne sur la même
> DB partagée avec l'ancien code jusqu'à une semaine. `user_content_status` fait 5 059
> lignes / 2 Mo : la création d'index est instantanée, pas besoin de `CONCURRENTLY`.

### Lot 0 — Rendre le succès mesurable  *(prérequis absolu, réversible, sans schéma)*

1. Sortir l'analytics de `dispose()` : résoudre le service **une fois** en `initState`
   (`late final AnalyticsService _analytics;`), plus aucun `ref.read` dans `dispose()`.
2. Émettre `article_completed` **au moment de l'événement**, pas à la fermeture — et **découpler du seuil
   30 s** (`analytics_service.dart:244`).
3. Remplacer le `catch` muet (`:1705`) par une remontée Sentry. *Un chemin de récompense ne doit jamais
   échouer en silence.*
4. **Corriger le bug de frontière de `closure_streak`** : `_update_closure_streak` estampille
   `last_closure_date = date.today()` (UTC serveur, `digest_service.py:2933`) alors que son déclencheur
   `maybe_record_implicit_completion` teste `today_paris()` (`:1573`). Entre 00h et 02h Paris l'été, la
   complétion est comptée pour J et datée J-1 → série cassée ou dédoublée.
   **Prérequis à toute exposition de `closure_streak`.**
5. Introduire le helper canonique `editorial_day()` dans `app/utils/time.py` (bascule **07h30 Europe/Paris**,
   miroir exact de `TourneeProgressService.dayKey:50-58`).

**Instrumentation à créer — `article_finished`**, avec les propriétés qui évitent de refaire l'erreur du
bucket ≥90 : `is_partial`, `render_mode`, `completion_source`, `reached_footer_permanent`, `progress_raw`,
`time_spent_seconds`, `scrollable` *(désambiguïse enfin le bucket 0 : rebond vs article court lu en entier)*,
`article_char_count`.

**Sortie attendue** : la distribution réelle des fins de lecture par jour-utilisateur (P50 / P75 / P90).
**C'est elle qui fixe le chiffre du lot 3.**

### Lot 1 — Le contrat de données  *(additif pur, aucun backfill)*

```
user_content_status.completed_at      timestamptz NULL   -- horodaté SERVEUR, first-write-wins
user_content_status.completion_source varchar(12) NULL   -- 'in_app' | 'short' | 'web'
```

> **Sémantique retenue** : `completed_at` = « l'utilisateur a atteint le bas de ce que Facteur lui a
> présenté ». `completion_source` conserve **gratuitement** le signal strict « lu chez l'éditeur ».

| source | cas | détection | part du catalogue |
|---|---|---|---|
| `in_app` | contenu complet | bas de l'extent article | ~10 % |
| `short` | article non scrollable | latch `_checkShortArticle` (`:927-942`) | — |
| `web` | article partiel lu chez l'éditeur | pont JS, progress normalisé ≥ 0,98 | ~90 % |

**Pourquoi pas un état `completed` dans l'enum `ContentStatus`** — c'est le risque le plus sérieux du dossier :
l'exclusion des contenus vus s'écrit `status.in_([SEEN, CONSUMED])` dans `recommendation_service.py:2727-2745`
et `digest_selector.py:833-843`. Un statut `completed` ne matcherait **ni l'un ni l'autre** → *les articles lus
jusqu'au bout reviendraient dans le feed*. Pire : la garde d'idempotence
(`ON CONFLICT ... WHERE status != 'consumed'`, `content_service.py:121-138`) laisserait repasser une ligne
`completed` et re-déclencherait `increment_consumption` + `_adjust_interest_weight` +
`maybe_record_implicit_completion`. Double comptage silencieux.

**Effets de bord reco : nuls.** `completed_at` est orthogonal à `status` ; les deux filtres ne le voient pas.
`completed` **n'implique jamais** `consumed` → le seuil de complétion implicite du digest (80 %) et donc
`closure_streak` restent strictement inchangés.

Idempotence : `completed_at = COALESCE(completed_at, now())` — premier écrit gagne, monotone, exactement
l'idiome déjà en place pour `reading_progress` (`func.greatest`, `content_service.py:102-113`).
Le client n'envoie **jamais** d'horodatage.

**Migration** : head unique vérifié `181c618da382` → `rd01_ucs_completed_at`
(`down_revision = "181c618da382"`). `alembic upgrade head` validé localement contre une base
**vide**, un seul head après ajout. Appliquée automatiquement au boot Railway.

**Mobile** : `_articleCompleted` (`ValueNotifier<bool>` frère de `_footerPermanent`), 3 latches
(`:2194-2199` / `:927-942` / `:857-865`), durabilité offline via `PendingReadQueue` avec un préfixe de clé
`done:` — **aucune migration Hive**.

> ⚠️ Le latch vit dans le `NotificationListener` appelé sur **chaque frame de scroll** (`:2168-2221`) :
> `if (_articleCompleted.value) return;` en tête, sans allocation ni `setState`.

`reading_progress` : **ni réparé, ni supprimé — gelé et démoté.** En changer la formule créerait un historique
à sémantique mixte, indistinguable a posteriori. L'UI bascule sur `completed_at`.

### Lot 2 — L'état visuel  *(mobile only — c'est la demande initiale, livrable seul)*

**Dans l'article** — un **cachet**, pas une coche. La `checkCircle` est déjà le vocabulaire du « Lu »
déclenché **au bout d'1 seconde** (`articleReadThreshold`, `read_sync_service.dart:16`) : la réutiliser
importerait sa dévaluation.

Le cachet est un composant **qui existe déjà à l'identique deux fois** dans le produit
(`closing_card_v18.dart:107-127` « FIN DE TOURNÉE », `feedback_closing_card.dart:70-73` « TON AVIS COMPTE ») :
`Transform.rotate(-2°)` + bordure 1.5 px + Courier Prime 10 / w700 / letterSpacing 2.0, fond transparent.

```
┌──────────────────────┐   -2°, bordure + texte #2E7D32
│ ✓✓ LU JUSQU'AU BOUT  │   Courier Prime 10 / w700 / ls 2.0
└──────────────────────┘   PhosphorIcons.checks(bold) 11px
```

> ⚠️ Les deux cachets existants utilisent **`#2E7D32` en dur** (`sectionBonnes`), pas `colors.success`
> (`#27AE60`). Reprendre `#2E7D32` pour la cohérence.

Placement mode in-app : **dans le flux**, sous le dernier paragraphe, au-dessus des perspectives
(`EdgeInsets.only(left: 16, top: 24, bottom: 8)`). Pas d'overlay — il reste là, et si l'utilisateur re-scrolle
il y est encore. Mode WebView (impossible d'injecter dans un DOM tiers) : même cachet flottant 12 px au-dessus
de la `GlassPill`, **auto-effacé après 2400 ms**.

**Chronologie exacte :**

| t | événement |
|---|---|
| 0 ms | `HapticFeedback.lightImpact()` — un atterrissage, pas un tick. Jamais `medium`/`heavyImpact`. |
| 0 → 400 ms | barre de progression : cross-fade ocre → vert, `easeOut` |
| 80 → 380 ms | cachet : opacity 0→1 + translateY +6→0, 300 ms `easeOutCubic` |
| 800 → 1050 ms | retrait de la barre (opacity 1→0, 250 ms) — l'instrument de mesure se retire une fois la mesure faite |
| 1050 ms | **fin.** Pas de toast, pas de modale, pas de son. |

Anti-double-buzz : sur contenu complet, `_footerPermanent` et `_articleCompleted` tombent dans la même frame
→ le second absorbe l'haptique.
Ré-ouverture d'un article déjà terminé : cachet présent **dès la première frame**, sans animation ni haptique
(c'est un *état*, pas un événement).
Reduce-motion : cachet à opacité pleine sans translate, **haptique conservée** (c'est le canal accessible).

**Dans le feed** — pas de teinte de fond. Sur crème `#F2E8D5`, un vert à 4 % est sous le seuil de perception ;
à 8 % il vire **kaki** et détruit la sensation papier. À la place, un **filet vertical 3 px** sur le bord gauche
(idiome du filet de journal, déjà présent dans le produit) + l'icône `checks` 13 px en fin de ligne méta,
sans fond ni ombre. Fréquence attendue : ~1 carte sur 16 → une distinction, pas un motif.

**Unification** : un seul widget `ReadStateMark` pour `FluxContinuArticleCard`, `EssentielHiFiCard`, `FeedCard`.
*(`_ReadCheckBadge` est aujourd'hui **dupliqué** entre les deux premiers — occasion de factoriser.)*

**Retraits** (le vrai travail) :
- `_ReadCheckBadge` — le cercle vert plein déclenché après **1 seconde**. C'est ce qui a dévalué le vert.
- le rendu **pill** de `ReadingBadge` (rectangle vert saturé + texte blanc bold + drop shadow) — sa logique
  graduée est conservée, son rendu disparaît.
- le libellé **« Parcouru »** + icône `eye` : ne pas renvoyer à l'utilisateur un commentaire sur sa lecture
  superficielle. L'opacité suffit.

**Réhabilitation** : `AnimatedFeedCard` (174 l.) est **du code mort — 0 référence dans `lib/` et `test/`**,
alors que c'est littéralement « la carte verte à la sortie » demandée (overlay déclenché sur la transition
`isConsumed` false→true, `:74-83`). Le monter, branché sur `completed`, **restylé** : sa pill est en
`grey.shade700` (contredit la convention verte), son scrim est noir à 60 %, sa courbe est `elasticOut`
(vocabulaire de jeu, pas celui du produit) et il dure 1000 ms. → filet + `checks`, `easeOutCubic`, 320 ms,
sans scrim. **Pas d'haptique** : elle a déjà eu lieu dans l'article. Un événement, une vibration.

Corriger au passage 3 incohérences déjà présentes : seuil vidéo `>= 25` (`readingLabel`) vs `>= 30`
(`ReadingBadge`) ; commentaire « 30s timer » (`content_model.dart:225`) alors que le seuil réel est 1 s ;
un `consumed` à 10 % affiche « Parcouru » sur fond **vert** (branches désaccordées, `reading_badge.dart:32-48`).

**Piège de cache identifié** : `FluxContinuCacheService.patchContentStatus:147-149` **n'écrit une clé que si
elle existe déjà** dans le payload — un champ neuf serait **silencieusement ignoré**. À traiter explicitement.

### Lot 3 — L'objectif du jour  *(conditionnel — gate ci-dessous)*

**Le compteur est dérivé, jamais stocké.** Aucune colonne `daily_count` / `daily_count_date`, aucun job de
reset, aucune dérive :

```sql
SELECT count(*) FROM user_content_status
WHERE user_id = :uid AND completed_at >= :day_start AND completed_at < :day_end;
```

C'est exactement le motif stateful qui a produit `weekly_count` + `week_start` et ses bugs de frontière
qu'on évite ici.

Exposé via `StreakResponse` (`schemas/streak.py:8`) → `daily_completed` + `daily_goal`, servie par
`GET /api/streaks` **et** `GET /api/users/streak`, déjà consommée par `streakProvider` au démarrage.
**Zéro nouvelle plomberie mobile.** `daily_goal` = **constante serveur** → recalibrable **sans release client**.

**Frontière de jour : 07h30 Europe/Paris** (celle des éditions et du rituel). L'objectif est un objet
*éditorial*, pas calendaire : à minuit, un lecteur de 00h30 verrait son objectif repartir à zéro alors qu'il
lit encore l'édition de la veille. **Ne pas le brancher sur `current_streak`** (frontière minuit-device) :
les coupler créerait un décalage visible d'un jour pendant ~7h30 chaque nuit.

*(Il y a en réalité **quatre** frontières dans le repo : minuit device, minuit UTC, minuit Paris, 07h30 Paris.)*

**Véhicule : la carte de clôture, pas la Notif du jour.** Unanimité des trois experts. La Notif du jour est un
système de *messages ponctuels*, pas de compteur : slot unique en concurrence avec 9 messages scorés,
**consommé au tap**, **cooldown 30 jours à la croix** (un dismiss accidentel tue la feature un mois), cap
3/jour, frontière minuit local. Et surtout elle est en **tête** de l'Essentiel — **avant** la lecture :
*un objectif montré avant l'effort est une demande.*

`ClosingCardV18` a un slot `secondary` explicitement documenté (`:42-46`), elle est **après** la lecture, elle
porte déjà « Tu es à jour » et le tampon « FIN DE TOURNÉE ». C'est le moment de fermeture du PRD (FR21.2).

**Réhabilitation** : `closing_recap.dart` (99 l.) est mort en `lib/` mais **couvert par 200 lignes de tests
verts** — `buildClosingRecap` compte déjà les articles lus par section et `formatClosingRecap` produit
« Tu as lu sur la Tech (4) et la Politique (2). ». C'est le foyer naturel de l'objectif du jour.

**Le rendu : une phrase, pas une jauge.** Pas de barre, pas d'anneau, pas de « 2/2 », pas de cases à remplir
(deux cases à remplir *sont* une jauge) :

- **objectif atteint** → cachet `LU JUSQU'AU BOUT` + « Deux articles lus jusqu'au bout aujourd'hui. » +
  tagline. Aucun CTA.
- **1 seule lecture aboutie** → « Un article lu jusqu'au bout aujourd'hui. » **Aucun « plus qu'un ! »,
  aucun « 1/2 ».**
- **0 lecture aboutie** → **le bloc ne s'affiche pas.** La carte de clôture reste ce qu'elle est aujourd'hui.

> C'est la réponse au cas majoritaire : **il n'y a pas d'objectif raté, parce que l'objectif n'est jamais
> affiché comme cible** — seulement, rétrospectivement, comme accomplissement.
> On ne peut pas rater un objectif qu'on ne nous a jamais montré.

**Où vit le chiffre, alors ?** Un seul endroit : le bottom sheet explicatif de la flamme
(`streak_explainer_modal.dart`, qui a déjà 3 slots de métriques + un calendrier 14 j alimenté par
`GET /api/streaks/activity`, **déjà disponible et inutilisé**). L'utilisateur y va volontairement.
Règle consultée sur consentement, jamais poussée.

**La Notif du jour garde un rôle** : la tagline de **découverte**, **une seule fois**
(`notif_du_jour_message.dart` + candidat à relevance ~0.65). C'est exactement son usage prévu, et c'est trivial.

**Taglines** — ton affirmatif (proche de « Tu es à jour » / « FIN DE TOURNÉE »), tutoiement, présent, aucun
emoji, aucun point d'exclamation :

1. **« Moins d'info, plus de compréhension. »** *(la référence, à pondérer le plus fort)*
2. **« Tu n'as pas tout lu. Tu as bien lu. »** ⭐ *(autorise explicitement la finitude)*
3. « Lire jusqu'au bout, c'est déjà comprendre. »
4. « Deux articles, lus en entier. C'est une bonne journée. »
5. « Ce que tu retiendras demain, c'est ça. »
6. « Le reste attendra. Ça, tu le sais maintenant. »
7. « Une lecture finie vaut mieux qu'une pile commencée. »
8. « Rien de plus à lire aujourd'hui. C'est le principe. »

⚠️ **À écarter** : toute formulation comparative type « deux articles lus valent mieux que vingt survolés ».
Le survol est le comportement de ~94 % des ouvertures — cette phrase fait honte à l'utilisateur médian.

Rotation : le jitter FNV-1a déterministe de `notif_du_jour_provider.dart:48-58` est réutilisable tel quel,
sans le système de cap/cooldown.

### Lot 4 — Flamme  *(conditionnel)*

**Double flamme : coupée.** L'actif sous-jacent est vide (14/121 users), et surtout : **deux séries = deux
façons d'échouer par jour**, dans un plan dont tout l'objet est de réduire le nombre de verdicts quotidiens.
Contrainte de place également : le header (`main_shell.dart:157`) est un `Stack` avec logo centré ~90 pt ;
deux indicateurs ≈ 120 pt entrent en collision avec le logo dès 390 pt de large.

**À la place — flamme unique, enrichie, en additif seulement :**
- Le chiffre reste `current_streak`. **Personne ne perd rien.** *(Basculer sur `closure_streak` ferait chuter
  un bêta-testeur de 40 jours à 3 : la pire journée possible pour la confiance.)*
- Un **anneau fin `#2E7D32` 1.5 px** autour du badge 29×29, présent le reste de la journée une fois la journée
  refermée. Il ne dépend **pas** de `closure_streak` : c'est un état du jour, il fonctionne dès le jour 1.
- Le **pulse quotidien existant** (900 ms, scale 1.0→1.22, déjà codé) **est déplacé** : il se déclenche à la
  clôture, plus à l'ouverture de l'app. Même animation, meilleur déclencheur.
- **Jamais d'état négatif permanent.** Pas de flamme désaturée tant que la journée n'est pas close — ce serait
  un signal de déficit affiché tous les matins.

`closure_streak` et ses paliers 1/7/30 s'expriment dans le bottom sheet explicatif, pas dans le header.

---

## 4. Garde-fous « expérience calme » — ce qu'on refuse explicitement

| # | Refus | Raison |
|---|---|---|
| 1 | Aucune **push de rappel de série** | Le pattern le plus anxiogène de la catégorie. La seule push du produit reste la livraison du matin. |
| 2 | Aucun **badge rouge / pastille de compteur** | L'état de lecture n'est pas un état d'erreur. |
| 3 | Aucun **compte à rebours**, aucune heure limite | — |
| 4 | Aucun **affichage d'objectif non atteint** | 0 lecture → le bloc ne se rend pas. Pas de « 0/2 », pas de case vide, pas de placeholder gris. |
| 5 | Aucune **interruption modale** en fin d'article | Plafond : 380 ms de feedback dans le flux. L'article se termine ; il ne te félicite pas. |
| 6 | Aucun **son** | — |
| 7 | Aucune **escalade intra-session** | Le 2ᵉ article terminé reçoit exactement le même feedback que le 1ᵉʳ. Pas de combo. |
| 8 | Aucun **confetti / `elasticOut` / Lottie** sur la lecture | Vocabulaire de jeu. Celui du produit est le papier, le tampon, `easeOutCubic`. |
| 9 | Aucun **second compteur** dans le header | Cf. lot 4. |
| 10 | Aucune **comparaison sociale**, classement, moyenne | — |
| 11 | Aucun **« streak freeze » / « répare ta série »** | Boucle de culpabilité monétisable, et présuppose que la perte compte. |
| 12 | Aucun **double haptique** pour un même événement (article → feed) | Un événement, une vibration. `lightImpact` maximum. |
| 13 | Ne rien exposer qui dépende d'une **métrique cassée** | Rien de visible adossé à `article_completed` avant le lot 0. |
| 14 | **`gamification_enabled` doit devenir un vrai interrupteur en réglages, dans la même release** | Le flag existe (défaut `true`) **sans aucune UI**. Si on ajoute de la surface objectif/série, l'opt-out doit exister au même moment. **Gate dur.** |

Découpage du gate `gamification_enabled` : l'objectif journalier et la flamme sont **gatés** (c'est de la
gamification) ; le cachet et la marque sur les cartes ne le sont **pas** (c'est un affordance d'état de lecture).

---

## 5. Mesure

> ⚠️ **Avec 22 utilisateurs à ≥5 jours actifs, aucun A/B test n'a de puissance statistique.** On lit des
> tendances sur cohorte avant/après (≥14 j) + du qualitatif (3-5 entretiens, mini-NPS `well_informed` déjà
> en place).

| Lot | Primaire | Contre-métriques (rollback si franchies) |
|---|---|---|
| **0** | `article_finished` remonte pour ≥70 % des actifs ; distribution P50/P75/P90 établie | — |
| **2** | part des articles ouverts qui se terminent (baseline ~32 %) | temps médian **ne descend pas sous 18 s** (baseline 20) ; part des fins en < 10 s ≤ **15 %** ; articles ouverts/jour **ne dépasse pas ~6** (baseline 3,95) — au-delà, on a fabriqué du volume, l'inverse de la promesse ; crash-free ≥ niveau actuel |
| **3** | part des jours actifs où l'objectif est atteint — cible **45-60 %**. < 40 % → on baisse. > 80 % → décoratif, on supprime | durée de session **ne monte pas** ; nb de sessions/jour stable ; taux de dismiss de la carte de clôture stable |
| **4** | `closure_streak > 0` chez ≥40 % des users à ≥3 jours actifs | — |

**Gate lot 2 → lot 3** : ≥14 jours de données propres et distribution réelle connue.
**Gate lot 3 → lot 4** : `closure_streak > 0` chez ≥40 % des users à ≥3 jours actifs. *Si le seuil n'est pas
atteint, le lot 4 est annulé.*

---

## 6. Ce que je coupe de la demande initiale

| Coupé | Raison |
|---|---|
| **Objectif « 5 articles jusqu'au bout »** | Plafond dur à 3,95 ouvertures/jour actif ; demanderait ×4 le volume, dans une app anti-volume. Provisoirement **2**, mais le chiffre est une **sortie** du lot 0. |
| **Double flamme** | Actif vide (14/121), et deux séries = deux façons d'échouer par jour. Remplacée par un anneau sur la flamme unique. |
| **Objectif dans la file « Notif du jour »** | Cooldown 30 j à la croix, consommation au tap, cap 3/jour, position **avant** la lecture. La notif garde la tagline de découverte one-shot. |
| **Carte « légèrement verte »** | Vert + crème = kaki ; et teinte + opacité + badge = 3 signaux pour un état. Remplacée par un filet 3 px. |
| **Tagline « compréhension » sur un compteur d'articles** | C'est une promesse de **journée**, pas d'article — surtout sur 90 % de teasers. Elle reste au niveau de la carte de clôture. |

---

## 7. Les 4 décisions qui te reviennent

1. **Le CTA de fin d'article devient-il vert ?** *(ton idée d'origine)* — Recommandation : **non pour le
   bouton, oui pour la zone.** Le CTA reste ocre (c'est une **action** : « Lire sur Le Monde » ; un bouton vert
   dirait « fais ceci » dans la couleur qui dit « c'est fait » partout ailleurs, et validerait le *site* plutôt
   que la lecture). Le **footer change bien de couleur** — via le cachet vert + la barre de progression qui
   vire au vert. Alternative si tu préfères : CTA vert uniquement sur `_articleCompleted` (2 lignes de diff).
2. **Inverse-t-on l'opacité des cartes lues ?** *(le point le plus risqué)* — Aujourd'hui finir un article
   fait **pâlir** la carte à 0.6 : le produit dit « ceci compte moins maintenant ». Proposition : terminé →
   **retour à 1.0** + marque ; simplement parcouru → 0.72. Contre-argument : le grisé aide aussi à repérer le
   non-lu dans le feed. **Ton appel.**
3. **Sémantique de `completed_at`** = « bas de ce que Facteur affiche » (marche pour les 90 % de teasers),
   `completion_source='web'` conservant gratuitement le signal strict « lu chez l'éditeur ».
   **Irréversible sans migration.**
4. **Périmètre du GO** : lots 0+1+2 seuls (la demande visuelle, livrable et mesurable), ou 0+1+2+3 d'emblée ?
   Recommandation : **0+1+2**, puis on calibre le chiffre sur données réelles.

---

## 8. Divergences entre experts, tranchées

| Sujet | UX (Sally) | PM (John) | Archi (Winston) | Arbitrage |
|---|---|---|---|---|
| CTA vert | non — collision sémantique | oui | oui | **non pour le bouton, vert sur la zone** (décision 1) |
| `AnimatedFeedCard` | à supprimer | — | à réhabiliter | **réhabiliter restylé** — vérifié : 0 référence, c'est du code mort, pas du code vivant à retirer |
| Objectif : chiffre | 2 | mesuré, gaté | ~1,2/jour observé | **2 provisoire, arrêté après le lot 0** |
| Double flamme | non | non | lot 4 possible | **coupée**, anneau à la place |
| Gradation du badge | 2 états | 3 barreaux honnêtes | `completed_at` binaire | **2 états visuels**, les 3 barreaux vivent dans la donnée |

**Corrections apportées aux experts :** le PM annonçait « 66 % des utilisateurs n'ouvrent l'app qu'un jour »
(source `Application Opened`, 80 users, **onboarding inclus**). Sur la population **authentifiée**
(`session_start`, 56 users) : **32 %** à un seul jour, **22** à ≥5 jours, **7,36** jours actifs en moyenne
sur 30. Les deux sont vrais mais l'écart mesure l'**activation**, pas la rétention de la lecture — sa
conclusion « ne pas optimiser pour les réguliers » s'en trouve affaiblie.

---

## 9. Références vérifiées

`content_detail_screen.dart` : `:245` `_footerPermanent` · `:927-942` article court · `:857-865`
`_applyWebReadingProgress` · `:947-952` effets · `:1682-1707` `dispose()` · `:2168-2221` scroll listener ·
`:2558-2566` `usePrimary`
`html_utils.dart:159-164` · `read_sync_service.dart:16,29-89,122-124,205-237` ·
`content_model.dart:209-228` · `reading_badge.dart:32-48` · `animated_feed_card.dart` *(mort)* ·
`closing_recap.dart` *(mort, testé)* · `closing_card_v18.dart:42-46,107-127` ·
`flux_continu_cache_service.dart:147-149` · `main_shell.dart:157` · `streak_indicator.dart` ·
`notif_du_jour_*` · `content_service.py:74-187` · `digest_service.py:1573,2917-2973` ·
`recommendation_service.py:2727-2745` · `digest_selector.py:833-843` · `streak_service.py:40-97` ·
`schemas/streak.py:8` · alembic head `181c618da382` (1 seul head, 44 révisions)

---

## 10. Journal d'implémentation (24/07/2026)

### Décisions du PO au GO

1. **Footer tout en vert**, et le CTA « Lire sur … » descend en **`colors.secondary`** — l'état prend
   la couleur, l'action se retire. *(Arbitrage retenu contre la ronde 1 UX, qui voulait garder l'ocre.)*
2. **Pas d'inversion d'opacité** : les cartes lues restent à `Opacity(0.6)`. Le grisé garde sa fonction
   de repérage du non-lu.
3. Sémantique `completed_at` = « bas de ce que Facteur affiche » : **validée**.
4. Périmètre : **lots 0+1+2+3** d'emblée.

### Écarts assumés par rapport au plan

| Point | Plan | Livré | Pourquoi |
|---|---|---|---|
| Emplacement du cachet | dans le flux de l'article | **dans le pied de page** | Seul emplacement qui marche dans les 4 modes de rendu : impossible d'injecter dans le DOM de l'éditeur en WebView, qui est le chemin nominal (~90 % du catalogue). Un seul cachet au lieu de deux variantes. |
| Filet vert sur les cartes | via un `ReadStateMark` neuf | **non livré** ⚠️ | `AnimatedFeedCard` a été *restylée* (filet vertical, `easeOutCubic` 320 ms, plus de scrim noir ni d'`elasticOut`, aucune haptique) mais **reste orpheline : 0 référence dans `lib/` et `test/`**. Le filet vert n'existe pas à l'écran. Le tableau annonçait « réhabilitée » à tort — corrigé le 25/07. À brancher en PR 2 mobile. |
| `closing_recap.dart` | à réhabiliter | **laissé en l'état** | Le bloc de clôture n'a pas besoin du détail par section — une phrase suffit, et le récap par section rouvrirait la question du critère « lu » permissif. À reprendre si le PO veut le détail. |
| Lot 4 (flamme) | conditionnel, après gate | **livré** | L'anneau ne dépend pas de `closure_streak` (qui est vide) : c'est un état du jour dérivé de `daily_completed`, il fonctionne dès le jour 1. Le gate ne portait que sur l'affichage d'une seconde série — toujours coupée. |

### Vérifications

- **Backend** : 2 485 tests passés (dont 13 nouveaux), 0 échec.
- **Mobile** : 2 111 tests (dont 17 nouveaux). **33 échecs = exactement la baseline de `main`**, mesurée
  en stashant la branche. **0 régression.** `flutter analyze` : 0 erreur, aucun nouveau warning.
- **Alembic** : ⚠️ **affirmation fausse au moment du merge** — `rd01` a bien été jouée contre une
  base vide, mais depuis la *branche*, où elle était seule. Sur `main`, `pt01` (PR #1008, mergée
  2 h plus tôt) porte le même `down_revision = 181c618da382` : **deux heads, aucune révision de
  merge**, `alembic upgrade head` sans cible. Le boot staging démarrait quand même l'app sur un ORM
  mappant `completed_at` / `completion_source` absentes → 500 sur feed, digest, statut, streaks.
  Réparé par la révision de merge `mg04_merge_pt01_rd01` + garde `len(heads) != 1` au boot et sur
  la sonde readiness + rejeu du smoke Alembic sur `push: main`. Voir la PR « hotfix Alembic ».
- **API** : bootée localement, contrat vérifié dans l'OpenAPI
  (`ContentStatusUpdate.completed/completion_source`, `CompletionSource ∈ {in_app, short, web}`,
  `StreakResponse.daily_completed/daily_goal`).
- **Bout en bout contre une vraie base** : `completed_at` posé et estampillé serveur ; relecture
  ne déplace pas l'horodatage (first-write-wins) ; compteur du jour dérivé correct ; un `consumed`
  seul ne crée aucune complétion et ne bouge pas le compteur ; la combinaison
  `completed` + `status=consumed` est rejetée ; une complétion de J-3 ne compte pas aujourd'hui.

### Ce qui reste ouvert

- **Le chiffre de `DAILY_COMPLETION_GOAL` (= 2) est provisoire.** Il doit être arrêté sur la
  distribution réelle de `article_finished`, après ~2 semaines de collecte. Il est en constante
  serveur (`streak_service.py`) précisément pour être recalibré **sans release client**.
- **Pas encore de tagline de découverte dans la « Notif du jour »** (message one-shot expliquant
  l'objectif). À ajouter si le PO le souhaite — le plan la prévoit, elle est triviale.
- **Validation QA web** (`/validate-feature`) non exécutée : Flutter web n'était pas lancé dans cet
  environnement. Les parcours visuels (cachet, CTA secondary, filet, anneau) restent à valider à l'œil.
