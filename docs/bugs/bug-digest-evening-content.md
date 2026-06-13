# Bug — Digest rempli d'articles d'hier soir (~22h)

> Statut : fix prêt — décalage du cron 06:00 → 07:30 Paris.

## Observation utilisateur

Le digest "Essentiel" du matin contient des articles datés de la veille au soir (~22h), pas les Unes du matin attendues. Reporté plusieurs fois sur des digests générés à 06:01 Paris, avec des articles publiés entre 22h la veille et 04h ce matin.

## Cause racine (confirmée par les données prod)

Le digest est bien **généré à 06:01 Paris** (le cron fonctionne, la timezone est correcte). Le problème n'est pas le moment de génération — c'est le **contenu sélectionné**.

À 06:00 Paris, le pool d'articles candidats (`packages/api/app/jobs/digest_generation_job.py:329`) est :
```python
cutoff = datetime.now(UTC) - timedelta(hours=48)
stmt.where(Content.published_at >= cutoff).order_by(Content.published_at.desc()).limit(200)
```
Les 200 contenus les plus récents à 06:00 Paris sont mécaniquement ceux publiés entre **~22h la veille et 04h ce matin** (édition du soir + dépêches nocturnes). **Les Unes du matin** (Le Monde ~06h30, Le Figaro ~07h, Libération ~07h) **ne sont pas encore publiées** quand le cron démarre.

### Preuve : digest Essentiel du 13/05 (généré à 06:01:33 Paris)

Sujet rank 1 — « Mort en garde à vue à Agde » :
- Le Figaro : publié 12/05 22:28 Paris
- lanouvellerepublique.fr : publié 12/05 23:08 Paris
- Le Monde : publié 13/05 01:05 Paris

### Distribution `published_at` par heure Paris (7 derniers jours)

```
h_paris | articles
--------+---------
   0    | 122
   1    | 106
   2    | 101
   3    |  64
   4    |  83
   5    | 215   ← rampe AFP / wires nocturnes
   6    | 509   ← saut net : Unes du matin commencent à tomber
   7    | 490
   8    | 438
   9    | 408
  ...   |
```

Le saut 215 → 509 entre 5h et 6h Paris est la fenêtre de publication des Unes du matin. À 07:30 Paris, le pool candidat couvre intégralement cette fenêtre.

## Pourquoi les patchs précédents ont raté

Les agents précédents ont cherché :
- Des bugs de timezone (correct : UTC vs Paris)
- Des bugs de cron APScheduler
- Des bugs de notif Android
- Des bugs de throughput batch

Personne n'a regardé **le `published_at` des articles dans le digest** — la vraie observation utilisateur. Le timestamp `generated_at` du digest est correct ; les *articles* dedans ne le sont pas.

Le commentaire du code disait explicitement la cause (`scheduler.py:186` avant fix) :
> *« 6h00 Paris — avancé de 8h pour pré-générer avant le réveil »*

L'intention (digest prêt quand l'utilisateur se réveille) était bonne, l'effet est inverse : on génère **avant** que les rédactions n'aient publié leurs Unes du matin.

## Correction

Décalage du cron 06:00 → **07:30 Paris** :

| Fichier | Avant | Après |
|---------|-------|-------|
| `app/workers/scheduler.py` — `DIGEST_CRON_HOUR_PARIS` | `6` | `7` |
| `app/workers/scheduler.py` — `DIGEST_CRON_MINUTE_PARIS` | (absent, implicite `0`) | `30` |
| `app/workers/scheduler.py` — trigger `daily_digest` | 06:00 | 07:30 |
| `app/workers/scheduler.py` — trigger `digest_watchdog` | 07:30 | 08:15 (après le cron principal) |
| `app/main.py` — garde catchup | `if now.hour < CRON_HOUR` | `if now_minutes < cron_minutes or now.hour >= 10` |
| `tests/workers/test_scheduler.py` | assertions hour=6, watchdog 7:30 | hour=7 minute=30, watchdog 8:15 |
| `docs/data-architecture/data-pipeline.md` | 08:00 (déjà périmé) | 07:30 |

### Garde catchup : pourquoi `hour >= 10` ?

Avant : `if now.hour < DIGEST_CRON_HOUR_PARIS: return` — un redéploiement Railway l'après-midi laissait passer le catchup, qui pouvait régénérer un digest avec du contenu d'après-midi. Après : fenêtre stricte `[07:30, 10:00[`. Si la fenêtre est ratée, on attend le lendemain — mieux qu'un digest pourri à 16h.

## Ce qui n'est PAS le bug (pistes mortes)

- Timezone APScheduler → OK
- `now_paris()` / `today_paris()` → OK (`zoneinfo`, vérifié)
- Throughput batch / variantes is_serene=false générées tard → existe mais c'est **secondaire** (impact 1-2 users par jour) ; à observer après le patch principal pour décider s'il faut l'attaquer aussi
- Notifs Android locales → 100% device-side, sans impact sur le contenu serveur

## Monitoring post-merge

Sur 3-5 jours, refaire la requête « `published_at` des articles dans le digest du jour » pour confirmer que les Unes du matin remontent :

```sql
SELECT
  dd.target_date,
  dd.generated_at AT TIME ZONE 'Europe/Paris' AS gen_paris,
  c.published_at AT TIME ZONE 'Europe/Paris' AS pub_paris,
  c.source_id, c.title
FROM daily_digest dd
CROSS JOIN LATERAL jsonb_array_elements(dd.articles) AS art
JOIN contents c ON c.id = (art->>'content_id')::uuid
WHERE dd.target_date = current_date
  AND dd.is_serene = false
ORDER BY dd.user_id, pub_paris DESC
LIMIT 50;
```

Critère de succès : la majorité des articles ont `pub_paris` du jour entre 05h et 07h30, pas la veille au soir.
