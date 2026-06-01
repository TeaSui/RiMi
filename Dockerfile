# syntax=docker/dockerfile:1
# Root-level Dockerfile for Fly.io (build context = repo root)
# server/ contains the Go application

FROM golang:1.22-alpine AS builder
WORKDIR /build
COPY server/go.mod server/go.sum ./
RUN go mod download
COPY server/ .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /app/server ./cmd/api

FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /app
COPY --from=builder /app/server .
COPY --from=builder /build/migrations/ ./migrations/
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/app/server"]
