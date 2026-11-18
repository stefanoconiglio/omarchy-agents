#!/bin/sh
# Load Panel.qml in a Quickshell instance of its own, with Omarchy's Commons,
# Ui and services and no window, and print what the projects view shows.
#   tests/panel-harness/run.sh                      the live summary
#   HARNESS_PROJECTS=/nonexistent tests/panel-harness/run.sh   no summary
#   tests/panel-harness/run.sh --cswap              ACCOUNTS, with the cswap stub
#                                                   (prints what it was asked, and
#                                                   PASS or FAIL for the pin and
#                                                   the bar after a switch)
#   HARNESS_PANEL=/elsewhere/Panel.qml tests/panel-harness/run.sh --cswap
#                                                   another copy of the panel
# The instance's folder is a temporary one: a plugin folder may hold no
# symlinks (omarchy plugin validate refuses them). The usage update the
# panel runs (bin/agents-usage-update, setting usageCommand) is replaced by a
# stub that does nothing (tests/usage-stub/, also first on PATH in place of
# Omarchy's omarchy-agent-usage-update): the panel reads the usage records on
# this machine as they are, and never rewrites them or reads the transcripts.
# PASS when the panel ran the stub, FAIL when it did not.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
shell="${OMARCHY_PATH:-/usr/share/omarchy}/shell"
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
cp "$here/shell.qml" "$dir/"
export HARNESS_USAGE="$here/../usage-stub/omarchy-agent-usage-update" USAGE_STUB_LOG="$dir/usage.log"
: > "$USAGE_STUB_LOG"
for d in Commons Ui services; do ln -s "$shell/$d" "$dir/$d"; done
if [ "${1:-}" = --cswap ]; then
    export HARNESS_CSWAP="$here/../cswap-stub/cswap" CSWAP_STUB_LOG="$dir/cswap.log" CSWAP_STUB_STATE="$dir/cswap.active"
    : > "$CSWAP_STUB_LOG"
fi
HARNESS_PANEL="${HARNESS_PANEL:-$(cd "$here/../.." && pwd)/Panel.qml}" PATH="$here/../usage-stub:$PATH" \
    timeout 40 qs -p "$dir" 2>&1 |
    grep -E "HARNESS|Error" | grep -v "host portal" || true
if [ -n "${CSWAP_STUB_LOG:-}" ]; then
    sed 's/^/HARNESS stub was run with: /' "$CSWAP_STUB_LOG"
fi
if [ -s "$USAGE_STUB_LOG" ]; then
    echo "HARNESS PASS the panel ran the usage stub: $(head -n1 "$USAGE_STUB_LOG")"
else
    echo "HARNESS FAIL the panel never ran the usage stub (usageCommand not honoured?)"
fi
