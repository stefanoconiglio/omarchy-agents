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

## 2026-10-07 18:37 CEST — Outline instead of the dark pill; colours from the theme

Request (user): drop the dark fill; keep only the outline, softer, as a border grouping the items
of one tool, the same on the battery, ping, Memory and Agents widgets. Normal values must stay
readable on every theme. Decisions (user): softer outline; thresholds ping orange 50–100 ms, red
from 100 ms and down; battery orange below 30%, red below 15%; Agents orange from 80%, red from
90%; Memory orange from warnPercent (85), red from 90%.

- Attention.js / Attention.qml, the same in each of the four plugins: normal text in the bar's
  colour; the outline that colour at 45% opacity; orange and red from the theme's colors.toml
  (`~/.local/state/omarchy/current/theme`) when they really are orange (hue 12–45°) or red
  (340–12°) with HSV saturation at least 0.35, otherwise #f97316 / #ef4444; then darkened (light
  bar) or lightened (dark bar) in 5% steps until 3:1 against the bar background (`bar.background`;
  a transparent bar assumed black or white, opposite to its text). Reloaded when the file changes
  and when the shell's theme colours change (theme-set sends them over IPC).
- Measured on the 22 stock themes, contrast of the fixed colours against each bar background:
  green #22c55e 2.0–2.3:1 on the five light themes, red #dc2626 2.6:1 on everforest and nord.
  Theme colours as named: red 2.3:1 on miasma, 2.8:1 on solitude, orange 2.8:1 on rose-pine; and
  several are not orange or red at all (hackerman green, vantablack and white grey, lumon blue,
  lupine blue and magenta, matte-black orange = a red). After the rules: every orange and red at
  3.05:1 or more, orange and red at least 16° of hue apart.
- Checked on the live bar (rose-pine, light): all four outlined, no QML error; with temporary IPC
  hooks (removed) forcing values: normal, orange #c57a53 (theme orange, raised from 2.8 to 3.1:1)
  and red #b4637a (theme red) on all four. Not seen on a dark theme (the user's theme was not
  changed).
- Here: one outline around the two numbers and the icon; the fixed #ea580c / #dc2626 replaced;
  README.

## 2026-10-07 19:06 CEST — Standard red; large numbers everywhere

Decisions (user): red is always the standard one (Rosé Pine's own red, #b4637a, is a muted rose,
close to its orange); all outlined widgets in the large type.

- Attention.js: red is #ef4444 on every theme, still raised to 3:1 against the bar; orange stays
  the theme's when it really is orange, now hue 18–45° (was 12–45°: Catppuccin Latte's orange,
  #d84e2b at 12°, was 12° from the red). On the 22 stock themes: theme orange used on 9, every
  colour at 3.02:1 or more, orange and red at least 18° apart (Nord).
- Memory and Agents: numbers drawn as Text, bold, `Style.font.title` (14 px), like the ping and
  battery faces (WidgetButton has no bold); the item registers as a click target and reports
  `tooltipHovered`; ink centred on the digits' bounding box; each number at least as wide as
  "88%", so 9→10% doesn't move the bar (100% does, by a digit).
- Checked on the live bar (Rosé Pine): all four large and bold, no QML error; forced through
  temporary hooks (removed): normal, orange #c57a53, red #ef4444 on all four; 5% and 100%.
- Here: the two WidgetButtons replaced by bold Text numbers; README.
- Seen by the user on Retro Fallout (dark theme): fine. Published (user's decision):
  https://github.com/stefanoconiglio/omarchy-agents.
