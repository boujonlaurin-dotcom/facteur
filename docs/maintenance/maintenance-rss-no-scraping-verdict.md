# Maintenance — Vérification légale : ingestion RSS, pas de scraping

> Type : Maintenance (investigation, **aucun code**). Question du PO : le corps
> complet de certains articles (ex. The Conversation) s'affiche dans le reader
> Facteur — est-ce du scraping illégal ?

## Verdict : RSS-only, aucun scraping d'article

Le backend **n'extrait jamais** le texte d'article depuis la page web. Tout le
contenu affiché provient **exclusivement du flux RSS/Atom fourni par l'éditeur
lui-même**.

## Preuves

1. **Peuplement de `Content.html_content`** — `sync_service.py` (~l.388-399) : la
   valeur vient **uniquement** de `entry.content` (`content:encoded` en RSS, full
   content en Atom) ou `entry.summary`, tous deux des champs `feedparser` du flux.
   Aucune ligne ne fetch l'URL de l'article pour en extraire le corps.

2. **Seul fetch vers l'URL de l'article** — `_fetch_html_head()`
   (`sync_service.py` ~l.500-519) : **50 KB max** (`Range: bytes=0-50000`), utilisé
   **uniquement** pour la détection de paywall (JSON-LD `isAccessibleForFree`,
   meta `og:article:content_tier`). Le résultat n'est **ni stocké ni affiché**.

3. **BeautifulSoup** (`requirements.txt`) sert **seulement à la découverte de flux
   RSS** (`rss_parser.py` : scan des `<link rel="alternate">` / `<a href>`), jamais
   à extraire du contenu d'article. Aucune lib d'extraction full-text
   (trafilatura, newspaper, goose, readability, justext) n'est présente.

4. **Aucun worker/cron d'enrichissement** de corps post-ingestion (workers/, jobs/,
   tasks/ audités).

## Pourquoi The Conversation s'affiche en entier

The Conversation **publie volontairement le full-text dans son RSS** (contenu sous
licence Creative Commons, republication explicitement encouragée). Facteur ne fait
que rendre ce que l'éditeur diffuse dans son propre flux.

## Question résiduelle (produit/légal, hors scope technique)

Il ne s'agit **pas** d'un problème de scraping (inexistant), mais d'un choix
produit : republier inline le full-text RSS de **toutes** les sources — y compris
celles qui le mettent en RSS sans souhaiter un réaffichage sans leur habillage.

Piste éventuelle si on veut durcir la posture (option « B » écartée par le PO le
2026-07-02, à replanifier si besoin) : n'afficher inline le full-text que pour les
sources l'autorisant (flag `source.allow_full_reader` / allowlist type CC), sinon
teaser + « Lire sur le site ». Migration additive requise.

**Décision du 2026-07-02** : ne rien coder, documenter le verdict (ce fichier).
