# Facteur Admin Backoffice Dockerfile (Streamlit)
FROM python:3.12-slim

WORKDIR /app

# Install dependencies (copy to /tmp to avoid shadowing the source copy below)
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir --timeout 300 --retries 5 -r /tmp/requirements.txt

# Copy application files into /app/admin/ so that
# "from admin.utils.xxx import ..." works with PYTHONPATH=/app
COPY . admin/

# Set Python path so admin package is importable
ENV PYTHONPATH=/app

# Create non-root user
RUN adduser --disabled-password --gecos '' appuser
USER appuser

# Expose port (documentation only)
EXPOSE 8501

# Run Streamlit
# --server.headless true  disables browser auto-open (required for production)
# --server.address 0.0.0.0 listens on all interfaces (required for Railway)
# PORT variable is injected by Railway
CMD ["/bin/sh", "-c", "streamlit run admin/app.py --server.port ${PORT:-8501} --server.address 0.0.0.0 --server.headless true"]
