# 🛡️ Infrastructure Guidelines

## G1: Docker Build Completeness
> **"If it's imported or executed, it must be in the Docker image."**

Before adding `import X` or `subprocess.exec("scripts/Y.py")`, verify X/Y is copied in the Dockerfile.

**Checklist before deploy:**
- [ ] New Python imports → File is in `COPY app/`
- [ ] New scripts → Added to `COPY scripts/`  
- [ ] New config files → Explicitly copied

---

## G2: Graceful Startup Degradation
> **"Non-essential checks should warn, not crash."**

| Scenario | Action |
|----------|--------|
| Config file missing | ⚠️ Log warning, continue |
| DB slow/unreachable | ⚠️ Log warning, continue |
| Schema mismatch | 🔴 Crash (data integrity) |

---

## G3: Sandbox C-Binding Libraries
> **"C-binding libraries must be process-isolated."**

Libraries with native C extensions (`curl_cffi`, `playwright`, heavy ML) can crash the event loop.

**Solutions:**
1. Subprocess (current: `scripts/fetch_rss.py`)
2. Separate microservice/worker

---

## G4: Port Hygiene
> **"Always check port before starting server."**

```bash
lsof -i :8080  # Check what's using the port
kill -9 <PID>  # Force kill zombie if needed
```

---

## CI Protection

The `build-docker.yml` workflow runs on every push to `packages/api/` and:
1. Builds the Docker image
2. Verifies critical files exist (`alembic.ini`, `alembic/`, `scripts/`)
3. Tests that container starts without crash
