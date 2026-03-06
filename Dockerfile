# syntax=docker/dockerfile:1.7

############################
# Builder
############################
FROM elixir:1.19-otp-28-alpine AS builder

RUN apk add --no-cache \
    build-base \
    git \
    nodejs \
    npm \
    bash

WORKDIR /app

ENV MIX_ENV=prod

# Install hex/rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Install deps (cache friendly)
COPY mix.exs mix.lock ./

RUN --mount=type=cache,target=/root/.cache/mix \
    mix deps.get --only prod

RUN --mount=type=cache,target=/root/.cache/mix \
    mix deps.compile

# Copy config
COPY config config

# Compile deps that depend on config
RUN --mount=type=cache,target=/root/.cache/mix \
    mix deps.compile

# Copy source
COPY lib lib
COPY priv priv
COPY assets assets

# Compile
RUN mix compile

# Build assets
RUN mix assets.deploy

# Build release
RUN mix release

############################
# Runtime
############################
FROM alpine:3.23 AS app

RUN apk add --no-cache \
    openssl \
    ncurses-libs \
    libstdc++ \
    curl

WORKDIR /app

COPY --from=builder /app/_build/prod/rel/vivvo ./

ENV HOME=/app
ENV MIX_ENV=prod

CMD ["bin/vivvo", "start"]
