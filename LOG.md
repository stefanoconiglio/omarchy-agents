# Log

One dated entry per working session: what changed, decisions and who made them, open questions.
The machine-side record (shell.json, backups, inventory) is in omarchy-customizations' LOG.md.

## 2026-10-07 05:20 CEST — The account under the plan

Request (user): the panel shows the plan ("PRO") but not which account Claude Code is logged in
with. The user has three Claude seats: one on the unibg address, two on the gmail address, one of
which is in the university's organization; the panel must tell them apart. Then the same for Codex.

- `omarchy plugin clone omarchy.agents` (Omarchy 4.0.4) → id `coniglio.agents`,
  `clonedFrom: omarchy.agents`; first commit, unchanged.
- Where the account is: Omarchy's collector (`omarchy-agent-usage-claude`) reads the plan from
  `~/.claude/.credentials.json` (`rateLimitTier`, `subscriptionType`), which holds no account.
  Claude Code keeps it in `~/.claude.json`, `oauthAccount`: `emailAddress`,
  `organizationName`, `organizationType` and more. On this machine, the personal Pro seat:
  organization "<gmail address>'s Organization", type `claude_pro`. The seat in the
  university's organization was not logged in here, so its name and type were not seen. Codex:
  `~/.codex/auth.json`, the id token's `email` claim (the unibg address, plan `edu`);
  its organization list has one entry titled "Personal" despite the edu plan, so it is not shown.
- Account.js: the two `jq` filters, run through `sh -c` so a missing file prints `{}` (logged
  out: line hidden) while a file that doesn't parse prints nothing (keeps the last value);
  `lines()`: Claude → email, then "Personal account" when the organization is
  "<email>'s Organization", else the organization's name; Codex → email. Base64url decoding
  of the token in jq (`-`/`_`, padding).
- Panel.qml: the hero and up to two dim, body-small lines in a column, the lines aligned with
  the hero's labels; read at start, on opening and on refresh.
- Checked with node: live files (gmail + "Personal account"; unibg for Codex), missing file,
  truncated file, Codex auth without an id token, the organization rules, the token decoding at
  every payload length 1–17. On the live panel after `omarchy restart shell`: both tabs as
  expected, no QML error.
- Not checked: the label for the university seat's organization (not logged in here).
- No preview image: it would publish the addresses.
- Decision (user): own public repository, github.com/stefanoconiglio/omarchy-agents, symlinked
  into `~/.config/omarchy/plugins/coniglio.agents`.

## 2026-10-07 05:31 CEST — Session and weekly use in the bar

Request (user): left of the icon, two numbers like the Memory widget's (`󰍛 64%  󰓡 33%`): the
percentage of the session and weekly limits.

- Panel.qml: the bar face is a Row: a WidgetButton with `󰔟 85%  󰃭 14%` (Memory's style: glyph,
  space, percentage, two spaces between), then Omarchy's icon button, unchanged. Both call the
  same press handler (left: panel, right: launch an agent, middle: next provider); the panel
  anchors to the row. The text button shows its own tooltip ("Session 85% · resets in 4h 19m",
  weekly the same) and turns urgent when either window reaches 90%, Omarchy's threshold for the
  icon. Hidden on a vertical bar.
- Whose numbers: setting `barProvider`, default `claude`. Not the panel's selected tab: Omarchy's
  icon alarm follows the tab, but numbers that switched provider with no name next to them would
  be misread.
- Windows found by the panel's own `limitWindows()` titles ("Session", "Weekly"), so Codex's
  "5h window" works too. A window past its `resetsAt` shows 0% (clock ticks every 60 s).
- Freshness: Omarchy refreshes everything every `refreshIntervalSec` (900 s); a new Timer runs
  `usage.refreshLimits()` (`omarchy-agent-usage-update --limits-only`) every `barRefreshSec`,
  default 300 s, minimum 60.
- Checked on the live bar after `omarchy restart shell`: `󰔟 80%  󰃭 13%`, matching
  `claude.json` (0.8, 0.13), then 85% / 14% after the restart's refresh. With a temporary IPC
  hook (removed): tooltip text; clock +3 h, session still 1 h 19 min from reset, unchanged;
  +60 h, both past reset, 0% and 0%. Panel opens under the widget. No QML error.
- Not checked: the urgent colour at 90% (no window there yet); a click on the numbers (same
  handler as the icon, which was checked through IPC only); a vertical bar.

## 2026-10-07 05:35 CEST — Orange and red

Request (user): colour the numbers, orange past 80%, red past 90%.

- Two WidgetButtons, one per window, instead of one label, so each number takes its own colour:
  `foreground` is the bar's text colour, `#ea580c` (orange) from 80%, `#dc2626` (red) from 90%,
  on the unrounded fraction. The single urgent state from 90% is gone. Fixed colours, not the
  theme's: few themes have an orange. Contrast on the light bar (#faf4ed-like) about 3.2:1 and
  4.4:1, more on a dark one.
- Checked on the live bar with a temporary hook (removed) forcing the fractions: 0.79 / 0.14
  normal; 0.80 orange; 0.89 orange, 0.80 orange; 0.90 red, 0.85 orange; 0.97 and 0.93 red. Live
  afterwards: session 87% orange, weekly 14% normal. Not seen on a dark theme.
