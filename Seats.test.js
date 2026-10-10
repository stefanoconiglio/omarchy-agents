// node Seats.test.js
const assert = require("assert")
const S = require("./Seats.js")

const now = Date.parse("2026-10-10T12:00:00Z")
const windows = [
  { title: "Session", percent: 0.42, resetAt: "2026-10-10T14:10:00Z" },
  { title: "Weekly", percent: 0.63, resetAt: "2026-10-13T16:00:00Z" },
  { title: "Opus 5", percent: 0.9, resetAt: "2026-10-13T16:00:00Z" }
]

// Picking: the first Session and Weekly, model-scoped windows ignored.
const picked = S.pickWindows(windows)
assert.deepStrictEqual(picked.session, { percent: 0.42, resetAt: "2026-10-10T14:10:00Z" })
assert.strictEqual(picked.weekly.percent, 0.63)

// Filing: under provider and email (case-insensitive), replacing the old reading.
let ledger = S.parse("")
assert.deepStrictEqual(ledger.accounts, {})
ledger = S.record(ledger, "claude", { email: "a@x.it", org: "Uni" }, windows, now)
ledger = S.record(ledger, "claude", { email: "B@y.com", org: "" }, windows.slice(1, 2), now + 1000)
ledger = S.record(ledger, "claude", { email: "A@x.it", org: "Uni" }, windows.slice(0, 1), now + 2000)
assert.strictEqual(Object.keys(ledger.accounts).length, 2)
assert.strictEqual(ledger.accounts["claude:a@x.it:Uni"].weekly, null)
assert.strictEqual(ledger.accounts["claude:b@y.com:"].session, null)

// The same email in another organization is another seat.
const seats = S.record(ledger, "claude", { email: "a@x.it", org: "a@x.it's Organization" }, windows, now)
assert.strictEqual(Object.keys(seats.accounts).length, 3)
assert.deepStrictEqual(S.others(seats, "claude", { email: "a@x.it", org: "Uni" }).map(a => a.org),
  ["", "a@x.it's Organization"])

// Nothing filed without an account or without windows.
assert.strictEqual(S.record(ledger, "claude", {}, windows, now), ledger)
assert.strictEqual(S.record(ledger, "claude", { email: "c@z" }, [], now), ledger)

// Round trip through the file.
assert.deepStrictEqual(S.parse(JSON.stringify(ledger)), ledger)
assert.deepStrictEqual(S.parse("{broken").accounts, {})

// Others: not the current account, not other providers, last seen first.
ledger = S.record(ledger, "codex", { email: "a@x.it" }, windows, now)
let rest = S.others(ledger, "claude", { email: "a@x.it", org: "Uni" })
assert.deepStrictEqual(rest.map(a => a.email), ["B@y.com"])
rest = S.others(ledger, "claude", null)
assert.deepStrictEqual(rest.map(a => a.email), ["A@x.it", "B@y.com"])

// Fresh probes only: not filed before, made after the credentials changed.
const seat = { email: "a@x.it", org: "Uni", fetchedAtMs: 5000, credentialsMs: 4000 }
assert.strictEqual(S.freshProbe(S.parse(""), "claude", seat), true)
const filed = S.record(S.parse(""), "claude", seat, windows, now, seat.fetchedAtMs)
assert.strictEqual(filed.probes.claude, 5000)
assert.strictEqual(S.freshProbe(filed, "claude", seat), false)
assert.strictEqual(S.freshProbe(filed, "claude", Object.assign({}, seat, { fetchedAtMs: 6000 })), true)
assert.strictEqual(S.freshProbe(filed, "codex", seat), true)
// The bug this guards against: the figures of the seat logged in before
// (probed at 5000), read after a switch to another seat (credentials 5500).
assert.strictEqual(S.freshProbe(S.parse(""), "claude",
  { email: "a@x.it", org: "a@x.it's Organization", fetchedAtMs: 5000, credentialsMs: 5500 }), false)
assert.strictEqual(S.freshProbe(S.parse(""), "claude", {}), false)
// Filing without a probe time keeps the probes already recorded.
assert.strictEqual(S.record(filed, "codex", { email: "c@z" }, windows, now).probes.claude, 5000)

// Texts.
assert.strictEqual(S.windowText(picked.session, now), "42% · 2h 10m")
assert.strictEqual(S.windowText(picked.weekly, now), "63% · 3d 4h")
assert.strictEqual(S.windowText(picked.session, Date.parse("2026-10-10T15:00:00Z")), "0% · reset")
assert.strictEqual(S.windowText({ percent: 0.12, resetAt: "" }, now), "12%")
assert.strictEqual(S.windowText(null, now), "—")
assert.strictEqual(S.ageText("2026-10-10T11:59:30Z", now), "now")
assert.strictEqual(S.ageText("2026-10-10T11:35:00Z", now), "25m")
assert.strictEqual(S.ageText("2026-10-10T09:00:00Z", now), "3h")
assert.strictEqual(S.ageText("2026-10-08T09:00:00Z", now), "2d")

console.log("Seats.js: all assertions pass")
