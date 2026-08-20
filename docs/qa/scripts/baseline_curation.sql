-- Baseline « qualité de la curation » — requêtes de référence
-- Cf. docs/bugs/bug-curation-essentiel-personnalisation.md
--
-- Rejouer avec :
--   psql "$DATABASE_URL_RO" -X -f docs/qa/scripts/baseline_curation.sql
-- Résultats figés au 01/08/2026 :
--   docs/bugs/bug-curation-essentiel-personnalisation-baseline.md
--
-- Prérequis : `ALTER ROLE claude_analytics_ro BYPASSRLS;` (appliqué le 2026-08-01).
-- Sans lui, daily_digest / contents / user_content_status renvoient 0 ligne
-- (RLS) et toutes les métriques ci-dessous sortent vides SANS erreur.
--
-- Fenêtre : 30 jours glissants. `rank` 1-5 = ce que la carte « Ton Essentiel »
-- affiche réellement ; 6-10 = généré puis tronqué, jamais vu.

\set ON_ERROR_STOP on
\timing off

-- Depuis le bump v4 (score mixte, PR 4), v3 et v4 coexistent ~30 j : M1-M4
-- sont groupées par format_version pour lire l'avant/après en un seul run,
-- sans jamais mélanger les cohortes.
-- ⚠️ Jumeau Python : `packages/api/scripts/dryrun_subject_mix.py` réimplémente
-- M1-M4 (seuils 0.50/0.10, zones 1-5/6-10) pour le re-tri simulé — toute
-- retouche de définition ici doit y être répercutée.
CREATE TEMP VIEW slots AS
SELECT
    d.user_id,
    d.target_date,
    d.mode,
    d.format_version,
    (s ->> 'rank')::int                              AS rank,
    s ->> 'theme'                                    AS theme,
    (s -> 'actu_article' ->> 'content_id')::uuid     AS content_id,
    (s -> 'actu_article' ->> 'source_id')::uuid      AS source_id,
    s -> 'actu_article' ->> 'source_name'            AS source_name,
    (s -> 'actu_article' ->> 'is_user_source')::bool AS is_user_source,
    s ->> 'selection_reason'                         AS selection_reason,
    (s ->> 'source_count')::int                      AS source_count
FROM daily_digest d,
     LATERAL jsonb_array_elements(d.items -> 'subjects') s
WHERE d.target_date >= CURRENT_DATE - 30
  AND d.format_version LIKE 'editorial\_v%'
  AND jsonb_typeof(s -> 'actu_article') = 'object';

CREATE TEMP VIEW top5 AS SELECT * FROM slots WHERE rank BETWEEN 1 AND 5;

\echo '=== M1 — Slots du top-5 quasi-universels vs réellement personnels ==='
-- Un slot est « quasi-universel » si l'article qui l'occupe est présent dans le
-- top-5 d'au moins 50 % des utilisateurs servis ce jour-là dans ce mode ;
-- « personnel » s'il l'est chez moins de 10 %.
WITH day_users AS (
    SELECT target_date, mode, format_version, COUNT(DISTINCT user_id) AS users_total
    FROM top5 GROUP BY 1, 2, 3
),
art_share AS (
    SELECT t.target_date, t.mode, t.format_version, t.content_id,
           COUNT(DISTINCT t.user_id)::float / du.users_total AS share
    FROM top5 t JOIN day_users du USING (target_date, mode, format_version)
    GROUP BY t.target_date, t.mode, t.format_version, t.content_id, du.users_total
)
SELECT t.format_version, t.mode,
       COUNT(*)                                                        AS slots,
       ROUND((100.0 * AVG((a.share >= 0.50)::int))::numeric, 1)        AS pct_quasi_universels,
       ROUND((100.0 * AVG((a.share <  0.10)::int))::numeric, 1)        AS pct_personnels
FROM top5 t JOIN art_share a USING (target_date, mode, format_version, content_id)
GROUP BY t.format_version, t.mode ORDER BY t.format_version, t.mode;

\echo ''
\echo '=== M2 — Personnalisation affichee (1-5) vs tronquee (6-10) ==='
SELECT format_version,
       CASE WHEN rank <= 5 THEN '1-5 (affiche)' ELSE '6-10 (jamais vu)' END AS zone,
       COUNT(*)                                                     AS slots,
       ROUND((100.0 * AVG(is_user_source::int))::numeric, 1)        AS pct_source_suivie,
       ROUND((100.0 * AVG((source_count = 1)::int))::numeric, 1)    AS pct_mono_source
FROM slots WHERE rank BETWEEN 1 AND 10
GROUP BY 1, 2 ORDER BY 1, 2;

\echo ''
\echo '=== M3 — Repartition des themes dans le top-5 ==='
SELECT format_version,
       COALESCE(theme, '(null)')                                  AS theme,
       COUNT(*)                                                   AS slots,
       ROUND((100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY format_version))::numeric, 1) AS pct_top5
FROM top5 GROUP BY 1, 2 ORDER BY 1, 3 DESC;

\echo ''
\echo '=== M4 — Pourvoyeurs : part du top-5 et CTR ==='
SELECT s.format_version,
       s.source_name,
       COUNT(*)                                                      AS slots,
       ROUND((100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY s.format_version))::numeric, 2) AS pct_top5,
       COUNT(ucs.content_id)                                         AS lus,
       ROUND((100.0 * COUNT(ucs.content_id) / COUNT(*))::numeric, 2) AS ctr_pct
FROM top5 s
LEFT JOIN user_content_status ucs
       ON ucs.user_id = s.user_id
      AND ucs.content_id = s.content_id
      AND ucs.status = 'consumed'
GROUP BY s.format_version, s.source_name ORDER BY 3 DESC LIMIT 15;

\echo ''
\echo '=== M5 — CTR du top-5 : source suivie vs non suivie ==='
SELECT CASE WHEN s.is_user_source THEN 'source suivie' ELSE 'source non suivie' END AS zone,
       COUNT(*)                                                      AS slots,
       COUNT(ucs.content_id)                                         AS lus,
       ROUND((100.0 * COUNT(ucs.content_id) / COUNT(*))::numeric, 2) AS ctr_pct
FROM top5 s
LEFT JOIN user_content_status ucs
       ON ucs.user_id = s.user_id
      AND ucs.content_id = s.content_id
      AND ucs.status = 'consumed'
GROUP BY 1 ORDER BY 1;

\echo ''
\echo '=== M6 — CTR global du top-5 (metrique de non-regression) ==='
SELECT COUNT(*)                                                      AS slots,
       COUNT(ucs.content_id)                                         AS lus,
       ROUND((100.0 * COUNT(ucs.content_id) / COUNT(*))::numeric, 2) AS ctr_pct
FROM top5 s
LEFT JOIN user_content_status ucs
       ON ucs.user_id = s.user_id
      AND ucs.content_id = s.content_id
      AND ucs.status = 'consumed';

\echo ''
\echo '=== M7 — selection_reason : taux d acces au top-5 ==='
SELECT selection_reason,
       COUNT(*) FILTER (WHERE rank <= 5)                             AS top5,
       COUNT(*)                                                      AS total,
       ROUND((100.0 * COUNT(*) FILTER (WHERE rank <= 5) / COUNT(*))::numeric, 1) AS pct_atteint_top5
FROM slots WHERE rank BETWEEN 1 AND 10
GROUP BY 1 HAVING COUNT(*) >= 200 ORDER BY 3 DESC;

-- ============================================================================
-- Bloc C-1 (PR 3) — signal `perso` : santé de user_interests / user_subtopics.
-- ⚠️ Ces tables ne sont PAS couvertes par le GRANT de claude_analytics_ro
--    (BYPASSRLS ne donne pas le SELECT). Lancer ce bloc via le rôle service
--    (MCP Supabase) ou après un `GRANT SELECT ON user_interests, user_subtopics
--    TO claude_analytics_ro;`. Valeurs figées au 02/08/2026.
-- ============================================================================

\echo ''
\echo '=== M8 — user_interests sur un theme MUTE (attendu 0 apres migration) ==='
SELECT COUNT(*) AS lignes, COUNT(DISTINCT ui.user_id) AS comptes
FROM user_interests ui
JOIN user_personalization up ON up.user_id = ui.user_id
WHERE ui.interest_slug = ANY(COALESCE(up.muted_themes, '{}'));

\echo ''
\echo '=== M9 — user_interests fabriques (1,0 < weight < 1,2) : ne plus croitre ==='
SELECT COUNT(*) FILTER (WHERE weight > 1.0 AND weight < 1.2) AS fabriques,
       COUNT(*)                                             AS total
FROM user_interests;

\echo ''
\echo '=== M10 — users a amplitude user_subtopics < 0,2 (signal plat) ==='
WITH amp AS (
    SELECT user_id, MAX(weight) - MIN(weight) AS amplitude
    FROM user_subtopics GROUP BY user_id
)
SELECT COUNT(*) FILTER (WHERE amplitude < 0.2) AS users_plats,
       COUNT(*)                                AS users_total
FROM amp;

\echo ''
\echo '=== M11 — doublons (user_id, topic_slug) dans user_subtopics (attendu 0) ==='
SELECT COUNT(*) AS paires_en_double
FROM (
    SELECT user_id, topic_slug
    FROM user_subtopics
    GROUP BY user_id, topic_slug
    HAVING COUNT(*) > 1
) t;
