#!/bin/sh
# Load Panel.qml in a Quickshell instance of its own, with Omarchy's Commons,
# Ui and services and no window, and print what the projects view shows.
#   tests/panel-harness/run.sh                      the live summary
#   HARNESS_PROJECTS=/nonexistent tests/panel-harness/run.sh   no summary
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
shell="${OMARCHY_PATH:-/usr/share/omarchy}/shell"
for d in Commons Ui services; do ln -sfn "$shell/$d" "$here/$d"; done
HARNESS_PANEL="$(cd "$here/../.." && pwd)/Panel.qml" timeout 40 qs -p "$here" 2>&1 |
    grep -E "HARNESS|Error" | grep -v "host portal" || true
