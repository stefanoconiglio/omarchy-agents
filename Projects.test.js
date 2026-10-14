// node Projects.test.js
const assert = require("assert")
const P = require("./Projects.js")

const fig = (today, week, month, all) => ({ today, week, month, all })
const summary = P.parse(JSON.stringify({
  updated: "2026-10-14 23:04",
  today: "2026-10-14",
  projects: [
    { path: "~/repos/alpha", name: "alpha", agents: { claude: fig(5, 900, 2000, 3000) } },
    { path: "~/repos/beta", name: "beta", agents: { claude: fig(0, 300, 300, 300), codex: fig(1, 50, 50, 50) } },
    { path: "~/old", name: "~/old", agents: { claude: fig(0, 0, 0, 7000) } },
    { path: "Drive:x", name: "Drive:x", agents: { codex: fig(0, 0, 10, 10) } },
    { path: "~/repos/gamma", name: "gamma", agents: { claude: fig(0, 300, 400, 900) } }
  ]
}))

// Parsing: a missing file, a half-written one and a foreign JSON are no summary.
assert.strictEqual(P.parse(""), null)
assert.strictEqual(P.parse("{\"updated\": \"2026"), null)
assert.strictEqual(P.parse("{\"providers\": []}"), null)
assert.ok(summary)

// Top: one agent's, by the last 7 days (ties by everything), the first one full.
const top = P.top(summary, "claude", 3)
assert.deepStrictEqual(top.map(r => r.name), ["alpha", "gamma", "beta"])
assert.deepStrictEqual(top.map(r => r.share), [1, 300 / 900, 300 / 900])
assert.strictEqual(top[0].month, 2000)
assert.deepStrictEqual(P.top(summary, "claude", 1).map(r => r.name), ["alpha"])
// Projects with nothing in the last 7 days are left out; so are other agents'.
assert.deepStrictEqual(P.top(summary, "codex", 4).map(r => r.name), ["beta"])
assert.deepStrictEqual(P.top(summary, "fireworks", 4), [])
assert.deepStrictEqual(P.top(null, "claude", 4), [])

// Count: every project the agent was ever used in.
assert.strictEqual(P.count(summary, "claude"), 4)
assert.strictEqual(P.count(summary, "codex"), 2)
assert.strictEqual(P.count(null, "codex"), 0)

// The stamp: the time on the day it was written, the date too after.
assert.strictEqual(P.stampText(summary, "2026-10-14"), "23:04")
assert.strictEqual(P.stampText(summary, "2026-10-15"), "2026-10-14 23:04")

const format = n => String(n)
assert.strictEqual(P.rowTooltip(top[0], summary, "2026-10-14", format),
  "~/repos/alpha\nToday 5 · 7 days 900 · 30 days 2000 · all 3000\nAs of 23:04 · click for its days")

console.log("Projects: all tests passed")
