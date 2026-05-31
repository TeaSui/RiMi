# Multi-stage, distroless, non-root build (plan A1).
# SECRETS-01: no secrets baked in — all come from env at runtime.

FROM golang:1.22-alpine AS builder
WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /app/server ./cmd/api

FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /app
COPY --from=builder /app/server .
COPY migrations/ ./migrations/
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/app/server"]
