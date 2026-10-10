#!/bin/bash

# Which Claude seat the collector's last limits probe measured, for the
# ledger of other accounts (Seats.js).
#
# The seat is asked of Anthropic with the login token itself
# (api/oauth/profile), so it is always the account of the token the collector
# probed with: ~/.claude.json, which the panel's hero reads, can name another
# seat for a while after a switch, as every running Claude Code rewrites it.
# The answer is cached per token (a hash of it names the file), so the lookup
# runs once per login or token refresh, not on every probe. The token never
# leaves this script: it reaches curl on stdin, not on the command line.
#
# Prints one JSON object:
#   {"email", "org", "fetchedAtMs", "credentialsMs"}
# fetchedAtMs: when the collector last probed (its claude-limits.json);
# credentialsMs: when the credentials last changed. A probe older than the
# credentials may have measured the seat logged in before. Prints {} when
# there is no login, and nothing (exit 1) when the lookup fails.

set -u

dir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
credentials=$dir/.credentials.json
cache=${XDG_CACHE_HOME:-$HOME/.cache}
probe=$cache/omarchy/agent-usage/claude-limits.json
profiles=$cache/omarchy/agents/profiles

token=$(jq -r '.claudeAiOauth.accessToken // empty' "$credentials" 2>/dev/null)
if [[ -z $token ]]; then
  echo '{}'
  exit 0
fi

credentials_ms=$(( $(stat -c %Y "$credentials") * 1000 ))
fetched_ms=$(jq -r '.fetchedAtMs // 0' "$probe" 2>/dev/null || echo 0)

umask 077
mkdir -p "$profiles"
seat=$profiles/$(printf '%s' "$token" | sha256sum | cut -c1-32).json
if [[ ! -s $seat ]]; then
  answer=$(printf 'header = "Authorization: Bearer %s"\nheader = "anthropic-beta: oauth-2025-04-20"\n' "$token" \
    | curl -sf -m 10 -K - https://api.anthropic.com/api/oauth/profile \
    | jq -ce '{email: (.account.email // ""), org: (.organization.name // "")} | select(.email != "")') || exit 1
  printf '%s\n' "$answer" > "$seat.tmp" && mv "$seat.tmp" "$seat"
  # One file per token: keep the last 20.
  ls -1t "$profiles"/*.json 2>/dev/null | tail -n +21 | xargs -r rm -f
fi

jq -c --argjson fetched "$fetched_ms" --argjson credentials "$credentials_ms" \
  '. + {fetchedAtMs: $fetched, credentialsMs: $credentials}' "$seat"
