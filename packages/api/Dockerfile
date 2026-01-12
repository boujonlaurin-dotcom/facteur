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

# Expose port
EXPOSE 8000

# Run application
# On utilise une chaine pour shell execution afin que $PORT soit interprété
CMD uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}

