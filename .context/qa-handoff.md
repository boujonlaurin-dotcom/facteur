# QA Handoff — Invitation feedback « un café en visio » (Story 13.3)

> Rempli par l'agent dev. Input de /validate-feature. Story :
> `docs/stories/core/13.3.invitation-feedback-humaine.story.md`.

## Feature développée

L'invitation à un call qualitatif (Epic 13) était invisible (enfouie dans la toute
dernière boîte de la page) et pointait vers un lien Calendly mort. Elle devient une
**entrée slim posée 2 sections avant la fin de la Tournée**, qui se déploie **une
seule fois** en modale avec nos deux visages, un ask à « 5 minutes » et trois
sorties nettes. La carte de fin de tournée est allégée en conséquence.

## PR associée
À créer (`/go`) vers `main`.

## Écrans impactés

| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Tournée du jour (l'Essentiel) | `/flux-continu` | Modifié — nouvelle entrée inline à `sections.length - 3` |
| Modale d'invitation | bottom sheet | Réécrite (`CallInviteSheet`) |
| Carte de fin de tournée | `/flux-continu` (bas de page) | Modifié — teaser retiré, micro-vote compacté |

## Pré-requis de test

L'entrée n'apparaît que si le backend renvoie `should_show: true` sur
`GET /feedback/invite` (gating segmenté : `active` / `low_active` / `returning`,
et ni snooze ni `MAX_SHOWS=2` ni statut terminal en base). Si rien ne s'affiche,
vérifier/réinitialiser la ligne `feedback_invites` du user de test avant de
conclure à un bug.

Le nudge d'auto-ouverture est persisté dans SharedPreferences sous
`nudge.feedback_call_auto_modal.seen` : le supprimer pour rejouer le scénario 2.

## Scénarios

### 1. Placement — l'invitation est vue sans aller au bout (le cœur du fix)
Ouvrir la Tournée, scroller normalement. **Attendu** : l'entrée slim (deux photos
rondes qui se chevauchent + « Django & Laurin aimeraient t'entendre 5 minutes. » +
« Prendre un café ») apparaît **avant** la carte « Fin de tournée », pas dedans.

### 2. Auto-déploiement, une seule fois
Premier passage éligible : la modale s'ouvre **seule** quand l'entrée entre dans
le viewport (pas dès le chargement de la page, alors qu'on est encore en haut).
La refermer, puis recharger la Tournée. **Attendu** : plus d'auto-ouverture, seule
l'entrée inline reste ; un tap dessus rouvre la modale.

### 3. Contenu de la modale
**Attendu** : les deux photos (DJANGO / LAURIN) rendues, pas de monogramme de
repli ; tampon « TON AVIS COMPTE » ; titre « On peut te prendre 5 minutes ? » ;
signature « Django & Laurin, tes facteurs » ; **trois** boutons distincts :
« Prendre un café », « Plus tard », « On l'a déjà fait ». Aucun em-dash à l'écran.

### 4. Réservation
Taper « Prendre un café ». **Attendu** : ouverture de
`https://calendar.app.google/Yy1fLcasYk1uVbVT7` en navigateur externe (pas de
page d'erreur), et la modale se referme.

### 5. Sorties — l'entrée disparaît tout de suite
Taper « Plus tard » (ou « On l'a déjà fait »). **Attendu** : la modale se ferme
**et** l'entrée inline disparaît de la Tournée dans la foulée (le statut est
relu). Recharger : elle ne revient pas.

### 6. Carte de fin de tournée — pas d'overflow
Descendre jusqu'à la carte « Fin de tournée ». **Attendu** : tampon « TON AVIS
COMPTE » + les trois emojis (😴 🙂 🔥), sans plus aucun bloc d'invitation ; la
boîte tient dans l'écran, aucun bandeau jaune/noir d'overflow. Voter, vérifier la
bascule vers « Merci pour ton retour ».

### Cas limites
- **Tournée courte** (moins de 2 sections) : aucune entrée d'invitation, aucun crash.
- **User non éligible** : rien ne se rend (ni entrée, ni modale), et aucun appel à
  `POST /feedback/invite/shown` dans l'onglet réseau.

## Critères d'acceptation
- [ ] L'entrée est atteignable sans scroller jusqu'au tout dernier pixel.
- [ ] L'auto-ouverture ne se produit **qu'une fois**, et seulement quand l'entrée
      est visible.
- [ ] Le lien Google Agenda ouvre une vraie page de réservation.
- [ ] Les trois sorties font trois choses différentes (`accepted` / `declined` /
      `already_done` dans l'onglet réseau).
- [ ] Aucun overflow sur la carte de clôture en 390x844.
- [ ] Console sans erreur, réseau sans 4xx/5xx inattendu.

## Notes techniques
Viewport de test : **390x844**, sémantique activée au boot (cf. skill
`facteur-qa-web` — Flutter web = canvas).
