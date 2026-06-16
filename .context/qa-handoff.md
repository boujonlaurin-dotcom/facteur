# QA Handoff — Onboarding sources : re-mapping taxonomie + badge « Spécialisé en X »

> Rempli par l'agent dev après VERIFY. Input de `/validate-feature` (agent QA Chrome).

## Feature développée

Pendant l'onboarding, l'écran de reco sources devient « wow » : chaque sujet (subtopic)
sélectionné obtient **au moins une source spécialisée visible**, badgée « Spécialisé en X ».
Côté backend, un script aligne le vocabulaire des `granular_topics` des sources sur la
taxonomie 51-slugs des users/articles (re-dérivée du contenu réellement publié) et élargit
le catalogue curé. Côté mobile, le recommender ajoute un badge spécialiste sur la spécialité
dominante d'une source, **et** une garantie de couverture qui rapatrie le meilleur spécialiste
curé pour tout sujet choisi non couvert (carte distincte par sujet, pré-cochée).

> ⚠️ La partie data (re-tag + promotion en base) est **gatée PO** et tourne séparément
> (`scripts/retag_and_promote_sources.py --apply --allow-prod`) après merge. La validation QA
> ci-dessous porte sur l'**UI mobile** (badge + visibilité). Sur l'env staging, l'effet plein
> n'apparaît qu'une fois la base re-taggée ; le badge et la garantie restent testables avec
> les `granular_topics` déjà présents.

## PR associée
<!-- gh pr view --web après /go -->

## Écrans impactés
| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Onboarding — Sources (« sur mesure ») | flow onboarding, étape sources | Modifié |

## Scénarios de test

### Scénario 1 : Happy path — sujet avec spécialiste
**Parcours** :
1. Lancer l'onboarding, choisir des thèmes (ex. Tech, Société) puis des sous-sujets variés
   (ex. `IA`, `Climat`).
2. Passer le swipe de calibration, arriver sur l'écran « ① Suggestions sur mesure ».
**Résultat attendu** : pour chaque sous-sujet choisi qui dispose d'un spécialiste curé, une
carte porte un chip teinté primary **« 🎯 Spécialisé en {sujet} »** (ex. « Spécialisé en
Intelligence artificielle »). Ces cartes apparaissent **en tête** des suggestions et sont
**pré-cochées**.

### Scénario 2 : Edge case — sujets « pauvres »
**Parcours** :
1. Refaire l'onboarding en choisissant des sous-sujets réputés minces
   (ex. `Fact-checking`, `Relations et amour`, `Jeux vidéo`).
**Résultat attendu** : au moins une carte « Spécialisé en X » remonte pour chacun **quand la
data le permet** (cartes distinctes par sujet). Si aucun spécialiste curé n'existe pour un
sujet sur l'env testé, pas de carte fantôme et pas d'erreur — dégradation propre.

### Scénario 3 : Pas de doublon / cohérence des chips
**Parcours** :
1. Choisir un sujet dont la source dominante matche (ex. une source dont la spécialité
   dominante est exactement le sujet choisi).
**Résultat attendu** : la carte montre **un seul** chip « Spécialisé en X » (pas de double
chip « X » thème + « Spécialisé en X »). La source n'apparaît pas deux fois.

## Critères d'acceptation
- [ ] ≥1 carte « Spécialisé en {sujet} » visible par sous-sujet sélectionné (quand un
      spécialiste curé existe).
- [ ] Le badge utilise le bon libellé FR (`getTopicLabel`) pour les 51 slugs.
- [ ] Les cartes spécialistes sont en tête des suggestions et pré-cochées.
- [ ] Pas de doublon de carte ni de double chip thème+spécialiste.
- [ ] Console sans erreur, pas de requête 4xx/5xx inattendue.

## Zones de risque
- Spécialité dominante = `granularTopics.first` : dépend de l'ordre (par share desc) écrit par
  le re-tag backend. Sur un env non encore re-taggé, l'ordre vient du seed CSV.
- Cap des suggestions (`_suggestionsLimit = 18`) : les spécialistes sont placés en tête pour
  survivre au cap — vérifier qu'ils ne sont jamais tronqués.

## Dépendances
- Aucune nouvelle API. Sérialisation existante `granular_topics` / `articles_30d`
  (`schemas/source.py`, `routers/sources.py`). Pas de migration Alembic.
- Effet data complet conditionné à l'apply prod gaté PO du script de re-tag/promotion.
