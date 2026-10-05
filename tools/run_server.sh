#!/bin/sh
# Run the campaign server from the repository (builds it first if needed).
#   tools/run_server.sh [port] [extra scserver flags...]
# Defaults: port 8060, data in ./data, the web build in build/web,
# telemetry in playtest_logs/. Set SC_INVITE_KEY to require an invite key
# for creating campaigns. Ctrl+C stops it cleanly.
set -e
cd "$(dirname "$0")/.."
port=${1:-8060}
[ $# -gt 0 ] && shift
if [ ! -x build/server/scserver ] || [ -n "$(find server -name '*.go' -newer build/server/scserver 2>/dev/null | head -1)" ]; then
	tools/build_server.sh
fi
exec build/server/scserver -addr ":$port" -data "${SC_DATA_DIR:-./data}" -web build/web -log-dir playtest_logs "$@"
