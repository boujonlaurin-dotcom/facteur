# État d'Avancement du MVP Facteur

**Date de mise à jour :** 15 février 2026
**Méthode :** Analyse des stories BMAD

---

## 📊 Vue d'ensemble

### Progression globale par Epic

| Epic | Stories | Complétées | En cours | Draft | Progression |
|------|---------|------------|----------|-------|-------------|
| **Epic 1 : Fondations & Infrastructure** | 5 | 4 | 0 | 1 | **80%** ✅ |
| **Epic 2 : Onboarding & Profil** | 8 | 8 | 0 | 0 | **100%** ✅ |
| **Epic 3 : Gestion des Sources** | 4 | 5 | 0 | 0 | **100%** ✅ |
| **Epic 4 : Feed & Algorithme** | 6 | 3 | 1 | 2 | **50%** 🚧 |
| **Epic 5 : Consommation & Gamification** | 4 | 0 | 0 | 4 | **0%** ⏳ |
| **Epic 6 : Premium & Paiement** | 0 | 0 | 0 | 0 | **0%** ❌ |
| **Epic 7 : Mise en perspective** | 5 | 2 | 0 | 3 | **40%** 🚧 |
| **Epic 10 : Digest Central** | 6 | 5 | 1 | 0 | **90%** ✅ |
| **Epic 11 : Personnalisation Avancée** | 4 | 2 | 1 | 1 | **50%** 🚧 |

**Total MVP :** 42 stories identifiées
**Complétées :** 28 stories (66.7%)
**En cours :** 3 stories (7.1%)
**Draft/Ready :** 11 stories (26.2%)

---

## ✅ Epic 1 : Fondations & Infrastructure (80%)

**Statut :** Presque complet, base solide établie

### Stories complétées
- ✅ **1.1** : Setup Flutter (structure, thème, navigation)
- ✅ **1.2** : Setup FastAPI + Supabase (API, workers, migrations)
- ✅ **1.3** : Authentification Supabase (email, Apple, Google)
- ✅ **1.4** : Navigation de base (go_router, bottom nav, redirects)

### Stories restantes
- ⏳ **1.5** : Auth Convenience (rester connecté, reset password) - **Draft**

**Impact :** L'infrastructure est opérationnelle. Story 1.5 est un confort, pas bloquante.

---

## ✅ Epic 2 : Onboarding & Profil (100%)

**Statut :** **COMPLET** - Toutes les stories implémentées

### Stories complétées
- ✅ **2.1** : Modèle de données Profil (tables, API, RLS)
- ✅ **2.2** : Onboarding Section 1 "Overview" (4 questions + réactions)
- ✅ **2.2b** : Onboarding Section 2 "App Preferences" (6 questions conditionnelles)
- ✅ **2.2c** : Onboarding Section 3 "Source Preferences" (thèmes, formats, sources)
- ✅ **2.2d** : Animation de conclusion (particules, messages progressifs)
- ✅ **2.3** : Sauvegarde profil après onboarding (API, retry, mode dégradé)
- ✅ **2.4** : Redirection vers Feed (WelcomeBanner animé)
- ✅ **2.5** : Bypass onboarding utilisateurs existants (cache local, redirect logic)

**Killer Feature identifiée :** 🎯 **Onboarding ludique et personnalisé**
- Questionnaire en 3 sections (10-12 questions)
- Réactions contextuelles après chaque réponse clé
- Animation de conclusion élégante
- Personnalisation dès le premier usage

---

## ✅ Epic 3 : Gestion des Sources (75%)

**Statut :** Fonctionnel, catalogue et sync opérationnels

### Stories complétées
- ✅ **3.1** : Modèle de données Sources & Contenus (tables, enums, RLS)
- ✅ **3.2** : Import catalogue de sources curées (24 sources, upsert, détection RSS)
- ✅ **3.3** : Service de synchronisation RSS (articles, podcasts, YouTube, toutes les 30min)
- ✅ **3.5** : Configuration des "Trusted Sources" (toggle sources du catalogue)
- ✅ **7.6** : Expansion de la Base de Sources Analysées (114+ sources candidates importées, filtrage "Ghost" implémenté)

### Stories manquantes
- ❌ **3.4** : Ajout de source personnalisée par URL (reporté V0)

**Killer Feature identifiée :** 🎯 **Catalogue curé de 24 sources de qualité**
- Sources triées par thème (Tech, Géopolitique, Économie, Société, Culture)
- Types variés : Articles, Podcasts, YouTube
- Sync automatique toutes les 30 minutes
- Sélection de "Sources de Confiance" pour personnalisation

---

## 🚧 Epic 4 : Feed & Algorithme (50%)

**Statut :** Partiellement implémenté, core fonctionnel

### Stories complétées
- ✅ **4.2** : Écran Feed principal (liste scrollable, pull-to-refresh, infinite scroll, états UI)
- ✅ **4.3** : Card de contenu (preview avec thumbnail, titre, source, actions)
- ✅ **4.6** : Filtres rapides (par type : Tous, À lire, À écouter, À voir)

### Stories en cours
- 🚧 **4.4** : Action "Sauvegarder pour plus tard" (backend fait, archive-on-save en cours)

### Stories prêtes/à faire
- ⏳ **4.1** : Algorithme de tri et personnalisation (Ready - scoring, diversité, pagination)
- ⏳ **4.5** : Action "Pas intéressé" (Draft - backend fait, UI à compléter)

**Killer Feature identifiée :** 🎯 **Feed personnalisé avec algorithme intelligent**
- Tri basé sur thèmes préférés, fraîcheur, type de contenu
- Exclusion automatique des contenus vus/masqués
- Diversité (évite la saturation d'une source)
- Pagination et infinite scroll fluides

---

## ⏳ Epic 5 : Consommation & Gamification (0%)

**Statut :** Non démarré, mais backend prêt

### Stories prêtes
- 🚧 **5.1** : Écran Détail Contenu (Core fait, support Vidéo robuste ajouté, reste Article Reader)
- ⏳ **5.3** : Tracking automatique "Contenu consommé" (Ready - API faite, WebView à intégrer)
- ⏳ **5.4** : Système de Streak quotidien (Ready - backend fait, UI à compléter)
- ⏳ **5.7** : Écran Sauvegardés (à faire - liste, tri, actions)

**Killer Feature identifiée :** 🎯 **Gamification avec Streak quotidien**
- Validation automatique si ≥1 contenu consommé/jour
- Affichage 🔥 X jours consécutifs
- Animation de progression
- Motivation à revenir chaque jour

---

## ❌ Epic 6 : Premium & Paiement (0%)

**Statut :** Non démarré

**Stories prévues (non créées) :**
- 6.1 : Intégration RevenueCat
- 6.2 : Logique Trial / Premium
- 6.3 : Écran Paywall
- 6.4 : Flow d'achat App Store
- 6.5 : Gestion de l'abonnement
- 6.6 : Comportement app selon statut

**Impact :** Bloquant pour le lancement commercial. MVP peut être testé sans paiement.

---

## 🚧 Epic 7 : Mise en perspective (40%)

**Statut :** Backend avancé, frontend à faire

### Stories complétées
- ✅ **7.1** : Profiling éditorial des sources (bias_stance, reliability_score)
- ✅ **7.2** : Clustering de "Stories" par similarité (pg_trgm, cluster_id)

### Stories à faire
- ⏳ **7.3** : API Perspectives (Draft - endpoint à créer)
- ⏳ **7.4** : CTA "Comparer les angles" dans le Header (Draft)
- ⏳ **7.5** : Bottom Sheet "Mise en Perspective" (Draft)

**Killer Feature identifiée :** 🎯 **Mise en perspective (Ground News style)**
- Regroupement automatique des articles similaires (clustering)
- Affichage du positionnement éditorial des sources
- Comparaison des angles éditoriaux sur un même sujet
- Lutte contre les bulles informationnelles

---

## ✅ Epic 10 : Digest Central (90%)

**Statut :** Core complet, polish en cours
**Pivot majeur :** Remplacement du feed infini par un digest quotidien de 5-7 articles curatés, créant un sentiment de "fini" (Slow Media).

### Stories complétées
- ✅ **10.1** : Modèle DailyDigest + DigestCompletion (JSONB items, completion tracking)
- ✅ **10.2** : DigestSelector — algorithme de sélection (scoring multi-facteurs, diversité source/thème, trending detection, fallback candidates)
- ✅ **10.3** : Endpoints Digest (GET /digest, POST /generate, POST /action, POST /complete)
- ✅ **10.4** : Job de génération batch (scheduler 8h Europe/Paris, global trending context, concurrency limité)
- ✅ **10.5** : Mobile — Écran Digest complet (cards, actions read/save/like/dismiss, progress bar, welcome modal, closure screen)

### Stories en cours
- 🚧 **10.6** : Polish UX — animations de transition, streak celebration, digest summary post-completion

### Architecture technique
- **Backend** : DigestService (989 lignes) orchestre sélection → stockage → réponse. DigestSelector (1250 lignes) gère scoring, diversité, trending.
- **Mobile** : Freezed models + Riverpod providers avec cache in-memory par jour.
- **Score Breakdown** : 8+ facteurs par article (récence, thème, source suivie, qualité, biais, sous-thèmes, trending, custom source). Transparence "pourquoi cet article ?".
- **Diversité** : Max 1 article/source, max 2 articles/thème, min 3 sources distinctes.
- **Fallback** : Emergency candidates si sélection standard échoue (sources suivies + curated).

**Killer Feature identifiée :** **Digest quotidien avec clôture** — 5-7 articles, sentiment de "fini" en 2-4 minutes.

---

## 🚧 Epic 11 : Personnalisation Avancée (50%)

**Statut :** Backend modes implémentés, mobile Tab Selector en cours
**Objectif :** 4 modes de digest configurables + feed filtré par thème.

### Stories complétées
- ✅ **11.1** : filter_presets.py — filtres partagés feed/digest (serein, theme_focus, perspective bias)
- ✅ **11.2** : Intégration modes dans DigestSelector (pour_vous, serein, perspective, theme_focus) + endpoint PUT /preferences + GET /top-themes

### Stories en cours
- 🚧 **11.3** : Mobile Tab Selector — pills horizontales en haut du digest, identité visuelle par mode (couleur, gradient, emoji, icône Phosphor), AnimatedContainer, régénération immédiate (POST /generate?mode=X&force=true)

### Stories à faire
- ⏳ **11.4** : Feed filtré par thème — chips thématiques ordonnées par UserInterest.weight DESC, filtrage côté API

### Modes de digest

| Mode | Comportement Backend | Identité Visuelle |
|------|---------------------|-------------------|
| **Pour vous** (défaut) | Scoring standard multi-facteurs | Terracotta, icône sparkle |
| **Serein** | Exclut thèmes anxiogènes (société, politique, économie, international) + mots-clés négatifs | Vert, icône leaf |
| **Changer de bord** | +80 pts pour articles de biais opposé au profil utilisateur | Bleu, icône scales |
| **Focus thématique** | Filtre sur un seul thème choisi par l'utilisateur | Violet, icône target |

**Architecture technique :**
- `filter_presets.py` centralise les filtres partagés entre feed et digest
- `calculate_user_bias()` détermine le biais politique de l'utilisateur à partir de ses sources suivies
- `get_opposing_biases()` retourne les biais opposés pour le mode Perspective
- Régénération on-demand : POST /api/digest/generate?mode=X&force=true déclenche une nouvelle sélection immédiate

---

## 🎯 Killer-Features identifiées

### 1. Onboarding ludique et personnalisé (✅ COMPLET)
**Valeur :** Personnalisation dès le premier usage, expérience engageante  
**Statut :** 100% implémenté  
**Impact :** Différenciation forte vs agrégateurs RSS classiques

### 2. Catalogue curé de sources de qualité (✅ COMPLET)
**Valeur :** 24 sources triées par thème, types variés  
**Statut :** 100% implémenté (import + sync)  
**Impact :** Pas de "cold start problem", contenu immédiat

### 3. Feed personnalisé avec algorithme intelligent (🚧 50%)
**Valeur :** Tri basé sur préférences, fraîcheur, diversité  
**Statut :** UI complète, algo backend Ready (à intégrer)  
**Impact :** Expérience de découverte fluide et pertinente

### 4. Gamification avec Streak quotidien (⏳ 0%)
**Valeur :** Motivation à revenir chaque jour, sentiment de progression  
**Statut :** Backend Ready, UI à compléter  
**Impact :** Rétention et engagement quotidien

### 5. Mise en perspective (Ground News style) (🚧 40%)
**Valeur :** Comparaison des angles éditoriaux, lutte contre les bulles
**Statut :** Backend avancé (profiling + clustering), UI à faire
**Impact :** Différenciation forte, positionnement "Slow Media" renforcé

### 6. Digest quotidien avec clôture (✅ 90%)
**Valeur :** 5-7 articles curatés, sentiment de "fini" en 2-4 minutes
**Statut :** Core complet (backend + mobile), polish UX en cours
**Impact :** Pivot Slow Media — remplace le feed infini par une expérience finie et satisfaisante

### 7. Modes de digest configurables (🚧 50%)
**Valeur :** 4 modes (Pour vous, Serein, Changer de bord, Focus thématique)
**Statut :** Backend complet, mobile Tab Selector en cours
**Impact :** Personnalisation profonde, chaque humeur a son digest

---

## 📈 État de maturité par composant

### Backend (FastAPI)
- ✅ **Infrastructure** : 100% (API, DB, Auth, Workers)
- ✅ **Onboarding** : 100% (profil, préférences, intérêts)
- ✅ **Sources** : 100% (catalogue, sync RSS, trusted sources)
- 🚧 **Feed** : 70% (algorithme Ready, endpoints à finaliser)
- ✅ **Digest** : 95% (sélection, scoring, diversité, actions, completion, batch job)
- ✅ **Modes Digest** : 90% (4 modes, filter_presets, regeneration on-demand)
- ✅ **Gamification** : 80% (streak backend fait, tracking consommation)
- ✅ **Perspectives** : 60% (profiling + clustering faits, API à créer)

### Frontend (Flutter)
- ✅ **Infrastructure** : 100% (navigation, auth, thème)
- ✅ **Onboarding** : 100% (3 sections, animations, sauvegarde)
- ✅ **Sources** : 100% (écran sources, trusted toggle)
- ✅ **Feed** : 80% (UI complète, algo à connecter)
- ✅ **Digest** : 85% (écran complet, cards, actions, closure, welcome modal, progress bar)
- 🚧 **Modes Digest** : 40% (Tab Selector en cours, mode switcher créé)
- 🚧 **Détail** : 50% (écran créé, player vidéo mobile/web implémenté, à finaliser : mode lecture article)
- ⏳ **Gamification** : 20% (streak indicator fait, animations à compléter)
- ⏳ **Perspectives** : 0% (UI à créer)

---

## 🚀 Prochaines étapes critiques pour MVP

### Priorité 1 : Finaliser le Digest (Epic 10 + 11)
1. **10.6** : Polish UX digest — animations, streak celebration, summary
2. **11.3** : Mobile Tab Selector — pills modes, identité visuelle, AnimatedContainer
3. **11.4** : Feed filtré par thème — chips ordonnées par UserInterest.weight

### Priorité 2 : Compléter le Feed Legacy (Epic 4)
1. **4.1** : Intégrer l'algorithme de tri (backend Ready → connecter au frontend)
2. **4.4** : Finaliser "Sauvegarder" avec archive-on-save
3. **4.5** : Compléter "Pas intéressé" (UI bottom sheet)

### Priorité 3 : Consommation de contenu (Epic 5)
1. **5.1** : Finaliser l'écran Détail Contenu (mode lecture article)
2. **5.3** : Intégrer WebView avec tracking automatique
3. **5.7** : Créer l'écran Sauvegardés

### Priorité 4 : Premium (Epic 6) - Bloquant pour lancement
1. **6.1-6.6** : Intégration RevenueCat, trial, paywall

### Priorité 5 : Perspectives (Epic 7) - Nice-to-have MVP
1. **7.3-7.5** : API + UI perspectives (peut être reporté V1)

---

## 📊 Métriques de progression

### MVP Core (sans Premium)
- **Complétion :** ~75%
- **Blocages :** Aucun majeur
- **Avancement clé :** Digest Central (Epic 10) quasi-complet, modes digest (Epic 11) en cours

### MVP Complet (avec Premium)
- **Complétion :** ~65%
- **Blocages :** Epic 6 non démarré
- **Avancement clé :** Pivot Digest-First réussi, feed legacy relégué à "Explorer plus"

### Epic 8 : Progression & Stabilisation
- **Statut :** Mobile 95%, Backend 100% (Stabilisation effectuée)
- **Résolution :** Port standardisé à 8080. Optimisation des pools de connexion DB et redirection active des slashes.
- ✅ **8.0** : Stabilisation Backend (Concurrence sync RSS limitée à 5, import optimisé avec fallbacks pour médias français, fix httpx leakage).

---

## 💡 Points forts du projet

1. **Pivot Digest-First réussi** : Core digest complet (sélection, scoring, diversité, actions, completion)
2. **Architecture solide** : Backend et frontend bien structurés, services modulaires
3. **Onboarding exceptionnel** : Expérience ludique et personnalisée complète
4. **Infrastructure robuste** : Sync RSS automatique, catalogue curé, batch job digest
5. **Personnalisation avancée** : 4 modes de digest, filter_presets partagés feed/digest
6. **Innovation perspectives** : Backend avancé pour différenciation

## ⚠️ Points d'attention

1. **Premium non démarré** : Bloquant pour monétisation
2. **Tab Selector mobile** : UI modes digest à finaliser (Epic 11.3)
3. **Feed thème mobile** : Chips thématiques pas encore implémentées (Epic 11.4)
4. **Consommation de contenu** : Mode lecture article à finaliser
5. **Perspectives UI** : Backend avancé mais frontend à faire

---

*Document généré via analyse des stories BMAD - Facteur MVP*
*Dernière MAJ: 2026-02-15*
