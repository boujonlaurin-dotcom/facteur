# Plan d'implémentation — Digest Éditorialisé

**Version:** 1.0
**Date:** 10 mars 2026
**Statut:** Prêt pour exécution par agent dev
**Réf :** [Epic 10 Phase 5](../../stories/core/10.digest-central/epic-10-digest-central.md) · [Design docs](./README.md)

---

## Vue d'ensemble des étapes

```
ÉTAPE 1 ─ Sources deep (backend data)
ÉTAPE 2 ─ Pipeline curation LLM (backend service)
ÉTAPE 3 ─ Pipeline rédaction LLM (backend service)
ÉTAPE 4 ─ Format editorial_v1 + endpoint (backend API + modèles)
  ── TEST A ── Validation pipeline end-to-end (CLI/curl) ──
ÉTAPE 5 ─ Modèles Dart + provider (frontend data)
ÉTAPE 6 ─ Layout éditorial + widgets (frontend UI)
ÉTAPE 7 ─ Cartes, badges, ArticlePairView (frontend UI)
ÉTAPE 8 ─ Closure inline + feedback (frontend UI)
  ── TEST B ── Validation intégration complète (app) ──
ÉTAPE 9 ─ Mode serein (pipeline + frontend)
  ── TEST C ── Validation is_serene + ton serein ──
```

---

## ÉTAPE 1 — Sources deep (Story 10.22)

**Objectif :** Intégrer ~20 sources "deep" dans l'infra existante pour alimenter le matching "pas de recul".

**Tâches :**
1. Ajouter champ `source_tier` (String, default "mainstream") au modèle `Source` (`packages/api/app/models/source.py`)
2. Créer migration Alembic pour `ALTER TABLE source ADD COLUMN source_tier VARCHAR(20) DEFAULT 'mainstream'`
3. Ajouter les ~20 sources deep dans `sources/sources_master.csv` avec `Status: CURATED`, `source_tier: deep`
4. Vérifier les feed URLs RSS de chaque source deep (existence, parsing OK)
5. Mettre à jour le script d'import pour supporter le champ `source_tier`
6. Adapter le job de purge pour ne pas supprimer les articles des sources `source_tier = "deep"` (rétention longue)

**Fichiers :** `models/source.py`, `alembic/versions/`, `sources/sources_master.csv`, script d'import, job de purge
**Critère de validation :** `SELECT count(*) FROM source WHERE source_tier = 'deep'` → ~20 ; `SyncService` synchronise les nouvelles sources sans erreur.

---

## ÉTAPE 2 — Pipeline curation LLM (Story 10.23)

**Objectif :** Créer le service qui détecte les sujets chauds, sélectionne 3 sujets via LLM, et matche actu + deep.

**Tâches :**
1. Créer `packages/api/app/services/editorial_pipeline.py` — orchestrateur principal
2. Réutiliser `ImportanceDetector.build_topic_clusters()` pour la détection sujets chauds (étape 1 pipeline)
3. Implémenter l'appel LLM curation : envoyer les N clusters, recevoir 3 sujets + `deep_angle` (étape 2 pipeline)
4. Implémenter le matching actu (étape 3A) : pour chaque sujet, chercher dans les sources user, fallback mainstream
5. Implémenter le matching deep (étape 3B) : pré-filtre par embedding/keyword sur sources `source_tier = "deep"`, puis évaluation LLM
6. Créer `packages/api/config/editorial_prompts.yaml` avec les prompts de curation et matching configurables
7. Créer `packages/api/config/editorial_config.yaml` avec les paramètres pipeline (subjects_count, deep_candidates_prefilter, etc.)

**Fichiers :** nouveau `services/editorial_pipeline.py`, `config/editorial_prompts.yaml`, `config/editorial_config.yaml`
**Critère de validation :** appel CLI/test qui produit 3 sujets avec actu + deep matchés pour un user donné.

---

## ÉTAPE 3 — Pipeline rédaction LLM (Story 10.24)

**Objectif :** Générer les textes éditoriaux (intros, transitions, closure) via LLM.

**Tâches :**
1. Ajouter au `editorial_pipeline.py` l'étape de rédaction (étape 4 pipeline)
2. Implémenter l'appel LLM rédaction avec le prompt complet (voir [02-editorial.md](02-editorial.md) §6.1)
3. Implémenter la sélection pépite (étape 5 — slot 4) : LLM choisit 1 article surprenant hors sujets chauds
4. Implémenter le coup de cœur (étape 5 — slot 5) : query top (likes + saves) 48h, fallback 2e pépite
5. Ajouter les prompts de rédaction et pépite dans `editorial_prompts.yaml`

**Fichiers :** `services/editorial_pipeline.py`, `config/editorial_prompts.yaml`
**Critère de validation :** la pipeline complète produit un JSON avec header_text, 3 subjects (intro_text, transition_text, actu, deep), pepite, coup_de_coeur, closure_text.

---

## ÉTAPE 4 — Format editorial_v1 + endpoint (Story 10.25)

**Objectif :** Stocker le digest éditorial et l'exposer via l'API existante.

**Tâches :**
1. Définir le schema Pydantic `EditorialDigestResponse` dans `packages/api/app/schemas/digest.py`
2. Adapter `DigestService.get_or_create_digest()` pour appeler la pipeline éditoriale quand le mode le requiert
3. Adapter `GET /api/digest` pour renvoyer le format `editorial_v1` quand le digest est éditorial
4. Stocker dans `DailyDigest.items` (JSONB) avec `format_version = "editorial_v1"`
5. Adapter `DigestGenerationJob` pour utiliser la pipeline éditoriale dans le batch

**Fichiers :** `schemas/digest.py`, `services/digest_service.py`, `routers/digest.py`, `jobs/digest_generation_job.py`
**Critère de validation :** `curl /api/digest` retourne un JSON editorial_v1 complet avec textes édito.

---

## 🧪 TEST A — Validation pipeline end-to-end

**Avant de toucher au frontend.** Valider que la pipeline backend produit des digests éditoriaux corrects.

**Tests :**
1. Générer un digest éditorial pour un user test → vérifier structure JSON complète
2. Vérifier que les articles actu viennent bien des sources user (ou fallback)
3. Vérifier que les articles deep viennent des sources `source_tier = "deep"`
4. Vérifier les textes édito : ton, longueur, structure (header, intros, transitions, closure)
5. Vérifier la dégradation gracieuse : sujet sans deep → pas de `deep_article` dans le JSON
6. Vérifier le fallback LLM indisponible → digest topics_v1 classique

**Ajustements attendus :**
- Itérer sur les prompts de curation et rédaction (via YAML, sans code)
- Valider le hit rate deep (combien de sujets trouvent un deep pertinent ?)
- Affiner les critères `is_paid` sur les nouvelles sources

---

## ÉTAPE 5 — Modèles Dart + provider (Story 10.25 frontend)

**Objectif :** Le frontend parse et expose le nouveau format.

**Tâches :**
1. Ajouter les modèles `EditorialSubject`, `EditorialSlot` dans `digest/models/digest_models.dart`
2. Étendre `DigestResponse` pour supporter `editorial_v1` (champs headerText, subjects, closureText, ctaText, pepite, coupDeCoeur)
3. Adapter `DigestProvider` pour parser le format `editorial_v1`
4. Retirer le mode `perspective` de `DigestMode` (D2, D10)
5. Run `dart run build_runner build --delete-conflicting-outputs`

**Fichiers :** `digest/models/digest_models.dart`, `digest/models/digest_mode.dart`, `digest/providers/digest_provider.dart`
**Critère de validation :** le provider charge un digest editorial_v1 sans erreur et expose les données correctement.

---

## ÉTAPE 6 — Layout éditorial + widgets texte (Story 10.26)

**Objectif :** Afficher le digest éditorial avec le nouveau layout (éditos, transitions, header dynamique).

**Tâches :**
1. Créer `IntroText` widget (N1) — texte éditorial 2-3 phrases
2. Créer `TransitionText` widget (N2) — liaison entre sujets
3. Créer `SectionDivider` widget (N4) — "Et aussi…"
4. Modifier `DigestBriefingSection` : branchement `editorial_v1` (D3), header dynamique `headerText` (D1)
5. Créer le conteneur `EditorialSubjectBlock` qui assemble IntroText + cartes + TransitionText
6. Ajuster le mode selector à 2 modes (D2)
7. Simplifier la progression (D6) — dots discrets au lieu de barre segmentée

**Fichiers :** nouveaux widgets dans `digest/widgets/`, modification `digest_briefing_section.dart`
**Critère de validation :** le digest s'affiche avec les textes édito entre les cartes, header dynamique, transitions. Les cartes sont encore dans le format existant (badges mis à jour à l'étape suivante).

---

## ÉTAPE 7 — Cartes, badges, ArticlePairView (Story 10.27)

**Objectif :** Les cartes articles utilisent les badges sémantiques et le swipe actu/deep fonctionne.

**Tâches :**
1. Créer `ArticleBadge` widget — 4 badges fixes (🔴 🔭 🍀 💚) avec couleurs design system
2. Modifier `DigestCard` : remplacer le reason badge par `ArticleBadge` (D4), retirer rank badge (D5)
3. Créer `ArticlePairView` (N3) — PageView horizontal actu/deep, basé sur TopicSection existant
4. Créer `PepiteBlock` (N5) — mini-édito + carte 🍀
5. Créer `CoupDeCoeurBlock` (N5) — carte 💚 + "Gardé par N lecteurs"
6. Tester le conflit de gestes : swipe horizontal (PageView) vs swipe droit (SwipeToOpenCard)

**Fichiers :** nouveaux widgets, modification `digest_card.dart`
**Critère de validation :** swipe entre actu et deep fonctionne, badges affichés, pépite et coup de cœur visibles.

---

## ÉTAPE 8 — Closure inline + feedback (Story 10.28)

**Objectif :** La closure est un bloc inline en fin de digest avec CTA feedback.

**Tâches :**
1. Créer `ClosureBlock` widget — texte closure + CTA + bouton feedback
2. Créer `FeedbackBottomSheet` (N6) — 3 emojis + TextField optionnel + envoi
3. Modifier le flow de completion dans `DigestProvider` : ne plus naviguer vers écran closure séparé en mode editorial_v1 (D7)
4. Stocker le feedback localement (ou endpoint dédié si dispo)

**Fichiers :** nouveaux widgets, modification `digest_provider.dart`
**Critère de validation :** la closure s'affiche inline, le bottom sheet feedback s'ouvre et permet de soumettre.

---

## 🧪 TEST B — Validation intégration complète

**Test end-to-end sur l'app.**

1. Ouvrir l'app → le digest editorial s'affiche avec header dynamique
2. Scroller → les 3 sujets avec éditos et transitions sont lisibles
3. Swiper horizontalement sur un sujet → passage de l'actu au deep (et retour)
4. Tap sur une carte → ouvre l'article
5. Swipe droit → ouvre l'article (pas de conflit avec le PageView horizontal)
6. Voir la pépite et le coup de cœur en fin de digest
7. Atteindre la closure → texte éditorial + CTA
8. Tap "Donner un retour" → bottom sheet feedback fonctionnel
9. Vérifier qu'un digest sans deep pour certains sujets s'affiche correctement (dégradation)

**Ajustements attendus :**
- Calibration du conflit de gestes swipe horizontal / SwipeToOpenCard
- Ajustements visuels (spacing, typo, couleurs badges) après review visuelle
- Ajustement du completionThreshold (combien d'articles sur 5-8 pour valider ?)

---

## ÉTAPE 9 — Mode serein (transversal)

**Objectif :** Le mode serein fonctionne sur toute la chaîne.

**Tâches :**
1. Backend : ajouter le prompt serein dans `editorial_prompts.yaml` (variante ton calme)
2. Backend : filtrer les candidats actu et deep avec `is_serene = true` quand mode serein actif
3. Backend : si deep ne passe pas `is_serene` → ne pas inclure de deep pour ce sujet
4. Frontend : masquer les emojis 🔴 et 🔭 des badges en mode serein (juste le texte)
5. Frontend : le gradient container utilise les couleurs serein existantes (vert/lotus)

**Fichiers :** `editorial_pipeline.py`, `editorial_prompts.yaml`, `digest_card.dart` (badges), `digest_briefing_section.dart` (gradient)
**Critère de validation :** un digest serein n'a pas de contenu anxiogène, le ton est calme, les badges sont sans emoji rouge.

---

## 🧪 TEST C — Validation is_serene + ton serein

1. Générer un digest serein → vérifier que les sujets anxiogènes sont exclus
2. Vérifier le ton : pas de 🔴/🚨, formulations neutres, closure bienveillante
3. Vérifier que `is_serene` est fiable sur un échantillon de 50 articles récents
4. Si `is_serene` peu fiable → documenter les ajustements nécessaires (classification LLM ?)

---

## Résumé séquentiel

| Étape | Story | Type | Dépend de | Estimation |
|-------|-------|------|-----------|-----------|
| 1 | 10.22 | Backend | — | 3-4h |
| 2 | 10.23 | Backend | 1 | 6-8h |
| 3 | 10.24 | Backend | 2 | 4-5h |
| 4 | 10.25 | Backend | 3 | 3-4h |
| **TEST A** | — | QA | 4 | 2-3h |
| 5 | 10.25 | Frontend | 4 | 2-3h |
| 6 | 10.26 | Frontend | 5 | 4-5h |
| 7 | 10.27 | Frontend | 6 | 4-5h |
| 8 | 10.28 | Frontend | 7 | 3-4h |
| **TEST B** | — | QA | 8 | 3-4h |
| 9 | Transversal | Full-stack | 8 | 3-4h |
| **TEST C** | — | QA | 9 | 2h |

**Total estimé : ~40-50h**
