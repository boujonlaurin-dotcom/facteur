# Architecture de collecte & d'évaluation — critères C1 à C11

> **Import** : conversion markdown de
> `FACTEUR_architecture-collecte-evaluation_C1-C11_2026-07-07.html` (v1.0 du
> 07/07/2026). Fondé sur : méthodologie ouverte v1.2 (§4 grille, §5 protocole) et
> batch-test #1 disponibilité des données (27/06/2026). Les choix marqués
> « arbitrage n° » sont des défauts réversibles, à valider en revue méthodo.

*Rapport d'opérationnalisation · 7 juillet 2026 · Périmètre : la grille de
notation uniquement (Annexes A/B/C hors scope V1) · Ancré sur la stack Facteur
(Supabase · scripts · sous-agents Claude)*

**L'essentiel.** L'architecture repose sur deux principes : (1) séparer
strictement la collecte de l'évaluation — la collecte produit des signaux bruts,
horodatés et sourcés dans Supabase ; l'évaluation (sous-agents) ne lit que ce
data store, jamais le web — et (2) router chaque signal vers l'une de trois
voies : CODE pour tout ce qui est déterministe, AGENT pour tout ce qui demande
lecture et jugement, HUMAIN pour l'inaccessible (paywall) et le contradictoire
(double évaluation, calibration). Sur les ~40 signaux de la grille : environ
40 % sont collectables par code, 45 % par agents, 15 % exigent l'humain.

## 1. Principe fondateur : collecte ≠ évaluation

La méthodo l'exige déjà implicitement (§5.1 : traçabilité, reproductibilité,
contestabilité). L'architecture le rend physique : deux phases, un data store
entre les deux.

**La phase de collecte ne note jamais.** Elle produit des signaux : des
observations factuelles avec source, URL, date, citation et capture (snapshot).
**La phase d'évaluation ne collecte jamais** : les sous-agents évaluateurs
reçoivent les signaux d'un média pour un critère, appliquent le barème du §4, et
rendent un score justifié qui cite les signaux utilisés.

Quatre garanties directement alignées sur la méthodo :

- **Reproductibilité** — on peut re-noter (nouvelle version du barème, nouveau
  modèle, contre-expertise) sans re-collecter. Indispensable pour le processus
  contradictoire (§6) : si un média conteste, on rejoue l'évaluation sur les
  mêmes données.
- **Traçabilité** — chaque point attribué pointe vers des `signal_id` précis,
  eux-mêmes liés à des snapshots horodatés. La fiche publiée (§5.5.1) se génère
  mécaniquement.
- **Auditabilité du non-collecté** — le data store enregistre aussi ce qui a été
  cherché sans être trouvé (« absence vérifiée ») et ce qui n'a pas pu être
  atteint (« bloqué accès »). Deux statuts différents, deux effets différents sur
  la note.
- **Coût maîtrisé** — la collecte (chère : fetch, navigation, lecture) tourne une
  fois ; l'évaluation (bon marché : lecture de JSON) peut tourner N fois.

## 2. Les trois voies de collecte

**Règle de routage** : le code pour le déterministe, l'agent pour le jugement,
l'humain pour l'inaccessible et le contradictoire. Un signal descend toujours au
niveau le plus bas (le moins cher) capable de le produire de façon fiable.

### VOIE A — CODE

Scripts + edge functions Supabase, planifiables (cron). Déterministe, répétable,
quasi gratuit.

- **Crawl structurel** : détection et snapshot des pages types (mentions légales,
  à propos, chartes, corrections, publicité) via chemins connus + sitemap.
- **Registres structurés** : API Pappers (propriété, comptes), liste CPPAP,
  registre JTI, liste des membres et avis CDJM (cdjm.org, scrapable).
- **Constitution du corpus** : échantillonnage stratifié rubrique × mois sur 90
  jours (§5.4) via sitemap/RSS — sélection aléatoire scriptée, donc documentée et
  rejouable.
- **Pré-métriques d'articles** : bylines, labels (« Tribune », « Sponsorisé »),
  liens sortants, patterns (« selon… », « Mise à jour »), dates.

### VOIE B — AGENT

Sous-agents Claude spécialisés, avec accès web (dont fetch navigateur). Lecture,
recherche ouverte, qualification.

- **Recherche ouverte** : débunkages, condamnations judiciaires, départs de
  journalistes, déclarations de dirigeants, couverture du propriétaire.
- **Qualification** : pondérer chaque débunkage (émetteur / gravité / suite
  donnée, §4.1 C1), juger la qualité d'une charte (clauses contraignantes ou
  déclaratives ?).
- **Analyse de corpus** : sourçage (C2), info/opinion (C4), diversité des
  perspectives (C10), cadrage (C11) — article par article, avec grille fermée.
- **Extraction structurée** : transformer une page « Qui sommes-nous » en données
  actionnariales normalisées.

### VOIE C — HUMAIN

Rare et ciblé : là où ni le code ni l'agent ne peuvent aller, ou là où la méthodo
exige un regard second.

- **Corpus paywallé** : copie manuelle d'articles inaccessibles déposée dans le
  corpus store — une fois déposé, l'analyse redevient voie B.
- **Double évaluation C9 / C11 (⚑ méthodo)** : second évaluateur humain,
  divergences documentées.
- **Validation du fallback C1** : les recoupements de véracité faits par agent
  sont contresignés avant d'entrer au score.
- **Golden set de calibration** : notation humaine de référence pour mesurer
  l'accord agent/humain avant de faire confiance au harness.

**Pourquoi ce routage est robuste** : le batch-test #1 (27/06) a montré que le
point de rupture n'est pas l'intelligence mais l'accès (blocklist
lemonde.fr/mediapart.fr, paywalls) et la disponibilité (zéro donnée tierce sur
les médias de niche). L'architecture traite donc l'accès comme une propriété du
signal (statut dédié) et non comme un échec de collecte.

## 3. Pipeline global

1. **Référentiel** — fiche média : domaine, volume/jour, type de paywall,
   audiovisuel ou presse en ligne. Conditionne échantillons (§5.4) et routage.
2. **Collecte** — 3 voies en parallèle. Sortie unique : des signaux horodatés +
   snapshots. Zéro notation.
3. **Data store** — Supabase. Signaux, corpus, débunkages, snapshots. Statuts :
   présent / absent vérifié / partiel / bloqué accès.
4. **Évaluation** — 1 sous-agent par critère, sans accès web. Barème §4 + règles
   codées (corroboration, N/A, fraîcheur).
5. **Synthèse & QA** — score renormalisé, lettre, niveau de confiance
   (§5.3-É3). Double éval C9/C11, QA humaine par échantillon.
6. **Restitution** — fiche détaillée (§5.5.1) générée depuis les signaux cités +
   carte média. Puis contradictoire (§6).

## 4. Mapping critère par critère (extraits vague 1)

### C1 — Véracité et exactitude (20 pts · continue · Rigueur)

| Signal (méthodo §4.1) | Voie | Brique concrète |
|---|---|---|
| Recensement des débunkages (5 fact-checkers IFCN + avis CDJM) | CODE + AGENT | Scripts de recherche ciblée par domaine sur chaque fact-checker + scrape des avis CDJM (indexés par média) → l'agent trie les faux positifs et remplit la table debunkages. |
| Qualification de chaque débunkage : émetteur / gravité / suite donnée | AGENT | Grille fermée de la méthodo (3 dimensions × modalités) appliquée par l'agent à chaque entrée — le calcul de pondération devient ensuite du code pur. |
| Condamnations judiciaires (diffamation, fausses nouvelles) | AGENT | Recherche Légifrance + presse juridique ; chaque trouvaille exige la décision source (pas un article seul, règle §5.2). |
| Décisions ARCOM (médias audiovisuels uniquement) | CODE | Base des décisions ARCOM, filtrable par éditeur. Presse en ligne → signal marqué « N/A structurel », neutre (arbitrage n°2). |
| Fallback : vérification manuelle de 5 articles factuels si < 3 débunkages / 2 ans | AGENT + HUMAIN | Déclenchement automatique (règle codée sur la table debunkages). L'agent recoupe les affirmations clés auprès de sources primaires ; l'humain contresigne avant entrée au score. |

*Point d'attention batch* : critère radicalement asymétrique. Médias exposés
(CNEWS, Le Monde) = données tierces abondantes ; médias de niche (Reporterre,
Next) = zéro. Pour eux, le fallback n'est pas l'exception mais la voie
principale — à budgéter comme telle.

### C5 — Transparence de la propriété et du financement (10 pts · continue · Transparence)

| Signal | Voie | Brique concrète |
|---|---|---|
| Page « Qui sommes-nous » / structure actionnariale affichée | CODE + AGENT | Crawl + snapshot ; l'agent extrait la structure déclarée en données normalisées. |
| Mentions légales complètes (forme juridique, capital, immatriculation) | CODE | Crawl /mentions-legales + vérification de complétude par champs attendus (checklist codable). |
| Croisement registres : Pappers (propriété, comptes), CPPAP (reconnaissance presse) | CODE | API Pappers (officialisé, remplace Societe.com — arbitrage n°6) + liste CPPAP publiée. Le croisement déclaré vs registre est documenté hors score. |
| Sources de financement décrites, rapports financiers, déclaration de conflits d'intérêts | AGENT | Lecture des pages À propos / transparence financière ; recherche du rapport annuel. |

*Verdict batch* : ✅ disponible et homogène sur les 5 médias testés, petits
inclus. Fondation fiable de la V1 — à scorer en premier.

### C7 — Séparation contenu éditorial / publicité (4 pts · continue · Transparence)

| Signal | Voie | Brique concrète |
|---|---|---|
| Mentions « Contenu sponsorisé / partenaire / publi-reportage » sur les contenus payés | CODE | Détection des labels types sur le site et le corpus. |
| Absence de native advertising non labellisé ; séparation visuelle claire | AGENT | Jugement visuel (captures navigateur) : un contenu payé maquetté comme un article se voit, ne se regexe pas. |
| Politique publicitaire publiée (page « Publicité » / « Régie ») | CODE + AGENT | Crawl + lecture de substance. |

*Verdict batch* : ✅ quasi homogène (4 ✅, 1 🟡). Scorable en V1 sans friction.

### C8 — Engagement déontologique formel (4 pts · continue · Transparence)

| Signal | Voie | Brique concrète |
|---|---|---|
| Charte éditoriale / déontologique publique | CODE + AGENT | Crawl + snapshot ; l'agent vérifie la substance (engagements réels vs page marketing). |
| Adhésion CDJM | CODE | Liste des membres sur cdjm.org — lookup direct. |
| Certification JTI en cours de validité | CODE | Registre JTI. Règle codable en dur : JTI valide = score plein C8, sans examen complémentaire (§4.2) — le seul critère de la grille avec un raccourci automatique. |
| Médiateur, comité d'éthique, processus de réclamation | AGENT | Recherche sur site + ours. |

*Verdict batch* : solide. Beaucoup d'auto-déclaratif chez les petits médias :
assumé en V1 — la présence vérifiable du document vaut preuve (arbitrage n°7).

### C9 — Indépendance éditoriale (10 pts · 3 niveaux 0/5/10 · Indépendance · ⚑ double évaluation)

| Signal | Voie | Brique concrète |
|---|---|---|
| Charte d'indépendance, société de journalistes, gouvernance rédactionnelle | AGENT | Lecture qualifiante : la différence entre « partiel » (charte déclarative) et « complet » (droit de veto, droit d'agrément) est une question de clauses, pas de présence — cœur du prompt évaluateur. |
| Couverture observable de sujets touchant le propriétaire ⚑ | AGENT | Recherche site-spécifique après résolution de la propriété via C5/Pappers. Non abouti au batch #1 — à instruire en priorité au batch #2. |
| Signaux négatifs : avis CDJM d'ingérence, départs documentés de journalistes | AGENT | Corpus CDJM (déjà collecté pour C1) + recherche presse professionnelle (avec corroboration §5.2). |
| Double évaluation (fortement recommandée) | HUMAIN | Second évaluateur humain sur les mêmes signaux ; divergences documentées dans la fiche. |

*Verdict batch* : ✅ 4/5 médias documentés. L'échelle à 3 niveaux réduit la
surface de subjectivité : l'agent propose un niveau + justification, l'humain
tranche en cas de doute.

### C11 — Transparence du positionnement éditorial (6 pts · 3 niveaux 0/3/6 · Transparence · ⚑ double évaluation recommandée)

| Signal | Voie | Brique concrète |
|---|---|---|
| Ligne éditoriale / manifeste explicite sur le site | CODE + AGENT | Crawl (pages « Manifeste », « Notre projet »…) ; l'agent juge la lisibilité pour un lecteur lambda — c'est le barème (opaque / partiel / transparent), pas le contenu politique (qui relève de l'Annexe B, hors V1). |
| Déclarations publiques des dirigeants éditoriaux | AGENT | Recherche interviews / tribunes des dirigeants. |
| Cohérence : analyse de cadrage sur 5 articles du corpus C10 | AGENT | Le cadrage observé correspond-il au positionnement affiché ? Vague 2. |
| Double évaluation recommandée | HUMAIN | Même mécanisme que C9. |

*Verdict batch* : ✅ bien documenté. La partie structurelle (manifeste) est
scorable en vague 1 ; la partie cohérence (cadrage) suit le corpus C10 en
vague 2.

*(C2, C3, C4, C6, C10 : article-dépendants, vague 2 — cf. document source pour
le mapping complet.)*

## 5. Modèle de données (Supabase)

Sept tables (`media_eval_*`). Le principe : tout ce que la fiche d'évaluation
(§5.5.1) doit publier — source, URL, date, citation — est un champ obligatoire
dès la collecte, pas une reconstruction a posteriori.

- **medias** — id, nom, domaine ; type presse en ligne / audiovisuel (conditionne
  la neutralité ARCOM) ; volume_articles_jour (tailles d'échantillon §5.4) ;
  paywall (routage voie C) ; rubriques_opinion (où vivent les tribunes, pour C4).
- **snapshots** — media_id, url, type_page (mentions_legales / charte /
  corrections / publicite / a_propos…) ; contenu, hash, capture_at (preuve
  horodatée — gère aussi les incohérences internes, arbitrage n°7) ; mode_acces.
- **corpus_articles** — media_id, url, titre, date_pub, rubrique, strate_mois
  (stratification §5.4 documentée) ; texte ; mode_acquisition ; pre_metriques
  jsonb (voie A).
- **signaux** (la table pivot) — media_id, critere, type_signal ; statut
  present / absent_verifie / partiel / bloque_acces (la distinction clé,
  arbitrage n°3) ; valeur jsonb (observation factuelle + citation) ; voie,
  collecteur ; source_urls[], snapshot_id, collecte_at ; sources_consultees[]
  (si rien trouvé : la preuve qu'on a cherché, §5.3-É1).
- **debunkages** — media_id, url, date, resume ; emetteur, poids_emetteur
  (CDJM / IFCN tiers = plein ; concurrent direct = réduit) ; gravite
  (matérielle / trompeuse / fabrication) ; suite_donnee (corrigé / sans
  réaction / refus documenté).
- **evaluations** — media_id, critere, score, niveau ; justification,
  signal_ids[] (chaque point cite ses signaux — traçabilité §5.1) ; evaluateur
  (agent:<version> / humain:<nom> — permet la double éval C9/C11) ;
  version_methodo, version_prompt, evalue_at (re-notation comparable dans le
  temps).
- **fiches** — media_id, score_brut, score_renormalise, lettre ; criteres_na[],
  confiance HAUTE / MOYENNE / BASSE (règle §5.3-É3 — BASSE = non publiable) ;
  statut brouillon / contradictoire (§6) / publiée.

## 6. Le harness d'évaluation par sous-agents

Un sous-agent par critère, avec un contrat d'entrée/sortie strict. Les agents
collecteurs (voie B) et les agents évaluateurs sont des rôles distincts — jamais
le même agent qui cherche et qui note.

**Le contrat évaluateur**

- **Entrée** : les signaux du data store pour (média, critère) + le barème §4 du
  critère + les pré-métriques du corpus. Aucun accès web. Si un signal manque,
  l'agent le dit — il ne va pas le chercher.
- **Sortie** : JSON structuré `{ critere, score, niveau, justification,
  signal_ids_cites[], flags[] }`. Un score sans signal_ids est rejeté par
  validation.
- **Flags** : `donnees_insuffisantes` (→ N/A), `signaux_contradictoires`
  (→ score partiel + justification), `bloque_acces` (→ « non évaluable pour
  cause d'accès », jamais converti en 0), `revue_humaine_requise`.

**Les garde-fous de la méthodo, codés en dur (pas confiés au LLM)**

Tout ce qui est une règle mécanique du §5.3 sort du prompt et devient une
validation programmatique :

- **Corroboration (§5.2)** : ≥ 2 sources indépendantes pour un score plein ;
  aucun critère fondé sur une seule source externe → check sur les source_urls
  des signaux cités.
- **Fraîcheur** : données > 2 ans → N/A automatique.
- **Déclencheur fallback C1** : < 3 débunkages sur 2 ans dans debunkages → tâche
  de vérification manuelle créée automatiquement.
- **Raccourci JTI** : certification valide → C8 plein, sans passage par l'agent.
- **Synthèse** : renormalisation sur 100 (règle de trois sur les critères
  évaluables), lettre A–E, niveau de confiance HAUTE / MOYENNE / BASSE — pur
  calcul.
- **Neutralité ARCOM** : média de presse en ligne → les signaux ARCOM sont
  exclus du comparatif inter-médias (N/A structurel).

**Calibration avant confiance**

Avant d'évaluer en série : constituer un golden set noté à la main critère par
critère. Chaque version du harness (prompt ou modèle) est mesurée contre ce
set : accord exact sur les critères à 3 niveaux (C9, C10, C11), écart toléré sur
les échelles continues. On ne publie rien tant que l'accord agent/humain n'est
pas stable. Ensuite, la QA humaine passe en échantillonnage (1 fiche sur N revue
intégralement) + double évaluation systématique C9/C11.

## 7. Cas limites & arbitrages par défaut

| # | Arbitrage | Choix par défaut intégré |
|---|---|---|
| 1 | C1 sur les médias à faible empreinte | Fallback (5 articles) = voie par défaut, déclenchée automatiquement si < 3 débunkages / 2 ans. Pondération émetteur/gravité/suite portée par la table debunkages. |
| 2 | Biais ARCOM (audiovisuel sur-instruit) | Absence de données ARCOM pour la presse en ligne = N/A structurel, neutre. Codé dans le référentiel média (type). |
| 3 | « Bloqué » ≠ « absent » | Statut `bloque_acces` natif dans la table signaux. Jamais converti en score 0 ; affiché « non évaluable pour cause d'accès » dans la fiche. |
| 4 | Médias à fort paywall | Cascade : ① compte abonné de test → ② reproductions tierces (avis CDJM, décisions de justice) en proxy → ③ collecte manuelle humaine en dernier recours. Le mode_acquisition reste tracé. |
| 5 | Barème C3 (politique vs pratiques) | Les deux familles de signaux sont collectées et valorisées. Le délai ≤ 48 h devient optionnel, jamais bloquant. |
| 6 | NewsGuard / Societe.com faibles en pratique | NewsGuard retiré du protocole opérationnel. Pappers officialisé comme registre propriété/comptes (API, gratuit). |
| 7 | Auto-déclaratif des petits médias | Accepté pour la transparence (C8, C11) : la présence vérifiable du document vaut preuve. Incohérences internes gérées par snapshots horodatés + hash. |

**Prérequis technique non négociable** : le fetch simple est aveugle sur
lemonde.fr et mediapart.fr (blocklist) et sur les sites à rendu JavaScript. Les
agents collecteurs doivent disposer d'un fetch navigateur, sinon ~40 % du panel
reste invisible sur les critères article-dépendants.

## 8. Phasage & budget

**Vague 1 — scorable dès maintenant (le socle structurel)** : C5 · C7 · C8 · C9
· C11 (partie manifeste) + C1 (volet données tierces). Collecte code + agents
sur pages du média et registres ouverts. Homogène sur tous les médias, petits
inclus (validé au batch #1). Budget observé : ~25–30 appels d'outils web et
5–10 min d'agent par média.

**Vague 2 — dépend du corpus (les critères article-dépendants)** : C2 · C4 · C6
· C10 + C1 (fallback) + C11 (volet cadrage). Prérequis : fetch navigateur +
stratégie paywall + échantillonneur §5.4. À lancer sur 2–3 médias pilotes avant
d'industrialiser.

**Ordre de mise en route** : ① 7 tables Supabase + référentiel médias ; ②
scripts voie A du socle (crawl structurel, Pappers, CPPAP, CDJM, JTI) ; ③ agents
collecteurs voie B du socle ; ④ golden set (notation humaine vague 1) ; ⑤
sous-agents évaluateurs vague 1 + garde-fous codés → mesure d'accord contre le
golden set ; ⑥ échantillonneur §5.4 + stratégie paywall → vague 2.
