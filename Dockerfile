# syntax=docker/dockerfile:1.6

# ---------- builder ----------
# Full Python image with pip + a compiler available, used only to resolve and
# install dependencies. None of it ships — only /install is copied forward.
FROM python:3.11-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /build

# build-essential is insurance for any C-based transitive dep. psycopg[binary]
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential \
 && rm -rf /var/lib/apt/lists/*

COPY pyproject.toml ./
COPY src/ ./src/

# Install the app + all deps
RUN pip install --upgrade pip \
 && pip install --no-cache-dir --target=/install .


# ---------- runtime ----------
# Debian 12 slim. Wider surface than distroless (has a shell + apt)
FROM python:3.11-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app \
    PORT=8080

# Apply outstanding OS security updates and patch the pip toolchain.
# Then run as a non-root uid matching the chart's securityContext.runAsUser (1000).
RUN apt-get update \
 && apt-get upgrade -y --no-install-recommends \
 && rm -rf /var/lib/apt/lists/* \
 && pip install --no-cache-dir --upgrade pip setuptools wheel \
 && useradd --uid 1000 --no-create-home --shell /usr/sbin/nologin app

WORKDIR /app

# Only the installed packages cross over — no compiler, no pip.
COPY --from=builder /install /app

USER 1000

EXPOSE 8080

# Exec form. Invoke via `python -m` since console scripts aren't on PATH.
ENTRYPOINT ["python", "-m", "uvicorn", "agent.main:app", "--host", "0.0.0.0", "--port", "8080"]
