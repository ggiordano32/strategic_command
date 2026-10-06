#!/bin/sh
# Build the campaign server (server/, Go) into build/server/scserver: one
# static binary (pure-Go SQLite, no cgo). Uses `go` from PATH, else the
# user-level toolchain in ~/.local/go (see docs/SERVER.md).
#   tools/build_server.sh [--test]   (--test also runs go vet and go test)
# SC_BUILD_OUT=path builds there instead (tests use a scratch path so the
# binary of a running server is never replaced).
set -e
cd "$(dirname "$0")/.."
if ! command -v go >/dev/null 2>&1; then
	PATH="$HOME/.local/go/bin:$PATH"
fi
cd server
if [ "$1" = "--test" ]; then
	go vet ./...
	go test ./...
fi
out=${SC_BUILD_OUT:-../build/server/scserver}
case "$out" in /*) ;; *) [ -n "$SC_BUILD_OUT" ] && out="../$SC_BUILD_OUT" ;; esac
mkdir -p "$(dirname "$out")"
CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o "$out" ./cmd/scserver
echo "Built $out ($(du -h "$out" | cut -f1))"
