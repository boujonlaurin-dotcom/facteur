---
status: resolved
trigger: "SQLAlchemy MissingGreenlet error in Facteur backend digest API"
created: "2026-02-04T00:00:00Z"
updated: "2026-02-04T00:00:00Z"
---

## Current Focus

hypothesis: Lazy-loaded relationship access in async context causing MissingGreenlet
test: Found _build_digest_response() uses session.get() without eager loading, then accesses content.source
expecting: Line 408 in digest_service.py triggers lazy load of source relationship
next_action: Confirm this is the root cause and document the fix

## Symptoms

expected: Digest API should return digest data via /api/digest endpoint
actual: 500 error with MissingGreenlet exception, app crashes
errors: "sqlalchemy.exc.MissingGreenlet: greenlet_spawn has not been called; can't call await_only() here"
reproduction: Loading digest via /api/digest endpoint
started: Unknown when it started

## Eliminated

## Evidence

- timestamp: "2026-02-04"
  checked: digest.py router
  found: Uses AsyncSession properly with Depends(get_db), all endpoints are async def
  implication: Router layer is correctly configured for async

- timestamp: "2026-02-04"
  checked: digest_service.py
  found: Uses AsyncSession, all methods are async, uses await for all DB operations
  implication: Service layer appears correctly configured for async

- timestamp: "2026-02-04"
  checked: digest_selector.py
  found: Uses AsyncSession, all methods are async
  implication: Selector layer appears correctly configured for async

- timestamp: "2026-02-04"
  checked: digest_service.py _build_digest_response() method (lines 364-424)
  found: Line 386 uses `await self.session.get(Content, content_id)` without eager loading. Line 408 accesses `content.source` which triggers lazy loading of the relationship
  implication: This is the root cause - accessing a lazy-loaded relationship in async context causes MissingGreenlet error

- timestamp: "2026-02-04"
  checked: Content model (content.py line 70)
  found: `source: Mapped["Source"] = relationship(back_populates="contents")` uses default lazy loading
  implication: Accessing this relationship without eager loading triggers a synchronous database query

- timestamp: "2026-02-04"
  checked: Other methods that work correctly
  found: `_get_emergency_candidates()` and `_get_candidates()` in digest_selector.py both use `.options(selectinload(Content.source))`
  implication: The fix pattern already exists in the codebase - need to apply same pattern to _build_digest_response

## Resolution

root_cause: |
  In `digest_service.py` method `_build_digest_response()` at line 386, content is fetched using 
  `await self.session.get(Content, content_id)` which does NOT eagerly load relationships. 
  Then at line 408, `content.source` is accessed, which triggers SQLAlchemy's lazy-loading 
  mechanism. In async SQLAlchemy, lazy loading requires synchronous database calls which 
  are not allowed without greenlet_spawn, causing the MissingGreenlet error.
  
  The Content model defines the source relationship with default lazy loading:
  `source: Mapped["Source"] = relationship(back_populates="contents")`
  
  When the code tries to access content.source, SQLAlchemy attempts to execute a synchronous
  query to fetch the related Source object, but psycopg (async driver) requires greenlet_spawn
  to bridge sync/async contexts, which hasn't been called.

fix: |
  Replace the `session.get()` call with a proper select query using `selectinload()` to 
  eagerly load the source relationship. This is the same pattern already used in other 
  methods like `_get_emergency_candidates()` and `_get_candidates()`.
  
  Code change needed in digest_service.py, _build_digest_response() method:
  
  FROM (lines 385-393):
  ```python
  # Fetch content details
  content = await self.session.get(Content, content_id)
  if not content:
      logger.warning(...)
      continue
  ```
  
  TO:
  ```python
  # Fetch content details with eager loading of source
  from sqlalchemy.orm import selectinload
  content_result = await self.session.execute(
      select(Content).options(selectinload(Content.source)).where(Content.id == content_id)
  )
  content = content_result.scalar_one_or_none()
  if not content:
      logger.warning(...)
      continue
  ```

verification: |
  1. The /api/digest endpoint should return digest data without 500 errors
  2. No MissingGreenlet exception in logs
  3. Digest items should include proper source information (source.name, source.theme)

files_changed:
  - packages/api/app/services/digest_service.py (lines 385-393)
