# Digest Éditorialisé — Design Docs

**Date:** 10 mars 2026
**Statut:** Draft — Brainstorm Laurin + Claude
**Objectif:** Transformer le digest quotidien en expérience éditoriale avec pont actu → deep

## Documents

| # | Document | Contenu |
|---|----------|---------|
| 1 | [Pipeline](01-pipeline.md) | Architecture technique, sources deep, matching LLM, assemblage, config |
| 2 | [Éditorial](02-editorial.md) | Ton Facteur, exemples complets, prompts LLM, mode serein, badges |
| 3 | [Frontend](03-frontend.md) | Specs UI, widgets, swipe actu/deep, layout, animations, fichiers impactés |

## Résumé du concept

Le digest passe de "voilà l'actu" à **"voilà pourquoi c'est important — et voici comment comprendre en profondeur"**.

**Structure :**
- 3 sujets chauds, chacun avec un texte édito (LLM) + swipe entre 🔴 L'actu du jour et 🔭 Le pas de recul
- 🍀 Pépite du jour (sélection éditoriale)
- 💚 Coup de cœur (signal communautaire)
- Closure : "✅ T'es à jour"

**Pipeline :** détection sujets chauds → curation LLM → match actu (sources user) + match deep (sources curated) → rédaction éditoriale LLM → assemblage

**Config sans code :** tous les prompts et paramètres sont externalisés en YAML.
