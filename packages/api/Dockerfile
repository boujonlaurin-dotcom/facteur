# Facteur API Dockerfile
FROM python:3.12-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY app/ app/

# Create non-root user
RUN adduser --disabled-password --gecos '' appuser
USER appuser

# Expose port (documentation only)
EXPOSE 8000

# Run application - using explicit shell to ensure $PORT expansion
# Added --proxy-headers to trust Railway's proxy (fixes https -> http redirects)
CMD ["/bin/sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --proxy-headers --forwarded-allow-ips='*'"]
