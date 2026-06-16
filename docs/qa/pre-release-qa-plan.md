# Plan QA pré-release — Facteur

> Plan exécutable pour la release store. La validation porte sur le build web
> `main`/staging avec un viewport mobile. Les builds natifs et la production ne
> sont pas couverts par cette passe.
>
> Outillage : **Playwright Agent CLI** (`playwright-cli`). Lire les skills
> [`facteur-qa-web`](../../.claude/skills/facteur-qa-web/SKILL.md) et
> [`playwright-cli`](../../.claude/skills/playwright-cli/SKILL.md). Lancer la QA
> d'un parcours via `/validate-feature`.

---

## 1. Métadonnées

| Champ | Valeur |
|-------|--------|
| Version cible | `1.0.0+1` |
| Date de la passe | 2026-06-15 |
| Branche / environnement | `main` / staging |
| Build testé | `https://boujonlaurin-dotcom.github.io/facteur/` |
| Commit candidat | `8c7ddc158026b6ba99e6c5d7357d65404897538a` |
| API pointée | `api-staging-40d3` |
| Viewport de référence | `390 × 844` (iPhone 14 Pro) |
| Périmètre | Top Critique en profondeur ; Important en smoke ciblé |
| Statut | ❌ no-go |

### Comptes de test

| Compte | État attendu | Usage |
|--------|--------------|-------|
| `test.facteur@proton.me` | Compte rempli, feed peuplé | C2 à C4 et smokes |
| `laurin.facteur@proton.me` | Réinitialisé par le PO | C1 onboarding vierge |
| `boujon.laurin@gmail.com` | Réinitialisé par le PO | Repli C1 onboarding vierge |

Mot de passe commun : `09091997`.

> Flutter web utilise un canvas : activer la sémantique au boot avant tout
> `snapshot`, puis la réactiver après chaque `goto` ou `reload`.

---

## 2. Stratégie et règles d'exécution

1. Exécuter C1 à C4 dans l'ordre, avec un rapport PASS/FAIL par parcours.
2. Après chaque action significative, vérifier la console et les requêtes réseau.
   Tout 4xx/5xx inattendu est un bug même si l'UI masque l'erreur.
3. Prendre une capture avant/après les interactions structurantes. Si un widget
   Flutter n'est pas sémantisé, utiliser les coordonnées à partir d'une capture.
4. Passer les edge cases transverses sur chaque parcours Critique.
5. Exécuter ensuite les parcours Importants en smoke léger si aucun blocant ne
   rend la suite non pertinente.

Classification :

| Résultat | Signification |
|----------|---------------|
| PASS | Attendus vérifiés, aucune régression significative |
| FAIL — Critical | Parcours cœur bloqué ou perte/corruption de données |
| FAIL — Major | Fonction principale cassée ou UX fortement dégradée |
| FAIL — Minor | Défaut limité, contournement simple |
| WARNING | Comportement suspect ou assertion non vérifiable sur le web |
| NOT RUN | Précondition ou donnée de test indisponible |

---

## 3. Périmètre priorisé

### Critique — release-blocking

| ID | Parcours | Risque principal | Ancrage code |
|----|----------|------------------|--------------|
| C1 | Onboarding complet, utilisateur vierge | Porte d'entrée fortement retouchée ; sortie ou calibration bloquée | `features/onboarding/screens/onboarding_screen.dart`, `questions/swipe_disambiguator_question.dart`, `questions/subtopics_question.dart`, `providers/onboarding_provider.dart`, `core/api/user_api_service.dart` |
| C2 | Essentiel du jour et fit des cartes | Collapse à une carte, contenu daté, snap/haptique fragile | `features/flux_continu/screens/flux_continu_screen.dart`, `utils/section_fit.dart`, `widgets/essentiel_hi_fi_card.dart`, `providers/flux_continu_provider.dart` |
| C3 | Reader / article | Empilement couverture média, Analyse Facteur, trois modes et deep reco | `features/detail/screens/content_detail_screen.dart`, `widgets/deep_recommendation_card.dart`, `feed/widgets/perspectives_bottom_sheet.dart`, `settings/models/display_mode_spec.dart` |
| C4 | Fiche source v3 et ajout de source | Endpoint `/profile`, invalidation immédiate et mute précédemment instable | `features/sources/widgets/source_detail_modal.dart`, `widgets/source_add_panel.dart`, `custom_topics/widgets/topic_chip.dart` |

La fonctionnalité **« Pas de recul » / deep recommendation** du reader est incluse
explicitement dans C3 bien qu'elle soit absente du changelog.

### Important — smoke ciblé

| Parcours | Vérification minimale |
|----------|-----------------------|
| Flâner | « Tes sources discrètes » visible ; « Actu chaude » regroupée par sujet de façon cohérente |
| Tournée | Tap sur un titre de section ouvre « tout lire » ; empty-state thème mono-source exploitable |
| Veille | Contenus globalement pertinents ; entrée dédiée présente dans les réglages |
| Grille | Mot du jour issu d'un vrai titre ; origine « où il se cachait » affichée |
| Progression | Deux nouvelles lettres présentes : défis curation et palier de fond |

### Nice-to-have

- Badges de formats secondaires.
- Carrousels secondaires de Flâner.
- Modes d'affichage sur les écrans hors reader.

---

## 4. Scénarios Critiques

### C1 — Onboarding vierge

Précondition : compte réellement réinitialisé côté staging.

1. Se connecter avec un compte vierge.
   - Attendu : redirection automatique vers `/onboarding`.
2. Parcourir les intros puis la sélection d'objectifs.
   - Vérifier que « Continuer » est bloqué sans objectif.
   - Sélectionner `anxiety` pour déclencher la branche `digestMode`.
3. Compléter Approche et Indépendance.
   - Attendu : transitions sans saut visuel ni étape sautée.
4. Sélectionner au moins un thème, puis ajouter un sous-sujet custom.
   - Attendu : clavier fermé immédiatement, chip custom visible, champ non masqué
     par le clavier.
5. Swiper 5 à 8 cartes de calibration dans les deux directions.
   - Attendu : drag suit le doigt, seuil de fling proche de 28 % de largeur,
     badge directionnel animé, pôles net-positifs sous le deck, overlay
     « On affine » à la fin.
   - Sonde : si le set est vide, auto-skip sans écran gris.
6. Vérifier la sélection des sources.
   - Attendu : sources principales précochées, sources swipées à droite cochées,
     au moins une source requise.
   - Un badge vidéo/podcast ne doit jamais être affiché sur un article.
7. Compléter `digestMode`, puis finaliser.
   - Attendu : animation de conclusion, loader pendant
     `POST /users/onboarding`, puis `/flux-continu`.
   - Le retour arrière ne doit pas rouvrir l'onboarding.
8. Vérifier les états dégradés observables.
   - Aucun double POST au double-tap.
   - Un échec de création de sujet custom est signalé après l'onboarding sans
     bloquer sa finalisation.

### C2 — Essentiel du jour et fit

Précondition : compte rempli avec feed peuplé.

1. Se connecter et attendre le Flux Continu.
   - Attendu : squelette puis contenu complet en deux à trois reframes maximum.
   - Aucun contenu daté de la veille dans l'Essentiel du jour.
2. Examiner l'Essentiel.
   - Attendu : un lead et jusqu'à quatre cartes medium.
   - Chaque carte tient dans l'écran sans overflow ni coupe par le header/footer.
3. Basculer en mode Minimaliste depuis le sélecteur d'affichage.
   - Attendu : l'Essentiel ne s'effondre pas à une seule carte à tort
     (`kMinPlausibleUsableHeight = 360`, plafond minimaliste = 6).
4. Effectuer plusieurs flings entre sections.
   - Attendu : un snap par section et un seul retour haptique par snap.
   - Sur web, classer l'haptique en WARNING si elle n'est pas vérifiable.

### C3 — Reader / article

1. Ouvrir un article depuis le feed.
   - Attendu : en-tête épuré ; tap sur la source ouvre sa fiche.
2. Scroller jusqu'à la couverture médiatique.
   - Attendu : carrousel de titres comparés ; tap ouvre l'article externe.
3. Déclencher « Analyse Facteur ».
   - Attendu : spinner, synthèse en 10 à 30 secondes, disclaimer visible.
   - En cas d'erreur : état explicite et action retry.
4. Tester Normal, Minimaliste et Lisible.
   - Attendu : rendu réellement différent (images/fontScale) sans overflow.
   - En Lisible, l'image reste en pleine largeur.
5. Atteindre le bas du reader.
   - Si « Pas de recul » est présent, le tap ouvre l'article recommandé.
   - Si `deepPending=true`, la carte peut apparaître après environ 2,2 secondes,
     mais ne doit pas rester en attente indéfiniment.

### C4 — Fiche source v3 et ajout

1. Ouvrir une fiche source depuis le reader ou le feed.
   - Attendu : header média-d'abord avec logo, domaine et signaux.
   - L'évaluation est repliée par défaut ; son dépliage montre fiabilité,
     trois jauges et bord politique.
2. Examiner la couverture par thèmes et les articles récents.
   - Attendu : barres de pourcentage et trois articles cliquables vers le reader.
3. Rechercher une source du catalogue puis la suivre.
   - Attendu : ses articles apparaissent dans le feed en environ une seconde,
     sans refresh manuel.
4. Masquer une source depuis l'ArticleSheet.
   - Attendu : confirmation visible, aucune `StateError`, source retirée du feed.
5. Vérifier les données partielles.
   - Source sans évaluation : « Pas encore évaluée ».
   - Source sans article sur 30 jours : section articles masquée.

---

## 5. Edge cases et risques connus

À sonder sur chaque parcours Critique :

- Feed vide / première ouverture et compte existant.
- Offline et erreurs 4xx/5xx avec message utilisateur exploitable.
- Double-tap sur passer, suivre, masquer et finaliser.
- Navigation arrière depuis un écran profond.
- Cohérence des données après navigation puis retour.
- Console JS sans erreur inattendue. Une erreur résiduelle au boot est tolérée
  uniquement si elle est identifiée et sans impact.

Risques connus couverts par la passe :

- Fit des cartes et plancher `kMinPlausibleUsableHeight`.
- Snap/haptique du Flux Continu.
- Mode Minimaliste réduit à une carte.
- Mute source et ordre `await` → `mounted` → `invalidate` → `pop`.
- Recall Tournée pour un thème mono-source.
- Faux positifs de clustering dans Perspectives / Actu chaude.

### Hors scope — risques connus non testés

- Notification « Essentiel du jour » lorsque l'app est fermée, notamment le
  risque `digestProvider` orphelin.
- Builds natifs Android APK et iOS.
- Token Railway et endpoint `/app/update`.

Ces points ne peuvent pas être considérés comme validés par une passe web staging.

---

## 6. Critères go/no-go

**GO** si :

- C1 à C4 sont PASS.
- Aucun FAIL Critical ou Major n'est ouvert.
- Aucun 4xx/5xx inattendu n'est observé sur les actions nominales.
- Les smokes Importants ne révèlent pas de parcours inaccessible.
- Les seuls écarts restants sont Minor, WARNING ou hors scope, documentés et
  explicitement acceptés par le PO.

**NO-GO** si :

- Un compte vierge ne peut pas terminer l'onboarding.
- L'Essentiel ou le reader est inutilisable sur `390 × 844`.
- Une action suivre/masquer produit une erreur ou des données incohérentes.
- Un appel nominal retourne un 4xx/5xx non géré.
- Une régression empêche l'accès à un parcours Critique.

Une précondition manquante produit `NOT RUN`, jamais un PASS implicite. Un C1
`NOT RUN` faute de compte réinitialisé exige une validation PO avant le GO.

---

## 7. Résultats d'exécution

> **Re-run 2026-06-16** sur le **backend candidat** `api-staging-40d3` (build web
> local pointé staging, playwright-cli 390×844, compte `test.facteur@proton.me`).
> Critère bloquant levé : **0 requête vers `facteur-production`**. Détail complet :
> [`.context/qa/dev-handoff-2026-06-16.md`](../../.context/qa/dev-handoff-2026-06-16.md).

| ID | Résultat | Notes / preuves |
|----|----------|-----------------|
| C1 | NOT RUN | Onboarding vierge mutant non rejoué cette passe — à faire après déblocage Grille. Faisable en 390×844 via playwright-cli. |
| C2 | NOT RUN (partiel) | Login + Essentiel cinq articles OK sur staging. Fit complet/minimaliste et snap/haptique non rejoués. |
| C3 | NOT RUN (partiel) | Reader et Couverture médiatique visibles. Analyse Facteur, trois rendus et deep reco non rejoués. **Favicons : CORS corrigé** (proxy backend, `image/png` + ACAO `*`). |
| C4 | PASS (endpoint) | `GET /api/sources/{id}/profile` → **200** (schéma complet : source, theme_distribution, recent_articles, articles_30d) ; id inconnu → **404**. Le 404 du 15/06 était un artefact prod (v3 non déployée). Ajout/mute UI non rejoués. |
| Important | PARTIEL | Veille `/config` 404 = empty-state géré (conforme). **Grille `/today` → 500 `ProgrammingError`** (drift Alembic multi-head, colonnes `hybrid_*` non appliquées sur DB partagée) → **blocant restant, décision infra**. |

### Synthèse

- PASS : 0
- FAIL Critical : 1
- FAIL Major : 2
- FAIL Minor : 0
- WARNING : 1
- NOT RUN / partiel : 3
- Verdict : **NO-GO**

### Défauts observés

#### Critical — cible QA branchée sur production

- Le build `https://boujonlaurin-dotcom.github.io/facteur/` appelle
  `https://facteur-production.up.railway.app/api`, alors que cette passe a été
  arbitrée sur `api-staging-40d3`.
- Le workflow [`.github/workflows/build-web.yml`](../../.github/workflows/build-web.yml)
  utilise lui aussi l'API production par défaut.
- Impact : la passe staging demandée n'est pas exécutable sur cette URL et les
  actions mutantes C1/C4 ne peuvent pas être lancées sans toucher la production.

#### Major — fiche source v3 indisponible

- Depuis le reader, ouvrir la fiche « Home Fil actu - actualités ».
- Requête observée :
  `GET /api/sources/f88f4548-eca5-4c85-92c7-301d8434c701/profile` → 404.
- Résultat : fallback avec identité, évaluation et gestion de source seulement ;
  couverture par thèmes et articles récents absents.

#### Major — Grille indisponible

- Au boot : `GET /api/grille/today` → 404.
- Corps : `{"detail":"Aucun mot du jour disponible"}`.
- Le smoke « mot du jour issu d'un vrai titre » est impossible.

#### Warning — favicons Couverture médiatique

- Le reader charge directement plusieurs URLs
  `https://www.google.com/s2/favicons?...`.
- Le navigateur les bloque par CORS, avec des erreurs console répétées.

### Éléments conformes observés

- Login du compte rempli et arrivée sur `/flux-continu`.
- Essentiel du 15 juin avec cinq articles, sans overflow horizontal visible sur
  `390 × 844`.
- Le passage au mode Minimaliste conserve les cinq articles de l'Essentiel.
- Reader lisible, image pleine largeur, titre/résumé visibles.
- Couverture médiatique présente avec sept angles et bouton Analyse Facteur.
- Entrée « Crée ta veille » présente dans Réglages.
- Les trois options Normal / Minimaliste / Lisible sont présentes.
- Carrousel « Tes sources discrètes » présent dans Flâner.

### Captures et rapports

Conserver les captures et rapports de cette passe dans `.context/qa/` avec un
préfixe `c1-`, `c2-`, `c3-`, `c4-` ou `smoke-`.

Captures de cette passe :

- `.context/qa/c2-feed-after-login.png`
- `.context/qa/c2-minimaliste-feed.png`
- `.context/qa/c3-reader-top.png`
- `.context/qa/c4-source-profile.png`
- `.context/qa/settings.png`
- `.context/qa/display-modes.png`
- `.context/qa/smoke-flaner.png`
- `.context/qa/smoke-flaner-lower.png`
- `.context/qa/smoke-progression.png`

---

## 8. Hors périmètre documentaire

- Intégration Playwright en CI.
- Suite `.spec.ts` automatisée.
- Merge, commit ou publication sans validation explicite du PO.
