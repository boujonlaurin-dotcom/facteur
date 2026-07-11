# QA Handoff — Paywalls Premium « Fact·eur·isse » (PR 2 mobile)

## Contexte

Implémentation de la maquette « Paywalls Premium » : écran **Soutien** (porte 1, lettre des fondateurs), **murs de feature** (porte 2 : veille plein écran + sheets sources/analyses/serein), gating client-side (cap 30 sources, veille premium, quota 1 analyse/jour, personnalisation serein), confirmation « lien envoyé ». Le CTA n'ouvre jamais un paiement : il déclenche `POST /api/checkout/send-link` (magic link Supabase par email, PR backend #954).

⚠️ **Web = état free uniquement** : RevenueCat est null sur web (`customerInfoProvider` → null → non-premium). Ne pas tester les états premium en web.

⚠️ Les photos fondateurs sont des **placeholders** (aplats de couleur) en attendant les vraies images.

## Écrans impactés

- Réglages (bottom sheet) : tuile « Nous soutenir », badge `N/30` sur Mes sources, stamp `PREMIUM` sur Ma veille/Crée ta veille, sous-row « Personnaliser mes bonnes nouvelles » (lock).
- `/soutien` : écran Soutien complet.
- `/soutien/veille-wall` : mur veille.
- `/soutien/lien-envoye` : confirmation.
- Intro veille : stamp « RÉSERVÉ AUX FACT·EUR·ISSES » + CTA verrouillé.
- Ajout de source : pill « N / 30 médias suivis ».
- Perspectives / Analyse Facteur : gate quota 1/jour (bannière quota épuisé sous le CTA en free).

## Scénarios

1. **Happy path Soutien** : Réglages → « Nous soutenir » → écran Soutien (eyebrow, headline, lettre 2 §, carte bonus avec 2 stamps BIENTÔT, 3 réassurances, prix 3 €/mois, CTA « Reçois ton lien pour nous rejoindre », disclaimer stores). Tap CTA → soit confirmation « Ton lien est en route. » (backend avec send-link), soit toast d'erreur propre, jamais de crash.
2. **Mur veille** : Réglages → « Crée ta veille » (compte free sans veille) → mur veille (3 bénéfices, MissionCard « Notre histoire → » → Soutien, prix, CTA).
3. **Intro veille gated** : deep-link `/veille/config` en free → redirection mur veille.
4. **Cap sources** : ajout de source → pill « N / 30 médias suivis » au-dessus de la recherche (absente en mode veille).
5. **Serein** : Réglages → sous-row « Personnaliser mes bonnes nouvelles » avec cadenas → tap → PaywallSheet variante serein (« Un mode serein à ton image »).
6. **Lien envoyé** : « Renvoyer le lien » 2× de suite → le second affiche « Patiente une minute avant de renvoyer. » (429) si backend actif.
7. **Console/réseau** : pas d'erreurs console inattendues, pas de 4xx/5xx hors 429 attendu.

## Critères d'acceptation

- Aucune copy avec em-dash « — ».
- Aucun crash sur images manquantes (fallback monogramme).
- Navigation retour cohérente (swipe back plein écran).
