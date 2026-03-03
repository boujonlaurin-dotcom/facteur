# Handoff Frontend — Epic 11 : Custom Topics (Partie 2 - UI & UX)

Tu es un agent d'implémentation Frontend Flutter. Ta mission est de construire **l'interface utilisateur** complète pour l'Epic "Custom Topics" en utilisant les Providers Riverpod déjà développés par l'agent précédent.

## Contexte
La vue unifiée "Mes Intérêts", les cartes de feed avec "Chip Topic" (✓), le clustering d'articles, et le panneau de suggestions demandent un grand soin d'intégration visuelle. Pour ne pas détériorer ta fenêtre de contexte LLM, on se concentre ici **100% sur l'UI et les tests de widgets**.

**Stack :**
- Flutter / Riverpod
- PhosphorIcons (pour `PhosphorIcons.check`)
- Golden Tests (si applicable) ou Widget Tests

**Documents à lire :**
1. `docs/stories/core/11.custom-topics.story.md` (Spécifications focus Feed & Settings)
2. `docs/stories/core/11.custom-topics/convergence.md` (Validation du design v3 : curseur compact, pas d'header)
3. `docs/stories/core/11.custom-topics/wireframes/` (les 3 mockups markdown .md)

---

## 📋 Tâches (Plan de travail)

### 1. Settings : Page "Mes Intérêts"
- Créer l'écran `MyInterestsScreen`.
- Implémenter l'affichage en `ExpansionTile` ouverts par défaut, groupant thèmes macro et custom topics.
- **Curseur 3 crans compact** : intégré dans les en-têtes (inline). Les labels textes (Suivi, Intéressé, Fort) n'apparaissent dynamiquement que pendant ou juste après un `onTouch` (fade in/out).
- **Suggestions in-situ** : bloc au format `○ Cybersécurité [+ Suivre]` qui ajoute instantanément à 2/3 au clic.

### 2. Feed : Cartes et Clusters
- Modifier le footer de la `ContentCard` : Remplacer l'icône Info ℹ️ et Masquer 👁️ par la **Topic Chip**. Ex: `[IA ✓]` (si suivi, bg color terracotta) ou `[Éco]` (si non suivi, surface bg).
- UI de **Chip de Cluster** : Sous l'article représentatif, si le backend fournit un cluster, afficher la chip compacte `▸ 4 autres articles sur l'IA`.
- Au "tap" de la chip de cluster, `Navigator.push` vers `TopicExplorerScreen`.

### 3. Topic Explorer
- Créer l'écran `TopicExplorerScreen` (similaire à un feed source classique).
- Intégrer en inline header le bouton `Modifier la priorité` (ouvre le même slider 3 crans dynamique) ou `[+ Suivre]`.

### 4. Tests Widgets & Intégration Visuelle
- Écrire des Widget Tests pour vérifier que le slider change bien l'état du provider.
- Vérifier les états vides et le loading shimmer sur le bouton "Suivre".
- S'assurer que le Bottom Nav (Essentiel, Explorer, Settings) n'est pas détérioré par le layout.

## 🛑 Guardrails
1. Ne réinvente pas le design system : utilise les tokens existants du projet (`Theme.of(context)`).
2. L'icône de suivi sur carte est `PhosphorIcons.check`, sobre, pas un emoji emoji pin massif.
3. Toujours valider le rendu du curseur 3 crans : il doit rester visible et utilisable même sur petits écrans (iPhone SE).
