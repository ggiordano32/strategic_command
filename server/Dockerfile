# Strategic Command server image: the Go binary plus the web export.
# Build from the repository root (the web build must exist: tools/export_web.sh):
#   docker build -f server/Dockerfile -t strategic-command:latest .
# Run (data in a named volume, port 8060):
#   docker run -d --name sc -p 8060:8060 -v sc-data:/data strategic-command:latest
# See docs/SERVER.md.

FROM golang:1.27-alpine AS build
WORKDIR /src
COPY server/go.mod server/go.sum ./
RUN go mod download
COPY server/ ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o /out/scserver ./cmd/scserver \
 && mkdir -p /out/data

# distroless/static: CA certificates (for Discord over HTTPS), tzdata, a
# nonroot user (65532), no shell.
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/scserver /usr/local/bin/scserver
COPY build/web/ /srv/web/
COPY --from=build --chown=65532:65532 /out/data /data
USER 65532:65532
ENV SC_ADDR=:8060 \
    SC_DATA_DIR=/data \
    SC_WEB_DIR=/srv/web \
    SC_LOG_DIR=/data/playtest_logs
VOLUME ["/data"]
EXPOSE 8060
ENTRYPOINT ["/usr/local/bin/scserver"]
