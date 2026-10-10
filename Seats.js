// The limits of every account the panel has seen, kept after a switch.
//
// Each time a provider's limits come in, they are filed under the account
// logged in at that moment (Account.js), as its session and weekly window:
// percent used and reset time. The ledger lives in one JSON file, so an
// account logged out of keeps its last reading, and the panel can say when
// its windows reset.
//
// Plain functions, so the file runs under node too (Seats.test.js).

// The session and weekly windows out of the panel's normalized limit windows
// ({title, percent, resetAt}); the first of each, as on the bar.
function pickWindows(windows) {
  var found = { session: null, weekly: null }
  var list = windows || []
  for (var i = 0; i < list.length; i++) {
    var w = list[i] || {}
    var entry = { percent: Number(w.percent), resetAt: String(w.resetAt || "") }
    if (!(entry.percent >= 0)) continue
    if (w.title === "Session" && !found.session) found.session = entry
    else if (w.title === "Weekly" && !found.weekly) found.weekly = entry
  }
  return found
}

// One seat per provider, email and organization: the same email can hold a
// personal seat and one in an organization.
function key(providerId, account) {
  return String(providerId) + ":" + String(account.email).toLowerCase() + ":" + String(account.org || "")
}

// The ledger with this reading filed; the same ledger when there is nothing
// to file (no account, or neither window).
function record(ledger, providerId, account, windows, nowMs) {
  var accounts = (ledger && ledger.accounts) || {}
  if (!account || !account.email) return ledger
  var picked = pickWindows(windows)
  if (!picked.session && !picked.weekly) return ledger
  var next = {}
  for (var k in accounts) next[k] = accounts[k]
  next[key(providerId, account)] = {
    provider: String(providerId),
    email: String(account.email),
    org: String(account.org || ""),
    session: picked.session,
    weekly: picked.weekly,
    seenAt: new Date(nowMs).toISOString()
  }
  return { schemaVersion: 1, accounts: next }
}

// The parsed ledger, or an empty one for a missing or unreadable file.
function parse(text) {
  try {
    var data = JSON.parse(String(text || ""))
    if (data && typeof data.accounts === "object" && data.accounts) return data
  } catch (e) {}
  return { schemaVersion: 1, accounts: {} }
}

// One provider's accounts other than the current one (an account record
// from Account.js, or null), last seen first.
function others(ledger, providerId, current) {
  var accounts = (ledger && ledger.accounts) || {}
  var currentKey = current && current.email ? key(providerId, current) : ""
  var out = []
  for (var k in accounts) {
    var a = accounts[k]
    if (!a || a.provider !== providerId) continue
    if (key(providerId, a) === currentKey) continue
    out.push(a)
  }
  out.sort(function(x, y) { return String(y.seenAt).localeCompare(String(x.seenAt)) })
  return out
}

// A window as it stands now: once its reset time has passed, the account has
// the whole allowance back, whatever the last reading said.
function project(w, nowMs) {
  if (!w) return null
  var reset = w.resetAt !== "" ? new Date(w.resetAt).getTime() : NaN
  if (isFinite(reset) && reset <= nowMs) return { percent: 0, resetMs: -1, reset: true }
  return { percent: Number(w.percent), resetMs: isFinite(reset) ? reset - nowMs : -1, reset: false }
}

function duration(ms) {
  var minutes = Math.floor(ms / 60000)
  var hours = Math.floor(minutes / 60)
  var days = Math.floor(hours / 24)
  if (days > 0) return days + "d " + (hours % 24) + "h"
  if (hours > 0) return hours + "h " + (minutes % 60) + "m"
  return Math.max(1, minutes) + "m"
}

// "42% · 2h 10m" (used, and time to the reset), "0% · reset" once it has
// reset, "12%" with no reset time known (a session window not yet opened),
// "—" with no reading.
function windowText(w, nowMs) {
  var p = project(w, nowMs)
  if (!p) return "—"
  var text = Math.round(Math.max(0, p.percent) * 100) + "%"
  if (p.reset) return text + " · reset"
  if (p.resetMs > 0) return text + " · " + duration(p.resetMs)
  return text
}

// How long ago an account was last read: "now", "25m", "3h", "2d".
function ageText(seenAt, nowMs) {
  var t = new Date(String(seenAt || "")).getTime()
  if (!isFinite(t)) return ""
  var ms = nowMs - t
  if (ms < 60000) return "now"
  return duration(ms).split(" ")[0]
}

if (typeof module !== "undefined") {
  module.exports = {
    pickWindows: pickWindows,
    record: record,
    parse: parse,
    others: others,
    project: project,
    windowText: windowText,
    ageText: ageText
  }
}
