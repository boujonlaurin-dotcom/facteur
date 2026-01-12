# Facteur — Product Requirements Document (PRD)

**Version:** 1.0  
**Date:** 7 janvier 2026  
**Auteur:** BMad Method  
**Statut:** Validé

---

## Change Log

| Date | Version | Description | Auteur |
|------|---------|-------------|--------|
| 07/01/2026 | 1.0 | Création initiale | BMad Method |
| 12/01/2026 | 1.1 | Mise à jour Algorithme V2 & Transparence | Antigravity |

---

## Goals

- Permettre aux utilisateurs de connecter des sources variées (RSS, podcasts, YouTube)
- Filtrer et prioriser automatiquement les contenus selon le profil utilisateur
- Créer une expérience d'onboarding ludique qui personnalise dès le premier usage
- Proposer une sélection curée de sources de qualité (catalogue de 24 sources)
- Monétiser via un modèle premium simple dès le lancement (trial 7 jours puis paywall)
- Valider l'hypothèse : "Les gens paieront pour une UX fluide de consommation d'info"
- Lutter contre les bulles informationnelles via une fonctionnalité de "mise en perspective" (Ground News style)
- Garantir la qualité via le FQS (Facteur Quality Score) : Scoring objectif des sources sur l'indépendance, la rigueur et l'expérience utilisateur (paywalls).
- Maintenir une pluralité d'opinions : Équilibrer le catalogue avec des sources de bords politiques variés (Gauche, Libéral, Conservateur) de haute tenue.

---

## Background Context

**Facteur** répond à un problème croissant : la surcharge informationnelle. Les utilisateurs sont submergés par des dizaines de sources (newsletters, podcasts, chaînes YouTube, articles), sans savoir distinguer l'important du bruit. Les algorithmes des réseaux sociaux optimisent l'engagement plutôt que la valeur, créant un "flou mental" post-scrolling et enfermant les utilisateurs dans des bulles informationnelles.

Les solutions existantes (agrégateurs RSS, apps de news) échouent soit par manque de personnalisation, soit par opacité algorithmique. Facteur se positionne comme un **middleware de consommation intentionnelle** — un filtre intelligent entre les sources de confiance de l'utilisateur et sa consommation quotidienne, avec une philosophie "Slow Media" : apprendre par morceaux sur le long terme, pas suivre l'actu éphémère.

---

## Functional Requirements

| ID | Exigence |
|----|----------|
| **FR1** | L'utilisateur peut créer un compte via email ou connexion sociale (Apple, Google) |
| **FR1bis** | L'utilisateur peut réinitialiser son mot de passe en cas d'oubli |
| **FR1ter** | L'utilisateur peut choisir de rester connecté entre les sessions |
| **FR2** | L'utilisateur complète un questionnaire d'onboarding de 10-12 questions réparties en 3 sections pour définir son profil et ses préférences |
| **FR3** | Le système propose automatiquement des contenus personnalisés depuis un catalogue de sources curées |
| **FR4** | L'utilisateur peut ajouter des sources personnalisées via URL (flux RSS, podcast, chaîne YouTube) |
| **FR5** | Le système détecte automatiquement le type de source (RSS article, RSS podcast, RSS YouTube) |
| **FR6** | Le système agrège et synchronise les contenus de toutes les sources toutes les 30 minutes |
| **FR7** | L'algorithme trie et priorise les contenus selon le profil utilisateur (moteur modulaire V2 : thèmes, feedback comportemental, préférences statiques) |
| **FR8** | L'utilisateur voit un feed personnalisé avec preview de chaque contenu (thumbnail, titre, source, raison de recommandation, durée) |
| **FR9** | L'utilisateur peut cliquer sur un contenu pour voir un écran détail enrichi avant redirect |
| **FR10** | Le système marque automatiquement un contenu comme "consommé" après un temps suffisant (~30s article, ~60s vidéo/podcast) |
| **FR10bis** | Le système affiche un streak quotidien pour encourager l'habitude (si gamification activée) |
| **FR10ter** | Le système affiche une barre de progression hebdomadaire (si gamification activée) |
| **FR11** | L'utilisateur peut ajouter un contenu à sa liste "À consulter plus tard", ce qui l'archive automatiquement du feed principal (triage) |
| **FR12** | L'utilisateur peut indiquer "pas intéressé" pour masquer un contenu et affiner l'algo |
| **FR13** | L'utilisateur peut gérer ses sources personnalisées (ajouter, supprimer, voir la liste) |
| **FR14** | L'utilisateur peut souscrire à un abonnement premium via l'App Store (iOS) |
| **FR15** | L'utilisateur peut gérer son abonnement (voir statut, gérer via iOS) |
| **FR16** | L'utilisateur peut modifier son profil et ses préférences |
| **FR17** | Après 7 jours de trial, l'accès est bloqué sans abonnement (paywall obligatoire) |
| **FR18** | L'utilisateur peut accéder à d'autres points de vue sur une même actualité depuis l'écran détail |
| **FR19** | Le système regroupe automatiquement les articles similaires par "Story" (clustering) |
| **FR20** | Le système affiche le positionnement éditorial (biais) des sources via une échelle visuelle |

---

## Non-Functional Requirements

| ID | Exigence |
|----|----------|
| **NFR1** | Le feed doit charger en moins de 2 secondes |
| **NFR2** | Le scroll du feed doit être fluide à 60fps |
| **NFR3** | L'app doit fonctionner sur iOS 15+ |
| **NFR4** | L'app doit respecter le RGPD (consentement, droit à l'oubli, export données) |
| **NFR5** | Les données utilisateur doivent être chiffrées en transit (HTTPS) et au repos |
| **NFR6** | L'authentification doit utiliser des standards sécurisés (OAuth 2.0, JWT) |
| **NFR7** | Le système doit supporter au moins 1000 utilisateurs simultanés pour le MVP |
| **NFR8** | Les sources doivent être synchronisées au moins toutes les 30 minutes |
| **NFR9** | L'app doit fonctionner en mode hors-ligne avec les contenus déjà chargés |
| **NFR10** | Le code doit être cross-platform (Flutter) pour faciliter le portage Android |

---

## User Interface Design Goals

### Overall UX Vision

> **Facteur doit offrir une expérience de "clarté apaisante"** — l'opposé du chaos des réseaux sociaux. L'utilisateur doit ressentir qu'il progresse et apprend, pas qu'il "scrolle dans le vide".

**Principes directeurs :**
- **Minimalisme intentionnel** : Peu d'éléments, chacun a un but clair
- **Progression visible** : L'utilisateur voit qu'il avance (streak, barre)
- **Finitude** : Sentiment de "j'ai fini pour aujourd'hui" possible (≠ scroll infini)
- **Fluidité** : Transitions douces, pas de friction

**Inspirations UX :** Deepstash (fluidité), Superhuman (clarté), Duolingo (gamification)

### Key Interaction Paradigms

| Interaction | Comportement |
|-------------|--------------|
| **Scroll vertical** | Navigation dans le feed principal |
| **Tap sur card** | Ouvre l'écran détail |
| **Tap sur bookmark** | Ajouter à la liste "À consulter plus tard" et retirer du feed principal (triage) |
| **Menu "..."** | Actions secondaires (pas intéressé, voir source) |
| **Pull to refresh** | Actualiser le feed |

### Core Screens

| # | Écran | Description |
|---|-------|-------------|
| 1 | **Onboarding** | Questionnaire 10-12 questions en 3 sections + animation finale |
| 2 | **Feed principal** | Liste de contenus personnalisés avec preview cards |
| 3 | **Détail contenu** | Preview enrichi avant redirect |
| 4 | **À consulter plus tard** | Liste des contenus mis de côté |
| 5 | **Progression** | Streak + barre hebdo + stats |
| 6 | **Mes sources** | Gestion des sources custom |
| 7 | **Profil / Settings** | Paramètres compte, préférences, abonnement |
| 8 | **Paywall** | Écran de conversion premium |

### Branding

| Aspect | Direction |
|--------|-----------|
| **Crédibilité** | Inspiration Le Monde — sérieux, typographie éditoriale |
| **Accessibilité** | Inspiration Notion — simplicité, clarté |
| **Chaleur** | Touche humaine du facteur — couleurs chaudes en accent |
| **Thème** | **Sombre par défaut** |

**Palette (dark mode) :**
- Fond : #121212 / #1A1A1A
- Cards : #1E1E1E / #252525
- Texte : #F5F5F5
- Accent chaud : Terracotta #E07A5F
- Accent secondaire : Bleu #6B9AC4

### Accessibility

Niveau cible : **WCAG AA**

### Target Platforms

- **MVP** : iOS (iPhone) uniquement
- **V1** : Android

---

## Technical Assumptions

### Stack Technique

| Composant | Technologie |
|-----------|-------------|
| **Mobile App** | Flutter |
| **Backend API** | Python + FastAPI |
| **Database** | PostgreSQL (via Supabase) |
| **Auth** | Supabase Auth |
| **Paiements** | RevenueCat |
| **Hosting** | Railway / Render |

### Repository Structure

**Monorepo**

```
facteur/
├── apps/
│   └── mobile/          # App Flutter
├── packages/
│   └── api/             # Backend FastAPI
├── docs/                # Documentation
└── shared/              # Types partagés
```

### Service Architecture

**Monolithe simple**

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Mobile App │────▶│  REST API   │────▶│ PostgreSQL  │
└─────────────┘     └─────────────┘     └─────────────┘
                           │
                    ┌──────┴──────┐
                    ▼             ▼
              ┌──────────┐  ┌──────────┐
              │ RSS      │  │ RevenueCat│
              │ Fetcher  │  │ (Paiements)│
              └──────────┘  └──────────┘
```

### Testing Requirements

| Type | Scope | Couverture cible |
|------|-------|------------------|
| Unit tests | Logique métier, algo | >60% |
| Integration tests | API endpoints | Flows critiques |
| E2E | ❌ Hors scope MVP | V1 |

### Additional Technical Assumptions

- RSS Parsing : librairie robuste (feedparser Python)
- YouTube RSS : `https://www.youtube.com/feeds/videos.xml?channel_id=CHANNEL_ID`
- Refresh strategy : Cron job toutes les 30 min
- Error tracking : Sentry
- Logging : Structured JSON

---

## Epic List

| # | Epic | Objectif | Stories |
|---|------|----------|---------|
| 1 | Fondations & Infrastructure | Setup Flutter + FastAPI + Supabase, auth, navigation | 5 |
| 2 | Onboarding & Profil | Questionnaire ludique 3 sections, profil utilisateur | 8 |
| 3 | Gestion des Sources | Catalogue curé, sync RSS, sources custom | 5 |
| 4 | Feed & Algorithme | Algo de tri, feed personnalisé, actions | 6 |
| 5 | Consommation & Gamification | Détail, tracking auto, streak, progression | 7 |
| 6 | Premium & Paiement | RevenueCat, trial, paywall, abonnement | 6 |
| 7 | Mise en perspective | Clustering de stories et profiling de sources (Ground News style) | 5 |

**Total : 36 stories**

---

## Epic 1 : Fondations & Infrastructure

**Objectif :** Setup projet Flutter + FastAPI + Supabase, authentification, écran de base.

### Story 1.1 : Setup projet Flutter

**As a** développeur,  
**I want** un projet Flutter initialisé avec la structure de base,  
**so that** je puisse commencer le développement mobile.

**Acceptance Criteria :**
1. Projet Flutter créé avec la dernière version stable
2. Structure de dossiers organisée (lib/screens, lib/widgets, lib/services, lib/models)
3. Thème sombre configuré avec la palette définie (fond #121212, accent terracotta)
4. Linter configuré (flutter_lints)
5. Le projet compile et s'exécute sur simulateur iOS

---

### Story 1.2 : Setup backend FastAPI + Supabase

**As a** développeur,  
**I want** un backend FastAPI connecté à Supabase,  
**so that** l'app puisse stocker et récupérer des données.

**Acceptance Criteria :**
1. Projet FastAPI initialisé avec structure de base (routers, models, services)
2. Connexion à Supabase PostgreSQL fonctionnelle
3. Route health-check `/api/health` retourne `{"status": "ok"}`
4. Variables d'environnement configurées (.env)
5. Documentation API auto-générée (Swagger UI)

---

### Story 1.3 : Authentification Supabase

**As a** utilisateur,  
**I want** créer un compte et me connecter via email ou Apple/Google,  
**so that** mes données soient sauvegardées et sécurisées.

**Acceptance Criteria :**
1. Supabase Auth configuré avec providers Email, Apple, Google
2. Écran de connexion Flutter avec options Email + Social
3. Flow de création de compte email (email + password)
4. Flow de connexion sociale (Apple Sign-In, Google Sign-In)
5. Token JWT stocké de manière sécurisée sur le device
6. Déconnexion fonctionnelle
7. L'utilisateur authentifié est créé dans la table `users` Supabase

---

### Story 1.4 : Navigation de base et écran Home placeholder

**As a** utilisateur,  
**I want** voir un écran d'accueil après connexion,  
**so that** je sache que l'app fonctionne.

**Acceptance Criteria :**
1. Navigation configurée (go_router ou auto_route)
2. Écran Home placeholder affichant "Bienvenue [email]"
3. Bouton de déconnexion fonctionnel
4. Redirection automatique vers Login si non authentifié
5. Redirection automatique vers Home si déjà authentifié

---

### Story 1.5 : Fonctionnalités de confort d'authentification

**As a** utilisateur,  
**I want** rester connecté et pouvoir réinitialiser mon mot de passe en cas d'oubli,  
**so that** je gagne du temps et ne perde pas l'accès à mon compte.

**Acceptance Criteria :**
1. Checkbox "Rester connecté" sur l'écran de login
2. Lien "Mot de passe oublié ?" menant à un flow de récupération par email
3. Intégration avec Supabase Auth pour le reset
4. Persistance de session gérée selon le choix utilisateur


## Epic 2 : Onboarding & Profil Utilisateur

**Objectif :** Créer une expérience d'onboarding ludique (10-12 questions, 3 sections) qui collecte les préférences et personnalise l'expérience.

### Story 2.1 : Modèle de données Profil Utilisateur

**As a** développeur,  
**I want** un modèle de données pour stocker le profil et les préférences utilisateur,  
**so that** l'algorithme puisse personnaliser le contenu.

**Acceptance Criteria :**
1. Table `user_profiles` créée : user_id, display_name, age_range, gender, created_at, onboarding_completed
2. Table `user_preferences` créée : user_id, preference_key, preference_value
3. Table `user_interests` créée : user_id, interest_slug, weight
4. API endpoints CRUD pour le profil utilisateur
5. Row Level Security (RLS) configuré

---

### Story 2.2 : Onboarding Section 1 "Overview"

**As a** nouvel utilisateur,  
**I want** répondre à des questions sur mes grands objectifs,  
**so that** Facteur comprenne pourquoi je suis là.

**Acceptance Criteria :**
1. 3-4 écrans couvrant : objectifs avec Facteur, âge, genre, préférence d'approche
2. Réactions engageantes après chaque réponse clé expliquant la philosophie Facteur
3. UI ludique avec illustrations/animations légères
4. Indicateur de progression visible (section 1/3)
5. Réponses stockées localement pendant le flow

---

### Story 2.2b : Onboarding Section 2 "App Preferences"

**As a** nouvel utilisateur,  
**I want** définir mes préférences d'usage de façon indirecte,  
**so that** l'app s'adapte à ma façon de consommer l'info.

**Acceptance Criteria :**
1. 4-5 écrans avec questions indirectes :
   - Big-picture vs Detail-oriented
   - Préférence réponses tranchées vs nuancées
   - Actu récente vs Analyses long-terme
   - Activation ou non de la gamification
2. Questions formulées de façon engageante (choix visuels, mini-scénarios)
3. Réactions contextuelles après certaines réponses
4. Indicateur de progression (section 2/3)

---

### Story 2.2c : Onboarding Section 3 "Source Preferences"

**As a** nouvel utilisateur,  
**I want** indiquer mes préférences de sources et formats,  
**so that** Facteur me propose les bons contenus.

**Acceptance Criteria :**
1. 3-4 écrans couvrant :
   - Thèmes principaux (multi-sélection)
   - Préférence formats courts vs longs
   - 2-3 questions de préférence rapide entre sources
2. Si gamification activée → Question sur l'objectif personnel
3. Indicateur de progression (section 3/3)
4. Bouton "Finaliser" déclenche l'animation de conclusion

---

### Story 2.2d : Animation de conclusion onboarding

**As a** nouvel utilisateur,  
**I want** voir une animation de "configuration" à la fin du questionnaire,  
**so that** je comprenne que Facteur prépare mon expérience personnalisée.

**Acceptance Criteria :**
1. Écran avec animation de chargement élégante
2. Messages progressifs : "Chargement de tes sources...", "Configuration de tes préférences...", "Préparation de ton feed..."
3. Durée ~3-5 secondes
4. Transition fluide vers le Feed

---

### Story 2.3 : Sauvegarde du profil après onboarding

**As a** nouvel utilisateur,  
**I want** que mes réponses soient sauvegardées,  
**so that** je n'aie pas à refaire le questionnaire.

**Acceptance Criteria :**
1. À la fin du questionnaire, réponses envoyées à l'API
2. Profil créé/mis à jour dans `user_profiles`
3. Intérêts stockés dans `user_interests` avec pondération
4. Préférences stockées dans `user_preferences`
5. Flag `onboarding_completed = true`

---

### Story 2.4 : Redirection vers Feed après onboarding

**As a** nouvel utilisateur,  
**I want** accéder directement à mon feed personnalisé après l'onboarding,  
**so that** je puisse commencer à consommer du contenu immédiatement.

**Acceptance Criteria :**
1. Après animation, redirection automatique vers le Feed
2. Feed affiche immédiatement des contenus personnalisés
3. Message de bienvenue optionnel
4. Pas d'écran intermédiaire de sélection de sources

---

### Story 2.5 : Bypass onboarding pour utilisateurs existants

**As a** utilisateur existant,  
**I want** accéder directement au feed si j'ai déjà fait l'onboarding,  
**so that** je ne perde pas de temps.

**Acceptance Criteria :**
1. Au login, vérification du flag `onboarding_completed`
2. Si `true` → redirection vers Feed
3. Si `false` → redirection vers Onboarding
4. Option de refaire l'onboarding depuis Settings

---

## Epic 3 : Gestion des Sources

**Objectif :** Catalogue de sources curées, synchronisation RSS, sources personnalisées.

### Story 3.1 : Modèle de données Sources & Contenus

**As a** développeur,  
**I want** un modèle de données pour les sources et leurs contenus,  
**so that** l'app puisse stocker et servir les articles/podcasts/vidéos.

**Acceptance Criteria :**
1. Table `sources` : id, name, url, type, theme, description, logo_url, is_curated
2. Table `contents` : id, source_id, title, url, thumbnail_url, description, published_at, duration_seconds, content_type
3. Table `user_sources` : user_id, source_id, is_custom, added_at
4. Table `user_content_status` : user_id, content_id, status, seen_at, time_spent_seconds
5. Index et RLS configurés

---

### Story 3.2 : Import du catalogue de sources curées

**As a** développeur,  
**I want** importer le catalogue de sources curées dans la base,  
**so that** tous les utilisateurs aient accès à du contenu de qualité.

**Acceptance Criteria :**
1. Script d'import depuis `sources.csv`
2. 24 sources initiales importées
3. Types correctement détectés
4. Thèmes assignés
5. Flag `is_curated = true`
6. Script réexécutable (upsert)

---

### Story 3.3 : Service de synchronisation RSS

**As a** système,  
**I want** synchroniser automatiquement les contenus depuis les flux RSS,  
**so that** le feed soit toujours à jour.

**Acceptance Criteria :**
1. Service Python parsant RSS (articles, podcasts, YouTube)
2. Gestion des 3 types de flux
3. Extraction métadonnées complètes
4. Déduplication par URL
5. Job planifié toutes les 30 minutes
6. Logging des erreurs

---

### Story 3.4 : Ajout de source personnalisée par l'utilisateur

**As a** utilisateur,  
**I want** ajouter mes propres sources via URL,  
**so that** je puisse suivre des contenus hors catalogue.

**Acceptance Criteria :**
1. Écran "Mes sources" avec bouton "Ajouter"
2. Détection automatique du type de source
3. Validation URL et flux
4. Extraction channel_id pour YouTube
5. Source ajoutée avec `is_custom = true`
6. Sync immédiate des contenus

---

### Story 3.5 : Écran "Mes Sources"

**As a** utilisateur,  
**I want** voir et gérer mes sources,  
**so that** je sache d'où vient mon contenu.

**Acceptance Criteria :**
1. Liste des sources avec logo, nom, type, thème
2. Section "Sources du catalogue" (lecture seule)
3. Section "Mes sources ajoutées" (supprimables)
4. Bouton "Ajouter une source"

---

## Epic 4 : Feed & Algorithme

**Objectif :** Feed personnalisé avec algorithme de tri basé sur les préférences.

### Story 4.1 : Algorithme de tri et personnalisation

**As a** utilisateur,  
**I want** voir un feed personnalisé selon mes préférences,  
**so that** les contenus les plus pertinents apparaissent en premier.

**Acceptance Criteria :**
1. ✅ Endpoint API `/api/feed` avec contenus triés
2. ✅ Algorithme modulaire V2 (Core, Static, Behavioral)
3. ✅ Transparence : affichage de la raison de recommandation (badge discret)
4. ✅ Exclusion des contenus vus et masqués
5. ✅ Pagination (20/page, infinite scroll)

---

### Story 4.2 : Écran Feed principal

**As a** utilisateur,  
**I want** voir mon feed de contenus personnalisés,  
**so that** je puisse découvrir ce qui m'intéresse.

**Acceptance Criteria :**
1. Liste scrollable de cards
2. Pull-to-refresh
3. Infinite scroll
4. États vide et chargement
5. Bottom navigation bar

---

### Story 4.3 : Card de contenu (preview)

**As a** utilisateur,  
**I want** voir un aperçu attractif de chaque contenu,  
**so that** je puisse décider si je veux le consulter.

**Acceptance Criteria :**
1. Card : thumbnail (header), titre (body)
2. Footer distinct : source, actions, type
3. Indicateur type (📄 🎧 🎬)
4. Durée estimée
5. Date relative
6. Icône bookmark 🔖 + Menu "..."

---

### Story 4.4 : Action "À consulter plus tard"

**As a** utilisateur,  
**I want** ajouter un contenu à ma liste "À consulter plus tard",  
**so that** je puisse y revenir quand j'ai le temps.

**Acceptance Criteria :**
1. Tap 🔖 → ajout à la liste
2. Feedback visuel immédiat
3. Toggle (re-tap = retirer)

---

### Story 4.5 : Action "Pas intéressé"

**As a** utilisateur,  
**I want** indiquer qu'un contenu ne m'intéresse pas,  
**so that** l'algorithme apprenne mes préférences.

**Acceptance Criteria :**
1. Via menu "..." → "Pas intéressé"
2. Contenu masqué (animation)
3. Statut `hidden` enregistré
4. Toast feedback

---

### Story 4.6 : Filtres rapides

**As a** utilisateur,  
**I want** filtrer mon feed par type ou thème,  
**so that** je puisse me concentrer sur ce que je veux.

**Acceptance Criteria :**
**Acceptance Criteria :**
1. Barre de filtres horizontale ("Chips")
2. Filtres "Intent" :
   - "Douceur" (Positive vibes, évite Pol/Eco)
   - "Penser contre" (Perspective, sources opposées)
   - "Deep Dive" (Formats longs)
   - "À la une" (Articles récents < 24h)
3. Mise à jour instantanée du feed
4. Reset possible ("Tout voir")

---

## Epic 5 : Consommation & Gamification

**Objectif :** Consultation des contenus avec tracking automatique, streak et progression.

### Story 5.1 : Écran Détail Contenu

**As a** utilisateur,  
**I want** voir un aperçu enrichi avant d'ouvrir un contenu,  
**so that** je puisse décider si je veux vraiment le consulter.

**Acceptance Criteria :**
1. Tap card → écran détail (pas redirect direct)
2. Affichage complet : thumbnail, titre, source, date, durée, description
3. Bouton "Lire/Écouter/Voir"
4. Boutons secondaires : Sauvegarder, Pas pour moi

---

### Story 5.2 : Redirect vers source externe

**As a** utilisateur,  
**I want** ouvrir le contenu dans un navigateur,  
**so that** je puisse le consulter sur le site d'origine.

**Acceptance Criteria :**
1. Ouverture WebView in-app
2. Option navigateur externe (Settings)
3. Tracking du temps passé

---

### Story 5.3 : Tracking automatique "Contenu consommé"

**As a** utilisateur,  
**I want** que mes contenus soient automatiquement marqués comme lus,  
**so that** je voie ma progression sans effort.

**Acceptance Criteria :**
1. Timer à l'ouverture WebView
2. Seuils : 30s article, 60s vidéo/podcast
3. Marquage automatique si seuil atteint
4. Feedback au retour "✓ Contenu ajouté à ta progression !"

---

### Story 5.4 : Système de Streak quotidien

**As a** utilisateur,  
**I want** voir mon streak de jours consécutifs,  
**so that** je sois motivé à revenir chaque jour.

**Acceptance Criteria :**
1. Table `user_streaks`
2. Jour validé si ≥1 contenu consommé
3. Streak incrémenté/reset
4. Affichage "🔥 X jours"
5. Animation célébration record
6. Notification optionnelle si risque de perte

---

### Story 5.5 : Barre de progression hebdomadaire

**As a** utilisateur,  
**I want** voir ma progression vers un objectif hebdomadaire,  
**so that** je me sente accomplir quelque chose.

**Acceptance Criteria :**
1. Objectif configurable (défaut : 10/semaine)
2. Barre visuelle "X/Y (Z%)"
3. Reset lundi 00h
4. Messages d'encouragement contextuels
5. Célébration à 100%

---

### Story 5.6 : Écran Progression

**As a** utilisateur,  
**I want** voir un récapitulatif de ma progression,  
**so that** je puisse mesurer mon apprentissage.

**Acceptance Criteria :**
1. Streak central avec flamme
2. Barre progression hebdo
3. Stats : cette semaine, ce mois, total
4. Répartition par type et thème
5. Si gamification désactivée : stats uniquement

---

### Story 5.7 : Écran "À consulter plus tard"

**As a** utilisateur,  
**I want** accéder à mes contenus sauvegardés,  
**so that** je puisse les consulter plus tard (liste "À consulter").

**Acceptance Criteria :**
1. Liste des contenus mis à consulter (`saved`)
2. Même format cards
3. Tri par date de sauvegarde
4. Action "Retirer"
5. État vide

---

## Epic 6 : Premium & Paiement

**Objectif :** Abonnement premium avec RevenueCat, trial 7 jours, paywall bloquant.

### Story 6.1 : Intégration RevenueCat

**As a** développeur,  
**I want** intégrer RevenueCat pour gérer les abonnements,  
**so that** la gestion des paiements soit simplifiée.

**Acceptance Criteria :**
1. Compte RevenueCat configuré
2. Produits App Store Connect créés
3. SDK intégré dans Flutter
4. Webhook → Backend
5. Table `user_subscriptions`

---

### Story 6.2 : Logique Trial / Premium

**As a** produit,  
**I want** définir la logique d'accès trial vs premium,  
**so that** les utilisateurs puissent tester avant de payer.

**Acceptance Criteria :**
1. Nouvel utilisateur → Trial 7 jours
2. Trial : accès complet
3. Après trial sans abo : accès bloqué (paywall)
4. Avec abo : accès illimité
5. Endpoint `/api/user/subscription`

---

### Story 6.3 : Écran Paywall

**As a** utilisateur en fin de trial,  
**I want** voir une proposition d'abonnement claire,  
**so that** je puisse décider de continuer.

**Acceptance Criteria :**
1. Design attractif, valeur mise en avant
2. Prix affichés clairement
3. Bouton CTA "S'abonner"
4. Liens CGV et politique confidentialité
5. Texte légal App Store

---

### Story 6.4 : Flow d'achat App Store

**As a** utilisateur,  
**I want** m'abonner via l'App Store,  
**so that** le paiement soit sécurisé.

**Acceptance Criteria :**
1. Flow achat natif iOS
2. Gestion états : en cours, succès, échec
3. Mise à jour statut immédiate
4. Feedback "🎉 Bienvenue dans Facteur Premium !"
5. Restauration achats existants

---

### Story 6.5 : Gestion de l'abonnement

**As a** utilisateur premium,  
**I want** voir et gérer mon abonnement,  
**so that** je sache quand il expire.

**Acceptance Criteria :**
1. Section "Abonnement" dans Settings
2. Affichage statut, date renouvellement
3. Bouton "Gérer" → paramètres iOS
4. Info sur comment annuler

---

### Story 6.6 : Comportement app selon statut

**As a** utilisateur,  
**I want** que l'app s'adapte à mon statut,  
**so that** l'expérience soit cohérente.

**Acceptance Criteria :**
1. Trial actif : badge "Essai - X jours"
2. Trial J-2 : notification + banner
3. Trial expiré : paywall bloquant
4. Premium : aucune restriction
5. Premium expiré : paywall bloquant

---


---

## Epic 7 : Mise en perspective (Ground News Style)

**Objectif :** Lutter contre les bulles informationnelles en permettant de comparer les angles éditoriaux sur un même sujet.

**Status : ✅ MVP Done (12/01/2026)**

> **Pivot MVP**: L'approche initiale de clustering interne a été abandonnée au profit d'une recherche live via Google News RSS, offrant un meilleur taux de couverture (~100% vs ~20%) sans infrastructure additionnelle.

---

### Story 7.1 : Profiling éditorial des sources ✅

**As a** développeur,  
**I want** enrichir le modèle des sources avec des données de positionnement éditorial,  
**so that** le système puisse qualifier la perspective de chaque contenu.

**Status: Done**

**Acceptance Criteria :**
1. ✅ Table `sources` enrichie : `bias_stance`, `reliability_score`, `bias_origin`
2. ✅ Script d'import mis à jour pour intégrer ces données depuis CSV
3. ✅ Gestion des sources sans données (cas par défaut: `UNKNOWN`)
4. ✅ 22/27 sources curées avec données de biais

---

### Story 7.2 : MVP Perspectives - Backend ✅

**As a** utilisateur,  
**I want** voir des points de vue alternatifs sur un article,  
**so that** je puisse me forger une opinion plus nuancée.

**Status: Done**

**Acceptance Criteria :**
1. ✅ Endpoint `GET /contents/{id}/perspectives` fonctionnel
2. ✅ Extraction de mots-clés significatifs (noms propres prioritaires)
3. ✅ Recherche Google News RSS (~400ms latence)
4. ✅ Mapping de biais pour ~50 sources françaises

---

### Story 7.3 : MVP Perspectives - Frontend ✅

**As a** utilisateur,  
**I want** accéder aux perspectives alternatives depuis l'écran article,  
**so that** je puisse facilement consulter d'autres points de vue.

**Status: Done**

**Acceptance Criteria :**
1. ✅ Bouton ⚖️ dans le header (articles uniquement)
2. ✅ Bottom sheet avec Bias Bar et liste de perspectives
3. ✅ Tap ouvre l'article externe
4. ✅ Loading state pendant la recherche

---


## Next Steps

### UX Expert Prompt

> Crée les spécifications front-end détaillées pour Facteur en te basant sur ce PRD. Focus sur l'onboarding (10-12 écrans, 3 sections), le feed principal, l'écran détail, et le système de gamification (streak, progression). Thème sombre, palette terracotta/bleu, inspirations Notion + Le Monde + Deepstash.

### Architect Prompt

> Crée l'architecture technique détaillée pour Facteur en te basant sur ce PRD. Stack : Flutter + FastAPI + Supabase + RevenueCat. Focus sur le modèle de données, l'API REST, le service de sync RSS, et l'algorithme de recommandation. Monorepo, déploiement Railway/Render.

---

*Document généré via BMad Method*

