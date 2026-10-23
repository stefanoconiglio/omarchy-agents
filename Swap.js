// The Claude seats claude-swap (`cswap`) manages, for the panel's ACCOUNTS.
//
// cswap keeps every seat's login and reads each one's 5-hour and weekly use
// (`cswap list --json`); the panel shows them, switches seat with
// `cswap switch <n> --json` and opens `cswap tui`. The command is a setting
// (cswapCommand), so a test can drive a stub instead.
//
// Plain functions, so the file runs under node too (Swap.test.js).

// The words of the command, from the setting ("cswap" when empty).
function command(setting) {
  var words = String(setting || "").trim().split(/\s+/).filter(function(w) { return w !== "" })
  return words.length > 0 ? words : ["cswap"]
}

function listArgv(words) { return words.concat(["list", "--json"]) }
function switchArgv(words, number) { return words.concat(["switch", String(number), "--json"]) }
function tuiArgv(words) { return ["omarchy-launch-tui", "--app-id=TUI.float"].concat(words, ["tui"]) }

// Whether `cswap auto` runs: a process whose command line runs the command's
// program with `auto` (the unit `cswap auto --json`, or one in a terminal).
// pgrep runs without a shell, so its own command line is not matched.
function autoArgv(words) {
  var name = String(words[0]).split("/").pop().replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
  return ["pgrep", "-f", "(^|/)" + name + " auto( |$)"]
}

// One window: percent used as a fraction, as Omarchy's limits are, and its
// reset time (empty when the window has not opened yet).
function windowOf(w) {
  if (!w || !(Number(w.pct) >= 0)) return null
  return { percent: Number(w.pct) / 100, resetAt: String(w.resetsAt || "") }
}

// The parsed list: {ok, error, active, seats}. ok is false when the output is
// not cswap's list (no cswap, a failure); error names the failure cswap gave.
function parse(text) {
  var data = null
  try { data = JSON.parse(String(text || "")) } catch (e) {}
  if (!data || typeof data !== "object") return { ok: false, error: "", active: 0, seats: [] }
  if (data.error) return { ok: false, error: String(data.error.message || data.error.type || "error"), active: 0, seats: [] }
  if (!Array.isArray(data.accounts)) return { ok: false, error: "", active: 0, seats: [] }
  var seats = []
  for (var i = 0; i < data.accounts.length; i++) {
    var a = data.accounts[i] || {}
    if (!(Number(a.number) > 0)) continue
    // Usage too old to act on, or a seat whose login has expired, still has
    // its last reading: shown, marked stale.
    var usage = a.usage || a.lastGoodUsage || null
    var age = a.usage ? a.usageAgeSeconds : a.lastGoodAgeSeconds
    seats.push({
      number: Number(a.number),
      email: String(a.email || ""),
      org: String(a.organizationName || ""),
      alias: String(a.alias || ""),
      active: a.active === true,
      disabled: a.disabled === true,
      status: String(a.usageStatus || ""),
      stale: !a.usage,
      ageSeconds: Number(age) >= 0 ? Number(age) : -1,
      session: usage ? windowOf(usage.fiveHour) : null,
      weekly: usage ? windowOf(usage.sevenDay) : null
    })
  }
  seats.sort(function(x, y) { return x.number - y.number })
  return { ok: true, error: "", active: Number(data.activeAccountNumber) || 0, seats: seats }
}

// What a switch said: {ok, switched, message}. A switch that printed nothing
// readable failed.
function switchResult(text, exitCode) {
  var data = null
  try { data = JSON.parse(String(text || "")) } catch (e) {}
  if (data && data.error) return { ok: false, switched: false, message: String(data.error.message || "switch failed") }
  if (!data || exitCode !== 0) return { ok: false, switched: false, message: "cswap switch failed (exit " + exitCode + ")" }
  return { ok: true, switched: data.switched === true, message: String(data.message || "") }
}

// "#2 dev", "#2": the seat's number as cswap counts it, and its alias.
function badge(seat) {
  return "#" + seat.number + (seat.alias ? " " + seat.alias : "")
}

// What the seat's line says on the right: why it can't be switched to, or
// how old its reading is.
function note(seat) {
  if (seat.active) return "active"
  if (seat.disabled) return "held out"
  if (seat.status && seat.status !== "ok" && seat.status !== "unavailable") return seat.status.replace(/_/g, " ")
  if (seat.stale) return "old reading"
  return ""
}

// A window as it stands now: once its reset time has passed, the seat has
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

if (typeof module !== "undefined") {
  module.exports = {
    command: command,
    listArgv: listArgv,
    switchArgv: switchArgv,
    tuiArgv: tuiArgv,
    autoArgv: autoArgv,
    parse: parse,
    switchResult: switchResult,
    badge: badge,
    note: note,
    project: project,
    windowText: windowText
  }
}
