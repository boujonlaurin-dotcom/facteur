"""Jobs package for background tasks and scheduled operations.

This package contains jobs that run periodically to perform
background operations like digest generation, content syncing,
and analytics aggregation.

Exports:
    DigestGenerationJob: Daily batch digest generation
    run_digest_generation: Entry point for batch generation
    generate_digest_for_user: On-demand single user generation
"""

from app.jobs.digest_generation_job import (
    DigestGenerationJob,
    generate_digest_for_user,
    run_digest_generation,
)

__all__ = ["DigestGenerationJob", "run_digest_generation", "generate_digest_for_user"]
