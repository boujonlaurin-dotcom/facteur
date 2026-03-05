# ─────────────────────────────────────────────
# Stage 1 — Build Flutter Web
# ─────────────────────────────────────────────
FROM debian:bookworm-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl git unzip xz-utils zip ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ENV FLUTTER_VERSION=3.38.6
ENV FLUTTER_HOME=/opt/flutter
ENV PATH="$FLUTTER_HOME/bin:$PATH"

RUN git clone --depth 1 --branch $FLUTTER_VERSION \
    https://github.com/flutter/flutter.git $FLUTTER_HOME

# Enable web & pre-download artifacts
RUN flutter config --enable-web && flutter precache --web

WORKDIR /app

# Résoudre les dépendances en premier (cache layer)
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

# Copier le reste de l'app
COPY . .

# ── Build args (baked at build time via --dart-define) ──────────────────────
ARG API_BASE_URL=https://facteur-production.up.railway.app/api
ARG SUPABASE_URL
ARG SUPABASE_ANON_KEY
ARG POSTHOG_API_KEY
ARG APP_RELEASE_TAG

RUN flutter build web --release \
    --dart-define="API_BASE_URL=${API_BASE_URL}" \
    --dart-define="SUPABASE_URL=${SUPABASE_URL}" \
    --dart-define="SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}" \
    --dart-define="POSTHOG_API_KEY=${POSTHOG_API_KEY}" \
    --dart-define="APP_RELEASE_TAG=${APP_RELEASE_TAG}"

# ─────────────────────────────────────────────
# Stage 2 — Serve avec nginx
# ─────────────────────────────────────────────
FROM nginx:alpine

# Supprimer la conf par défaut
RUN rm /etc/nginx/conf.d/default.conf

# Le répertoire templates/ est traité par envsubst au démarrage du container
# → $PORT est injecté par Railway au runtime
COPY nginx.conf.template /etc/nginx/templates/default.conf.template

COPY --from=builder /app/build/web /usr/share/nginx/html

# Railway expose dynamiquement $PORT (pas forcément 80)
EXPOSE 8080
