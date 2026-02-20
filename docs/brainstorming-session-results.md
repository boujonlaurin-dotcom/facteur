# Brainstorming Session — Facteur

**Date** : 6 janvier 2026  
**Facilitateur** : BMad Master  
**Durée** : ~45 minutes  
**Techniques utilisées** : What If, Analogical Thinking, First Principles, Yes And, Priorisation convergente

---

## Executive Summary

### Sujet & Objectifs
- **Sujet** : Facteur — Outil de consommation intentionnelle de l'information
- **Objectif** : Idéation ciblée pour définir le MVP, avec ouverture sur le format (app vs extension vs newsletter)
- **Contraintes** : Budget et timing limités, validation d'hypothèses business

### Résultats clés
- **Format retenu** : App mobile (cross-platform Flutter/React Native, iOS first)
- **Hypothèse business à valider** : "Les gens paieront pour une expérience fluide et ludique"
- **Positionnement affiné** : Pas un agrégateur d'actu, mais un outil d'apprentissage par morceaux pour comprendre le monde sur le long terme

### Idées générées
- 25+ concepts explorés
- 6 fonctionnalités essentielles identifiées pour le MVP
- 4 fonctionnalités nice-to-have pour V1

---

## Vision Affinée

### Avant le brainstorming
> "Ton point d'entrée vers tes sources d'information fiables, saines et transparentes"

### Après le brainstorming
> **Facteur = Une app mobile personnalisée qui sélectionne et organise les meilleurs contenus (articles, podcasts, vidéos, extraits de livres) de mes sources de confiance, pour les personnes qui veulent apprendre et comprendre le monde sans tomber dans le doom scrolling.**

### Distinctions clés établies

| Ce que Facteur N'EST PAS | Ce que Facteur EST |
|--------------------------|-------------------|
| Agrégateur d'actualité | Outil d'apprentissage par morceaux |
| Flux continu d'infos du jour | Culture sur le long terme |
| "Être au courant" | "Apprendre et comprendre" |
| Temps limité imposé | Temps bien investi (variable) |
| Réseau social | Middleware de consommation intentionnelle |

---

## Technique 1 : What If — Exploration des formats

### Question : "Et si Facteur n'existait pas sous forme d'app ?"

**Réponses explorées :**
- ✅ Service postal (métaphore alignée avec le nom "Facteur")
- ✅ Feed WhatsApp / Newsletter (test léger, complément)
- ❌ Widget / Commande vocale (trop intrusif)

### Question : "Et si l'utilisateur ne pouvait consulter qu'une fois par jour ?"

**Insights :**
- Inspiration BeReal intéressante mais risque de FOMO
- Effet inverse possible : urgence face à l'information
- Philosophie Slow Media = non négociable
- **Tension centrale identifiée** : Engagement/Adoption ↔ Slow Media

### Question : "Qu'est-ce qui fait revenir sans urgence ?"

**Insight clé :**
> "Aucun levier ne peut être écarté car le défi est trop grand — notifications, gamification, liens sociaux, même FOMO raisonnée"

**Posture retenue** : Pragmatisme > Dogmatisme. Utiliser les leviers AU SERVICE du Slow Media, pas contre lui.

---

## Technique 2 : Analogical Thinking — Modèles inspirants

### Analogies explorées

| Domaine | Excessif → Intentionnel | Modèle | Pertinence Facteur |
|---------|-------------------------|--------|-------------------|
| Email | Inbox infinie → Tri intelligent | Superhuman / Hey | ⭐⭐⭐ Très pertinent |
| Alimentation | Buffet → Omakase (chef décide) | Confiance curateur | ⭐⭐⭐ Très pertinent |
| Finance | Dépenses impulsives → Enveloppes | YNAB, Bankin | ⭐⭐ Mécanisme intéressant |
| Fitness | Salle culpabilisante → Micro-doses | 7 Minute Workout | ⭐⭐ Micro-apprentissage |
| Musique | Playlist infinie → Album vinyle | Curation + finitude | ⭐ Philosophiquement parfait, commercialement risqué |
| Screen Time | Usage illimité → Friction positive | iOS Screen Time | ⭐⭐ Rappels utiles |

### Modèle retenu : "Superhuman de l'info"
- Tri intelligent avant que vous ne voyez
- Objectif = FINIR, pas scroller
- Premium assumé
- **Équivalent "Inbox Zero"** = Différencier l'important du bruit, passer le temps qu'on veut vraiment sur l'essentiel

### Concept de confiance
- **Curateur de confiance** = Pas Facteur lui-même, mais les sources existantes (médias, podcasts, newsletters de qualité)
- **Facteur = le FILTRE** entre les sources de confiance et l'utilisateur

---

## Technique 3 : First Principles — Décomposition fonctionnelle

### Problème fondamental
> L'utilisateur est submergé d'info, ne sait pas quoi est important, perd du temps et de l'énergie mentale.

### Décomposition COLLECTE → TRIE → PRÉSENTE → RESSORT

| Étape | Définition |
|-------|------------|
| **COLLECTE** | Agrège tout (newsletters, RSS, podcasts, vidéos, livres, web) avec filtre qualité/quantité |
| **TRIE** | Algo personnalisé + transparent + "lenses" thématiques au choix |
| **PRÉSENTE** | Fluide (inspiration Deepstash), mais différencié des réseaux sociaux |
| **RESSORT** | "Bien informé, cultivé, ludique" — l'opposé du flou post-Instagram |

### Sentiment final recherché
> "Ça change du flou duquel on sort après avoir zappé entre 2 vidéos de chats et 1 vidéo de géopolitique sur Insta"

**Mot clé** : Clarté vs Flou

---

## Technique 4 : Yes And — Construction collaborative

### Concept "Lenses" intentionnelles

**Évolution** : Pas des catégories (Tech, Politique) mais des INTENTIONS
- "Rester pertinent dans mon métier"
- "Comprendre les enjeux qui m'affectent"
- "Voir ce que les gens qui pensent différemment pensent"

**Statut MVP** : Out-of-scope (intégrable via algo plus tard)

### Transparence de l'algorithme

**Niveaux explorés :**
- A. Tag simple : "Via votre intérêt X" ✅ Retenu
- B. Explication courte : "3 de vos sources en parlent" ✅ Retenu
- C. Score visible : Pertinence 87% — ❌ Trop complexe MVP
- D. Contrôle total : Plus/moins de ceci — 🔶 Nice-to-have

**Concept social retenu :**
> "Les personnes avec vos intérêts ont recommandé cet article"

### Inspirations externes identifiées
- **Deepstash** : UX fluide, questionnaire onboarding ludique
- **Ground News** : Pluralité de points de vue (nice-to-have)

---

## Business Model

### Exploration des modèles

| Modèle | Verdict | Raison |
|--------|---------|--------|
| Premium B2C | ✅ MVP | Seul modèle viable pour tester "ils paieront" |
| Premium B2B | ✅ Scale | Phase 2, après validation B2C |
| Freemium | ❌ | Risque de perdre du temps sur mauvaises cibles, conversion difficile |
| Partenariats médias | ❌ Initial | Conflit d'intérêt (possible long-shot futur avec paiement au clic) |
| Bundle | ❓ | Pas de vue claire |

### Stratégie retenue

```
PHASE 1 (MVP)          →    PHASE 2 (Scale)
Premium B2C                  + B2B entreprises
Valider hypothèses           Revenus récurrents
Créer notoriété              Partenariats médias (long-shot)
```

### Essentiel (V0)
1. ✅ Agrégation multi-sources (RSS + Podcasts + YouTube via RSS)
2. ✅ Algo de tri/recommandation (règles simples)
3. ✅ Questionnaire ludique onboarding (profil + objectifs)
4. ✅ Paiement intégré (premium simple, 1 prix)
5. ✅ Lecture en redirect (avec preview)

### Nice-to-have (V1)
- 🔶 Transparence algo (tags simples expliquant pourquoi un contenu est proposé)
- 🔶 Pluralité de points de vue (inspiration Ground News)
- 🔶 Preuve sociale ("personnes comme vous ont aimé")
- 🔶 Contrôle utilisateur avancé (plus/moins de ceci)
- 🔶 Extension navigateur
- 🔶 Newsletters (parsing email)

### Out-of-scope MVP
- ❌ Lenses intentionnelles explicites (intégrées via algo)
- ❌ Lecture in-app complète
- ❌ ML/AI complexe

---

## Priorisation MVP

## Action Planning

### Top 3 priorités immédiates

| # | Priorité | Prochaine étape |
|---|----------|-----------------|
| 1 | **Définir le Project Brief** | Formaliser la vision et les objectifs avec le template BMad |
| 2 | **Créer le PRD** | Détailler les exigences fonctionnelles et non-fonctionnelles |
| 3 | **Designer l'onboarding** | Définir les 5-7 questions du questionnaire ludique |

### Questions ouvertes pour la suite
- Quel pricing exact ? (mensuel, annuel, quel montant ?)
- Quelles sources RSS/newsletters intégrer en premier ?
- Quel design system / identité visuelle ?
- Solo founder ou équipe ? Build vs buy vs outsource ?

---

## Décision Format MVP

### Dilemme exploré
- Newsletter/WhatsApp : Léger, rapide, mais ne teste pas l'hypothèse "ils paieront pour une UX fluide"
- App : Plus lourd, mais seul format qui valide l'hypothèse business clé

### Décision finale
> **App mobile** — Car l'hypothèse "les gens paieront pour une expérience fluide et ludique" ne peut pas être validée par une newsletter.


### Stack technique

| Aspect | Décision |
|--------|----------|
| **Plateforme** | Cross-platform (Flutter ou React Native) |
| **Priorité** | iOS first (utilisateurs plus enclins à payer) |
| **Ensuite** | Android (même codebase) |

---

## Spécifications MVP App

```
┌─────────────────────────────────────────────────────────────────┐
│                    MVP FACTEUR — APP MOBILE                     │
├─────────────────────────────────────────────────────────────────┤
│  FORMAT         │  Cross-platform (Flutter/React Native)       │
│                 │  iOS first, puis Android                      │
├─────────────────────────────────────────────────────────────────┤
│  ONBOARDING     │  Questionnaire ludique 5-7 questions         │
├─────────────────────────────────────────────────────────────────┤
│  SOURCES        │  RSS + Podcasts + YouTube (via flux RSS)     │
├─────────────────────────────────────────────────────────────────┤
│  ALGO           │  Règles simples basées sur profil utilisateur │
├─────────────────────────────────────────────────────────────────┤
│  TRANSPARENCE   │  V1 (hors scope MVP)                         │
├─────────────────────────────────────────────────────────────────┤
│  LECTURE        │  Redirect vers source avec preview/extrait   │
├─────────────────────────────────────────────────────────────────┤
│  PAIEMENT       │  Premium simple (1 prix, Stripe/RevenueCat)  │
├─────────────────────────────────────────────────────────────────┤
│  BUSINESS       │  B2C Premium → B2B (scale)                   │
└─────────────────────────────────────────────────────────────────┘
```

---

---

## Réflexion & Follow-up

### Ce qui a bien fonctionné
- L'analogie Superhuman a débloqué la vision "filtre intelligent"
- La tension Engagement ↔ Slow Media est clarifiée
- Le passage de "actu" à "apprentissage long terme" est structurant

### À explorer dans les prochaines sessions
- Design détaillé de l'onboarding
- Benchmark concurrentiel approfondi (Deepstash, Ground News, Artifact, etc.)
- Stratégie d'acquisition utilisateurs

### Recommandation
> Passer immédiatement à la création du **Project Brief** pour formaliser ces insights avant qu'ils ne se perdent.

---

*Document généré via BMad Method — Session de brainstorming facilitée*
