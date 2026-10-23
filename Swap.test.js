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
assert.deepStrictEqual(lab.session, { percent: 0.42, resetAt: "2026-10-10T14:10:00+00:00" })
assert.strictEqual(lab.weekly.percent, 0.63)
assert.strictEqual(lab.alias, "lab")
assert.strictEqual(lab.org, "Example Lab")
assert.strictEqual(personal.active, true)
assert.deepStrictEqual(personal.session, { percent: 0, resetAt: "" })
// A seat whose login expired keeps its last reading, marked stale.
assert.strictEqual(bob.stale, true)
assert.strictEqual(bob.disabled, true)
assert.strictEqual(bob.status, "token_expired")
assert.strictEqual(bob.weekly.percent, 0.91)
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

// Texts.
assert.strictEqual(S.badge(lab), "#1 lab")
assert.strictEqual(S.badge(personal), "#2")
assert.strictEqual(S.note(personal), "active")
assert.strictEqual(S.note(bob), "held out")
assert.strictEqual(S.note(Object.assign({}, bob, { disabled: false })), "token expired")
assert.strictEqual(S.note(Object.assign({}, bob, { disabled: false, status: "unavailable" })), "old reading")
assert.strictEqual(S.note(lab), "")
assert.strictEqual(S.windowText(lab.session, now), "42% · 2h 10m")
assert.strictEqual(S.windowText(lab.weekly, now), "63% · 3d 4h")
assert.strictEqual(S.windowText(lab.session, Date.parse("2026-10-10T15:00:00Z")), "0% · reset")
assert.strictEqual(S.windowText(personal.session, now), "0%")
assert.strictEqual(S.windowText(null, now), "—")

console.log("Swap.js: all assertions pass")
