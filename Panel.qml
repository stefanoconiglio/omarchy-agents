import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Account.js" as Account
import "Swap.js" as Swap
import "Projects.js" as Projects

Panel {
  id: root
  moduleName: "omarchy.agents"
  ipcTarget: "omarchy.agents"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color surface: Color.popups.background
  readonly property color track: Style.selectedFillFor(foreground, Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // The account each CLI is logged in with, under the plan in the hero:
  // Omarchy reads the plan from files that don't hold it (Account.js).
  readonly property string claudeConfigFile: {
    var dir = Quickshell.env("CLAUDE_CONFIG_DIR")
    return dir ? dir + "/.claude.json" : Quickshell.env("HOME") + "/.claude.json"
  }
  readonly property string codexAuthFile: (Quickshell.env("CODEX_HOME") || Quickshell.env("HOME") + "/.codex") + "/auth.json"
  property var accountRecords: ({})
  readonly property var accountLines: provider ? Account.lines(provider.providerId, accountRecords[provider.providerId]) : []

  function setAccount(providerId, raw) {
    var record = Account.parseRecord(raw)
    if (!record) return
    var next = Object.assign({}, accountRecords)
    next[providerId] = record
    accountRecords = next
  }

  // ---------- accounts: the Claude seats claude-swap manages ----------
  //
  // claude-swap (`cswap`) keeps every Claude seat's login and reads each
  // one's session and weekly use; ACCOUNTS lists them (Swap.js). A click on
  // another seat switches to it (`cswap switch <n>`), which changes the seat
  // every running Claude Code uses; the button opens cswap's dashboard. The
  // list is read when the panel opens and after a switch. Without cswap the
  // section stays away and the hero shows the account logged in alone.
  readonly property var cswapCommand: Swap.command(setting("cswapCommand", "cswap"))
  property var swapList: Swap.parse("")
  property bool swapAuto: false
  property int switchingTo: 0
  property string swapMessage: ""
  property bool swapMessageError: false
  readonly property var swapSeats: provider && provider.providerId === "claude" ? swapList.seats : []

  function readSeats() {
    if (!swapListProc.running) swapListProc.running = true
    if (!swapAutoProc.running) swapAutoProc.running = true
  }

  function switchSeat(number) {
    if (switchingTo !== 0 || number === swapList.active) return
    switchingTo = number
    swapMessage = ""
    swapSwitchProc.answer = null
    swapSwitchProc.exitCode = null
    swapSwitchProc.command = Swap.switchArgv(cswapCommand, number)
    swapSwitchProc.running = true
  }

  // Called when the switch's output and its exit are both in, in either order.
  function switchDone() {
    if (switchingTo === 0 || swapSwitchProc.answer === null || swapSwitchProc.exitCode === null) return
    var result = Swap.switchResult(swapSwitchProc.answer, swapSwitchProc.exitCode)
    switchingTo = 0
    swapMessage = result.message
    swapMessageError = !result.ok
    readSeats()
    readAccount()
    // The limits above were the old seat's.
    if (result.switched) usage.refreshLimits()
  }

  function openSwap() {
    Util.execArgv(Swap.tuiArgv(root.cswapCommand))
    root.close()
  }

  Process {
    id: swapListProc
    command: Swap.listArgv(root.cswapCommand)
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.swapList = Swap.parse(text) }
  }

  Process {
    id: swapAutoProc
    command: Swap.autoArgv(root.cswapCommand)
    onExited: function(exitCode) { root.swapAuto = exitCode === 0 }
  }

  Process {
    id: swapSwitchProc
    property var answer: null
    property var exitCode: null
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: { swapSwitchProc.answer = text; root.switchDone() } }
    onExited: function(exitCode) { swapSwitchProc.exitCode = exitCode; root.switchDone() }
  }

  function readAccount() {
    if (!claudeAccountProc.running) claudeAccountProc.running = true
    if (!codexAccountProc.running) codexAccountProc.running = true
  }

  // ---------- tokens by project ----------
  //
  // gwath's token counter (`gwath tokens`) counts each project's tokens day by
  // day from the same transcripts and writes a summary (README). When it is
  // there, TOKENS BY MODEL can switch to TOKENS BY PROJECT: the projects this
  // tab's agent used most in the last 7 days. A row opens that project's days,
  // ALL every project, in a floating terminal (`gwath tokens show`).
  readonly property string projectsFile: String(setting("projectsFile", "")) !== ""
    ? String(setting("projectsFile", ""))
    : (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/gwath/tokens.json"
  // The command that shows the projects, as words (`gwath tokens`).
  readonly property var tokensCommand: String(setting("tokensCommand", "gwath tokens")).trim().split(/\s+/)
  property var projectsSummary: null
  readonly property bool projectsAvailable: !!provider && Projects.count(projectsSummary, provider.providerId) > 0
  readonly property var projectRows: provider ? Projects.top(projectsSummary, provider.providerId, 4) : []
  // The view chosen stays for the shell's session; models when there is no
  // summary, projects when there are no models.
  property string tokensViewChoice: "project"
  readonly property string tokensView: models.length === 0 || (tokensViewChoice === "project" && projectsAvailable)
    ? "project" : "model"
  readonly property var tokensViews: {
    var views = []
    if (models.length > 0) views.push("model")
    if (projectsAvailable) views.push("project")
    return views
  }

  function toggleTokensView() {
    if (tokensViews.length > 1) tokensViewChoice = tokensView === "project" ? "model" : "project"
  }

  function openProjects(path) {
    Util.execArgv(["omarchy-launch-tui", "--app-id=TUI.float", "env", "LESS=RS"]
                    .concat(root.tokensCommand, ["show", path || "--all"]))
    root.close()
  }

  FileView {
    id: projectsFileView
    path: root.projectsFile
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.projectsSummary = Projects.parse(text())
    onLoadFailed: root.projectsSummary = null
  }

  // ---------- bar numbers: session and weekly use, left of the icon ----------
  //
  // One provider's, Claude Code's unless `barProvider` says otherwise: the
  // icon names no provider, so numbers that followed the panel's tab would
  // change meaning unseen. A window whose reset time has passed shows 0 until
  // the next refresh brings the new figure.
  readonly property string barProviderId: String(setting("barProvider", "claude"))
  readonly property int barRefreshSec: Math.max(60, Number(setting("barRefreshSec", 300)))
  readonly property bool barVertical: bar ? bar.vertical === true : false
  property double barNowMs: Date.now()
  readonly property var barProvider: {
    for (var i = 0; i < providers.length; i++)
      if (providers[i].providerId === barProviderId) return providers[i]
    return null
  }
  readonly property var barWindows: {
    var found = { session: null, weekly: null }
    var windows = limitWindows(barProvider)
    for (var i = 0; i < windows.length; i++) {
      var w = windows[i]
      var reset = w.resetAt !== "" ? new Date(w.resetAt).getTime() : NaN
      var current = { percent: isFinite(reset) && reset <= barNowMs ? 0 : w.percent, resetMs: isFinite(reset) ? reset - barNowMs : -1 }
      if (w.title === "Session" && !found.session) found.session = current
      else if (w.title === "Weekly" && !found.weekly) found.weekly = current
    }
    return found
  }

  // Each number by its own level: the bar's text colour, orange from 80%, red
  // from 90% (Attention.qml: the theme's own orange and red when it has them,
  // always readable on its bar). A soft outline groups numbers and icon.
  Attention { id: attention; bar: root.bar }

  function barColor(w) {
    if (!w) return attention.normal
    if (w.percent >= 0.9) return attention.red
    if (w.percent >= 0.8) return attention.orange
    return attention.normal
  }

  function barPercent(w) {
    return Math.round(Math.max(0, w.percent) * 100) + "%"
  }

  function barLabel(w, glyph) {
    return w && !barVertical ? glyph + " " + barPercent(w) : ""
  }

  function barTooltip() {
    if (!barProvider) return ""
    var lines = [barProvider.providerName]
    if (barWindows.session) lines.push("󰔟 Session " + barPercent(barWindows.session)
      + (barWindows.session.resetMs > 0 ? " · resets in " + formatDuration(barWindows.session.resetMs) : ""))
    if (barWindows.weekly) lines.push("󰃭 Weekly " + barPercent(barWindows.weekly)
      + (barWindows.weekly.resetMs > 0 ? " · resets in " + formatDuration(barWindows.weekly.resetMs) : ""))
    return lines.join("\n")
  }

  function handleBarPress(buttonCode) {
    if (buttonCode === Qt.RightButton) root.launchAgent()
    else if (buttonCode === Qt.MiddleButton) root.selectProvider(root.providerIndex + 1)
    else root.toggle()
  }

  readonly property var providers: usage.enabledProviders
  // The selection follows the provider, not the slot it happens to sit in: a
  // provider whose first scan lands while the panel is open would otherwise
  // shift the list underneath you and swap out what you were reading.
  property string selectedProviderId: ""
  readonly property int providerIndex: {
    for (var i = 0; i < providers.length; i++)
      if (providers[i].providerId === selectedProviderId) return i
    return 0
  }
  readonly property var provider: providers.length > 0 ? providers[providerIndex] : null

  property bool cursorActive: false

  // Countdowns and "updated" read this instead of Date.now() so the
  // panel keeps telling the truth while it sits open.
  property double nowMs: Date.now()

  readonly property var limits: limitWindows(provider)
  readonly property var models: modelRows(provider)
  readonly property var headline: bindingWindow(provider)
  readonly property var balance: provider ? (provider.balance || null) : null
  // A prepaid account runs low the way a subscription window fills up: the
  // last 10% of the funded credits lights the same alarm.
  readonly property bool balanceAlarming: !!balance && balance.funded > 0
    && balance.remaining / balance.funded <= 0.1
  readonly property bool alarming: (!!headline && headline.percent >= 0.9) || balanceAlarming

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  function selectProvider(index) {
    if (providers.length === 0) return
    var wrapped = ((index % providers.length) + providers.length) % providers.length
    selectedProviderId = providers[wrapped].providerId
  }

  function refreshNow() {
    usage.refreshAll(true)
    readAccount()
  }

  function launchAgent() {
    if (root.bar) root.bar.run("omarchy-agent --pick")
    root.close()
  }

  // ---------------------------------------------------------------- limits
  //
  // Both providers report the same two shapes: a short rolling session window
  // and a long weekly one. Everything below normalizes them into one record so
  // the meters and the hero speak a single language.

  // Claude spells its windows out ("Session (5-hour)"), Codex abbreviates
  // them ("5h window", "30m window"). Both have to land on the same record.
  function windowIsLong(text) {
    return text.indexOf("week") >= 0 || text.indexOf("7-day") >= 0 || text.indexOf("seven") >= 0
      || text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0
  }

  function windowSpanMs(label) {
    var text = String(label || "").toLowerCase()
    if (text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0) return 30 * 24 * 3600 * 1000
    if (windowIsLong(text)) return 7 * 24 * 3600 * 1000
    var hours = text.match(/(\d+)\s*-?\s*h(?:our)?\b/)
    if (hours) return Number(hours[1]) * 3600 * 1000
    var minutes = text.match(/(\d+)\s*-?\s*m(?:in(?:ute)?s?)?\b/)
    if (minutes) return Number(minutes[1]) * 60 * 1000
    return 0
  }

  function windowTitle(label) {
    var text = String(label || "").toLowerCase()
    if (text.indexOf("month") >= 0) return "Monthly"
    if (windowIsLong(text)) return "Weekly"
    if (text.indexOf("session") >= 0 || windowSpanMs(label) > 0) return "Session"
    var plain = String(label || "").replace(/\s*\(.*\)\s*/, "").trim()
    return plain === "" ? "Limit" : plain
  }

  // A collector that already knows which window a limit belongs to says so,
  // and that beats reading it back out of the label: a model-scoped limit is
  // titled after its model, and a name like "Opus 5 (1M context)" would parse
  // as a one-minute window.
  function limitWindow(label, percent, resetAt, title) {
    return {
      title: String(title || "") !== "" ? String(title) : windowTitle(label),
      percent: Number(percent),
      resetAt: String(resetAt || "")
    }
  }

  function limitWindows(p) {
    if (!p) return []
    var out = []
    var list = p.limits || []
    for (var i = 0; i < list.length; i++) {
      var entry = list[i] || {}
      var percent = Number(entry.percent)
      if (percent >= 0) out.push(limitWindow(entry.label, percent, entry.resetsAt, entry.title))
    }
    return out
  }

  // The window that decides how much room is left — the fullest one, since
  // that is what stops the next prompt.
  function bindingWindow(p) {
    var windows = limitWindows(p)
    var best = null
    for (var i = 0; i < windows.length; i++) {
      if (!best || windows[i].percent > best.percent) best = windows[i]
    }
    return best
  }

  function resetMsFor(w) {
    if (!w || w.resetAt === "") return -1
    var ms = new Date(w.resetAt).getTime()
    return isFinite(ms) ? ms - root.nowMs : -1
  }

  function formatDuration(ms) {
    if (!(ms > 0)) return "now"
    var minutes = Math.floor(ms / 60000)
    var hours = Math.floor(minutes / 60)
    var days = Math.floor(hours / 24)
    if (days > 0) return days + "d " + (hours % 24) + "h"
    if (hours > 0) return hours + "h " + (minutes % 60) + "m"
    return Math.max(1, minutes) + "m"
  }

  // ---------------------------------------------------------------- balance
  //
  // Prepaid agents report a credit ledger instead of rate-limit windows: the
  // record's balance object carries remaining, funded, and spent amounts.

  function currencyPrefix(currency) {
    var code = String(currency || "USD").toUpperCase()
    if (code === "USD") return "$"
    if (code === "EUR") return "€"
    if (code === "GBP") return "£"
    return code + " "
  }

  function formatMoney(value, currency) {
    var amount = Number(value)
    if (!isFinite(amount)) amount = 0
    return currencyPrefix(currency) + amount.toFixed(2)
  }

  function balanceDetailText(b) {
    if (!b || !(b.funded > 0)) return ""
    var text = formatMoney(b.spent, b.currency) + " spent of " + formatMoney(b.funded, b.currency) + " funded"
    if (b.estimated) text += " · estimated"
    return text
  }

  // ---------------------------------------------------------------- content

  // The plan you pay for, under the name of the tool it pays for. Limits live
  // in their own section; the hero just says what this is.
  function heroMeta(p) {
    if (!p) return ""
    if (String(p.usageStatusText || "") !== "") return p.usageStatusText
    var tier = String(p.tierLabel || "")
    if (tier === "") return "Subscription"
    return tier.charAt(0).toUpperCase() + tier.slice(1)
  }

  // Local calendar date, recomputed from nowMs so a panel left open across
  // midnight moves the "Today" row with the clock.
  function todayDate() {
    var now = new Date(root.nowMs)
    return now.getFullYear()
      + "-" + String(now.getMonth() + 1).padStart(2, "0")
      + "-" + String(now.getDate()).padStart(2, "0")
  }

  function dayName(date) {
    var parsed = new Date(String(date || "") + "T00:00:00")
    if (isNaN(parsed.getTime())) return String(date || "")
    return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][parsed.getDay()]
  }

  function dayLabel(date, today) {
    if (today) return "Today"
    return dayName(date)
  }

  function dayTooltip(day, today) {
    if (!day) return ""
    var parsed = new Date(String(day.date) + "T00:00:00")
    var label = isNaN(parsed.getTime())
      ? String(day.date)
      : dayName(day.date) + " " + (parsed.getMonth() + 1) + "/" + parsed.getDate()
    var text = label + " · " + usage.formatTokenCount(Number(day.messageCount || 0)) + " tokens"
    // Prompt and session counts only exist for today, so they ride along here
    // instead of taking a section of their own. Billing-API agents never
    // count prompts, and "0 prompts" would read as a quiet day, not a gap.
    if (today && provider && provider.hasPromptStats !== false)
      text += " · " + Number(provider.todayPrompts || 0) + " prompts · "
        + Number(provider.todaySessions || 0) + " sessions"
    return text
  }

  function weekPeak(p) {
    var days = p ? (p.recentDays || []) : []
    var peak = 0
    for (var i = 0; i < days.length; i++) peak = Math.max(peak, Number(days[i].messageCount || 0))
    return peak
  }

  function modelRows(p) {
    var usageByModel = p ? (p.modelUsage || {}) : {}
    var rows = []
    for (var id in usageByModel) {
      var bucket = usageByModel[id] || {}
      var input = Number(bucket.inputTokens || 0)
      var output = Number(bucket.outputTokens || 0)
      var cacheRead = Number(bucket.cacheReadInputTokens || 0)
      var cacheWrite = Number(bucket.cacheCreationInputTokens || 0)
      rows.push({
        name: usage.friendlyModelName(id),
        total: input + output + cacheRead + cacheWrite,
        input: input,
        output: output,
        cacheRead: cacheRead,
        cacheWrite: cacheWrite
      })
    }
    rows.sort(function(a, b) { return b.total - a.total })
    return rows.slice(0, 4)
  }

  function modelTooltip(row) {
    if (!row) return ""
    return "In " + usage.formatTokenCount(row.input)
      + " · out " + usage.formatTokenCount(row.output)
      + " · cache read " + usage.formatTokenCount(row.cacheRead)
      + " · cache write " + usage.formatTokenCount(row.cacheWrite)
  }

  // Only speaks up when the numbers cover more than this machine.
  function footerText() {
    if (usage.syncStatusText !== "") return usage.syncStatusText
    if (provider && provider.syncEnabled && provider.syncDeviceCount > 0)
      return "Merged from " + provider.syncDeviceCount + " device" + (provider.syncDeviceCount === 1 ? "" : "s")
    return ""
  }

  // Agents that ship a white mark carry an `assets/<id>-light.svg` twin for
  // light surfaces; marks that work on both (Claude's brand-orange) ship one
  // file. The luminance check decides which candidate to try first.
  function colorChannelLuminance(value) {
    var channel = Number(value)
    if (!isFinite(channel)) return 0
    return channel <= 0.03928 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4)
  }

  function colorLuminance(color) {
    return 0.2126 * colorChannelLuminance(color.r)
      + 0.7152 * colorChannelLuminance(color.g)
      + 0.0722 * colorChannelLuminance(color.b)
  }

  // Marks resolve by convention, so a new agent's data file needs nothing
  // from this panel: assets/<id>.svg if it ships one, the module's bar glyph
  // if it doesn't.
  function iconCandidatesForProvider(p, surfaceColor) {
    if (!p) return []
    var candidates = []
    if (colorLuminance(surfaceColor || Color.background) >= 0.5)
      candidates.push(Qt.resolvedUrl("assets/" + p.providerId + "-light.svg"))
    candidates.push(Qt.resolvedUrl("assets/" + p.providerId + ".svg"))
    return candidates
  }

  // Nothing to report, nothing in the bar: Bar.qml collapses a slot whose item
  // is invisible, so the icon appears the moment the first scan finds usage and
  // stays away entirely on a machine that has never run either CLI.
  visible: providers.length > 0
  implicitWidth: barVertical ? barFace.implicitWidth : outlineBox.width + Style.space(10)
  implicitHeight: barFace.implicitHeight

  onProviderIndexChanged: if (panelFlick) panelFlick.contentY = 0
  onOpenedChanged: if (opened) {
    cursorActive = false
    nowMs = Date.now()
    if (panelFlick) panelFlick.contentY = 0
    usage.refreshLimits()
    readAccount()
    readSeats()
    swapMessage = ""
    projectsFileView.reload()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Component.onCompleted: { readAccount(); readSeats() }

  Process {
    id: claudeAccountProc
    command: Account.accountProbe(root.claudeConfigFile, Account.claudeFilter())
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.setAccount("claude", text) }
  }

  Process {
    id: codexAccountProc
    command: Account.accountProbe(root.codexAuthFile, Account.codexFilter())
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.setAccount("codex", text) }
  }

  Main {
    id: usage
    settings: root.settings
  }

  // Cheap enough to keep running: it only re-evaluates text bindings, and a
  // stale "resets in 2h" on a panel that is open is worse than a timer.
  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refreshNow(); return "ok" }
    function next(): string { root.selectProvider(root.providerIndex + 1); return "ok" }
  }

  // The full refresh comes every refreshIntervalSec (15 min); the limits
  // alone, a single request per provider, more often for the bar.
  Timer {
    interval: root.barRefreshSec * 1000
    running: root.barProvider !== null
    repeat: true
    onTriggered: usage.refreshLimits()
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: root.barNowMs = Date.now()
  }

  // Same geometry as the other outlined widgets: even width, height of the
  // bar's parity, so centring leaves no half pixel.
  Rectangle {
    id: outlineBox
    visible: !root.barVertical
    anchors.centerIn: parent
    width: {
      var w = Math.ceil(barFace.implicitWidth) + Style.space(8)
      return w % 2 === 0 ? w : w + 1
    }
    height: {
      var size = root.bar ? root.bar.barSize : Style.bar.sizeHorizontal
      var h = size - Style.space(6)
      return (size - h) % 2 === 0 ? h : h - 1
    }
    radius: height / 2
    color: "transparent"
    border.width: Math.max(1, Math.round(Style.space(1.5)))
    border.color: attention.outline
  }

  Row {
    id: barFace
    anchors.centerIn: parent

    // The numbers in the outlined widgets' type (bold, title size), drawn by
    // hand since WidgetButton has no bold: so the item registers as a click
    // target and reports tooltipHovered itself, as WidgetButton would.
    Item {
      id: numbers
      visible: root.barLabel(root.barWindows.session, "x") !== "" || root.barLabel(root.barWindows.weekly, "x") !== ""
      width: visible ? numbersRow.width + Style.space(8) : 0
      height: root.bar ? root.bar.barSize : Style.bar.sizeHorizontal
      readonly property bool tooltipHovered: numbersMouse.containsMouse

      Component.onCompleted: if (root.bar && root.bar.registerClickTarget) root.bar.registerClickTarget(numbers)
      Component.onDestruction: if (root.bar && root.bar.unregisterClickTarget) root.bar.unregisterClickTarget(numbers)

      FontMetrics { id: numberMetrics; font: sessionText.font }
      // Digits set the baseline, so the numbers sit centred in the bar.
      TextMetrics { id: digitInk; font: sessionText.font; text: "88" }
      // Room for two digits, so 9% turning into 10% doesn't move the bar.
      TextMetrics { id: slotInk; font: sessionText.font; text: "󰔟 88%" }

      Row {
        id: numbersRow
        x: Style.space(4)
        y: Math.round((numbers.height - digitInk.tightBoundingRect.height) / 2
                      - digitInk.tightBoundingRect.y - numberMetrics.ascent)
        spacing: Style.space(10)

        BarNumber { id: sessionText; window: root.barWindows.session; glyph: "󰔟" }
        BarNumber { window: root.barWindows.weekly; glyph: "󰃭" }
      }

      MouseArea {
        id: numbersMouse
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: if (root.bar) root.bar.showTooltip(numbers, root.barTooltip())
        onExited: if (root.bar) root.bar.hideTooltip(numbers)
        onClicked: function(mouse) {
          if (root.bar) root.bar.hideTooltip(numbers)
          root.handleBarPress(mouse.button)
        }
      }
    }

    BarIconButton {
      id: button
      bar: root.bar
      text: "󱚣"
      active: root.alarming
      onPressed: function(buttonCode) { root.handleBarPress(buttonCode) }
    }
  }

  component BarNumber: Text {
    property var window: null
    property string glyph: ""
    visible: text !== ""
    width: Math.max(implicitWidth, slotInk.width)
    textFormat: Text.PlainText
    text: root.barLabel(window, glyph)
    color: root.barColor(window)
    font.family: root.fontFamily
    font.pixelSize: Style.font.title
    font.bold: true
  }

  KeyboardPanel {
    id: panel
    anchorItem: barFace
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    // No cap but the screen's, on purpose: this one is a dashboard, and the
    // whole point is reading limits and history without scrolling. A fixed
    // cap (640 px) hid the days and models once Other accounts was added.
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (dx !== 0) {
          root.cursorActive = true
          root.selectProvider(root.providerIndex + dx)
        }
        if (dy !== 0)
          panelFlick.contentY = root.clamp(panelFlick.contentY + dy * Style.space(56), 0,
                                           Math.max(0, panelFlick.contentHeight - panelFlick.height))
      }
      onActivateRequested: root.refreshNow()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refreshNow()
        else if (t === "p" || t === "P") root.toggleTokensView()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          // ---------- Hero: provider mark · name · plan · account ----------
          Column {
            width: parent.width
            visible: !!root.provider
            spacing: Style.space(6)

            PanelHero {
              id: hero
              visible: !!root.provider
              width: parent.width
              title: root.provider ? root.provider.providerName : ""
              meta: root.heroMeta(root.provider)
              foreground: root.foreground
              fontFamily: root.fontFamily

              iconComponent: Component {
                Item {
                  id: heroMark
                  property var candidates: root.iconCandidatesForProvider(root.provider, root.surface)
                  // Provider objects are rebuilt on every refresh, which churns the
                  // array's identity without changing its content. Restart the fallback
                  // walk only when the URLs change: re-pointing source at a URL whose
                  // load already failed emits no statusChanged, so an identity-only
                  // reset would strand the walker on a missing -light twin.
                  property string candidatesKey: candidates.join("\n")
                  property int candidateIndex: 0
                  onCandidatesKeyChanged: candidateIndex = 0

                  width: Style.font.display
                  height: Style.font.display

                  Image {
                    id: heroMarkImage
                    anchors.fill: parent
                    source: heroMark.candidateIndex < heroMark.candidates.length ? heroMark.candidates[heroMark.candidateIndex] : ""
                    sourceSize.width: Style.font.display * 2
                    sourceSize.height: Style.font.display * 2
                    fillMode: Image.PreserveAspectFit
                    // Advancing source from inside its own status change trips the
                    // binding-loop detector; defer the step one tick.
                    onStatusChanged: if (status === Image.Error && heroMark.candidateIndex < heroMark.candidates.length)
                      Qt.callLater(function() { heroMark.candidateIndex++ })
                  }

                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    visible: heroMarkImage.status !== Image.Ready
                    text: button.text
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.display
                  }
                }
              }
            }

            // The account, in its own case (the hero capitalises its meta
            // line): the email, then for Claude the organization of the seat.
            Repeater {
              model: root.accountLines
              Text {
                required property string modelData
                x: Style.font.display + Style.space(14)
                width: parent.width - x
                textFormat: Text.PlainText
                text: modelData
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
            }
          }

          Text {
            visible: root.providers.length === 0
            width: parent.width
            topPadding: Style.space(24)
            text: "No AI coding subscriptions found.\nAgents show up here once you've used them."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          // ---------- Provider switch ----------
          Row {
            id: providerSwitch
            visible: root.providers.length > 1
            width: parent.width
            spacing: Style.spacing.md

            readonly property real cellWidth: root.providers.length > 0
              ? (width - spacing * (root.providers.length - 1)) / root.providers.length
              : 0

            Repeater {
              model: root.providers

              Button {
                required property var modelData
                required property int index

                width: providerSwitch.cellWidth
                text: modelData.providerName
                selected: index === root.providerIndex
                hasCursor: root.cursorActive && index === root.providerIndex
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: {
                  root.cursorActive = true
                  root.selectProvider(index)
                }
                onHovered: function(isHovered) { if (isHovered) root.cursorActive = true }
              }
            }
          }

          // ---------- Status ----------
          BorderSurface {
            visible: !!root.provider && String(root.provider.usageStatusText || "") !== ""
            width: parent.width
            implicitHeight: statusText.implicitHeight + Style.spacing.xl * 2
            color: root.alpha(root.urgent, 0.10)
            borderSpec: Border.flat(root.alpha(root.urgent, 0.35), 1)
            radius: Style.cornerRadius

            Text {
              id: statusText
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              text: root.provider ? String(root.provider.authHelpText || "") : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          // ---------- Balance / limits ----------
          PanelSeparator {
            visible: balanceSection.visible || limitsSection.visible
            foreground: root.foreground
          }

          Column {
            id: balanceSection
            visible: !!root.balance
            width: parent.width
            spacing: Style.space(10)

            // The meter shows what is left, not what is used: a prepaid
            // account drains toward empty rather than filling toward a cap.
            readonly property real ratio: root.balance && root.balance.funded > 0
              ? root.clamp(root.balance.remaining / root.balance.funded, 0, 1)
              : -1

            PanelSectionHeader {
              width: parent.width
              text: "BALANCE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Item {
              width: parent.width
              implicitHeight: Math.max(balanceLabel.implicitHeight, balanceValue.implicitHeight)

              Text {
                id: balanceLabel
                text: "Prepaid credits"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: balanceValue
                textFormat: Text.PlainText
                text: root.balance ? root.formatMoney(root.balance.remaining, root.balance.currency) : ""
                color: root.balanceAlarming ? root.urgent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Meter {
              visible: balanceSection.ratio >= 0
              width: parent.width
              value: balanceSection.ratio
              alarming: root.balanceAlarming
            }

            Text {
              textFormat: Text.PlainText
              visible: text !== ""
              width: parent.width
              text: root.balanceDetailText(root.balance)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Column {
            id: limitsSection
            // On the Claude tab, ACCOUNTS shows the same windows, every seat's.
            visible: root.limits.length > 0 && root.swapSeats.length === 0
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "LIMITS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.limits

              LimitRow {
                required property var modelData
                width: limitsSection.width
                window: modelData
              }
            }
          }

          // ---------- Accounts (claude-swap) ----------
          PanelSeparator {
            visible: seatsSection.visible
            foreground: root.foreground
          }

          Column {
            id: seatsSection
            visible: root.swapSeats.length > 0
            width: parent.width
            spacing: Style.space(10)

            // ACCOUNTS, whether cswap auto runs, and the dashboard.
            Item {
              width: parent.width
              implicitHeight: seatsHeader.implicitHeight

              PanelSectionHeader {
                id: seatsHeader
                text: "ACCOUNTS · AUTO " + (root.swapAuto ? "ON" : "OFF")
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              PanelSectionHeader {
                anchors.right: parent.right
                anchors.verticalCenter: seatsHeader.verticalCenter
                text: "CSWAP ›"
                foreground: root.foreground
                fontFamily: root.fontFamily
                font.underline: swapHover.containsMouse

                MouseArea {
                  id: swapHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openSwap()
                }

                PanelToolTip {
                  visible: swapHover.containsMouse
                  text: "claude-swap's dashboard, in a terminal"
                  fontFamily: root.fontFamily
                }
              }
            }

            Repeater {
              model: root.swapSeats

              SeatRow {
                required property var modelData
                width: seatsSection.width
                seat: modelData
              }
            }

            Text {
              textFormat: Text.PlainText
              visible: root.swapMessage !== ""
              width: parent.width
              text: root.swapMessage
              color: root.swapMessageError ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          // ---------- Usage ----------
          PanelSeparator {
            visible: usageSection.visible
            foreground: root.foreground
          }

          Column {
            id: usageSection
            visible: !!root.provider && root.provider.recentDays && root.provider.recentDays.length > 0
            width: parent.width
            spacing: Style.spacing.md

            readonly property var days: root.provider ? (root.provider.recentDays || []) : []
            readonly property real peak: Math.max(1, root.weekPeak(root.provider))

            PanelSectionHeader {
              width: parent.width
              text: "TOKENS BY DAY"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: usageSection.days

              DayRow {
                required property var modelData
                required property int index

                width: usageSection.width
                day: modelData
                ratio: Number(modelData.messageCount || 0) / usageSection.peak
                // By date, not by position: the Claude stats-cache fallback can
                // hand us a window that stops short of today.
                today: String(modelData.date || "") === root.todayDate()
              }
            }
          }

          // ---------- Models / projects ----------
          PanelSeparator {
            visible: modelSection.visible
            foreground: root.foreground
          }

          Column {
            id: modelSection
            visible: root.tokensViews.length > 0
            width: parent.width
            spacing: Style.spacing.md

            // TOKENS BY MODEL · PROJECT: the view shown in full, the other one
            // faint; a click (or p) switches. By project, ALL opens every one.
            Item {
              width: parent.width
              implicitHeight: tokensBy.implicitHeight

              Row {
                id: tokensBy
                spacing: Style.space(6)

                PanelSectionHeader {
                  text: "TOKENS BY"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                Repeater {
                  model: root.tokensViews

                  PanelSectionHeader {
                    required property string modelData
                    text: modelData.toUpperCase()
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    opacity: modelData === root.tokensView ? 1 : 0.45
                    font.underline: viewHover.containsMouse && modelData !== root.tokensView

                    MouseArea {
                      id: viewHover
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.tokensViewChoice = parent.modelData
                    }
                  }
                }
              }

              PanelSectionHeader {
                id: allProjects
                visible: root.tokensView === "project"
                anchors.right: parent.right
                anchors.verticalCenter: tokensBy.verticalCenter
                text: "7 DAYS · ALL " + (root.projectsSummary ? root.projectsSummary.projects.length : 0) + " ›"
                foreground: root.foreground
                fontFamily: root.fontFamily
                font.underline: allHover.containsMouse

                MouseArea {
                  id: allHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openProjects("")
                }

                PanelToolTip {
                  visible: allHover.containsMouse
                  text: "Every project, every agent, in a terminal\nAs of "
                    + Projects.stampText(root.projectsSummary, root.todayDate())
                  fontFamily: root.fontFamily
                }
              }
            }

            Repeater {
              model: root.tokensView === "project" ? root.projectRows : []

              ProjectRow {
                required property var modelData
                width: modelSection.width
                row: modelData
              }
            }

            Text {
              textFormat: Text.PlainText
              visible: root.tokensView === "project" && root.projectRows.length === 0
              width: parent.width
              text: "No project in the last 7 days"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Repeater {
              model: root.tokensView === "model" ? root.models : []

              ModelRow {
                required property var modelData
                width: modelSection.width
                row: modelData
                // Scaled to the heaviest model, so the top row is always full —
                // the same scale-to-peak the weekly chart uses for its busiest day.
                share: modelData.total / Math.max(1, root.models[0].total)
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: text !== ""
            width: parent.width
            topPadding: Style.space(2)
            text: root.footerText()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  // A limit window: label and percentage, meter, and reset countdown.
  component LimitRow: Column {
    id: limitRow
    property var window: null

    readonly property bool alarming: window && window.percent >= 0.9

    spacing: Style.space(6)

    Item {
      width: parent.width
      implicitHeight: Math.max(limitLabel.implicitHeight, limitValue.implicitHeight)

      Text {
        id: limitLabel
        textFormat: Text.PlainText
        // A model-scoped window is titled after its model, and those names run
        // long enough to reach the percentage, so the title gives way first.
        text: limitRow.window ? limitRow.window.title : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        anchors.left: parent.left
        anchors.right: limitValue.left
        anchors.rightMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: limitValue
        textFormat: Text.PlainText
        text: limitRow.window && limitRow.window.percent >= 0
          ? Math.round(limitRow.window.percent * 100) + "%"
          : "—"
        color: limitRow.alarming ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Meter {
      width: parent.width
      value: limitRow.window ? limitRow.window.percent : -1
      alarming: limitRow.alarming
    }

    Text {
      id: resetText
      textFormat: Text.PlainText
      width: parent.width
      text: {
        var remainingMs = root.resetMsFor(limitRow.window)
        return remainingMs > 0 ? "Resets in " + root.formatDuration(remainingMs) : ""
      }
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // A seat as cswap's watch page draws it: its number (and alias) and email,
  // the organization under them, then a meter per window (5h, 7d and each
  // model's week) with the share used and the time to the reset. The active
  // seat is picked out; a click on another one switches to it.
  component SeatRow: Item {
    id: seatRow
    property var seat: null
    readonly property bool switchable: !!seat && !seat.active && root.switchingTo === 0
    readonly property var lines: seat ? Account.lines("claude", seat) : []

    implicitHeight: seatColumn.implicitHeight + Style.spacing.lg

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: root.alpha(root.foreground,
        seatRow.seat && seatRow.seat.active ? 0.1 : (seatHover.containsMouse && seatRow.switchable ? 0.07 : 0))
    }

    Column {
      id: seatColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      Item {
        width: parent.width
        implicitHeight: Math.max(seatEmail.implicitHeight, seatNote.implicitHeight)

        Text {
          id: seatEmail
          textFormat: Text.PlainText
          text: seatRow.seat ? Swap.badge(seatRow.seat) + "  " + (seatRow.lines[0] || "") : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: !!seatRow.seat && seatRow.seat.active
          elide: Text.ElideRight
          anchors.left: parent.left
          anchors.right: seatNote.left
          anchors.rightMargin: Style.spacing.sm
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          id: seatNote
          textFormat: Text.PlainText
          text: !seatRow.seat ? ""
            : root.switchingTo === seatRow.seat.number ? "switching…"
            : seatRow.seat.active ? "● active"
            : seatHover.containsMouse && seatRow.switchable ? "switch ›"
            : Swap.note(seatRow.seat)
          color: seatRow.seat && seatRow.seat.active ? root.foreground : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: !!seatRow.seat && seatRow.seat.active
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Text {
        visible: seatRow.lines.length > 1
        width: parent.width
        textFormat: Text.PlainText
        text: seatRow.lines.length > 1 ? seatRow.lines[1] : ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Repeater {
        model: seatRow.seat ? seatRow.seat.windows : []

        SeatWindow {
          required property var modelData
          width: seatColumn.width
          window: modelData
        }
      }

      Text {
        visible: !!seatRow.seat && seatRow.seat.windows.length === 0
        textFormat: Text.PlainText
        text: "no reading"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    MouseArea {
      id: seatHover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: seatRow.switchable ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: if (seatRow.switchable) root.switchSeat(seatRow.seat.number)
    }

    PanelToolTip {
      visible: seatHover.containsMouse && !!seatRow.seat
      text: !seatRow.seat ? ""
        : seatRow.seat.windows.map(function(w) { return Swap.windowDetail(w, root.nowMs) })
            .concat([seatRow.seat.active ? "The seat Claude Code uses now"
              : "Click: switch every Claude Code to this seat (cswap switch " + seatRow.seat.number + ")"])
            .join("\n")
      fontFamily: root.fontFamily
    }
  }

  // One window of a seat, on one line: its label, a meter, the share used
  // (red from 90%, as LIMITS) and the time to its reset.
  component SeatWindow: Item {
    id: seatWindow
    property var window: null
    readonly property var now: Swap.project(window, root.nowMs)
    readonly property bool alarming: !!now && now.percent >= 0.9

    implicitHeight: windowLabel.implicitHeight

    Text {
      id: windowLabel
      width: Style.space(44)
      textFormat: Text.PlainText
      text: seatWindow.window ? seatWindow.window.label : ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }

    Meter {
      anchors.left: windowLabel.right
      anchors.right: windowPercent.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      thickness: Math.max(Style.space(3), Math.round(Style.spacing.controlHeight * 0.1))
      value: seatWindow.now ? seatWindow.now.percent : -1
      alarming: seatWindow.alarming
    }

    Text {
      id: windowPercent
      width: Style.space(34)
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
      text: Swap.percentText(seatWindow.window, root.nowMs)
      color: seatWindow.alarming ? root.urgent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      anchors.right: windowReset.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: windowReset
      width: Style.space(48)
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
      text: Swap.resetText(seatWindow.window, root.nowMs)
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  // Rounded track showing the percentage of the allowance used.
  component Meter: Item {
    id: meter
    property real value: -1
    property bool alarming: false
    property real thickness: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))

    implicitHeight: thickness

    Rectangle {
      id: meterTrack
      anchors.fill: parent
      radius: height / 2
      color: root.track
    }

    Rectangle {
      anchors.left: meterTrack.left
      anchors.verticalCenter: meterTrack.verticalCenter
      height: meterTrack.height
      radius: meterTrack.radius
      width: meterTrack.width * root.clamp(meter.value, 0, 1)
      color: meter.alarming ? root.urgent : root.foreground

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }

  }

  // One row per day: label, bar, tokens. Today is picked out in full
  // foreground so the week reads as a run-up to right now.
  component DayRow: Item {
    id: dayRow
    property var day: null
    property real ratio: 0
    property bool today: false

    implicitHeight: Math.max(dayLabel.implicitHeight, dayValue.implicitHeight) + Style.spacing.sm

    Text {
      id: dayLabel
      textFormat: Text.PlainText
      text: root.dayLabel(dayRow.day ? dayRow.day.date : "", dayRow.today)
      color: dayRow.today ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: dayRow.today
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(52)
    }

    Rectangle {
      id: dayTrack
      anchors.left: dayLabel.right
      anchors.right: dayValue.left
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      height: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))
      radius: height / 2
      color: root.track

      Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        radius: parent.radius
        width: parent.width * root.clamp(dayRow.ratio, 0, 1)
        color: dayRow.today ? root.foreground : root.alpha(root.foreground, 0.55)

        Behavior on width {
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
      }
    }

    Text {
      id: dayValue
      textFormat: Text.PlainText
      text: usage.formatTokenCount(dayRow.day ? Number(dayRow.day.messageCount || 0) : 0)
      color: dayRow.today ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      horizontalAlignment: Text.AlignRight
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(52)
    }

    MouseArea {
      id: dayHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    PanelToolTip {
      visible: dayHover.containsMouse
      text: root.dayTooltip(dayRow.day, dayRow.today)
      fontFamily: root.fontFamily
    }
  }

  // A project, as a model row is drawn: its name (shortened in the middle,
  // where long paths repeat), its tokens in the last 7 days, and its share of
  // the busiest project behind them. A click opens its days.
  component ProjectRow: Item {
    id: projectRow
    property var row: null

    implicitHeight: projectName.implicitHeight + Style.spacing.lg

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, projectHover.containsMouse ? 0.09 : 0.05)
    }

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: parent.width * root.clamp(projectRow.row ? projectRow.row.share : 0, 0, 1)
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, 0.14)

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }

    Text {
      id: projectName
      textFormat: Text.PlainText
      text: projectRow.row ? projectRow.row.name : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideMiddle
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.right: projectTokens.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: projectTokens
      textFormat: Text.PlainText
      text: projectRow.row ? usage.formatTokenCount(projectRow.row.week) : ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    MouseArea {
      id: projectHover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: if (projectRow.row) root.openProjects(projectRow.row.path)
    }

    PanelToolTip {
      visible: projectHover.containsMouse
      text: root.projectsSummary
        ? Projects.rowTooltip(projectRow.row, root.projectsSummary, root.todayDate(), usage.formatTokenCount)
        : ""
      fontFamily: root.fontFamily
    }
  }

  // Model rows read as a table: the share bar fills the row behind the label
  // instead of stacking under it, which keeps the whole dashboard on one screen.
  component ModelRow: Item {
    id: modelRow
    property var row: null
    property real share: 0

    implicitHeight: modelName.implicitHeight + Style.spacing.lg

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, 0.05)
    }

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: parent.width * root.clamp(modelRow.share, 0, 1)
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, 0.14)

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }

    Text {
      id: modelName
      textFormat: Text.PlainText
      text: modelRow.row ? modelRow.row.name : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.right: modelTokens.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: modelTokens
      textFormat: Text.PlainText
      text: modelRow.row ? usage.formatTokenCount(modelRow.row.total) : ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    MouseArea {
      id: modelHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    PanelToolTip {
      visible: modelHover.containsMouse
      text: root.modelTooltip(modelRow.row)
      fontFamily: root.fontFamily
    }
  }
}
