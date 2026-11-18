// The account each CLI is logged in with, for the line under the hero.
//
// Claude Code keeps it in .claude.json (oauthAccount); Codex in auth.json,
// inside the id token. accountProbe() gives the jq filter that pulls it out,
// which prints {} when the file is gone (logged out) and nothing when the file
// can't be parsed (Claude Code rewrites its file often), so a bad read keeps
// the last value.

function claudeFilter() {
  return '{email: (.oauthAccount.emailAddress // ""), org: (.oauthAccount.organizationName // "")}'
}

// The id token's payload is base64url without padding; jq wants base64.
function codexFilter() {
  return '{email: (try (.tokens.id_token | split(".")[1] | gsub("-"; "+") | gsub("_"; "/")'
    + ' | . as $s | ($s + ("==" | .[0:((4 - ($s | length) % 4) % 4)])) | @base64d | fromjson'
    + ' | .email // "") catch "")}'
}

function accountProbe(file, filter) {
  return ["sh", "-c", 'if [ -e "$1" ]; then exec jq -c "$2" "$1"; else echo "{}"; fi',
          "sh", file, filter]
}

// The parsed record, or null when the output is not a whole JSON object.
function parseRecord(raw) {
  var text = String(raw || "").trim()
  if (text === "") return null
  try {
    var record = JSON.parse(text)
    return record && typeof record === "object" ? record : null
  } catch (e) {
    return null
  }
}

// A Claude seat on a personal plan sits in an organization the service names
// "<email>'s Organization"; any other name is a seat in someone's organization.
// Codex shows the email alone: its workspace title is "Personal" even on an
// education plan, which would mislead.
function lines(providerId, record) {
  if (!record || !record.email) return []
  var email = String(record.email)
  if (providerId !== "claude") return [email]
  var org = String(record.org || "")
  if (org === "") return [email]
  if (org === email + "'s Organization") return [email, "Personal account"]
  return [email, org]
}

if (typeof module !== "undefined") {
  module.exports = {
    claudeFilter: claudeFilter,
    codexFilter: codexFilter,
    accountProbe: accountProbe,
    parseRecord: parseRecord,
    lines: lines
  }
}
