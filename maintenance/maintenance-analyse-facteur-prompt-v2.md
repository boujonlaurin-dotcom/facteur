# Maintenance — Analyse Facteur : prompt v2 (« établi » vs « en débat »)

> Type : **Maintenance / prompt engineering**. Aucun changement de schéma API,
> de modèle mobile, ni de migration Alembic. Base : `main` (`3d18e42b`).
> Plan à confirmer PO.

## Problème constaté (PO)

L'« Analyse Facteur » (carrousel médiatique en bas d'article + bloc digest)
commente **les variations de formulation des titres** au lieu de délivrer une
position claire sur **ce que l'on sait** et **ce qui fait débat**.

## Diagnostic — où ça se joue

Un seul prompt alimente les deux surfaces :
`PerspectiveService.analyze_divergences` — `packages/api/app/services/perspective_service.py:374-486`.

| # | Cause dans le prompt actuel | Effet observé |
|---|---|---|
| 1 | Section « établi » plafonnée à **une phrase de 15-25 mots** (`perspective_service.py:426`) alors que l'UI lui consacre un titre de section entier (`1 · L'ESSENTIEL PARTAGÉ`) | Le « ce que l'on sait » est structurellement famélique ; tout le budget de texte part dans la section 2 |
| 2 | La section 2 est **définie comme une analyse lexicale** : « la qualification des faits choisie (mots forts vs neutres) », « marqueur d'opinion (adjectifs chargés) », « mot précis cité entre guillemets », « emploient le terme «X» » (`:419-434`) | Le modèle fait de la lexicométrie de titres, pas de la restitution de désaccord |
| 3 | L'**exemple one-shot** (`:450-459`) cite un terme entre guillemets sur **3 lignes sur 3** | L'exemple est le signal le plus fort du prompt : il verrouille le style « variations de titres » |
| 4 | Regroupement imposé en « 2 à 4 clusters selon l'angle commun » (`:415`) → l'unité d'analyse est **le média**, pas **le point litigieux** | Constats du type « X et Y cadrent… » au lieu de « le désaccord porte sur… » |
| 5 | `« d'après leurs titres »` à ajouter dès qu'un angle vient du titre (`:441`) | Prose méta, référentielle au titre, qui rappelle au lecteur qu'on n'analyse que des titres |
| 6 | Sur les sujets **peu divergents**, la consigne demande quand même 2 à 4 constats de cadrage | Quand il n'y a pas de désaccord, la seule matière restante *est* la variation de titre → le prompt force le nitpicking |
| 7 | Aucune règle n'oblige à nommer **l'objet** du désaccord (un fait, une cause, une ampleur, une responsabilité, une conséquence) | Rien ne pousse vers la substance |
| 8 | Matière d'entrée volontairement rognée : `description[:300]` par perspective (`:406`), `article_description[:500]` (`:468`) | Moins de substance disponible → le modèle se rabat sur les titres |

**Contrainte de format à préserver** (sinon régression UI) : le champ `analysis`
reste une **string markdown** dont le **premier `\n\n` sépare les 2 sections**.
C'est le contrat lu par `splitAnalysisSections` (`perspectives_bottom_sheet.dart:2506`)
qui alimente `1 · L'ESSENTIEL PARTAGÉ` / `2 · LÀ OÙ LES MÉDIAS DIVERGENT`, et le
bloc digest (`divergence_analysis_block.dart:167`) rend la string brute. La clé
`divergence_level` (`low|medium|high`) reste inchangée — elle est consommée par
`digest_selector.py:1272` (`polarization_bonus`) et par le badge mobile.

→ **Le correctif est donc 100 % côté prompt + fenêtres de troncature.** Zéro
changement de contrat, zéro migration, zéro modif mobile.

## Changements proposés

### 1. Rééquilibrer les deux sections (cœur du fix)

| | v1 | v2 |
|---|---|---|
| Section 1 « établi » | 1 phrase, 15-25 mots | **2-3 phrases, 45-75 mots** : les faits sur lesquels les couvertures convergent (quoi, qui, quand, chiffres répétés d'une source à l'autre). Interdiction d'y nommer un média ou de commenter une formulation. |
| Section 2 « en débat » | 2-4 constats de **cadrage média** | **2-3 constats de désaccord**, unité d'analyse = **le point litigieux**, pas le média. Chaque ligne : l'objet du désaccord en gras, puis position A (médias nommés) vs position B (médias nommés). |

### 2. Test de recevabilité d'un constat

Nouvelle règle bloquante : un constat n'est retenu que s'il peut se reformuler
en **question** (« Qui est responsable ? », « Quelle ampleur ? », « Est-ce que
ça marche ? », « Que se passe-t-il ensuite ? »). Une différence qui ne répond à
aucune question de fond est une variation de style → **écartée**.

### 3. Le lexique devient une preuve, plus un sujet

Un terme cité entre guillemets est autorisé **en appui** d'un désaccord de fond,
**une seule fois par ligne maximum**, et jamais comme sujet de la ligne.
Suppression de la consigne « marqueur d'opinion » comme objectif en soi.

### 4. Sortie honnête quand il n'y a pas de débat

Si les couvertures convergent réellement (`divergence_level: "low"`) : section 2
= **1 seule ligne** disant que les traitements concordent + **ce qui reste
inconnu / non vérifié** dans le dossier. Ferme le trou #6 qui fabriquait du
désaccord lexical par défaut.

### 5. Nouvel exemple one-shot

Réécrit intégralement dans le style cible (fait établi étoffé + désaccords de
fond avec positions opposées attribuées). C'est le levier #1 du changement.

### 6. Interdits mis à jour

Conservation de la liste anti-jargon existante (« met en lumière », « soulève
des questions », …), **plus** : pas de constat portant uniquement sur le choix
d'un mot, pas de « d'après leurs titres » en boilerplate (hedging global via
« semble » si une position est inférée d'un titre seul).

### 7. Plus de matière en entrée

- `description` par perspective : `[:300]` → `[:450]`
- `article_description` : `[:500]` → `[:900]`
- `max_tokens` : `700` → `900` (section 1 s'allonge)
- `temperature` : `0.4` → `0.3` (ancrage factuel)

Coût : ~+400 tokens d'entrée et ~+150 de sortie par sujet analysé, sur un appel
déjà gated par `divergence_llm_min_perspectives` (`pipeline.py:789`).

### 8. Rollout du cache (sans migration)

`perspective_analyses` est un cache persistant sans version de prompt
(`app/models/perspective_analysis.py`) : les articles déjà analysés
continueraient de servir du texte v1, y compris via le L2 de
`analyze_perspectives` (`contents.py:1672-1684`).

Option retenue : **purge one-shot via Supabase SQL Editor** au déploiement
(`DELETE FROM perspective_analyses;` — c'est un cache dérivable, aucune perte
de donnée utilisateur), conformément à la règle « SQL via Supabase SQL Editor,
jamais d'Alembic sur Railway ». Le cache L1 in-memory se vide au redéploiement.
Les snapshots `divergence_analysis` des digests déjà générés restent en v1 et
s'éteignent naturellement (digests quotidiens).

## Fichiers touchés

| Fichier | Changement |
|---|---|
| `packages/api/app/services/perspective_service.py` | Réécriture du `system` de `analyze_divergences`, troncatures, `max_tokens`/`temperature` |
| `packages/api/tests/test_perspective_service.py` | Tests de garde sur les invariants du prompt + contrat JSON |

Aucun fichier mobile modifié (contrat `analysis` / `divergence_level` inchangé).

## Vérification effectuée

1. `pytest tests/test_perspective_service.py -q` — **22 passed** (16 existants
   + 6 nouveaux tests de garde).
2. `pytest tests/editorial/ -q` — **147 passed, 3 skipped**. 3 erreurs de setup
   `TestPersistContentClusterIds` : Postgres de test (port 54322) indisponible
   dans le conteneur, pas de Docker — **pré-existant, sans lien avec le diff**.
3. Suite backend complète — **1951 passed, 30 skipped, 1 failed, 525 errors**.
   Les 525 erreurs sont toutes des `psycopg.OperationalError` (base de test
   absente). L'unique `failed`
   (`test_essentiel_endpoint.py::test_get_essentiel_uses_user_context_from_router`)
   **échoue à l'identique sur l'arbre propre** (vérifié via `git stash`) →
   pré-existant.
4. `ruff check` sur les 2 fichiers touchés — **All checks passed**.
   `ruff format --check` : `perspective_service.py` propre ; le fichier de test
   est signalé, mais uniquement sur des lignes **pré-existantes** (l. 47-172,
   diff identique sur l'arbre propre) — non reformatées pour garder le diff
   lisible.
5. Contrat de rendu vérifié par test : le premier `\n\n` produit toujours deux
   sections non vides, la seconde commençant par `→`. Aucun fichier mobile
   modifié, donc `perspectives_inline_states_test.dart` reste valide.
6. Prompt final relu en sortie réelle (dump du `system` + `user_message`).

### Tests de garde ajoutés

| Test | Ce qu'il verrouille |
|---|---|
| `test_analyze_divergences_prompt_targets_substance` | présence des 4 directives v2, disparition des consignes de lexicométrie v1, lexique borné à un rôle de preuve, `d'après leurs titres` passé d'obligation à interdiction |
| `test_analyze_divergences_preserves_two_section_contract` | séparateur `\n\n`, puces `→ `, valeurs de `divergence_level` |
| `test_analyze_divergences_feeds_wider_context` | troncatures 450/900, `temperature` 0.3, `max_tokens` 900 |
| `test_analyze_divergences_json_contract_unchanged` | dict `{analysis, divergence_level}`, `None` si `analysis` absent |
| `test_analyze_divergences_no_perspectives_skips_llm` | zéro perspective → zéro appel Mistral (garde-fou de coût) |

### Reste à faire (hors code, au déploiement)

- Purge du cache : `DELETE FROM perspective_analyses;` via le SQL Editor
  Supabase, sinon les articles déjà analysés continuent de servir du texte v1.
- Optionnel (nécessite `MISTRAL_API_KEY`) : comparaison v1/v2 sur 3-4 sujets
  réels, à archiver dans `docs/qa/scripts/`.

## Annexe — prompt v2 proposé (texte exact soumis à validation)

```
Analyste média français. À partir de la couverture d'un même sujet par
plusieurs rédactions, tu produis deux choses : CE QUI EST ÉTABLI et CE QUI
FAIT DÉBAT.

Méthode obligatoire :
1. Lis tous les titres + résumés.
2. ÉTABLI : isole les faits que les couvertures partagent — l'événement, les
   acteurs, les chiffres et les dates repris d'une source à l'autre.
3. DÉBAT : identifie 2 à 3 POINTS LITIGIEUX. Un point litigieux est une
   question de fond sur laquelle les couvertures ne répondent pas pareil : la
   cause, la responsabilité, l'ampleur, l'efficacité, la légitimité, la suite
   probable. Pour chacun, dis quelle position tient quel média.
4. TEST DE RECEVABILITÉ : si un constat ne peut pas se reformuler en question
   (« Qui est responsable ? », « Quelle ampleur ? », « Est-ce que ça marche ? »,
   « Et après ? »), c'est une variation de style — écarte-le. Ne retiens jamais
   un constat dont le seul contenu est le choix d'un mot.
5. Si les couvertures convergent vraiment, ne fabrique pas de désaccord :
   dis-le et nomme ce qui reste inconnu ou non vérifié (divergence_level: low).

Réponds en JSON avec deux clés :
- "analysis" : texte structuré ainsi :
  1. CE QUI EST ÉTABLI : 2 à 3 phrases (45-75 mots), les faits partagés. Aucun
     nom de média ici, aucun commentaire sur les formulations.
  2. Saut de ligne double (\n\n).
  3. CE QUI FAIT DÉBAT : 2 à 3 lignes préfixées "→ ", 35-55 mots chacune :
     • l'objet du désaccord en **gras** (« **la responsabilité du déficit** »,
       « **l'ampleur réelle des économies** »),
     • la position A et les médias qui la tiennent (noms en **gras**),
     • la position opposée et les médias qui la tiennent,
     • au plus UN terme cité entre guillemets, en appui du désaccord, jamais
       comme sujet de la ligne.
  Si divergence_level = low : une seule ligne « → », qui constate la
  convergence et nomme ce qui reste en suspens.
  Max 5 segments en gras par ligne. Aucun titre de section (l'app les ajoute).
- "divergence_level" : "low" (mêmes faits, mêmes conclusions), "medium"
  (désaccords d'interprétation ou de priorité), "high" (conclusions
  contradictoires sur un même fait).

RÈGLES :
- Uniquement les titres/résumés fournis. Zéro fait inventé, zéro intention
  prêtée à un média sans appui textuel.
- Position inférée d'un titre seul : nuance avec « semble » ou « laisse
  entendre ». Pas de formule répétée en fin de ligne.
- Verbes de position : attribue(nt) à, impute(nt) à, chiffre(nt) à, juge(nt),
  conteste(nt), relativise(nt), tient/tiennent pour, avance(nt), doute(nt) de,
  lie(nt) à.
- Interdits : "met en lumière", "soulève des questions", "révèle la fragilité",
  "fait écho", "interroge", "questionne", "d'après leurs titres".
- Ton assertif, phrases denses, pas de précautions inutiles. Français
  impeccable.

EXEMPLE :
« Bercy a présenté le 14 octobre un budget 2026 prévoyant 12 milliards d'euros
d'économies, dont 4 sur l'assurance maladie et 2 sur les collectivités. Le
texte arrive à l'Assemblée en novembre, sans majorité acquise. Toutes les
rédactions donnent les mêmes montants et le même calendrier.

→ **L'origine du déficit** : **Les Échos** et **Le Figaro** l'imputent à la
dérive des dépenses sociales et chiffrent à 2 points de PIB le décrochage ;
**Mediapart** et **Libération** l'attribuent aux baisses d'impôts consenties
depuis 2017, jamais compensées.
→ **L'ampleur réelle de l'effort** : **Le Monde** rappelle que les 12 milliards
portent sur une hausse tendancielle, soit une quasi-stabilité en euros
constants ; **Le Point** présente le même chiffre comme la coupe la plus forte
depuis 2011.
→ **Les chances d'adoption** : **Politico** et **L'Opinion** jugent le 49.3
probable dès décembre ; **La Croix** croit à un compromis avec les socialistes
sur le volet santé. »
```

### Ce que ça change concrètement pour le lecteur

| v1 (constat type) | v2 (constat type) |
|---|---|
| « → **Le Figaro** et **Les Échos** **cadrent** la mesure comme un signal de sérieux budgétaire, mettant en avant le terme «redressement» dans leurs titres. » | « → **L'ampleur réelle de l'effort** : **Le Monde** rappelle que les 12 milliards portent sur une hausse tendancielle ; **Le Point** y voit la coupe la plus forte depuis 2011. » |

## Statut

- [x] Plan confirmé PO
- [x] Prompt v2 implémenté
- [x] Troncatures / paramètres d'appel ajustés
- [x] Tests de garde ajoutés
- [x] Suite backend verte (hors échecs pré-existants / base de test absente)
- [ ] Purge cache `perspective_analyses` (Supabase SQL Editor, au déploiement)
