#!/bin/sh
# Load Panel.qml in a Quickshell instance of its own, with Omarchy's Commons,
# Ui and services and no window, and print what the projects view shows.
#   tests/panel-harness/run.sh                      the live summary
#   HARNESS_PROJECTS=/nonexistent tests/panel-harness/run.sh   no summary
#   tests/panel-harness/run.sh --cswap              ACCOUNTS, with the cswap stub
#                                                   (prints what it was asked)
# The instance's folder is a temporary one: a plugin folder may hold no
# symlinks (omarchy plugin validate refuses them).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
shell="${OMARCHY_PATH:-/usr/share/omarchy}/shell"
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
cp "$here/shell.qml" "$dir/"
for d in Commons Ui services; do ln -s "$shell/$d" "$dir/$d"; done
if [ "${1:-}" = --cswap ]; then
    export HARNESS_CSWAP="$here/../cswap-stub/cswap" CSWAP_STUB_LOG="$dir/cswap.log"
    : > "$CSWAP_STUB_LOG"
fi
HARNESS_PANEL="$(cd "$here/../.." && pwd)/Panel.qml" timeout 40 qs -p "$dir" 2>&1 |
    grep -E "HARNESS|Error" | grep -v "host portal" || true
if [ -n "${CSWAP_STUB_LOG:-}" ]; then
    sed 's/^/HARNESS stub was run with: /' "$CSWAP_STUB_LOG"
fi
