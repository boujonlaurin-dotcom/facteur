---
status: resolved
trigger: "Investigate the database session setup and async configuration in the Facteur backend. SQLAlchemy MissingGreenlet error when calling digest API."
created: "2026-02-04T00:00:00Z"
updated: "2026-02-04T00:00:00Z"
---

## Current Focus

hypothesis: MISSING GREENLET DEPENDENCY - SQLAlchemy async requires greenlet for context switching
status: CONFIRMED

## Symptoms

expected: Digest API should work with async database queries
actual: SQLAlchemy MissingGreenlet error when calling digest API
errors: MissingGreenlet error in psycopg.py when executing database queries
started: User reports async database session not properly configured

## Evidence

- timestamp: 2026-02-04
  checked: packages/api/app/database.py
  found: Async engine configured with psycopg driver (postgresql+psycopg://)
  implication: Using psycopg 3.x with native async support - configuration is correct

- timestamp: 2026-02-04
  checked: packages/api/app/config.py
  found: Database URL validator converts +asyncpg to +psycopg
  implication: Forcing psycopg driver over asyncpg - psycopg 3.x is preferred

- timestamp: 2026-02-04
  checked: packages/api/requirements.txt
  found: psycopg[binary,pool]>=3.2.0 (psycopg 3.x)
  implication: Modern psycopg with native async support

- timestamp: 2026-02-04
  checked: packages/api/pyproject.toml
  found: asyncpg>=0.29.0 listed but not used
  implication: Inconsistent dependency specification

- timestamp: 2026-02-04
  checked: packages/api/requirements.txt
  found: No explicit greenlet dependency
  implication: SQLAlchemy async requires greenlet for context switching

- timestamp: 2026-02-04
  checked: SQLAlchemy source in venv
  found: SQLAlchemy uses greenlet for _AsyncIoGreenlet class
  implication: greenlet is a required dependency for SQLAlchemy async

## Resolution

root_cause: MISSING GREENLET DEPENDENCY - SQLAlchemy async requires greenlet for context switching between sync and async code

fix_recommendation: Add greenlet>=3.0.0 to requirements.txt

files_involved:
  - packages/api/requirements.txt (needs greenlet added)
  - packages/api/pyproject.toml (should align dependencies)
