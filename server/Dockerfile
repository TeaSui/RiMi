# syntax=docker/dockerfile:1
# Multi-stage, distroless, non-root build.
# SECRETS-01: no secrets baked in — all come from env at runtime.

FROM golang:1.22-alpine AS builder
WORKDIR /build
# Cache dependency layer separately — only invalidated when go.mod/go.sum change.
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /app/server ./cmd/api

FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /app
COPY --from=builder /app/server .
COPY --from=builder /build/migrations/ ./migrations/
EXPOSE 8080
USER nonroot:nonroot
# HEALTHCHECK: distroless has no shell/wget, so liveness is delegated to the
# orchestrator (docker-compose healthcheck or DO App Platform http_path probe).
# Both target GET /v1/health, which returns 200 if the DB is reachable.
ENTRYPOINT ["/app/server"]
