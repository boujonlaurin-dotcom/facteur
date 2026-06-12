# QA Handoff — Story 26.2 : Lettres 3 et 4 du Facteur

> Ce fichier est rempli par l'agent dev à la fin du développement, après validation du PO.
> Il sert d'input à la commande /validate-feature de l'agent QA.

## Feature développée

Deux nouvelles lettres au catalogue backend (letter_3 « Ta tournée s'organise »,
letter_4 « Facteur de fond »), backfill automatique pour les users existants,
et 3 actions demandées par le PO : note sur un article sauvegardé, masquer
3 sources, donner son avis sur l'app (nouvel event `app_feedback_opened` émis
à l'ouverture de la modale « Donner mon avis »).

## PR associée

À créer via /go (base main). Branche : boujonlaurin-dotcom/progression-pr2-new-letters.

## Écrans impactés

- **Progression** (`/lettres`) : 5 lettres au lieu de 3 ; letter_3 s'active
  automatiquement pour un user qui avait fini letter_2.
- **Réglages** (`/settings`) : le tap sur « Donner mon avis » émet l'event
  analytics (aucun changement visuel).
- Navigation depuis une action de lettre : nouvelles destinations
  (`/veille/config`, `/saved`, `/settings/sources/add`, `/settings`, `/flaner`).

## Scénarios

### Happy path

1. Ouvrir Progression → vérifier 5 lettres, letter_3/4 affichées (upcoming ou
   active selon l'avancement du compte).
2. Tap sur chaque action de letter_3 → vérifier la redirection :
   - « Créer ta première veille » → écran de config veille
   - « Enregistrer 5 articles » → Flâner
   - « Écrire une note sur un article sauvegardé » → écran Sauvegardés
   - « Masquer 3 sources » → Flâner
   - « Ajouter 5 chaînes YouTube » → ajout de source
3. Tap sur « Donner ton avis sur l'app » (letter_4) → ouverture des réglages ;
   tap « Donner mon avis » → modale feedback + requête réseau analytics
   (`app_feedback_opened`) sans erreur.
4. Compléter une action (ex. masquer 3 sources depuis un article) → revenir
   sur Progression → l'action passe cochée après refresh.

### Edge cases

- User existant (3 rows) : GET /api/letters → 200, pas d'erreur, 5 lettres.
- User ayant déjà tout fini (L0-L2 archivées) : letter_3 doit être active.
- Note vide ou espaces → ne valide pas « Écrire une note ».
- Console sans erreurs, réseau sans 4xx/5xx inattendus sur tous ces flux.

## Critères d'acceptation

- [ ] 5 lettres visibles, ordre 00→04, grades cohérents avec le ladder
- [ ] Aucune erreur pour les users existants (backfill silencieux)
- [ ] Chaque action redirige vers un écran où le geste est faisable
- [ ] Event `app_feedback_opened` émis au tap « Donner mon avis »
