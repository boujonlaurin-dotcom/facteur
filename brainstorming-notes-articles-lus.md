# Brainstorming BMAD : Notes sur les articles lus

**Date :** 20 février 2026  
**Contexte :** Complément de la PR en cours (collections de sauvegardes). Objectif : passer d’une consommation passive à une vision active, sans créer une feature isolée.

---

## 1. Contexte & Ancrage

### Existant (aligné avec ta PR)
- **Sauvegardes** : `user_content_status.is_saved` + `saved_at` ; liste plate puis **collections** (groupes type Instagram).
- **Écran "Mes sauvegardes"** : tab dédié, bande "Récemment sauvegardés", progression de lecture, nudges feed/digest.
- **Flow** : Digest/Feed → sauvegarder → (optionnel) ranger dans une collection.

### Objectif produit
- **Passer de passif à actif** : l’utilisateur ne fait pas que lire/sauver, il **réagit** (réflexion, citation, idée).
- **Cohérence avec la sauvegarde** : même "système" (entrée depuis carte/détail, persistance user↔content), pas un module à part.

### Contrainte technique
- Données user↔content déjà centralisées dans **`user_content_status`** (user_id, content_id, status, is_saved, seen_at, time_spent_seconds, etc.). Les notes doivent s’y raccrocher ou en être le prolongement logique.

---

## 2. Idées brainstormées (divergence)

### A. Où attacher la note ?
| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| **A1. Colonne `user_content_status`** | `note_text TEXT`, `note_updated_at TIMESTAMPTZ` | Simple, une note par (user, content), pas de nouvelle table | Mélange statut et contenu rédactionnel ; migration sur table existante |
| **A2. Table dédiée `content_notes`** | user_id, content_id, body, created_at, updated_at | Séparation claire, évolutif (plusieurs notes, versioning plus tard) | Une table + jointure en plus |
| **A3. Sur `collection_items`** | note sur l’item dans une collection | Note = "pourquoi je l’ai mis dans cette collection" | Note seulement si article dans une collection ; doublon si dans plusieurs collections |

**Recommandation BMAD** : **A1** pour MVP (rapide, cohérent avec "une réaction par article") ; migration vers A2 si on veut plus tard "plusieurs notes" ou export.

---

### B. Quand / où saisir la note ?
| Option | Description | Intégration sauvegarde |
|--------|-------------|------------------------|
| **B1. Écran détail article** | Champ note sous les actions (Sauvegarder, Masquer) | Même écran que le bookmark → naturel |
| **B2. Bottom sheet après "Lu" / "Sauvegardé"** | "Une pensée à garder ?" (optionnel) | Lien direct avec l’action digest/feed |
| **B3. Dans l’écran Sauvegardés / détail collection** | Note éditable sur la carte ou en détail | Renforce "mes sauvegardes = mon espace de réflexion" |
| **B4. Partout** | B1 + B2 + B3 (éditable depuis détail, depuis closure, depuis sauvegardés) | Maximal mais risque de dilution |

**Recommandation BMAD** : **B1 + B3** — saisie/édition sur l’écran détail (partagé feed/digest/sauvegardés) + affichage/édition dans "Mes sauvegardes" (et détail collection). B2 en option plus tard (nudge post-closure).

---

### C. Affichage des notes (où elles apportent de la valeur)
| Lieu | Rôle |
|------|------|
| **Carte article (feed/digest)** | Indicateur discret "a une note" (icône crayon/quote) pour rappel, pas le texte |
| **Écran détail** | Zone note éditable (expandable ou toujours visible) |
| **Liste / grille Sauvegardés** | Même indicateur "a une note" ; au tap → détail avec note |
| **Détail collection** | Idem : indicateur + détail avec note |
| **Export / partage (futur)** | Inclure les notes dans un résumé "Mes réflexions de la semaine" |

---

### D. UX "active" sans surcharge
- **Optionnel** : jamais obligatoire ; pas de blocage au "Lu" / "Sauvegardé".
- **Court par défaut** : placeholder "Citation, idée, réaction…" ; limite caractères raisonnable (ex. 500–1000).
- **Indicateur léger** : une icône sur les cartes suffit ; pas de preview longue dans les listes.
- **Lien avec collections** : si l’article est dans une collection, la note peut être présentée comme "pourquoi je l’ai mis ici" (sans forcément l’attacher à `collection_items` en V1).

---

### E. Cohérence avec le "système sauvegarde"
- **Même entité logique** : (user, content) = statut + sauvegarde + collections + **note**.
- **API** : soit `PATCH /api/contents/{id}/status` avec `note_text`, soit `PUT /api/contents/{id}/note` dédié (plus lisible).
- **Mobile** : même provider/repository que pour le statut/sauvegarde (ex. `content_status_provider` ou `saved_*`) ; pas un feature-module "notes" isolé.
- **Règles** : note possible dès que l’article a été vu (status ≥ seen) ou sauvegardé ; pas besoin d’être dans une collection.

---

## 3. Questions en suspens

1. **Scope lecture** : Note uniquement sur articles "lus" ou aussi sur "sauvegardés non lus" ? (Recommandation : autoriser dans les deux cas.)
2. **Recherche** : Faut-il un filtre "avec note" dans Sauvegardés / collections ? (Recommandation : oui, filtre simple en V1.)
3. **Analytics** : Tracker "note_added" / "note_edited" pour mesurer passage à l’actif ? (Recommandation : oui, léger.)
4. **Modération** : Pas de modération côté contenu en V1 ; à prévoir si partage/export plus tard.

---

## 4. Prochaines étapes (convergence)

1. **Valider** les choix A1 (colonne), B1+B3 (détail + sauvegardés), et l’affichage C.
2. **Décider** API : extension du PATCH status vs `PUT /note` dédié.
3. **Rédiger** une story (epic 10 ou nouvelle epic "Engagement actif") avec AC et tâches techniques.
4. **Implémenter** après merge de la PR collections (pour réutiliser écran sauvegardés / détail collection).

---

*Document de travail — Brainstorming BMAD — À valider avec PO/PM*
