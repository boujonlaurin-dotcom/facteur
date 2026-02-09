# Prompt de Handoff : Finalisation Epic 9 (Custom RSS Feeds)

**Rôle** : Tu es un Senior FullStack Engineer (Flutter/FastAPI).
**Contexte** : Une feature "Ajout de sources RSS personnalisées" (Epic 9) a été entamée. Le backend a été refactorisé sur la branche `feat/refactor-rss-parsing` pour corriger des crashs critiques, mais l'intégration bout-en-bout (notamment l'affichage dans le feed) reste à valider.

**Branche de travail** : `feat/refactor-rss-parsing`

## Tes Objectifs 🎯

Tu dois finaliser et valider la feature de A à Z.

### 1. Backend (Déjà refactorisé, à valider)
*   **Vérifier** : `packages/api/app/services/source_service.py` doit utiliser exclusivement `RSSParser` (plus de logique custom pour YouTube).
*   **Tests** : Lancer `pytest packages/api/tests/test_rss_parser.py` et s'assurer que tout passe (notamment YouTube `@handle` et détection heuristique).
*   **Endpoint** : Vérifier que `POST /sources/custom` fonctionne et retourne bien une `SourceResponse` valide.

### 2. Frontend (Intégration & UX)
*   **Ajout** : L'écran `AddSourceScreen` (et le bouton dans `SourcesScreen`) doit appeler le bon endpoint.
*   **Différenciation Visuelle** : Dans la liste des sources (`SourcesScreen`), les sources ajoutées par l'utilisateur doivent être visuellement distinctes des sources curées (ex: icône spécifique, badge "Perso", ou section séparée).
    *   *Actuellement, c'est peut-être mélangé.*

### 3. Data Loop (Le point critique)
*   **Sync** : Une fois la source ajoutée, le `SyncService` (Job de background) doit être capable de fetcher cette source.
*   **Feed** : Les articles/vidéos de cette nouvelle source DOIVENT apparaître dans le `FeedScreen` de l'utilisateur.
    *   *Attention aux filtres de pertinence existants qui pourraient masquer le contenu.*

## Instructions d'Exécution 📝

1.  **Checkout** : Place-toi sur `feat/refactor-rss-parsing`.
2.  **Audit** : Lis `packages/api/app/services/source_service.py` et `apps/mobile/lib/features/sources/screens/sources_screen.dart`.
3.  **Dev/Fix** :
    *   Si le frontend ne distingue pas les sources custom -> Ajoute un badge ou une icône.
    *   Force une synchro immédiate ou simule-la pour vérifier que les contenus rentrent en base.
4.  **Verification** :
    *   Ajoute `https://www.youtube.com/@ChezAnatole`.
    *   Vérifie qu'elle apparait dans "Mes Sources".
    *   Vérifie que ses video apparaissent dans le Feed.

**Livrable** : Code fonctionnel sur la branche, et un rapport de test confirmant que "YouTube -> Source -> Feed" fonctionne.
