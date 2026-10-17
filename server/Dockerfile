# Strategic Command game server image. Two targets:
#   server  the API and live battle relay only, no web build (the public image)
#   full    server plus the web export in /srv/web (the default; the official
#           server). Needs build/web: tools/export_web.sh.
# Build from the repository root:
#   docker build -f server/Dockerfile --target server -t strategic-command-server .
#   docker build -f server/Dockerfile -t strategic-command:latest .       # full
# Run (data in a named volume, port 8060):
#   docker run -d --name sc -p 8060:8060 -v sc-data:/data strategic-command-server
# See server/README.md and docs/SERVER.md.

FROM golang:1.27-alpine AS build
ARG TARGETOS TARGETARCH
WORKDIR /src
COPY server/go.mod server/go.sum ./
RUN go mod download
COPY server/ ./
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -ldflags "-s -w" -o /out/scserver ./cmd/scserver \
 && mkdir -p /out/data

# distroless/static: CA certificates (for Discord over HTTPS), tzdata, a
# nonroot user (65532), no shell.
FROM gcr.io/distroless/static-debian12:nonroot AS server
COPY --from=build /out/scserver /usr/local/bin/scserver
COPY --from=build --chown=65532:65532 /out/data /data
USER 65532:65532
ENV SC_ADDR=:8060 \
    SC_DATA_DIR=/data \
    SC_WEB_DIR= \
    SC_LOG_DIR=/data/playtest_logs
VOLUME ["/data"]
EXPOSE 8060
ENTRYPOINT ["/usr/local/bin/scserver"]

FROM server AS full
COPY build/web/ /srv/web/
ENV SC_WEB_DIR=/srv/web
