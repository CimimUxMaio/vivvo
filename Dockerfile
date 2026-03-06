# ───────── Stage 1: Build Release ─────────
# Use official Elixir image with Node for assets
FROM elixir:1.19-otp-28-alpine AS builder

# Install build dependencies
RUN apk add --no-cache git build-base nodejs npm curl bash

# Set working directory
WORKDIR /app

# Copy mix.exs and mix.lock first (for caching deps)
COPY mix.exs mix.lock ./

# Install Elixir dependencies
RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get && \
    mix deps.compile

# Copy config (for production releases)
COPY config config

# Copy the rest of the code
COPY lib lib
COPY priv priv

# Compile the project
RUN MIX_ENV=prod mix compile

# ───────── Stage 2: Build assets ─────────
# Copy assets for caching Node/NPM deps
COPY assets/package.json assets/package-lock.json ./assets/
RUN cd assets && npm ci

# Copy assets source
COPY assets assets
RUN cd assets && npm run deploy

# Digest assets to priv/static
RUN MIX_ENV=prod mix phx.digest

# Build release
RUN MIX_ENV=prod mix release

# ───────── Stage 3: Runtime ─────────
FROM alpine:3.23 AS app
RUN apk add --no-cache bash openssl ncurses-libs

# Set environment variables
ENV MIX_ENV=prod \
    REPLACE_OS_VARS=true \
    LANG=C.UTF-8 \
    PORT=4000

WORKDIR /app

# Copy release from builder
COPY --from=builder /app/_build/prod/rel/vivvo ./

# Expose port
EXPOSE 4000

# Start the Phoenix release
CMD ["bin/vivvo", "start"]
