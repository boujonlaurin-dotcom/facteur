# Bug: Healthcheck Railway bloque par migrations Alembic manquantes

## Status: InProgress

## Date: 24/01/2026

## Symptome

- Deploiements Railway en FAILED avec raison "Healthcheck failure".
- Logs: `Can't locate revision identified by 'a8da35e3c12b'` lors de `alembic upgrade head`.
- L'app s'arrete au startup, le healthcheck ne demarre pas.
 - Build echoue intermittente: `pip install` timeout sur le download de `torch` (gros package).
- Nouveau crash: container lance sans `DATABASE_URL` et `alembic upgrade head` plante avec `NoSuchModuleError`.
- Nouveau crash: migrations Alembic echouent par timeout de pool DB au demarrage (pooler Supabase).

## Cause probable

- Migration Alembic `a8da35e3c12b_merge_heads.py` (et migrations liees) non versionnees dans Git.
- La base est deja au revision `a8da35e3c12b`, mais le code deploye ne la contient pas.

## Correctif cible

- Versionner les migrations Alembic manquantes (`a8da35e3c12b`, `f7e8a9b0c1d2`, `b7d6e5f4c3a2`, `1a2b3c4d5e6f`).
- Redeployer le service et verifier que `alembic upgrade head` passe.
 - Stabiliser le build Docker avec un timeout/retries plus permissifs sur `pip install`.
- Skipper les migrations si `DATABASE_URL` n'est pas defini (startup de build Railway/CI).
- Preferer le host DB direct Supabase pour les migrations afin d'eviter le pooler, avec resolution IPv4 si possible.
- Garder des retries plus longs sur `alembic upgrade head` pour gerer les timeouts transitoires.

## Verification

- `railway logs --deployment <ID>` ne contient plus d'erreur Alembic.
- `curl -i https://facteur-production.up.railway.app/api/health` retourne 200.
