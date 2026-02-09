# Stratégie Recommandation - Facteur

## Contexte Actuel

### Problème Identifié
L'algorithme de recommandation actuel est **trop basique** :
- Matching simple de 50 thèmes fixes (CoreLayer + ArticleTopicLayer)
- Bug critique : désalignement entre `Source.theme` (labels) et `UserInterest.interest_slug` (slugs)
- Résultat : recommandations quasi-aléatoires, pas de "personnalité" dans le feed

### Architecture Actuelle (V2)
```
ScoringEngine avec 7 layers:
- CoreLayer (matching thème + source follow)
- StaticPreferenceLayer
- BehavioralLayer  
- QualityLayer
- VisualLayer
- ArticleTopicLayer
- PersonalizationLayer
```

**Limites :**
- Pas d'apprentissage du comportement utilisateur
- Pas de découverte de nouveaux intérêts
- Interface de profiling ennuyeuse (formulaires)

---

## Approche "Lean" Retenue (Phase 1)

### Pivot stratégique
Après avoir écarté l'ingestion d'archives X (trop lourde), on part sur :

1. **NER Interne** (Named Entity Recognition)
   - Extraction automatique d'entités des articles (personnes, organisations, concepts)
   - Pas besoin de 50 thèmes fixes prédéfinis
   - Découverte dynamique des centres d'intérêt

2. **Liste de Following** (Social Graph Local)
   - L'utilisateur "follow" des comptes/sources
   - Le système apprend de cette curation
   - Approche "Twitter-like" mais privée

### Objectifs Phase 1
- [ ] Fixer le bug de matching thème (Single Taxonomy)
- [ ] Implémenter NER basique sur les titres/articles
- [ ] Connecter Following → Scoring
- [ ] MVP de profiling implicite

---

## Vision "Wow Effect" (Phase 2)

### Ce qu'on veut créer
> "Télépathie Produit" - L'utilisateur sent que l'app *le comprend* dès la première session

### Idées brainstormées (à valider)

#### A. Profiling Implicite (UX)
- **Temps de lecture** comme signal d'intérêt
- **Scroll velocity** = engagement vs skim
- **Re-lecture** d'articles = fort intérêt
- **Partage** = validation sociale du sujet

#### B. Gamification Découverte (PM)
- **"Spotify Wrapped" style** : "Tu as lu 23 articles sur le climat cette semaine"
- **Badges découverte** : "Explorateur de nouveaux horizons"
- **Challenges** : "Lis 3 articles hors de ta zone de confort"

#### C. Architecture Idéale (Architect)
- **Graph RAG** : Relations entre entités, sources, utilisateurs
- **Real-time Learning** : Mise à jour des poids à chaque interaction
- **Embeddings sémantiques** : Similarité article-article, user-user
- **Cold Start** : Onboarding intelligent basé sur 3-5 choix

#### D. Interface Profiling (UX)
- **Pas de formulaire** : Profiling via interactions naturelles
- **Cards interactives** : "Ça t'intéresse ?" swipe left/right
- **Découverte progressive** : On découvre l'utilisateur au fil du temps

---

## Questions en Suspens

1. **Privacy** : Jusqu'où peut-on tracker sans être intrusif ?
2. **Ressources** : NER interne vs API externe (OpenAI, etc.) ?
3. **Cold Start** : Comment créer le "Wow" dès le premier jour ?
4. **Équilibre** : Personnalisation vs serendipity (découverte aléatoire)

---

## Prochaines Étapes

1. **DIVERGER** : Session créative BMAD pour générer 5-10 idées Moonshot
2. **CONVERGER** : Filtrer par faisabilité (2 semaines / 1 dev)
3. **PLANIFIER** : Spécifier les Killer Features retenues

---

*Document de travail - Session BMAD à venir*
