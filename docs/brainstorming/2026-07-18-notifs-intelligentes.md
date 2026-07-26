# Brainstorming Session Results — « Notification intelligente »

**Session Date:** 2026-07-18
**Facilitator:** Claude (session agent-driven BMAD)
**Participant:** Laurin (PO)

---

## Executive Summary

**Topic :** La « notif intelligente » (heure choisie + sujets + apprentissage) comme levier n°1 de rétention/adoption pour le prochain step de Facteur.

**Session Goals :** Diverger largement (5 perspectives BMAD en parallèle) puis converger vers les solutions au meilleur ratio confiance-impact utilisateur / coût / risque-spam. Contrainte cardinale : être sollicité uniquement sur de l'hyper-pertinent, jamais de notifs « spam » ou régulières.

**Techniques Used :** First Principles + What If (analyst), SCAMPER sur les briques existantes (PM), Role Playing personas + parcours (UX), Assumption Reversal + Provocation (avocat du diable), carte de faisabilité/coût (architect).

**Total Ideas Generated :** ~55 idées brutes, convergées en 11 familles cotées et un top 3 d'exécution.

### Les 4 découvertes structurantes de la session

1. **L'infra est un bus de notifications qui s'ignore.** `push_deliveries` + le champ `kind` (idempotence `(device_id, target_date, kind)`) forment déjà un bus générique avec anti-doublon par jour et audit trail. Le dispatcher tourne toutes les 5 min avec résolution par timezone. Ajouter un type de notif = ajouter un `kind`, zéro migration. La « notification intelligente » n'est pas un nouveau système : c'est 2-3 nouveaux kinds + un gouverneur.
2. **Découpler détection et livraison.** Presque tout le spam vient de la confusion « ça vient d'arriver » = « il faut le dire maintenant ». Détection en continu (ingestion ~30 min), livraison au rituel (matin/soir). On garde ~100 % de la valeur informationnelle en supprimant ~95 % de l'intrusivité. La métaphore du facteur n'est pas du branding, c'est l'architecture : tournée à heure fixe, boîte persistante, recommandé exceptionnel.
3. **La version la plus sûre de cette feature n'envoie presque aucune notif nouvelle** : elle rend le push quotidien existant plus digne d'être ouvert (alerte fusionnée dans les bullets du push du matin). 80 % de la valeur pour 20 % du risque — et le risque évité est terminal (désactivation OS globale = mort du push quotidien qui porte le rituel).
4. **La rareté est le message.** Si Facteur notifie rarement, recevoir une notif Facteur est en soi une information (« ça sonne, donc c'est important »). C'est un actif de marque qu'aucun média à volume ne peut copier. Il doit être garanti structurellement (budget serveur, caps, canal séparé), pas espéré comportementalement.

---

## Technique Sessions

### 1. First Principles + What If — Mary (analyst)

**Principes premiers dégagés :**
- P1 : une notif n'a de valeur que si son absence aurait coûté quelque chose → le défaut est le silence.
- P2 : « bienvenue » vs « intrusive » n'est pas une propriété du contenu mais du **contrat** — l'utilisateur a écrit la règle (cloche posée), l'IA l'exécute et la raffine, jamais ne l'invente.
- P3 : le bon moment = le moment de disponibilité, pas le moment de l'événement.
- P4 : la confiance est un stock ; un service digne de confiance devient plus silencieux quand son solde baisse (inverse du re-engagement classique).
- P5 : la rareté est le message.

**Idées marquantes :** timbres hebdo (budget de notifs visible), « recommandé avec accusé » (chaque push explique son pourquoi en 1 tap + bouton de recalibrage), cloche sur source discrète, devis de fréquence à la création, recommandé d'événement cluster-gated, « fenêtre du facteur » (livraison groupée à la fenêtre apprise/déclarée), RAS quotidien (« rien d'important sur vos sujets » comme livrable premium), « j'ai failli vous prévenir » (calibration in-app zéro push), cloche contextuelle « suivre cette affaire » auto-expirante, sourdine automatique après 3 non-ouvertures.

### 2. SCAMPER sur l'existant — John (PM)

**Constat d'ancrage :** le dispatcher est généralisable par `kind` — c'est LE point de levier.

**Idées marquantes :** micro-récap personnalisé dans les bullets du push existant (0 notif ajoutée, coût S — le levier CTR le moins cher) ; alerte mot-clé = veille_keywords × dispatcher (S/M mais spam garanti sans garde-fous) ; warning fréquence à la création (S, anti-spam by design) ; push événement groupé via `find_hot_cluster` (compresseur : 1 événement = 1 notif) ; expansion sémantique = les keywords LLM des custom topics existent déjà, il manque juste l'UI de validation ; rotation 23.1 portée côté serveur comme gouverneur central ; cloche source réservée aux sources < N/semaine ; compteur de notifs visible (« 4 envoyées / budget 7 ») ; preset minimaliste/curieux comme matrice d'autorisation des kinds ; push data-only silencieux comme préchargeur du rituel (vitesse, pas interruption) ; skip du push les jours pauvres.

**Top 5 PM :** bullets personnalisés → gouverneur → alerte mot-clé + warning → événement groupé → budget visible/réglable.

### 3. Role Playing personas + parcours — Sally (UX)

**Scènes clés :** la Curieuse dont le sujet dormant « bouge enfin » (fusion dans la notif du rituel, une seule vibration) ; le Pro qui a choisi l'immédiat pour UNE alerte (vue événement 60 s, 3 perspectives, jamais 3 notifs pour 3 articles) ; l'utilisatrice au mot trop chaud (le warning aurait dû avoir lieu à la création ; en rattrapage, la notif propose elle-même de passer en récap hebdo) ; la cloche sur source mensuelle (« ça n'arrive qu'une fois par mois » — le MVP émotionnel, zéro risque par construction) ; le silence de 3 semaines (in-app : « en veille active, silence normal » — le silence devient une preuve de tri).

**Parcours :** cloche contextuelle dans le reader (entités pré-remplies) ; recherche sans résultat = « créer l'alerte » (la frustration devient une promesse) ; badge de rythme sur chaque source ; step Progression N+4 « Pose ta première cloche » ; devis de bruit vivant à la création avec 3 modes ordonnés (Immédiat grisé si mot trop chaud / **Dans ma prochaine tournée = défaut** / Récap hebdo) ; chips d'expansion sémantique opt-in avec impact fréquence ; re-demande de permission OS au moment du besoin avec fallback in-app assumé ; mise à jour silencieuse de la même notif Android quand l'événement grossit ; section « 🔔 Ton courrier suivi » en tête de Tournée (1-3 cartes, meurt avec l'édition — **jamais d'inbox infinie, jamais de badge rouge cumulatif**) ; les alertes vivent DANS « Mes intérêts » (la cloche est un état d'un intérêt, pas un objet à part) ; action « Moins souvent » native dans la notif elle-même ; plafond doux narré (« un facteur ne sonne pas 6 fois par jour »).

**3 principes UX :** (1) une alerte augmente une notif existante avant d'en créer une nouvelle ; (2) montrer le coût avant, le pourquoi après ; (3) le silence est un service, et la sortie est plus facile que l'entrée.

### 4. Assumption Reversal + Provocation — avocat du diable

**Renversements clés :** chaque notif supplémentaire érode la rétention même pertinente (la variable protectrice est la *prévisibilité*, pas la pertinence) ; l'utilisateur sur-souscrit toujours → **alertes à durée de vie** (expiration 30 j renouvelable en 1 tap) ; l'utilisateur ne veut pas choisir l'heure, il veut que Facteur tienne parole → l'intelligence = *quoi* mettre dans le créneau, jamais *quand* sonner ; la lenteur est le produit de Facteur (le temps réel est le produit des concurrents) ; l'apprentissage invisible = la boîte noire que le persona fuit → apprentissage propositionnel, jamais exécutif ; KPI inversés (succès = non-désactivation OS + rétention du rituel, jamais le CTR des alertes).

**Modes de destruction de confiance → garde-fous :** fatigue → désactivation OS globale (canal Android séparé + budget serveur) ; faux positifs ILIKE (l'audit veille 07/2026 a mesuré 60 % de hors-sujet au seuil 48 : jamais de push sur match brut) ; doublon 7h30/7h34 (fenêtre d'exclusion ±4h, fusion dans le payload) ; rafale d'une source (cap 1 notif/source/24h + mode digest-only auto) ; sur-souscription J1 (warning + plafond de cloches actives) ; cannibalisation de l'Essentiel par les récaps (la notif teaser, jamais le contenu) ; réglages-usine (un écran, 3 décisions max) ; perte du caractère sacré du push quotidien (wording/son/canal du rituel inchangés à vie, alertes silencieuses par défaut).

**Les 5 garde-fous non négociables :**
1. Budget global serveur, tous types confondus : **≤ 2 push/jour, ≤ 6/semaine**, appliqué avant FCM, non contournable par aucun réglage.
2. **Différé par défaut** : toute alerte est coalescée dans l'édition du créneau existant. Le temps réel n'existe pas en V1 ; s'il arrive, quota dur ~2/mois + seuil multi-sources.
3. **Canal OS séparé** pour les alertes, silencieux par défaut, « Ne plus recevoir ça » en 1 tap depuis la notif — une alerte ratée ne doit jamais pouvoir tuer le push quotidien.
4. **Aucun push sur match mot-clé ILIKE seul** — confirmation cluster/classification obligatoire ; le brut reste in-app. Cap anti-rafale 1 notif/source/24h.
5. **Apprentissage propositionnel et transparent uniquement** ; métrique de succès = rétention du rituel + non-désactivation OS, jamais le taux de clic.

### 5. Carte de faisabilité/coût — Winston (architect)

Constats vérifiés dans le code : dispatcher 5 min par timezone (`push_dispatcher.py`, `scheduler.py:616`), `push_deliveries` multi-kind sans migration, matching mot-clé écrit (`services/veille/feed_filter.py`), iOS = alert APNS simple (rendu riche Android-first), ingestion RSS/30 min (le « temps réel » est en réalité ~30-35 min).

| Rang | Famille | Coût | Note |
|---|---|---|---|
| 1 | **C** Alerte source (rare) | **S** | 1 colonne additive `notify` sur `user_sources`, job batch commun |
| 2 | **F** Warning/devis de fréquence | **S** | Endpoint preview ILIKE 30 j ; à livrer AVEC B, jamais après |
| 3 | **H** Budget/coalescing V1 | **S→M** | L'unicité `(device,date,kind)` donne 80 % gratuitement si les producteurs créent des candidats au lieu d'envoyer |
| 4 | **B** Alerte mot-clé/sujet | **M** | Version custom-topics-only = S ; matching article-major, jamais user-major |
| 5 | **A** Heure libre | **M** | Dispatcher prêt ; le coût est le CHECK `time_slot` (expand-contract 2 cycles) + 4 notifs locales en dur |
| 6 | **G** Expansion sémantique validée | **S/M** | L'enrichissement LLM custom topics existe déjà ; il manque l'UI chips |
| 7 | **J** Gating Progression | **S** | Trivial ; décision produit |
| 8 | **E** Cluster chaud → push événement | **M** | Cluster-major obligatoire ; calibration = le vrai coût caché |
| 9 | **I** UI dédiée de conso | **M/L** | V1 = deep-link ; le scope enfle vite (onglet vs section = ×3) |
| 10 | **D** Micro-récap LLM | **L** | Coût LLM = le mur ; version template d'abord, récap LLM partagé par thème (O(thèmes), pas O(users)) ensuite |
| 11 | **K** Apprentissage | **L/XL** | V1 = instrumentation seule (`push_opened` non tracké aujourd'hui) |

**3 pièges d'architecture :** (1) livrer B/C/E comme chemins d'envoi indépendants — dès la première alerte, les producteurs créent des candidats dans `push_deliveries`, un unique composeur (le dispatcher étendu) applique le budget et fusionne ; (2) toucher le CHECK `time_slot` ou tout DDL notif en une étape (DB partagée staging/prod → additif + nullable + 2 cycles hebdo) ; (3) matching user-major ou LLM par user×thème (max_connections=60, budget Mistral) — toujours article-major/cluster-major/thème-major.

---

## Idea Categorization

### Immediate Opportunities (prêtes à implémenter)

1. **Bullets personnalisés du push quotidien** — les teasers BigText mentionnent les sujets suivis (« ⚡ 2 articles sur [ton sujet] »). 0 notif ajoutée, coût S, agit sur le CTR de LA notif de rétention. Quick win de mesure.
2. **Cloche sur source rare** — cloche proposée uniquement si cadence < N/semaine (badge de rythme affiché), push « 📯 [Source] vient de publier — ça n'arrive qu'une fois par mois », deep-link reader. Spam-proof par construction, coût S, MVP émotionnel de la métaphore facteur.
3. **Devis de bruit à la création** — count ILIKE 30 j → « ~14 alertes/sem 🔴 / ~1/mois 🟢 », modes ordonnés par fréquence, Immédiat grisé si mot chaud. Coût S, la digue principale.
4. **Gouverneur V1 (architecture jour 1)** — producteurs → candidats `push_deliveries`, composeur unique, budget ≤ 2/jour et ≤ 6/semaine, canal Android séparé, fenêtre d'exclusion ±4h autour du push rituel.
5. **Instrumentation `push_opened`** — coût S, prérequis de tout apprentissage futur.

### Future Innovations (nécessitent développement/preuve d'usage)

- **Alerte sujet (cloche sur custom topic)** avec expansion sémantique en chips opt-in et gate cluster/classification avant push ; mode immédiat opt-in par alerte, plafonné, quiet hours 8h-21h.
- **Push événement groupé** (cluster chaud ∩ sujets suivis, cluster-major, mise à jour silencieuse de la même notif).
- **CTA contextuels** : cloche dans le reader (entités pré-remplies), empty state de recherche « créer l'alerte », step Progression N+4 « Pose ta première cloche ».
- **Section « Ton courrier suivi »** en tête de Tournée (1-3 cartes, meurt avec l'édition) + fiche de vie de l'alerte dans « Mes intérêts » (rythme constaté, 5 derniers signaux avec leur pourquoi, « en veille active », snooze).
- **Récap hebdo « lettre d'alerte »** (1/semaine, pipeline lettres, ton épistolaire) pour les sujets à fort volume.
- **Alertes à durée de vie** (expiration 30 j renouvelable 1 tap) + sourdine automatique après 3 non-ouvertures.
- **Compteur de sobriété visible** (« Facteur t'a envoyé 6 notifs ce mois-ci » + budget réglable).

### Moonshots

- **Le RAS quotidien** : vendre au Pro une garantie de silence vérifiable (« rien d'important sur vos sujets aujourd'hui » en badge passif) — le silence comme livrable premium.
- **« J'ai failli vous prévenir »** : le facteur montre in-app les candidats retenus au bord du seuil et demande « j'aurais dû sonner ? » — calibration active à zéro push.
- **Fenêtre du facteur apprise** : livraison à la fenêtre d'ouverture réelle apprise (borné ±90 min autour du slot choisi), sans jamais exposer de time picker.
- **Heure d'envoi auto** (`time_slot=auto`) pilotée par les données `push_opened`.

### Insights & Learnings

- Le contrat avant l'algorithme : l'IA exécute et raffine des règles écrites par l'utilisateur, elle n'en invente pas. Seule posture compatible avec un persona qui « se méfie des algos ».
- Le push quotidien est un actif sacré : wording/son/canal inchangés, tout le reste est silencieux par défaut et séparé.
- Ne pas mesurer la feature au CTR des alertes : succès = rétention du rituel + non-désactivation OS + zéro plainte volume. Prévoir une cohorte A/B sans alertes : si sa rétention est égale, la feature est du bruit.
- Le précédent interne existe déjà deux fois : la rotation « Notif du jour » 23.1 (max 3/jour, déterministe) et l'audit veille 07/2026 (60 % hors-sujet au seuil 48) — le premier donne l'architecture du gouverneur, le second interdit le push sur ILIKE brut.

---

## Action Planning — Top 3 priorisé

### #1 — PR fondation : « Gouverneur + push quotidien enrichi » (coût S/M)

**Rationale :** c'est le 80/20 identifié par 4 agents sur 5 — rendre la notif de rétention existante plus digne d'être ouverte, et poser le contrat d'architecture avant d'ouvrir le moindre nouveau kind. Zéro risque spam (aucune notif ajoutée), mesurable immédiatement.
**Contenu :** composeur unique étendu dans `push_dispatcher.py` (producteurs → candidats → budget ≤ 2/jour, ≤ 6/semaine, fenêtre ±4h) ; canal Android « Alertes » séparé silencieux ; bullets BigText personnalisés par sujets suivis ; instrumentation `push_opened` ; compteur de notifs envoyées lisible depuis `push_deliveries`.
**Next steps :** brief PM (Epic 30, story 30.1), mesurer le CTR du push quotidien avant/après sur 2 semaines.

### #2 — « La cloche » V1 : alerte source rare + devis de bruit (coût S)

**Rationale :** meilleur ratio simplicité/valeur/sécurité de toute la session (rang 1 et 2 de la carte des coûts). Le cas d'usage (la revue mensuelle qu'on rate toujours) est le plus « facteur » de tous, le risque spam est nul par construction (la rareté de la source EST le garde-fou), et il installe le geste « poser une cloche » + le devis de bruit qui serviront à tout le reste.
**Contenu :** colonne additive `notify` sur `user_sources` ; badge de rythme (« ~1/mois ») sur les sources ; cloche 1-tap réservée aux sources < N/semaine ; job batch article-major ; kind `source_alert` coalescé dans la tournée par défaut ; endpoint preview de fréquence ; re-demande de permission OS au moment du besoin avec fallback in-app.
**Next steps :** story 30.2 ; définir le seuil N (proposition : < 3 articles/semaine) ; migration additive (1 cycle, nullable).

### #3 — « La cloche » V2 : alerte sujet cluster-gated (coût M, sur preuve d'usage de #2)

**Rationale :** le cœur « intelligent » demandé (et candidat monétisation pour le Professionnel Efficace), mais le plus dangereux — donc dernier, une fois le gouverneur en place et le geste cloche validé. Custom-topics-only (les keywords LLM existent déjà), jamais de push sur ILIKE seul (gate cluster multi-sources ou classification concordante), expansion sémantique en chips opt-in, mode immédiat = opt-in par alerte, plafonné, quiet hours.
**Next steps :** story 30.3+ ; calibrer le gate cluster sur données réelles avant tout envoi (log interne des candidats pendant 2 semaines, revue des faux positifs — pattern audit veille) ; décider ensuite E (push événement) et le récap hebdo selon les métriques.

### Questions tranchées par le brainstorm

- **Heure libre (time picker) : NON en V1.** Convergence unanime analyst/reversal/UX : le créneau matin/soir n'est pas une limitation, c'est le contrat de prévisibilité. L'intelligence porte sur le *contenu* du créneau. Ouverture future : `time_slot=auto` appris des données `push_opened` — sans jamais exposer de picker.
- **Temps réel vs regroupé : différé par défaut, partout.** L'immédiat n'existe qu'en opt-in par alerte, réservé aux signaux structurellement rares, plafonné, quiet hours 8h-21h — et pas en V1.
- **Progression : oui comme surface de découverte** (step « Pose ta première cloche »), non comme prérequis bloquant. Coût S, à glisser dans #2.
- **UI dédiée : pas d'inbox.** Section éphémère en tête de Tournée + gestion dans « Mes intérêts ». V1 = deep-link.

### Questions ouvertes pour le brief

> **Tranchées le 2026-07-18** — voir le [micro-rapport de décision](2026-07-18-notifs-intelligentes-decisions.md) : free en V1, seuil < 1/sem, plafond 5, naming « Alerte », skip jours pauvres remonté comme question produit séparée.

1. Positionnement freemium : l'alerte sujet (#3) est-elle un argument premium (persona Pro payeur) ou un standard d'adoption ?
2. Seuil « source rare » (N/semaine) et plafond de cloches actives (proposition : 5).
3. Le skip du push les jours pauvres (E2 de John) : compatible avec le rituel/streak ou sacrilège ?
4. Naming : « cloche », « courrier suivi », « le facteur garde un œil » — à tester.

---

*Session facilitée avec les méthodes BMAD (facilitate-brainstorming-session, brainstorming-techniques) — agents analyst, pm, ux-expert, architect + lentille adversariale.*
