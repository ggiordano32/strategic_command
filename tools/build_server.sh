#!/bin/sh
# Build the campaign server (server/, Go) into build/server/scserver: one
# static binary (pure-Go SQLite, no cgo). Uses `go` from PATH, else the
# user-level toolchain in ~/.local/go (see docs/SERVER.md).
#   tools/build_server.sh [--test]   (--test also runs go vet and go test)
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
mkdir -p ../build/server
CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o ../build/server/scserver ./cmd/scserver
echo "Built build/server/scserver ($(du -h ../build/server/scserver | cut -f1))"
