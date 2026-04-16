# QA Handoff — Digest UI Polish Phase 2 (sous-cartes article ouvert)

> Polish UI ciblé sur l'état "expanded" d'un topic editorial du digest : allégement des sous-cartes Analyse de biais + Pas de recul, harmonisation des page indicators.

## Feature développée

Refonte visuelle des blocs **Analyse de biais** (sobre, replié par défaut, CTA inline) et **Pas de recul** (info @ 5%, sans border-left), compactage du spacing wrapper expanded, et harmonisation des page indicator dots sur **3 carousels** de l'app (digest expanded, feed, community).

## PR associée

À créer après validation visuelle (cible `main`).

## Écrans impactés

| Écran | Route | Modifié |
|-------|-------|---------|
| Digest — Topic editorial expanded | `/digest` (tap sur topic editorial) | Modifié |
| Feed — Carousels topiques | `/feed` | Modifié (page indicator only) |
| Community — Carousel | écran community | Modifié (page indicator only) |

## Scénarios de test

### Scénario 1 — Digest Analyse de biais (E1.b — replié par défaut)
**Parcours** :
1. Aller sur `/digest`
2. Trouver un topic editorial avec analyse de biais (ex. topic rang 1)
3. Taper sur le topic pour l'ouvrir (expanded state)
4. Observer la sous-carte "🔍 Analyse de biais (N sources)"

**Résultat attendu** :
- Background **sobre** : `colors.surface` (#FDFBF7 light) + border 1px subtle (`colors.border @ 0.15`). Plus de gradient ocre/orange.
- Plus de tooltip ⓘ "Mistral Medium" dans le header
- DivergenceChip "Angles différents" visible (conservé)
- Bias spectrum bar visible (height 6px) avec labels Gauche/Centre/Droite à **8px** (vs 9px avant)
- Texte d'analyse **non visible** par défaut
- Chevron `▼ Lire l'analyse` cliquable visible (primary @ 0.7, 12px W500)

### Scénario 2 — Digest tap chevron révèle l'analyse
**Parcours** :
1. Depuis l'état précédent, taper sur "Lire l'analyse"

**Résultat attendu** :
- Texte d'analyse complet révélé (line-height 1.4 vs 1.5 avant — plus compact)
- CTA inline `Voir les N perspectives →` aligné droite (sans pill, primary @ 0.7, 11px W500)
- Plus de pile de logos sources (supprimée — épuration A3.b)
- Tap sur le texte le replie

### Scénario 3 — Pas de recul (B1.a + B2.c)
**Parcours** :
1. Toujours dans le topic editorial expanded, observer la sous-carte "🔭 Prendre du recul"

**Résultat attendu** :
- Background **bleu très clair** `colors.info @ 0.05` (ou 0.10 dark)
- Border 1px tout autour `colors.info @ 0.15` (plus de border-left épaisse)
- Padding interne **10px** (vs 12 avant)
- Tap → ouvre l'article (animation InkWell, plus FacteurCard bounce)

### Scénario 4 — Page indicator dots discrets (cohérence cross-app)
**Parcours** :
1. Sur le carousel d'un topic editorial expanded (digest), observer les dots
2. Aller sur `/feed`, observer les dots des carousels topiques
3. Aller sur la section community, observer les dots du carousel

**Résultat attendu sur les 3 écrans** :
- Dot actif : **16×6** (vs 24×10 avant) — `colors.primary` (digest, feed) ou `sunflowerYellow` (community)
- Dot inactif : **6×6** (vs 10×10 avant) — opacity **0.2** (vs 0.3 avant)
- Border-radius 3 (cohérent)

### Scénario 5 — Wrapper expanded compacté (C1.a)
**Parcours** :
1. Topic editorial expanded — vérifier l'espacement vertical

**Résultat attendu** :
- Espacements `SizedBox(height: 6)` au lieu de 8 entre carousel/dots/sous-cartes/feedback
- Sensation : ~80-110px gagnés sur l'ensemble

### Scénario 6 — Edge cases
- Topic avec **1 source** seule (pas de divergence) : CTA "Voir les N perspectives →" doit être absent même quand l'analyse est dépliée
- Topic **sans onCompare callback** : pas de CTA même déplié
- Topic **sans introText** dans Pas de recul : juste title + thumbnail + arrow (compact)

## Critères d'acceptation

- [ ] Sous-carte analyse rendue avec background neutre `colors.surface` + border subtle
- [ ] Tooltip ⓘ supprimé du header analyse
- [ ] DivergenceChip et bias bar conservés
- [ ] Bias bar labels en 8px
- [ ] Analyse repliée par défaut, chevron "Lire l'analyse" visible
- [ ] Tap chevron → texte révélé + CTA "Voir les N perspectives →" inline droite
- [ ] Pas de recul fond bleu très clair, border 1px, padding 10
- [ ] Page indicators 16×6/6×6/0.2 sur **3 carousels** (digest, feed, community)
- [ ] Aucune régression visuelle sur le mode dark
- [ ] Aucune régression sur les tests existants (suite mobile)

## Zones de risque

- **E1.b changement comportemental** : analyse repliée par défaut. Vérifier que l'utilisateur retrouve facilement l'info au tap. Si confusion, retour possible sur le pattern "3 lignes ellipsis + Lire la suite" (commit révert ciblé).
- **Dissymétrie A1.a (analyse neutre) vs B1.a (recul tinted bleu)** : assumé. Si visuellement étrange, fallback = passer le recul aussi sur surface neutre.
- **Mode dark** : `colors.surface` = #1C1C1C (sombre) ; `colors.info @ 0.10` (dark) testé via fallback. À vérifier visuellement.
- **Animation tap** : Pas de recul perd l'animation bounce de FacteurCard (remplacée par InkWell ripple). Si jugé trop neutre, possibilité de wrapper dans FacteurCard.

## Dépendances

Aucune. 100% changements front (Flutter widgets), pas d'impact API/DB/services.

## Fichiers modifiés (phase 2 uniquement)

```
apps/mobile/lib/features/digest/widgets/divergence_analysis_block.dart    # refonte complète
apps/mobile/lib/features/digest/widgets/pas_de_recul_block.dart           # bg + border + padding
apps/mobile/lib/features/digest/widgets/bias_spectrum_bar.dart            # labels 9→8
apps/mobile/lib/features/digest/widgets/topic_section.dart                # spacing 8→6 + indicator
apps/mobile/lib/features/digest/widgets/community_carousel_section.dart   # indicator dimensions
apps/mobile/lib/features/feed/widgets/feed_carousel.dart                  # indicator dimensions
apps/mobile/test/features/digest/widgets/divergence_analysis_block_test.dart  # E1.b tests
apps/mobile/test/features/digest/widgets/pas_de_recul_block_test.dart        # FacteurCard → InkWell
```

## Tests automatisés

- `flutter analyze` : 0 erreur (warnings info préexistants uniquement)
- `flutter test` ciblés : 17/17 passent (divergence + pas_de_recul)
- `flutter test` complet : 275 passent / 35 échecs **tous préexistants** (validés via stash)

## Ressources de référence

- Document de propositions : `.context/digest-ui-polish-phase2-proposals.md`
- Plan d'implémentation : `~/.claude/plans/hazy-humming-shannon.md`
- Captures avant : `/tmp/attachments/image-v2.png`, `/tmp/attachments/image-v3.png`
