# Méthodologie v1.2 — Amendements actés (extraits opérationnels)

> 🗂️ **Supersédé par la v1.3** (`methodologie-v1.3.md`). Plusieurs amendements ci-dessous
> sont **révisés** en v1.3 (décisions PO 18/07/2026) : fenêtre événementielle 730 j → **36
> mois** (§5), **raccourci JTI supprimé** (§1 : JTI = signal du C9 fusionné), lettres A–E
> reprises (§7). Ce document reste la référence des **runs v1.2**. Correspondance : Annexe B
> de la v1.3.

> **Import** : extraits de `FACTEUR_methodo-v1.2_reponses-commentaires_2026-07-02.md`
> (revue des 48 commentaires ouverts sur la v1.1.1). Seuls les amendements
> **nécessaires à la pipeline V0** sont repris ici, verbatim. Le document complet
> reste la référence pour la publication de la v1.2 finale.
> `version_methodo` des évaluations V0 = **`v1.2`** (grille §4 inchangée pour les
> critères vague 1, amendements ci-dessous inclus).

## 1. Certification JTI = score plein direct (C8)

> À l'inverse, une **certification JTI obtenue et en cours de validité** (audit
> tiers sur 130+ critères de processus) vaut à elle seule score plein sur C8,
> sans examen complémentaire : elle constitue le signal formel le plus exigeant
> actuellement disponible.

→ Codé en dur dans `build_eval_input.py` (raccourci `code:jti_shortcut`, pas
d'agent évaluateur pour C8 dans ce cas).

## 2. Pondération des vérifications négatives (C1)

> **Pondération des vérifications négatives.** Toutes les vérifications
> négatives n'ont pas le même poids. Chaque débunkage recensé est qualifié selon
> trois dimensions, documentées dans la fiche :
>
> | Dimension | Modalités | Effet sur l'évaluation |
> | --- | --- | --- |
> | **Émetteur** | Avis CDJM ou fact-checker IFCN tiers (poids plein) / rubrique de fact-checking d'un média concurrent direct (poids réduit, conflit d'intérêts potentiel documenté) | Pondération du signal |
> | **Gravité** | Erreur matérielle corrigeable (date, chiffre) / information substantiellement trompeuse / fabrication ou désinformation caractérisée | Gradation croissante |
> | **Suite donnée** | Correction publiée par le média (atténuant) / absence de réaction / refus documenté de corriger (aggravant, cf. signal existant) | Modulation |
>
> Une accumulation de débunkages de faible gravité corrigés rapidement ne peut à
> elle seule justifier un score nul ; à l'inverse, un unique cas de fabrication
> non corrigée le peut.

→ Portée par la table `media_eval_debunkages` (`poids_emetteur` **dérivé par
code**, `gravite`, `suite_donnee`) et par la grille de `determinations` de la
rubrique C1.

## 3. Confiance par critère

> Attribuer à chaque critère un **indice de confiance** (Haute / Moyenne /
> Basse) selon la densité des signaux : Haute = ≥ 2 sources indépendantes
> convergentes ; Moyenne = signaux corroborés mais peu nombreux, ou partiellement
> datés ; Basse = signal unique corroboré a minima, ou signaux mixtes. Cet indice
> figure dans la fiche et ne modifie pas le score : il qualifie sa robustesse.

## 4. Corroboration — cas limite

> **Cas limite.** Lorsqu'un signal pertinent n'est corroborable par aucune
> seconde source (paywall, archives inaccessibles, média peu documenté), il n'est
> pas utilisé pour la notation : le critère est évalué sur les seuls signaux
> corroborés ou, à défaut, marqué N/A. L'impossibilité de corroboration est
> consignée dans la fiche (sources consultées et réserves).

→ Garde-fou aval `ingest_evaluations.py` : score plein avec < 2 sources
indépendantes → plafonné au palier inférieur + flag `corroboration_insuffisante`.

## 5. Bornes temporelles des signaux hors-échantillon

> - **Signaux structurels positifs** (charte publiée, société de journalistes,
>   page corrections) : constatés à la date de l'évaluation, sans limite
>   d'ancienneté — c'est leur existence actuelle qui compte.
> - **Signaux événementiels** (débunkage, avis CDJM, correction, départ de
>   journalistes) : pris en compte sur une fenêtre maximale avant la date de
>   début de l'évaluation. Au-delà, ils sont mentionnés à titre descriptif dans
>   la fiche mais ne fondent aucune notation.

⚠️ **Divergence V0 assumée** : les amendements v1.2 proposent une fenêtre
événementielle de **36 mois** ; la décision PO du 07/07/2026 verrouille
**730 jours** pour le V0 (`FRAICHEUR_MAX_JOURS = 730`, cohérent avec le
déclencheur fallback C1 « < 3 débunkages / 2 ans » de l'architecture). À
réconcilier à la publication de la v1.2 finale.

## 6. Statut de l'ARCOM

Les amendements v1.2 proposent le **retrait de l'ARCOM** du document
méthodologique (registre d'État, asymétrie TV/presse). La décision PO du
07/07/2026 pour le V0 **conserve `sanction_arcom`** dans le registre des signaux
C1, avec le garde-fou d'asymétrie de l'architecture (arbitrage n°2) : pour un
média `type_media != audiovisuel`, l'absence de données ARCOM est un **N/A
structurel, neutre** — le collecteur s'auto-désactive. À réconcilier à la
publication de la v1.2 finale.

## 7. Échelle des lettres (§4.4.1 v1.2)

La v1.2 introduit une note synthétique **A à E**, d'« Excellent » à « Faible »,
appliquée au score renormalisé sur 100 :

| Lettre | Seuil (score renormalisé ≥) |
|---|---|
| A | 85 |
| B | 70 |
| C | 55 |
| D | 40 |
| E | 0 |

⚠️ Seuils repris de la décision PO du plan V0 (le §4.4.1 complet n'est pas dans
le PDF v1.1.1) — **à confirmer à l'import de la v1.2 finale** (`LETTRES` dans
`scripts/media_eval/schemas.py`).
