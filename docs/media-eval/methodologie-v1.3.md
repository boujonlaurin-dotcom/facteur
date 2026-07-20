# Méthodologie d'évaluation de la fiabilité des médias d'information francophones — v1.3

> **Statut du portage.** La grille §4 (critères C1–C10) est reprise **verbatim** du
> document source fourni par Laurin (18/07/2026). Les sections transverses (§1–3,
> §5–11) sont **consolidées depuis la v1.1.1** (`methodologie-v1.1.1.md`) et les
> amendements v1.2 (`methodologie-v1.2-amendements.md`), mises à jour selon les
> décisions PO du 18/07/2026 (Annexe C). Deux points référencés par la grille sont
> **tranchés pour la V0** : **§5.2.1** (coefficients de sources C1) = le mapping codé
> `derive_poids_emetteur` fait foi ; **Annexe A** (cartographie de propriété) = **hors
> périmètre V0** (le downgrade C6 niveau 0 repose sur la corroboration institutionnelle
> §5.2, faite inline par l'évaluateur). Détail en Annexe C (décisions 7-9).
>
> Ce fichier est la référence des rubriques `rubrics/v1.3/` (barème lu verbatim par
> les évaluateurs ; `version_prompt` = sha256 du fichier rubrique).

**Version** : 1.3 · **Date** : 18 juillet 2026 · **Statut** : Document de référence
(portage repo, en cours de validation PO)
**Licence** : libre accès (licence libre), réutilisable, modifiable et adaptable
sans restriction.

## Changements structurants v1.2 → v1.3

- **10 critères** au lieu de 11 : **fusion** de l'ex-C8 (engagement déontologique)
  et de l'ex-C11 (transparence du positionnement) en un seul critère **C9**
  (Engagement déontologique et transparence éditoriale).
- **Déplacement** de l'ex-C10 (Diversité des perspectives) vers l'**Axe 1**
  (Rigueur), renuméroté **C5**.
- **Pondération des axes : 60 / 20 / 20** (contre 50 / 30 / 20 en v1.2).
- Passage de plusieurs critères d'une échelle **continue** à des **barèmes à
  niveaux** discrets (4 ou 5 niveaux).
- **Fenêtre événementielle : 36 mois** (contre 730 jours en V0).

Table de correspondance complète : **Annexe B**.

## 1. Introduction et objectifs

Cette méthodologie propose un cadre reproductible et transparent pour évaluer la
fiabilité des médias d'information francophones. Elle repose sur la synthèse de
référentiels déontologiques internationalement reconnus et vise à documenter, de
manière factuelle et structurée, le respect par un média de normes
professionnelles établies.

L'évaluation porte spécifiquement sur les pratiques éditoriales et
informationnelles observables : vérification des faits, sourçage, transparence de
la propriété, distinction information/opinion, correction des erreurs, et
indépendance rédactionnelle. Elle ne juge ni la ligne éditoriale, ni les choix de
sujets traités, ni les opinions exprimées.

La méthodologie poursuit trois objectifs : **documenter** (fournir des données
structurées et justifiées sur les pratiques déontologiques des sources),
**responsabiliser** (inciter les médias à respecter les standards reconnus, en
rendant visibles les pratiques observées) et **servir de référence ouverte**
(protocole applicable par des chercheurs, organismes de déontologie, organisations
de fact-checking, ou tout évaluateur indépendant). Le protocole est conçu pour être
applicable aussi bien par un évaluateur humain que par un outil d'aide à
l'évaluation.

## 2. Périmètre et limites de l'évaluation

### 2.1. Ce que cette méthodologie couvre

La méthodologie évalue le degré de conformité d'un média d'information (à date,
principalement francophone) à un ensemble de bonnes pratiques journalistiques
reconnues, réparties en trois dimensions : **la rigueur informationnelle** (respect
des faits, qualité du sourçage, correction des erreurs, distinction
information/opinion, diversité des perspectives), **la transparence** (propriété,
financement, identité des auteurs, séparation contenu/publicité) et
**l'indépendance éditoriale et le pluralisme** (protection de la rédaction contre
les pressions extérieures, engagements déontologiques formels et transparence du
positionnement).

### 2.2. Non-couvert par cette méthodologie

La qualité littéraire, la pertinence des choix éditoriaux, l'orientation politique
ou idéologique, la recherche de « vérité » sur un plan philosophique, ou
l'exhaustivité des couvertures thématiques. Cette méthodologie ne prétend en aucun
cas correspondre à un label de vérité absolue (un score élevé indique de bonnes
pratiques, pas l'absence d'erreur), ni un classement de la « meilleure »
information. Elle n'a aucune vocation à s'associer à un outil de censure ou de
labellisation politique, ni à des évaluations en temps réel.

### 2.3. Choix normatifs et limites épistémologiques

**Ce que cette méthodologie valorise** : la transparence du positionnement
éditorial, le pluralisme des perspectives et la traçabilité des sources. Ces choix
sont conformes aux chartes de Munich et FIJ, mais il s'agit de choix subjectifs et
spécifiques à notre cadre de travail, pas de faits neutres.

**Limites structurelles** : la mesure de l'impact réel de l'information sur les
croyances des lecteurs ; la sélection de sujets opérée par le média — les critères
**C5** (diversité des perspectives) et **C9** (transparence du positionnement)
mesurent la pluralité et la transparence sur les sujets couverts, pas le choix de
ne pas couvrir certains sujets. La méthodologie ne différencie pas non plus
correction visible (« ex post ») et vérification avant publication (« ex ante »).

**Absence de neutralité substantive** : la méthodologie aspire à une application
identique quel que soit le média évalué (objectivité procédurale). Elle ne prétend
pas être neutre dans ses priorités (transparence, pluralisme, sourçage) ni dans ses
hypothèses normatives.

## 3. Référentiels fondateurs

Chaque critère s'appuie sur au moins deux référentiels indépendants (Charte de
Munich 1971 ; Charte d'éthique mondiale des journalistes FIJ 2019 ; Charte SNJ ;
CDJM ; JTI/RSF ; NewsGuard ; Ad Fontes Media ; MBFC). Sources exclues et
justification (Décodex, classement RSF, Acrimed) : identiques à la v1.1.1 §3.3. Les
référentiels précis de chaque critère figurent en tête de chaque rubrique de §4
(ligne « Réf. »).

## 4. Grille de critères

La grille comporte **dix critères** répartis en trois axes, pour un total de **100
points** : **rigueur informationnelle (60 pts)**, **transparence (20 pts)**,
**indépendance et pluralisme (20 pts)**. Cette répartition est un paramètre
configurable (documenter et justifier toute modification).

### Tableau récapitulatif

**Axe 1 — Rigueur informationnelle (60 pts)**

| # | Critère | Pts | Échelle | Échantillon requis |
|---|---|---|---|---|
| C1 | Véracité et exactitude | 20 | 5 niveaux (20/15/10/5/0) + indice d'exposition | Fact-checkers, registres + vérification sur échantillon (§5.4) |
| C2 | Sourçage et vérification | 15 | 5 niveaux (15/11/7/3/0) | 20–40 articles informatifs (selon volume) |
| C3 | Correction des erreurs | 10 | 5 niveaux (10/7/4/1/0) | Site du média + articles modifiés (§5.4) |
| C4 | Distinction information / opinion | 5 | 4 niveaux (5/3/1/0) | 15–25 articles mixtes |
| C5 | Diversité des perspectives | 10 | 3 niveaux (10/5/0) | 10–20 articles controversés (≥ 3 thématiques) |

**Axe 2 — Transparence (20 pts)**

| # | Critère | Pts | Échelle | Échantillon requis |
|---|---|---|---|---|
| C6 | Transparence propriété et financement | 10 | 5 niveaux (10/7/4/1/0) | Site du média + registres (Pappers, CPPAP) |
| C7 | Identification des auteurs | 6 | 4 niveaux (6/4/2/0) | Même échantillon que C2 |
| C8 | Séparation contenu / publicité | 4 | 4 niveaux (4/3/1/0) | Site du média (navigation générale) |

**Axe 3 — Indépendance éditoriale et pluralisme (20 pts)**

| # | Critère | Pts | Échelle | Échantillon requis |
|---|---|---|---|---|
| C9 | Engagement déontologique et transparence éditoriale | 10 | 3 niveaux (10/5/0) | Site du média + CDJM, JTI |
| C10 | Indépendance éditoriale | 10 | 3 niveaux (10/5/0) | Chartes, registres, couverture propriétaire |

**Total : 100 points.**

Le barème verbatim de chaque critère (définition, référentiels, signaux
observables, tables de notation, notes) est porté dans les rubriques
`rubrics/v1.3/C<k>.md`, lues verbatim par les évaluateurs. Les sections ci-dessous
(§4.1–§4.3) en reprennent le texte normatif.

### 4.1. Axe 1 : Rigueur informationnelle (60 points)

Le texte verbatim de C1 à C5 est en `rubrics/v1.3/C1.md` … `C5.md`. Points saillants
v1.3 :

- **C1 — Véracité et exactitude (20 pts, 5 niveaux)** : mesure la rareté des
  manquements avérés, établie à partir de vérifications de tiers et **lue à l'aune
  de l'exposition** (indice audience × ancienneté × reconnaissance, 3 paliers).
  Signaux pondérés par source (§5.2.1), gravité et suite donnée. Fenêtre 36 mois.
- **C2 — Sourçage et vérification (15 pts, 5 niveaux)** : sources nommées, liens
  cliquables, ≥ 2 sources indépendantes/article, attribution des citations,
  formulations prudentes. Sur échantillon (§5.4).
- **C3 — Correction des erreurs (10 pts, 5 niveaux)** : page corrections, mentions
  datées, canal de signalement, réponses aux évaluations externes. La suite donnée
  à un litige particulier relève de C1 (jamais compté deux fois).
- **C4 — Distinction information / opinion (5 pts, 4 niveaux)** : labellisation des
  contenus d'opinion, absence de jugements non attribués dans l'informatif, lexique
  des titres. L'analyse journalistique n'est pas de l'opinion au sens du critère.
- **C5 — Diversité des perspectives (10 pts, 3 niveaux, ex-C10, ⚑ double
  évaluation)** : pluralisme sur les controverses à désaccord légitime, **sans
  obligation de symétrie** (garde-fou « fausse balance » sur les faits établis).

### 4.2. Axe 2 : Transparence (20 points)

Texte verbatim en `rubrics/v1.3/C6.md` … `C8.md`.

- **C6 — Transparence propriété et financement (10 pts, 5 niveaux, ex-C5)** :
  actionnariat jusqu'aux personnes physiques, mentions légales, financement,
  conflits d'intérêts, rapport financier. La cartographie de propriété (Annexe A) est
  **hors périmètre V0** : la reconstitution d'actionnariat est faite inline par
  l'évaluateur, une divergence est consignée dans la fiche mais **ne modifie pas le
  score de C6**, sauf propriété manifestement erronée corroborée par une source
  institutionnelle.
- **C7 — Identification des auteurs (6 pts, 4 niveaux, ex-C6)** : signatures
  nominatives, biographies, statut de l'auteur.
- **C8 — Séparation contenu / publicité (4 pts, 4 niveaux, ex-C7)** : labellisation
  des contenus payés, séparation visuelle, politique publicitaire. Garde-fou :
  l'absence de politique publiée ne peut à elle seule faire descendre sous 3.

### 4.3. Axe 3 : Indépendance éditoriale et pluralisme (20 points)

Texte verbatim en `rubrics/v1.3/C9.md` et `C10.md`.

- **C9 — Engagement déontologique et transparence éditoriale (10 pts, 3 niveaux,
  fusion ex-C8 + ex-C11, ⚑ double évaluation)** : deux volets — engagement
  déontologique formel (charte **publique**, adhésion CDJM/JTI, dispositif de
  réclamation) et transparence de la ligne éditoriale. **JTI n'est plus un
  raccourci** : c'est un signal ; une adhésion sans charte publique vaut au maximum
  Partiel (5). Clarification actée : *une charte attestée mais non publiée ne
  constitue pas une trace d'engagement.*
- **C10 — Indépendance éditoriale (10 pts, 3 niveaux, ex-C9, ⚑ double
  évaluation)** : garanties formelles et **contraignantes** (veto, agrément,
  société de journalistes dotée de droits) ; l'ingérence documentée dégrade vers
  Absent.

## 5. Protocole d'évaluation

### 5.1. Principes directeurs

L'évaluation repose sur l'observation de signaux factuels, non sur le jugement
personnel de l'évaluateur : **traçabilité** (chaque point est justifié par un signal
observable cité — source, date, lien), **neutralité** (même protocole pour tous les
médias) et **transparence** (fiche complète publiée, reproductible et contestable).
**Règle absolue** : jamais de notation « au sentiment ». Si les données sont
insuffisantes, le critère est marqué **N/A** (ni présomption positive, ni négative).

### 5.2. Sources autorisées

**Sources directes** : pages « À propos », « Qui sommes-nous », « Mentions
légales » ; chartes (éditoriale, déontologique, d'indépendance) ; page de
corrections/errata ; page « Publicité » ou « Régie ». **Registres institutionnels** :
CDJM, ARCOM, JTI, Registre du Commerce / Pappers /
`recherche-entreprises.api.gouv.fr`, CPPAP. **Organismes de fact-checking** : AFP
Factuel, Les Décodeurs, CheckNews, Factuel (France Info), 20 Minutes Fake Off, et
tout vérificateur accrédité IFCN. **Sources exclues** : rumeurs, blogs non vérifiés,
évaluations de concurrents non documentées, opinion publique, MBFC et Ground.News
(transparence insuffisante — ils restent des référentiels de conception, pas des
sources de signaux).

#### 5.2.1. Coefficients de source (pondération des litiges C1)

Chaque litige C1 (débunkage, avis CDJM, condamnation) est pondéré selon la
**fiabilité de l'émetteur** du signal. Pour la V0, le coefficient de source §5.2.1
**est le mapping `poids_emetteur` dérivé par code** (décision PO 18/07/2026,
Annexe C-7) — il n'y a pas de tableau verbatim distinct à intégrer :

| Émetteur (normalisé) | `poids_emetteur` |
|---|---|
| ARCOM · justice · CDJM | **fort** |
| AFP Factuel · Les Décodeurs · CheckNews · Factuel (France Info) · Fake Off | **moyen** |
| Rubrique de fact-checking d'un média concurrent direct · émetteur inconnu | **faible** (conflit d'intérêts potentiel documenté) |

Le pipeline dérive ce coefficient depuis l'émetteur normalisé
(`scripts/media_eval/schemas.py`, `derive_poids_emetteur`) ; l'évaluateur pondère
chaque signal négatif par cette valeur avant de déterminer le niveau C1.

### 5.3. Étapes de l'évaluation

**Étape 1 — Collecte.** Pour chaque critère : identifier les signaux à observer ;
consulter les sources autorisées ; enregistrer chaque signal (source, URL exacte,
date, citation factuelle, snapshot).

**Étape 2 — Notation par niveaux.** En v1.3, chaque critère est noté par un
**niveau** défini par son barème (3, 4 ou 5 niveaux). Le pipeline automatisé
(évaluateurs) émet un **niveau discret** et le score est dérivé du niveau par code.
Données insuffisantes → **N/A** (exclu du calcul total). Le garde-fou de
**corroboration** (§5 amendements v1.2) reste applicable : un niveau haut fondé sur
moins de 2 sources indépendantes est plafonné au niveau inférieur, avec flag
`corroboration_insuffisante`.

> **Notation continue guidée par les niveaux** (décision PO 18/07/2026, Annexe C-10).
> Les niveaux **guident** la notation mais ne l'enferment pas : le notateur humain
> (gold, arbitrage) **peut noter entre deux paliers** en cas d'hésitation — un score
> intermédiaire (p. ex. 2 sur l'échelle C8 0/1/3/4) reste licite et exprime une
> détermination « entre » deux niveaux. Le niveau enregistré est alors le palier
> **guide** le plus proche. Le pipeline automatisé, lui, reste discret (un niveau par
> critère) pour rester reproductible et auditable.

**Étape 3 — Synthèse et renormalisation.** Le score total est calculé sur les seuls
critères **applicables** : les critères N/A sont exclus et l'assiette est
renormalisée sur 100. Déterminer le niveau de confiance global (HAUTE / MOYENNE /
BASSE) et les axes de force/faiblesse. La note synthétique **A–E** (§4.4.1
amendements v1.2 ; seuils en §5.5 ci-dessous) est appliquée au score renormalisé.

> **Règle propre à C1** (confirmée PO 18/07/2026, Annexe C-9). Pour un média à
> **exposition faible**, l'absence de litige ne vaut pas qualité : si aucun signal
> (tierces ni échantillon §5.4) n'est concluant, **C1 = N/A** et l'assiette est
> renormalisée sans C1.

**Étape 4 — Processus contradictoire.** Avant publication, le média évalué est
contacté (§6).

### 5.4. Protocole d'échantillonnage

**Période de référence du corpus** : 90 jours glissants à compter de la date de
début de l'évaluation. **Fenêtre des signaux événementiels** (débunkages, avis CDJM,
condamnations, ingérence — C1, C10) : **36 mois** avant la date de début (décision
PO 18/07/2026). Au-delà, un signal événementiel est mentionné à titre descriptif
mais ne fonde aucune notation. Les signaux **structurels** (charte, page
corrections, mentions légales…) sont constatés à date, sans limite d'ancienneté.

**Tailles d'échantillon** (par critère sur corpus) : C2/C7 — 20–40 articles
informatifs ; C4 — 15–25 articles mixtes ; C5 — 10–20 articles controversés
couvrant ≥ 3 thématiques ; C3 — articles modifiés + pages corrections/errata.
Pour les gros volumes, s'en tenir aux bornes hautes. **Stratification** :
répartition proportionnelle entre les principales rubriques du média et sur la
fenêtre. **Mode de sélection** : sélection aléatoire au sein de chaque strate
(rubrique × période).

### 5.5. Échelle des lettres (§4.4.1 v1.2)

Note synthétique A à E appliquée au score renormalisé sur 100 : **A ≥ 85 · B ≥ 70 ·
C ≥ 55 · D ≥ 40 · E ≥ 0**. Seuils repris de la décision PO du plan V0 (`LETTRES`
dans `scripts/media_eval/schemas.py`) — à confirmer à la publication finale.

## 6. Processus contradictoire et droit de réponse

Toute évaluation est communiquée au média concerné avant publication : notification
écrite de la fiche complète ; délai de réponse de 21 jours calendaires ; réponses
recevables (correction de données factuelles, documents complémentaires,
clarifications, contestation méthodologique argumentée) ; intégration des données
nouvelles vérifiables ; publication avec mention du processus contradictoire.
Procédure d'appel : réexamen par un évaluateur différent ; note de désaccord du
média annexable.

## 7. Limites connues et perspectives d'amélioration

**Limites v1.x** : biais de disponibilité (médias mieux dotés mécaniquement mieux
documentés) ; pas de vérification exhaustive ; dépendance aux fact-checkers (aucun
organisme → C1 lu à l'aune de l'exposition, échantillon §5.4 ou N/A) ; subjectivité
résiduelle (C5, C9, C10 → double évaluation) ; couverture géographique inégale.

### 7.1. Écart entre ligne déclarée et pratique éditoriale

C9 mesure la **formalisation publique** de la ligne éditoriale, non l'écart éventuel
entre cette ligne déclarée et la pratique. Cet écart, plus difficile à établir de
façon reproductible, **n'est pas mesuré à ce stade** ; sa part objectivable est
captée par le signal « lexique des titres » de C4. Amélioration envisagée :
méthode reproductible d'analyse de cadrage longitudinale.

**Autres améliorations envisagées** : pondération temporelle fine, augmentation de
l'échantillon, évaluation longitudinale, généralisation de l'inter-évaluation,
extension géographique.

## 8. Gouvernance et processus de révision

Révisions mineures : équipe d'évaluation (changelog). Révisions substantielles :
avis consultatif d'un comité externe (chercheurs SIC, représentants fact-checking
IFCN, CDJM ou équivalent, syndical de journalistes ; non constitué à date).
Contributions ouvertes.

## 9. Glossaire

Reprend le glossaire v1.1.1 (biais, débunkage, analyse de cadrage, fact-checking,
fiabilité, indépendance éditoriale, native advertising, positionnement éditorial,
pluralisme, processus contradictoire, sourçage, reproductibilité, signal
observable), complété en v1.3 par :

- **Indice d'exposition** — Estimation de la visibilité réelle d'un média
  (audience × ancienneté × reconnaissance par les pairs/institutions, 3 paliers),
  utilisée en C1 pour corriger le biais de volume des litiges et fixer la confiance :
  à exposition élevée, un socle de litiges mineurs corrigés est attendu et ne
  pénalise pas ; à exposition faible, l'absence de litige ne vaut pas qualité et le
  poids bascule sur la vérification par échantillon (§5.4).

## 10. Historique des versions

| Version | Date | Changements principaux |
|---|---|---|
| 1.0 | 1er avril 2026 | Conception initiale : 10 critères, 3 axes, protocole |
| 1.1 | 2 avril 2026 | Refonte structurelle : gouvernance, glossaire, C11 ajouté |
| 1.1.1 | 2 avril 2026 | Revues externes : C1/C4/C9/C11 renforcés, échantillonnage amélioré |
| 1.2 | 2 juillet 2026 | Amendements (JTI, pondération débunkages, temporalité, lettres A–E) |
| 1.3 | 18 juillet 2026 | 10 critères (fusion ex-C8 + ex-C11), diversité en Axe 1, axes 60/20/20, barèmes à niveaux, fenêtre 36 mois |

## 11. À propos

Méthodologie conçue dans le cadre du projet Facteur (Slow Medias), rédigée par
Laurin Boujon, mise à disposition sous licence libre. Contact :
boujon.laurin@gmail.com.

---

## Annexe A — Cartographie de propriété (hors périmètre V0)

> **Hors périmètre V0** (décision PO 18/07/2026, Annexe C-8). Le barème C6 (niveau 0)
> mentionne une **cartographie de propriété** qui reconstituerait de manière externe
> l'arbre de détention complet d'un média. Le **protocole formalisé de cette annexe**
> (sources institutionnelles retenues, méthode de reconstruction, seuil de
> corroboration) n'est **pas produit en V0**.
>
> **Règle opérante V0.** Le downgrade C6 au niveau 0 pour « propriété manifestement
> erronée » ne dépend **pas** d'un livrable Annexe A séparé : la reconstitution
> d'actionnariat est faite **inline par l'évaluateur** à partir du signal
> `structure_actionnariat` (repli Pappers / `recherche-entreprises.api.gouv.fr` /
> INPI), et le niveau 0 exige que l'erreur soit **corroborée par au moins une source
> institutionnelle** (§5.2). Une divergence entre l'arbre reconstitué et ce que le
> média rend visible est **consignée dans la fiche mais ne modifie pas le score de
> C6** (règle barème verbatim), sauf ce cas d'erreur manifeste corroborée.

## Annexe B — Table de correspondance v1.2 ↔ v1.3

**Règle d'interprétation de la base.** La version est portée **par run**
(`media_eval_runs.version_methodo`). Un run v1.2 (ex. `pilote-2026-07b`) et un run
v1.3 coexistent sans réécriture : le couple **(run → version_methodo, critere)**
désambiguïse les codes. Le CHECK SQL `critere IN ('C1'..'C11')` couvre `C1..C10` de
v1.3 ; **`C11` n'existe qu'en legacy v1.2** (ex-transparence du positionnement,
fusionnée dans C9 en v1.3). **Aucune migration des codes n'est requise.**

| v1.2 | Intitulé v1.2 | Pts · Axe | → | v1.3 | Intitulé v1.3 | Pts · Axe | Transformation |
|---|---|---|---|---|---|---|---|
| C1 | Véracité et exactitude | 20 · 1 | → | **C1** | Véracité et exactitude | 20 · 1 | Continue (5 profils) → 5 niveaux 20/15/10/5/0 **+ indice d'exposition** ; fenêtre 730 j → **36 mois** |
| C2 | Sourçage et vérification | 15 · 1 | → | **C2** | Sourçage et vérification | 15 · 1 | Continue → 5 niveaux 15/11/7/3/0 |
| C3 | Correction des erreurs | 10 · 1 | → | **C3** | Correction des erreurs | 10 · 1 | Continue → 5 niveaux 10/7/4/1/0 |
| C4 | Distinction info / opinion | 5 · 1 | → | **C4** | Distinction info / opinion | 5 · 1 | Continue → 4 niveaux 5/3/1/0 |
| C10 | Diversité des perspectives | 10 · 3 | → | **C5** | Diversité des perspectives | 10 · **1** | **Déplacé en Axe 1** ; barème 3 niveaux inchangé ; renuméroté **C10 → C5** |
| C5 | Transparence propriété / financement | 10 · 2 | → | **C6** | Transparence propriété / financement | 10 · 2 | Continue → 5 niveaux 10/7/4/1/0 ; renuméroté **C5 → C6** |
| C6 | Identification des auteurs | 6 · 2 | → | **C7** | Identification des auteurs | 6 · 2 | Continue → 4 niveaux 6/4/2/0 ; renuméroté **C6 → C7** |
| C7 | Séparation contenu / publicité | 4 · 2 | → | **C8** | Séparation contenu / publicité | 4 · 2 | Continue → 4 niveaux 4/3/1/0 ; renuméroté **C7 → C8** |
| C8 + C11 | Engagement déontologique **+** Transparence du positionnement | 4 · 2 **+** 6 · 2 | → | **C9** | Engagement déontologique et transparence éditoriale | 10 · **3** | **Fusion** ; passe en Axe 3 ; barème 3 niveaux 10/5/0 ; JTI = signal (plus un raccourci) |
| C9 | Indépendance éditoriale | 10 · 3 | → | **C10** | Indépendance éditoriale | 10 · 3 | Barème 3 niveaux inchangé ; renuméroté **C9 → C10** |

Totaux d'axes : v1.2 **50 / 30 / 20** → v1.3 **60 / 20 / 20**. Total 100 dans les deux
cas.

**Re-mapping du gold batch 1** (cnews, run v1.2 `pilote-2026-07b` → v1.3) : traité
au chantier de re-mapping (`scripts/media_eval/remap_v12_v13.py`, hors de ce
document). Les déterminations restent valides (les faits n'ont pas changé) ; seuls
numéros, poids et scores dérivés changent. Le critère fusionné C9 (ex-C8 négatifs 0
+ ex-C11 niveau 1) est soumis à validation gold.

## Annexe C — Registre des décisions PO (18/07/2026)

1. **60 / 20 / 20 fait foi.** Le header « Axe 1 (50 points) » du document source est
   un reliquat corrigé à 60 (C1 20 + C2 15 + C3 10 + C4 5 + C5 10).
2. **Fenêtre C1 = 36 mois.** Le code aligne `FRAICHEUR_MAX_JOURS` 730 → 1095 j
   (36 mois) en v1.3.
3. **Double évaluation = critères à 3 niveaux : C5, C9, C10.** Deux évaluateurs
   indépendants, non exposés l'un à l'autre ; désaccord → `revue_requise` + les deux
   valeurs documentées.
4. **Raccourci JTI supprimé.** JTI devient un signal parmi d'autres du C9 fusionné.
   Une adhésion sans charte publique = Partiel (5) au maximum ; l'évaluateur juge.
5. **ARCOM conservé tel quel.** `sanction_arcom` reste dans le registre C1, avec le
   garde-fou d'asymétrie audiovisuel (média non audiovisuel → absence de données
   ARCOM = N/A structurel neutre).
6. **Chaîne Google Doc ↔ repo « plus scalable »** : demande notée, **hors périmètre**
   de ce portage.
7. **§5.2.1 (coefficients de source C1) tranché** : le mapping codé
   `derive_poids_emetteur` (fort / moyen / faible) fait foi pour la V0 ; pas de
   tableau verbatim distinct à intégrer (cf. §5.2.1).
8. **Annexe A (cartographie de propriété) hors périmètre V0** : le downgrade C6
   niveau 0 repose sur la corroboration institutionnelle (§5.2), la reconstitution
   d'actionnariat étant faite inline par l'évaluateur (cf. Annexe A).
9. **Règle propre à C1 (§5.3) confirmée** : média à exposition faible sans signal
   concluant → C1 = N/A, assiette renormalisée sans C1.
10. **Notation continue guidée par les niveaux** (§5.3, Étape 2). En cas
    d'hésitation, le notateur humain (gold / arbitrage) peut noter **entre** deux
    paliers ; les niveaux guident sans enfermer. Le pipeline automatisé reste
    discret. Gold batch 1 v1.3 : les 3 cas CNEWS `revue_requise` (C6, C8, C9)
    tombent proprement sur un palier, aucun score intermédiaire requis
    (C6 niveau 2 = 4 · C8 niveau 2 = 3 · C9 niveau 0 = 0 ; cf. champ
    `decision_po` dans `golden/gold_v1_3.json`).

### Nettoyages éditoriaux appliqués au portage

- Header « Axe 1 (50 points) » → **60 points**.
- Titre « 10. Indépendance éditoriale » → **C10**.
- Note d'Annexe A de C6 : « ne modifie pas le score de **C5** » → **C6** (stale).
- Intégration verbatim en C9 de la clarification « une charte attestée mais non
  publiée ne constitue pas une trace d'engagement » (gap harness n°2, batch 1).

### Points référencés par la grille, résolus pour la V0

Les trois points référencés par le document critères-only mais absents du collé sont
**tranchés** (décisions 7-9 ci-dessus) — plus aucun trou ouvert :

- **§5.2.1** (coefficients de source C1) → le mapping codé `derive_poids_emetteur`
  (fort / moyen / faible) fait foi. **Résolu.**
- **Annexe A** (cartographie de propriété) → **hors périmètre V0**. **Résolu.**
- **§5.3** (règle propre à C1) → lecture confirmée. **Résolu.**
