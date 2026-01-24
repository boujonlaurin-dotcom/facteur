# Facteur API Dockerfile
FROM python:3.12-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --timeout 300 --retries 5 -r requirements.txt

# Copy application AND required configs/scripts
COPY app/ app/
COPY alembic.ini .
COPY alembic/ alembic/
COPY scripts/ scripts/

# Create non-root user
RUN adduser --disabled-password --gecos '' appuser
USER appuser

# Expose port (documentation only)
EXPOSE 8000

# Run migrations before starting the API when DATABASE_URL is available.
# Use explicit shell to ensure $PORT expansion.
# Added --proxy-headers to trust Railway's proxy (fixes https -> http redirects).
CMD ["/bin/sh", "-c", "if [ -n \"${DATABASE_URL:-}\" ]; then for i in 1 2 3 4 5 6 7 8 9 10; do alembic upgrade head && MIGRATED=1 && break; echo \"Migrations failed (attempt $i/10), retrying in 10s...\"; sleep 10; done; if [ -z \"${MIGRATED:-}\" ]; then echo \"Migrations failed after retries\"; exit 1; fi; else echo \"Skipping migrations: DATABASE_URL not set\"; fi && uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --proxy-headers --forwarded-allow-ips='*'"]
