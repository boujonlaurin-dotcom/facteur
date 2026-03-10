# Digest Éditorialisé — Design Docs

**Date:** 10 mars 2026
**Statut:** Draft — Brainstorm Laurin + Claude
**Epic :** [10 — Digest Central, Phase 5](../../stories/core/10.digest-central/epic-10-digest-central.md)
**Stories :** 10.22 → 10.28

## Objectif

Transformer le digest de "voilà l'actu" à **"voilà pourquoi c'est important — et voici comment comprendre en profondeur"**.

## Documents

| # | Document | Contenu | Stories couvertes |
|---|----------|---------|-------------------|
| 1 | [Pipeline](01-pipeline.md) | Architecture pipeline LLM, sources deep, matching actu/deep, config YAML | 10.22, 10.23, 10.24, 10.25 |
| 2 | [Éditorial](02-editorial.md) | Ton Facteur, exemples complets (normal + serein), prompts LLM, badges | 10.24 (prompts) |
| 3 | [Frontend — Delta](03-frontend.md) | **Deltas explicites** depuis les stories existantes (10.9-10.15), nouveaux widgets, checklist challengeable | 10.26, 10.27, 10.28 |

## Structure du digest

```
3 sujets × (édito LLM + 🔴 L'actu du jour ↔ 🔭 Le pas de recul)
+ 🍀 Pépite du jour (sélection éditoriale)
+ 💚 Coup de cœur (signal communautaire)
+ ✅ "T'es à jour" (closure)
```

## Deltas frontend (résumé)

Chaque modification de l'existant est numérotée D1-D10 dans [03-frontend.md](03-frontend.md) et référencée dans l'epic. Les modifications marquées "Challengeable: Oui" peuvent être retirées individuellement sans casser le reste.

## Pipeline

Détection sujets chauds → curation LLM → match actu (sources user) + match deep (sources curated) → rédaction éditoriale LLM → assemblage. Config sans code via YAML.
