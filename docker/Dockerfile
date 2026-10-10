# syntax=docker/dockerfile:1

# Build from the repository root:
#   docker build -f docker/Dockerfile -t items-api:dev .

ARG GO_VERSION=1.26

# ---- build stage -----------------------------------------------------------
# Runs on the builder's native platform and cross-compiles, so multi-arch
# builds do not need QEMU emulation.
FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine AS build
WORKDIR /src

# Dependency layer first so it is cached until go.mod changes. (The app has
# no third-party modules today; this keeps the Dockerfile correct if it gains
# some. Add go.sum to this COPY at that point.)
COPY app/go.mod ./
RUN go mod download

COPY app/ ./

ARG TARGETOS
ARG TARGETARCH
ARG VERSION=dev
RUN --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -trimpath -ldflags="-s -w -X main.version=${VERSION}" -o /out/items-api .

# ---- runtime stage ---------------------------------------------------------
# Distroless "static": CA certificates, tzdata, /etc/passwd and nothing else.
# No shell, no package manager, no libc. The :nonroot tag defaults to UID 65532.
FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=build /out/items-api /items-api

# Numeric UID:GID so Kubernetes can verify runAsNonRoot without resolving names.
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/items-api"]
