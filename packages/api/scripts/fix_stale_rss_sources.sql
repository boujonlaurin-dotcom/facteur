-- Fix stale RSS sources (2026-02-16)
-- Execute via Supabase SQL Editor
-- Context: ~19 sources with broken feed_url, ~40 Test Sources, SQL echo log spam

BEGIN;

-- ============================================================
-- A. Update repairable sources with new URLs
-- ============================================================

-- RadioFrance migrations (radiofrance.fr → radiofrance-podcast.net)
UPDATE sources SET feed_url = 'https://radiofrance-podcast.net/podcast09/rss_10078.xml'
WHERE name ILIKE '%pieds sur terre%';

UPDATE sources SET feed_url = 'https://radiofrance-podcast.net/podcast09/rss_14312.xml'
WHERE name ILIKE '%science cqfd%';

UPDATE sources SET feed_url = 'https://radiofrance-podcast.net/podcast09/rss_20682.xml'
WHERE name ILIKE '%mecaniques du complot%';

-- France Inter (station → Journal de France Inter podcast)
UPDATE sources SET feed_url = 'https://radiofrance-podcast.net/podcast09/rss_21207.xml'
WHERE name ILIKE '%france inter%';

-- Blast (new RSS URL)
UPDATE sources SET feed_url = 'https://api.blast-info.fr/rss.xml'
WHERE name ILIKE '%blast%' AND type = 'article';

-- Sismique (new Acast ID)
UPDATE sources SET feed_url = 'https://rss.acast.com/sismique'
WHERE name ILIKE '%sismique%';

-- Transfert (Audiomeans dead → Audion)
UPDATE sources SET feed_url = 'https://feeds.360.audion.fm/EZqjvOzZXgWIKWg0EETBQ'
WHERE name ILIKE '%transfert%';

-- Le Collimateur (new Audiomeans UUID)
UPDATE sources SET feed_url = 'https://feeds.audiomeans.fr/feed/64ee3763-1a46-44c2-8640-3a69405a3ad8.xml'
WHERE name ILIKE '%collimateur%';

-- ScienceEtonnante (wrong channel_id)
UPDATE sources SET feed_url = 'https://www.youtube.com/feeds/videos.xml?channel_id=UCaNlbnghtwlsGF-KzAFThqA'
WHERE name ILIKE '%scienceetonnante%';

-- La Croix (redesigned site)
UPDATE sources SET feed_url = 'https://www.la-croix.com/feeds/rss/site.xml'
WHERE name ILIKE '%la croix%';

-- Le Canard Enchaine (new RSS format)
UPDATE sources SET feed_url = 'https://www.lecanardenchaine.fr/rss/index.xml'
WHERE name ILIKE '%canard%';

-- Brut (/rss → /flux-rss)
UPDATE sources SET feed_url = 'https://www.brut.media/fr/flux-rss'
WHERE name ILIKE '%brut%' AND type = 'article';

-- RTS (/rss → ?format=rss/news)
UPDATE sources SET feed_url = 'https://www.rts.ch/info/suisse?format=rss/news'
WHERE name ILIKE '%rts%';

-- Revue Commentaire (WordPress broken → Cairn.info Atom)
UPDATE sources SET feed_url = 'https://shs.cairn.info/rss/revue/COMM'
WHERE name ILIKE '%commentaire%';

-- ============================================================
-- B. Disable sources with no RSS available
-- ============================================================

UPDATE sources SET is_active = false
WHERE name ILIKE ANY(ARRAY['%epsiloon%', '%techtrash%', '%le 1 hebdo%', '%associated press%']);

-- Les Echos (anti-bot 403)
UPDATE sources SET is_active = false
WHERE name ILIKE '%les échos%' OR name ILIKE '%les echos%';

-- ============================================================
-- C. Disable Test Sources (pytest fixtures leaked to prod)
-- ============================================================

UPDATE sources SET is_active = false
WHERE name = 'Test Source';

COMMIT;

-- ============================================================
-- Verification query (run after commit)
-- ============================================================
-- SELECT name, feed_url, is_active, last_synced_at
-- FROM sources
-- WHERE is_active = true
-- ORDER BY last_synced_at DESC NULLS LAST;
