# ── Build stage ───────────────────────────────
FROM golang:1.22-alpine AS builder

# Install CA certs and git (needed for go get)
RUN apk add --no-cache ca-certificates git

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download

COPY . .
# Build for the target platform's architecture. TARGETARCH is provided
# automatically by BuildKit (e.g. arm64 on Apple Silicon, amd64 on CI), so the
# binary matches the k3d node arch. Falls back to amd64 for non-BuildKit builds.
# CGO disabled → fully static binary, no libc dependency in the final image.
ARG TARGETARCH
RUN CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH:-amd64} \
    go build -ldflags="-w -s" -o /bin/backend .

# ── Final stage ───────────────────────────────
# Distroless: no shell, no package manager, minimal attack surface
FROM gcr.io/distroless/static:nonroot

COPY --from=builder /bin/backend /backend

# nonroot user (uid 65532) baked into distroless image
USER nonroot:nonroot

EXPOSE 8080
ENTRYPOINT ["/backend"]
