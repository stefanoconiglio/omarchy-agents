// node Swap.test.js
const assert = require("assert")
const fs = require("fs")
const path = require("path")
const S = require("./Swap.js")

const now = Date.parse("2026-10-10T12:00:00Z")
const list = fs.readFileSync(path.join(__dirname, "tests/cswap-stub/list.json"), "utf8")

// The command and what is run with it.
assert.deepStrictEqual(S.command(""), ["cswap"])
assert.deepStrictEqual(S.command("  uvx  claude-swap "), ["uvx", "claude-swap"])
assert.deepStrictEqual(S.listArgv(["cswap"]), ["cswap", "list", "--json"])
assert.deepStrictEqual(S.switchArgv(["cswap"], 4), ["cswap", "switch", "4", "--json"])
assert.deepStrictEqual(S.tuiArgv(["cswap"]), ["omarchy-launch-tui", "--app-id=TUI.float", "cswap", "tui"])

// cswap auto: the unit's command line and one typed in a terminal match;
// the dashboard, a one-off `auto --once` from another program's name, and a
// shell that merely mentions it in quotes do not.
const pattern = new RegExp(S.autoArgv(["cswap"])[2])
assert.deepStrictEqual(S.autoArgv(["cswap"]).slice(0, 2), ["pgrep", "-f"])
assert.ok(pattern.test("/home/u/.local/share/uv/tools/claude-swap/bin/python /home/u/.local/bin/cswap auto --json"))
assert.ok(pattern.test("cswap auto"))
assert.ok(!pattern.test("/usr/bin/python /home/u/.local/bin/cswap"))
assert.ok(!pattern.test("/usr/bin/python /home/u/.local/bin/cswap autoswitch"))
assert.ok(!pattern.test("bash -c pgrep -af 'cswap auto'"))
assert.ok(new RegExp(S.autoArgv(["/x/y/my.swap"])[2]).test("/x/y/my.swap auto"))
assert.ok(!new RegExp(S.autoArgv(["/x/y/my.swap"])[2]).test("/x/y/myXswap auto"))

// Parsing: every seat in cswap's order, the active one, the windows as fractions.
const parsed = S.parse(list)
assert.strictEqual(parsed.ok, true)
assert.strictEqual(parsed.active, 2)
assert.deepStrictEqual(parsed.seats.map(s => s.number), [1, 2, 4])
const [lab, personal, bob] = parsed.seats
assert.deepStrictEqual(lab.windows.map(w => w.label), ["5h", "7d", "Fable"])
assert.deepStrictEqual(lab.windows[0],
  { label: "5h", percent: 0.42, resetAt: "2026-10-10T14:10:00+00:00", clock: "16:10", ahead: false })
assert.strictEqual(lab.windows[1].percent, 0.63)
assert.strictEqual(lab.windows[1].ahead, true)
assert.strictEqual(lab.windows[2].percent, 0.05)
assert.strictEqual(lab.alias, "lab")
assert.strictEqual(lab.org, "Example Lab")
assert.strictEqual(personal.active, true)
assert.deepStrictEqual(personal.windows.map(w => w.label), ["5h", "7d"])
assert.deepStrictEqual(personal.windows[0], { label: "5h", percent: 0, resetAt: "", clock: "", ahead: false })
// A seat whose login expired keeps its last reading, marked stale.
assert.strictEqual(bob.stale, true)
assert.strictEqual(bob.disabled, true)
assert.strictEqual(bob.status, "token_expired")
assert.strictEqual(bob.windows[1].percent, 0.91)
assert.strictEqual(bob.ageSeconds, 7200)

// No cswap, a failure, something else: no seats.
assert.deepStrictEqual(S.parse(""), { ok: false, error: "", active: 0, seats: [] })
assert.deepStrictEqual(S.parse("{broken"), { ok: false, error: "", active: 0, seats: [] })
assert.strictEqual(S.parse('{"schemaVersion":1,"error":{"type":"X","message":"no accounts"}}').error, "no accounts")
assert.strictEqual(S.parse('{"accounts": [{"email": "x"}]}').seats.length, 0)

// A switch's answer.
assert.deepStrictEqual(S.switchResult('{"switched":true,"message":"Switched to Account-4"}', 0),
  { ok: true, switched: true, message: "Switched to Account-4" })
assert.deepStrictEqual(S.switchResult('{"schemaVersion":1,"error":{"type":"A","message":"No account 3"}}', 1),
  { ok: false, switched: false, message: "No account 3" })
assert.strictEqual(S.switchResult("", 127).message, "cswap switch failed (exit 127)")
assert.strictEqual(S.switchResult('{"switched":false,"message":"Already on Account-2"}', 0).switched, false)

// After a switch to seat 1: the pin on it at once, the list otherwise as read.
const switched = S.afterSwitch(parsed, 1)
assert.strictEqual(switched.active, 1)
assert.deepStrictEqual(switched.seats.map(s => s.active), [true, false, false])
assert.deepStrictEqual(switched.seats[0].windows, lab.windows)
assert.strictEqual(parsed.active, 2)
assert.strictEqual(personal.active, true)

// The bar's numbers from a seat: 5h and 7d, as they stand now.
assert.deepStrictEqual(S.pillWindows(lab, now),
  { session: { percent: 0.42, resetMs: (2 * 60 + 10) * 60000 }, weekly: { percent: 0.63, resetMs: ((3 * 24 + 4) * 60) * 60000 } })
assert.deepStrictEqual(S.pillWindows(personal, now).session, { percent: 0, resetMs: -1 })
assert.deepStrictEqual(S.pillWindows(lab, Date.parse("2026-10-10T15:00:00Z")).session, { percent: 0, resetMs: -1 })
// No reading of the seat: no numbers, never the previous seat's.
assert.deepStrictEqual(S.pillWindows(unreadSeat(), now), { session: null, weekly: null })
assert.deepStrictEqual(S.pillWindows(null, now), { session: null, weekly: null })
function unreadSeat() { return S.parse('{"accounts":[{"number":5,"usage":null}]}').seats[0] }

// The bug (7 Nov 2026): Omarchy's collector hands back a reading under 15 s
// old whoever's seat it was, so a record written just after a switch may be
// the old seat's; the bar keeps cswap's reading of the new seat until a record
// written 25 s after the switch.
const at = Date.parse("2026-11-07T11:01:05Z")
assert.strictEqual(S.standIn(0, at), false)
assert.strictEqual(S.standIn(at, at - 90000), true)
assert.strictEqual(S.standIn(at, at + 5000), true)
assert.strictEqual(S.standIn(at, at + 24999), true)
assert.strictEqual(S.standIn(at, at + 25000), false)
assert.strictEqual(S.standIn(at, 0), true)

// A record's time, with the microseconds Python writes.
assert.strictEqual(S.timeMs("2026-11-07T11:02:31.508600+00:00"), Date.UTC(2026, 10, 7, 11, 2, 31, 508))
assert.strictEqual(S.timeMs("2026-11-07T11:02:31+00:00"), Date.UTC(2026, 10, 7, 11, 2, 31))
assert.strictEqual(S.timeMs(""), 0)
assert.strictEqual(S.timeMs(undefined), 0)
assert.strictEqual(S.timeMs("garbage"), 0)

// Texts.
assert.strictEqual(S.badge(lab), "#1 lab")
assert.strictEqual(S.badge(personal), "#2")
assert.strictEqual(S.note(personal), "active")
assert.strictEqual(S.note(bob), "held out")
assert.strictEqual(S.note(Object.assign({}, bob, { disabled: false })), "token expired")
assert.strictEqual(S.note(Object.assign({}, bob, { disabled: false, status: "unavailable" })), "old reading")
assert.strictEqual(S.note(lab), "")
// No reading at all: the failure cswap names.
const unread = S.parse('{"accounts":[{"number":5,"email":"c@example.net","usageStatus":"unavailable","usage":null,"usageError":"http-429"}]}').seats[0]
assert.strictEqual(S.note(unread), "http-429")
const [five, week, fable] = lab.windows
assert.strictEqual(S.percentText(five, now), "42%")
assert.strictEqual(S.resetText(five, now), "2h 10m")
assert.strictEqual(S.resetText(week, now), "3d 4h")
assert.strictEqual(S.percentText(five, Date.parse("2026-10-10T15:00:00Z")), "0%")
assert.strictEqual(S.resetText(five, Date.parse("2026-10-10T15:00:00Z")), "reset")
assert.strictEqual(S.resetText(personal.windows[0], now), "")
assert.strictEqual(S.percentText(null, now), "—")
assert.strictEqual(S.windowDetail(five, now), "5h 42% · resets 2h 10m · 16:10")
assert.strictEqual(S.windowDetail(week, now), "7d 63% · resets 3d 4h · Oct 13 18:00 · ahead of pace")
assert.strictEqual(S.windowDetail(personal.windows[0], now), "5h 0%")
assert.strictEqual(S.windowDetail(five, Date.parse("2026-10-10T15:00:00Z")), "5h 0% · reset")

console.log("Swap.js: all assertions pass")
