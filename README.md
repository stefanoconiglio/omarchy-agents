# Agents, with the account and the limits

Omarchy's Agents widget with three additions: the session and weekly use in
the bar; under the plan in the panel's hero, the account each CLI is logged in
with; and, when gwath's token counter counts them, the tokens by project.

## In the bar

Left of the icon, as `󰔟 85%  󰃭 14%`: the share of the session (5-hour) and
weekly limits used, Claude Code's by default, with the icon inside a soft
outline that groups them. Each number is coloured by its own level: the bar's
text colour, orange from 80%, red from 90%, in bold title-size numbers. The
colours (`Attention.qml`, `Attention.js`): the theme's own orange when it has a
real one (some themes give the name to green, grey or blue), a standard orange
otherwise, and always a standard red; either one darkened or lightened just
enough to read at 3:1 against the bar. Hover for the reset times; clicks do
what the icon does.

- `barProvider` (default `claude`; `codex` for Codex's) picks whose limits.
  It does not follow the panel's tab: the icon names no provider, so the
  numbers would change meaning unseen.
- `barRefreshSec` (default 300, at least 60): how often the limits alone are
  fetched, one request per provider, the same one the panel makes when it
  opens. Omarchy's full refresh (`refreshIntervalSec`, 900) still runs.
- A window whose reset time has passed shows 0% until the next refresh.
- On a vertical bar only the icon shows.

## In the panel

```
Claude Code                      Codex
PRO                              EDU
you@gmail.com                    you@university.edu
Personal account
```

For Claude Code the second line is the seat's organization: "Personal account"
for a plan of your own, the organization's name for a seat in someone else's
(a company's or a university's Team or Enterprise plan). With several seats on
one email address, that line tells them apart. Codex shows the email alone.

Omarchy reads the plan from files that don't hold the account, so the panel
reads it itself, with `jq`, when the shell starts, when the panel opens and on
refresh (`r`):

- Claude Code: `oauthAccount.emailAddress` and `.organizationName` in
  `~/.claude.json` (`$CLAUDE_CONFIG_DIR/.claude.json` when that is set). The
  service names a personal plan's organization `<email>'s Organization`.
- Codex: the `email` claim of the id token in `~/.codex/auth.json`
  (`$CODEX_HOME/auth.json`). Only the email leaves `jq`.

After `/login` to another account, the next opening of the panel shows it. A
file read while it is being rewritten keeps the last value; a missing file
(logged out) hides the line. The code is in `Account.js`; `Panel.qml` only runs
it and draws the lines.

### Other accounts

Under the limits, the accounts you were logged in with before, on that tab's
CLI, each with the session and weekly use last read and the time to each
reset:

```
OTHER ACCOUNTS
you@university.edu · University               seen 3h
Session 42% · 1h 50m   Weekly 63% · 3d 4h
```

Every time a provider's limits come in (on every bar refresh, every 5 minutes,
open panel or not), they are filed under the account they were measured on,
in `~/.local/state/omarchy/agents/accounts.json`: one entry per provider,
email and organization, so two seats on one email stay apart.

- Claude Code: `claude-seat.sh` asks Anthropic (`api/oauth/profile`) whose
  login token the collector probed with; the answer is cached per token in
  `~/.cache/omarchy/agents/profiles/`, so that is one request per login or
  token refresh. Only a fresh probe is filed: one not filed before and made
  after the credentials last changed. `~/.claude.json`, which the hero reads,
  can name another seat for a while after a switch (every running Claude Code
  rewrites it), and Omarchy's collector reuses its last figures for a few
  minutes, and whenever a probe fails, whichever seat they came from.
- Codex keeps its login in one file, and its collector probes every time: the
  account is read again from that file.

The account you are logged in with now is left out of the list (its limits
are the section above). A window whose reset time has passed reads
`0% · reset`; a session window not yet opened has no reset time. Deleting the
file forgets the accounts. The code is in `Seats.js` (tests: `node Seats.test.js`) and `claude-seat.sh`.

### Tokens by project

When gwath's token counter (`gwath tokens`, in gwath, not published, which
counts each project's tokens day by day from the same transcripts) has
written its summary, TOKENS BY MODEL can switch to TOKENS BY PROJECT:

```
TOKENS BY MODEL PROJECT                  7 DAYS · ALL 42 ›
alpha                                               1.2B
beta                                              640.0M
Drive:…/lectures                                   85.3M
gamma                                              12.1M
```

- The four projects this tab's agent used most in the last 7 days, most
  first, each with a bar scaled to the first, as the model rows are. Hover a
  row for its path and its tokens today, in the last 7 and 30 days and in
  all, and the time of the count.
- Click MODEL or PROJECT in the header, or press `p`, to switch; the choice
  holds until the shell restarts. Projects come first when the summary is
  there; without it the section is Omarchy's TOKENS BY MODEL, unchanged. Same
  number of rows as the models, so the panel keeps its height.
- A click on a project opens its days, on ALL every project of every agent,
  in a floating terminal: `gwath tokens show <project>` and `gwath tokens show --all`,
  paged by `less` (`q` closes it).

The summary is `~/.local/state/gwath/tokens.json` (setting
`projectsFile`), watched by the panel; the command is `gwath tokens` (setting
`tokensCommand`, its words split at spaces; `show` and the project follow).
Anything that writes the summary in this form works:

```json
{"updated": "2026-10-14 23:00", "today": "2026-10-14",
 "projects": [{"path": "~/repos/alpha", "name": "alpha",
               "agents": {"claude": {"today": 0, "week": 0, "month": 0, "all": 0},
                          "codex": {"today": 0, "week": 0, "month": 0, "all": 0}}}]}
```

`week` is the last 7 days, `month` the last 30, `all` everything counted;
agents are named as the panel's tabs (`claude`, `codex`). The code is in
`Projects.js` (tests: `node Projects.test.js`); `Panel.qml` draws it.
`tests/panel-harness/run.sh` loads `Panel.qml` in a Quickshell instance of its
own, with no window, and prints what the projects view shows on each tab and
after `p` (with `HARNESS_PROJECTS=/nonexistent`, the fallback to the models).

## Install

```bash
omarchy plugin add https://github.com/stefanoconiglio/omarchy-agents.git --enable
```

The widget declares itself a clone of `omarchy.agents`, so enabling it puts it
in place of Omarchy's Agents widget with that widget's settings, and calls to
`omarchy.agents` reach it. To go back:

```bash
omarchy plugin remove coniglio.agents
```

Requires Omarchy 4. The first commit is `omarchy plugin clone omarchy.agents`
from Omarchy 4.0.4, unchanged; when an Omarchy update changes
`/usr/share/omarchy/shell/plugins/agents/`, compare it with that commit and
merge. After editing, `omarchy restart shell`.

MIT, as Omarchy ([LICENSE](LICENSE)). Omarchy's own description of the widget
follows.

---

## Agents (Omarchy)

One bar icon and one panel for every AI coding subscription on the machine.
The panel is strictly a display: it watches the usage records that
`omarchy-agent-usage-update` writes to `~/.local/state/omarchy/agents/usage/`
and draws whatever appears there. `Panel.qml` owns the bar button and the
popup; `Main.qml` discovers and watches the records (and handles the optional
cross-device aggregation); `Agent.qml` is the per-record file watcher.

## Panel

- **Hero** — the mark, the tool, and the plan it runs on ("Max 20x", "Pro").
  Auth and endpoint problems replace the plan line and repeat in a card.
- **Subscription switch** — one chip per enabled agent (`h`/`l` or click).
  It appears only when more than one agent is enabled.
- **Limits** — the percentage of each allowance used, a matching meter, and
  the time until the session or weekly window resets.
- **Balance** — prepaid agents report a credit ledger instead of limits:
  remaining credit, a fuel-gauge meter that drains toward empty, and
  funded-versus-spent detail.
- **Tokens by day** — one row per day for the last week: day, bar, tokens, with today
  bolded at the bottom. Hover today for its prompt and session count.
- **Tokens by model** — tokens per model with the bar behind each row scaled
  to the heaviest model,
  the same way the weekly chart scales to its busiest day. Hover for the
  input / output / cache split.

A subscription appears only when it is enabled in settings and has actually
recorded usage — on this machine or on a synced one. With one such agent
there is no switch row at all; with none, the module leaves the bar entirely
rather than sitting there with nothing to say. A CLI installed mid-session
shows up at the next refresh, so nothing polls the disk waiting for it.

That self-hiding is why the widget ships in the default bar layout: a machine
that has never run an AI coding agent draws nothing, and the icon arrives on
its own the first time a scan finds usage. Drop it with
`omarchy plugin disable omarchy.agents`.

## Data

Each agent is one JSON record in `~/.local/state/omarchy/agents/usage/`,
written by `omarchy-agent-usage-update`. That command runs one
`omarchy-agent-usage-<agent>` collector per agent; the widget invokes it
on its refresh timer and whenever you ask for a refresh, and picks up any
record that lands in the directory regardless of who wrote it.

Adding an agent therefore never touches this plugin: ship a collector that
prints the record contract (see the `claude` and `codex` collectors in
`bin/`), and the panel gains a tab. An `assets/<id>.svg` mark is optional —
with an `assets/<id>-light.svg` twin if the mark needs a dark variant for
light surfaces — and the bar glyph stands in when there is none.

| Collector | Limits | Local stats |
|---|---|---|
| `claude` | Anthropic's OAuth usage endpoint (5-hour session + 7-day weekly) | `~/.claude/projects` transcripts, opencode sessions on an Anthropic provider, plus `stats-cache.json` and `history.jsonl` as fallback |
| `codex` | The Codex app-server RPC | native Codex CLI session files (plus pi and opencode sessions) |
| `fireworks` | Estimated prepaid balance: configured funding minus rated account costs | Fireworks billing API, grouped by day and model for the last 30 days |

Claude limits need a signed-in CLI; without credentials the panel says so and
falls back to local stats only. A non-default Claude directory is honored via
`CLAUDE_CONFIG_DIR`, Codex via `CODEX_HOME`. Fireworks reads
`FIREWORKS_API_KEY` and `FIREWORKS_ACCOUNT_ID` first, then
`~/.fireworks/auth.ini` (which `firectl set-api-key` creates), then the key
opencode stores in `~/.local/share/opencode/auth.json` when Fireworks is
signed in there.

### Fireworks balance

The collector first asks the account's `:getBalance` endpoint for the real
prepaid ledger. That endpoint exists but is permission-gated, and as of
August 2026 no console-issued API key passes it — Fireworks appears to
reserve it for the dashboard session. The probe stays because it is cheap
and the live figure lights up automatically if Fireworks ever opens it to
keys. Until then the collector falls back to estimating the balance from
configuration in `~/.config/omarchy/agents/fireworks.json`:

```json
{
  "accountId": "",
  "fundedAmount": 20,
  "fundedAt": "2026-07-01"
}
```

Set `fundedAmount` to the credits purchased and optionally `fundedAt` to the
purchase date; with no date, the collector uses the account creation time. It
subtracts rated account costs and the panel labels the result as estimated.
For a later top-up, increase `fundedAmount` by the new credit while keeping
the original `fundedAt`, so both the funding and spend still cover the same
period. `accountId` only matters when one API key can access several
accounts. Without a configured `fundedAmount` the tab still shows token
usage, just no balance. With a live ledger, `fundedAmount` is optional and
only adds the meter and the spent-of-funded line under the real figure.

## Interactions

- Bar icon: left = panel, right = launch agent, middle = next subscription.
- Panel: `h`/`l` switch subscription, `j`/`k` scroll, `r` or Enter refresh,
  Tab moves to the neighboring bar panel, Esc closes.
- IPC: `omarchy-shell omarchy.agents <open|close|toggle|refresh|next>`.

## Settings

Settings live in the widget's entry in `~/.config/omarchy/shell.json`. The
top-level keys can be set with
`omarchy bar set omarchy.agents <key> <value>`:

| Key | Default | What it does |
|---|---|---|
| `refreshIntervalSec` | `900` | How often the usage records regenerate |
| `syncMode` | `"Off"` | `"On"` writes this machine's snapshot and merges the others |
| `syncDir` | `""` | A folder synced by Syncthing, Dropbox, rsync, … |
| `syncFileName` | `<hostname>.json` | This machine's snapshot file |
| `syncDeviceId` | hostname | Stable device name inside the snapshot |

Numbers need `--json`, or they land in `shell.json` as strings:

```bash
omarchy bar set omarchy.agents refreshIntervalSec 300 --json
omarchy bar set omarchy.agents syncDir '~/Sync/agent-usage'
```

Per-agent enablement is nested, and `set` writes its key literally rather
than walking a dotted path — so pass the whole `providers` object as JSON (or
edit `shell.json` directly):

```bash
omarchy bar set omarchy.agents providers '{
  "claude": { "enabled": true },
  "codex": { "enabled": false },
  "fireworks": { "enabled": true }
}' --json
```

`enabled` defaults to `true` for every discovered agent; set it to `false` to
hide a subscription that is installed. Disabled agents are also skipped when
the records regenerate.

With `syncMode` on, every `*.json` snapshot in `syncDir` is merged, so today,
the last 7 days, and the all-time totals cover every machine you code on —
active days are unioned by date rather than summed. Rate limits stay
per-account and are never merged. A record may declare `"scope": "account"`
when its stats are account-global rather than machine-local (Fireworks'
billing API); those merge by taking the widest value instead of summing, so
the same account synced from two machines is not counted twice.

One caveat on "all-time": the Codex collector only reads native session files
touched in the last 30 days, and Fireworks requests the last 30 days from its
billing API, so their totals and day counts cover that window. Claude's cover
every transcript still on disk.
