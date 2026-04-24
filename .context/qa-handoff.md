# QA Handoff — PR3 Catalogue Feature Nudges (Story 16.1)

**Branche** : `boujonlaurin-dotcom/nudge-catalogue`
**Base** : `main` (rebasée sur `9b29a44a`)
**Scope** : 6 feature nudges + kill switch Supabase + télémétrie PostHog

---

## ⚠️ Avant de tester — action manuelle requise

Le MCP Supabase est en read-only. **Appliquer manuellement** le SQL suivant via l'éditeur SQL Supabase avant tout test du kill switch :

Fichier : `.context/nudges-pr3-app-config.sql`

```sql
create table if not exists public.app_config (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);
alter table public.app_config enable row level security;
create policy "app_config readable by authenticated"
  on public.app_config for select to authenticated using (true);
insert into public.app_config(key, value)
  values ('nudges_enabled', 'true'::jsonb)
  on conflict (key) do nothing;
```

Vérification : `select * from public.app_config;` doit retourner `nudges_enabled = true`.

---

## Écrans et surfaces touchés

| Nudge                          | Surface                                 | Placement      | Trigger                                                      |
|--------------------------------|-----------------------------------------|----------------|--------------------------------------------------------------|
| `priority_slider_explainer`    | Sheet priorité source (long-press src)  | Inline banner  | 1ʳᵉ ouverture de la sheet                                    |
| `article_save_notes`           | Détail article (colonne FAB bookmark)   | Tooltip        | 1ʳᵉ ouverture article (legacy `has_seen_note_welcome` lu)    |
| `article_read_on_site`         | Détail article (fin d'article)          | Inline banner  | 4ᵉ article ouvert + scroll ≥ 50%                             |
| `feed_badge_longpress`         | Feed — 1ʳᵉ carte                        | Spotlight      | 2ᵉ ouverture Feed + ≥ 1 tap carte (prereq: welcome_tour vu)  |
| `feed_preview_longpress`       | Feed — 1ʳᵉ carte                        | Spotlight      | 3ᵉ ouverture Feed + ≥ 2 articles ouverts (prereq: badge vu)  |
| `perspectives_cta`             | Détail article (PerspectivesPill)       | Pulse 1×       | 2ᵉ article avec perspectives non-vides                       |

---

## Scénarios de validation (Chrome mobile viewport 390×844)

### Scénario 1 — priority_slider_explainer
1. Login compte test (reset prefs si besoin).
2. Feed → long-press badge source d'une carte → sheet priorité s'ouvre.
3. **Vérifier** : banner inline DM Sans au-dessus du slider avec copie « Glissez pour ajuster l'importance… ».
4. Tap le `X` → banner disparaît.
5. Fermer sheet, rouvrir → banner n'apparaît plus.

### Scénario 2 — article_save_notes (migration legacy)
1. Ouvrir 1ᵉʳ article.
2. **Vérifier** : tooltip DM Sans apparaît près du bookmark FAB avec « Sauvegardez cet article et ajoutez-y des notes personnelles. »
3. Tap sur le tooltip → disparition.
4. Rouvrir un autre article → pas de tooltip.
5. **Régression legacy** : pour un user qui avait `has_seen_note_welcome=true` avant PR3, vérifier qu'il ne voit PAS le tooltip (`NudgeStorage.isSeen()` lit la legacy key).

### Scénario 3 — article_read_on_site
1. Reset prefs (ou compte neuf).
2. Ouvrir 4 articles différents (peu importe le scroll sur les 3 premiers).
3. Sur le 4ᵉ article, scroller jusqu'à ≥50%.
4. **Vérifier** : banner inline apparaît en fin d'article avec « Préférez l'expérience du site original ? » + bouton « Ouvrir ».
5. Tap « Ouvrir » → navigateur externe s'ouvre, banner disparaît.
6. Rouvrir 4 autres articles → banner n'apparaît plus (markSeen).

### Scénario 4 — feed_badge_longpress
1. Reset prefs, compte avec welcome_tour déjà vu.
2. Ouvrir Feed (1ʳᵉ fois) → aucun nudge.
3. Tap sur une carte (ouvrir un article). Revenir au Feed (2ᵉ ouverture).
4. **Vérifier** : spotlight overlay sur la 1ʳᵉ balise (topic chip en priorité) avec bulle « Appuyez longuement sur une balise… ».
5. Long-press la balise pointée → conversion détectée, spotlight disparaît, sheet d'édition topic s'ouvre.
6. Rouvrir Feed → spotlight n'apparaît plus.

### Scénario 5 — feed_preview_longpress
1. Après avoir vu et dismiss `feed_badge_longpress` (prereq).
2. Ouvrir 2 articles de plus (total articleOpenCount ≥ 2).
3. Retourner au Feed (3ᵉ ouverture).
4. **Vérifier** : spotlight sur la 1ʳᵉ carte entière avec bulle « Appuyez longuement sur une carte pour un aperçu rapide… ».
5. Long-press la carte → aperçu article s'ouvre, spotlight disparaît.

### Scénario 6 — perspectives_cta
1. Ouvrir 1 article qui a des perspectives (non-vides, shouldDisplay=true) → aucun pulse.
2. Ouvrir 2ᵉ article avec perspectives.
3. **Vérifier** : pulse 1× (1.0 → 1.08 → 1.0, ~600ms) sur le bouton Perspectives flottant. Pas de boucle.
4. Tap le bouton Perspectives → scroll vers la section, conversion émise.
5. Rouvrir d'autres articles → plus de pulse.

### Scénario 7 — kill switch (nécessite accès dashboard Supabase)
1. Dans Supabase : `update public.app_config set value='false'::jsonb where key='nudges_enabled';`
2. Restart l'app.
3. **Vérifier** : aucun des 6 nudges n'apparaît. Le welcome tour reste inchangé (priority=critical).
4. Remettre à `true` + restart → les nudges non-vus peuvent à nouveau apparaître.

### Scénario 8 — queue + session budget (AC-15)
1. Scénario combiné : provoquer 2 nudges non-critical la même session.
2. **Vérifier** : seul le 1ᵉʳ s'affiche, le 2ᵉ est bloqué par le budget 1/session.
3. Cooldown global 24 h : après dismiss d'un nudge non-critical, un autre non-critical ne doit pas s'afficher.

---

## Télémétrie PostHog à vérifier

Dans PostHog, filtrer sur events `nudge_shown` et `nudge_dismissed`. Properties attendues :

```json
{
  "nudge_id": "article_save_notes",
  "surface": "article",
  "placement": "tooltip",
  "priority": "normal",
  "outcome": "dismissed"
}
```

Confirmer qu'un `nudge_shown` est émis à chaque apparition, et qu'un `nudge_dismissed` avec `outcome=converted` est émis sur tap CTA (read_on_site "Ouvrir", perspectives pill tap, long-press badge, long-press card).

---

## Cas limites à re-vérifier

- **Feed vide** : user dont Feed retourne 0 articles → `feed_badge_longpress` doit pouvoir s'afficher quand le feed se remplit ensuite.
- **Article sans topic chip** : `feed_badge_longpress` cible le badge source en fallback.
- **Article sans perspectives** : `perspectives_cta` ne doit jamais se déclencher.
- **Scroll scroll-to-site actif** (articles avec `hasInAppContent`) : `article_read_on_site` s'affiche quand même à ≥50%.

---

## Rollback

- Kill switch immédiat : `update public.app_config set value='false'::jsonb where key='nudges_enabled';` — effet au prochain boot client (fallback `true` si row absente).
- Full rollback code : revert du merge commit.
