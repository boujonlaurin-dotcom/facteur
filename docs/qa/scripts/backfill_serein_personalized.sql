-- Story 15.1 — Mode Serein Refine — Backfill `serein_personalized` sentinel
--
-- WHY: la nouvelle sémantique de `apply_serein_filter` traite la valeur stockée
-- de `sensitive_themes` comme un REMPLACEMENT verbatim des défauts
-- (`SEREIN_EXCLUDED_THEMES`). Avant cette story, la valeur stockée était
-- UNION'd avec les défauts. Sans ce backfill, tout utilisateur ayant
-- personnalisé `sensitive_themes` (par ex. `["culture"]`) perdrait
-- silencieusement les 4 défauts (politics/society/international/economy)
-- après deploy.
--
-- HOW (deux étapes, à exécuter dans l'ordre, dans une seule transaction) :
--   1. UPDATE : merger les 4 défauts dans la valeur JSON existante (dedup),
--      pour les utilisateurs qui n'ont PAS encore le sentinelle.
--   2. INSERT : poser `serein_personalized='true'` pour ces mêmes
--      utilisateurs.
--
-- Idempotent : la clause `user_id NOT IN (... serein_personalized ...)`
-- exclut les utilisateurs déjà flaggés, donc une seconde exécution est un
-- no-op. Étapes 1 et 2 doivent rester groupées : sinon, en cas
-- d'interruption entre les deux, certains utilisateurs auraient leur liste
-- mergée mais pas le sentinelle (ce qui est sans effet — la branche `else`
-- de `load_serein_preferences` retombe sur les défauts).
--
-- NOTE : pas de contrainte unique composite (user_id, preference_key) sur
-- `user_preferences` ; on s'appuie sur le filtre `NOT IN` pour
-- l'idempotence.

BEGIN;

-- 0) Preview : combien d'utilisateurs vont être traités ?
-- SELECT COUNT(DISTINCT user_id) FROM user_preferences
-- WHERE preference_key = 'sensitive_themes'
--   AND user_id NOT IN (
--     SELECT user_id FROM user_preferences WHERE preference_key = 'serein_personalized'
--   );

-- 1) Merge des défauts dans la liste existante (dedup, garde la valeur
--    JSON existante si elle est invalide ou non-array → safety net).
UPDATE user_preferences AS up
SET preference_value = (
        SELECT jsonb_agg(elem)::text
        FROM (
            SELECT jsonb_array_elements_text(up.preference_value::jsonb) AS elem
            UNION
            SELECT unnest(ARRAY['politics', 'society', 'international', 'economy']) AS elem
        ) merged
    ),
    updated_at = NOW()
WHERE preference_key = 'sensitive_themes'
  AND preference_value IS NOT NULL
  AND jsonb_typeof(preference_value::jsonb) = 'array'
  AND user_id NOT IN (
      SELECT user_id FROM user_preferences WHERE preference_key = 'serein_personalized'
  );

-- 2) Pose du sentinelle `serein_personalized='true'` pour les mêmes utilisateurs.
INSERT INTO user_preferences (id, user_id, preference_key, preference_value, created_at, updated_at)
SELECT
    gen_random_uuid(),
    sub.user_id,
    'serein_personalized',
    'true',
    NOW(),
    NOW()
FROM (
    SELECT DISTINCT user_id
    FROM user_preferences
    WHERE preference_key = 'sensitive_themes'
      AND user_id NOT IN (
          SELECT user_id FROM user_preferences WHERE preference_key = 'serein_personalized'
      )
) AS sub;

COMMIT;

-- 3) Vérifier (post-COMMIT) :
-- SELECT COUNT(*) FROM user_preferences WHERE preference_key = 'serein_personalized';
-- SELECT preference_value FROM user_preferences WHERE preference_key = 'sensitive_themes' LIMIT 5;
