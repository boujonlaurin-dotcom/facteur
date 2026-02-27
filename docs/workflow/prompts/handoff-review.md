# Prompt : Préparer le Handoff Review

> Utilisation : mentionne ce fichier à l'agent dev en fin de développement.
> Exemple : "Prépare le handoff review" ou "prépare le handoff"

---

## Instructions pour l'agent dev

Tu as terminé le développement. Prépare le handoff pour le peer reviewer en créant/mettant à jour le fichier `.context/pr-handoff.md` avec le contenu suivant :

```markdown
# PR — <titre descriptif du changement>

## Quoi
<Résumé en 2-3 lignes de ce qui a été modifié/ajouté>

## Pourquoi
<Problème résolu ou valeur ajoutée — contexte métier>

## Fichiers modifiés
<Liste des fichiers clés modifiés, groupés par domaine>
- Backend : ...
- Mobile : ...
- Config/Docs : ...

## Zones à risque
<Modules/fichiers où une erreur aurait le plus d'impact>

## Points d'attention pour le reviewer
<Ce qui mérite une relecture attentive — logique complexe, edge cases, patterns inhabituels>

## Ce qui N'A PAS changé (mais pourrait sembler affecté)
<Clarifier les faux positifs potentiels dans le diff>

## Comment tester
<Étapes pour vérifier que le changement fonctionne — en local ou en staging>
```

**Règles :**
- Sois factuel, pas marketing. Le reviewer est technique.
- Si tu as fait des choix d'architecture non évidents, explique pourquoi.
- Si tu as skippe quelque chose volontairement, dis-le (ex: "pas de test pour X car Y").
