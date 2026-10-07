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
