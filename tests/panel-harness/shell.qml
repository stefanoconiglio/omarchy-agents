import QtQuick
import Quickshell

// The agents panel loaded without a bar or a window (run.sh): once its records
// are in, it prints what TOKENS BY PROJECT would show on each tab, switches the
// view with p and back, and quits. HARNESS_PROJECTS names another summary file
// (one that does not exist: the panel must fall back to the models).
// HARNESS_USAGE names the usage update the panel runs (run.sh gives the
// stub in tests/usage-stub, so no test reads the transcripts).
// HARNESS_CSWAP names the cswap the panel runs (run.sh gives the stub in
// tests/cswap-stub, which switches nothing): it prints ACCOUNTS, clicks seat 1,
// then seat 3 (which the stub refuses), and prints what the panel says. The
// moment each answer is in, the pin and the bar's numbers must be on seat 1
// (the stub's 42% and 63%, read on 10 Oct 2026 at noon), not on the seat
// active before: it prints PASS or FAIL.
ShellRoot {
  id: shell
  property var panel: null
  property var expect: null

  Component.onCompleted: {
    // A file outside the config folder needs its full path (run.sh gives it).
    var c = Qt.createComponent("file://" + Quickshell.env("HARNESS_PANEL"))
    if (c.status === Component.Error) { console.log("HARNESS error:", c.errorString()); Qt.quit(); return }
    var settings = {}
    var file = Quickshell.env("HARNESS_PROJECTS")
    if (file) settings.projectsFile = file
    var cswap = Quickshell.env("HARNESS_CSWAP")
    if (cswap) settings.cswapCommand = cswap
    var usage = Quickshell.env("HARNESS_USAGE")
    if (usage) settings.usageCommand = usage
    panel = c.createObject(null, { settings: settings })
  }

  function percent(w) { return w ? Math.round(w.percent * 100) : -1 }

  // Every object under o (an item's children, a window's content), once.
  function walk(o, visit, seen) {
    if (!o || typeof o !== "object" || seen.indexOf(o) >= 0) return
    seen.push(o)
    visit(o)
    var keys = ["children", "data", "contentItem"]
    keys.forEach(function(k) {
      var v
      try { v = o[k] } catch (e) { return }
      if (!v || typeof v !== "object") return
      if (v.length !== undefined) { for (var i = 0; i < v.length; i++) walk(v[i], visit, seen) }
      else walk(v, visit, seen)
    })
  }

  // The hero's account lines: how many the Repeater beside PanelHero draws.
  function heroLines(p) {
    var n = -1
    walk(p, function(o) {
      if (o.iconComponent === undefined || o.meta === undefined || !o.parent) return
      for (var i = 0; i < o.parent.children.length; i++) {
        var c = o.parent.children[i]
        if (c.count !== undefined && typeof c.itemAt === "function") n = c.count
      }
    }, [])
    return n
  }

  // ACCOUNTS and TOKENS BY DAY on one grid: a seat's window rows (label,
  // meter, percent, time to the reset) and the day rows (label, track,
  // tokens), found by their properties, children in the order Panel.qml
  // declares them. Their labels start on one edge, their bars start and end
  // on one edge, their last numbers end on one edge, and every reading fits
  // its column (a guard for the narrower meters, not a bug seen).
  function grid(p) {
    var rows = []
    function left(i) { return Math.round(i.mapToItem(null, 0, 0).x) }
    function right(i) { return Math.round(i.mapToItem(null, 0, 0).x + i.width) }
    walk(p, function(o) {
      var c = o.children
      if (o.now !== undefined && o.alarming !== undefined && o.window !== undefined && c && c.length >= 4)
        rows.push({ kind: "seat " + c[0].text, label: c[0], bar: c[1], numbers: [c[2], c[3]] })
      else if (o.day !== undefined && o.ratio !== undefined && o.today !== undefined && c && c.length >= 3)
        rows.push({ kind: "day " + c[0].text, label: c[0], bar: c[1], numbers: [c[2]] })
    }, [])
    var edges = rows.map(function(r) {
      var last = r.numbers[r.numbers.length - 1]
      return { row: r.kind, label: left(r.label), barStart: left(r.bar), barEnd: right(r.bar), numbersEnd: right(last),
               crowded: r.numbers.filter(function(t) { return t.text !== "" && t.implicitWidth > t.width + 0.5 })
                          .map(function(t) { return t.text + " " + Math.round(t.implicitWidth) + ">" + Math.round(t.width) }) }
    })
    var seats = edges.filter(function(e) { return e.row.indexOf("seat") === 0 }).length
    var days = edges.length - seats
    var same = seats > 0 && days > 0 && edges.every(function(e) {
      return e.label === edges[0].label && e.barStart === edges[0].barStart
        && e.barEnd === edges[0].barEnd && e.numbersEnd === edges[0].numbersEnd })
    var crowded = edges.filter(function(e) { return e.crowded.length > 0 })
    console.log("HARNESS", (same ? "PASS " : "FAIL ") + "ACCOUNTS and TOKENS BY DAY on one grid",
                JSON.stringify({ seats: seats, days: days, edges: edges.map(function(e) {
                  return e.row + ": " + [e.label, e.barStart, e.barEnd, e.numbersEnd].join(" ") }) }))
    console.log("HARNESS", (seats > 0 && crowded.length === 0 ? "PASS " : "FAIL ") + "every reading fits its column",
                JSON.stringify(crowded.map(function(e) { return e.row + ": " + e.crowded.join(", ") })))
  }

  function bar(p) {
    return { active: p.swapList.active,
             pin: p.swapSeats.filter(function(s) { return s.active }).map(function(s) { return s.number }),
             session: percent(p.barWindows.session), weekly: percent(p.barWindows.weekly) }
  }

  // switchingTo goes back to 0 when cswap's answer is in.
  Connections {
    target: shell.panel
    function onSwitchingToChanged() {
      if (!shell.panel || shell.panel.switchingTo !== 0 || !shell.expect) return
      var got = shell.bar(shell.panel)
      var want = shell.expect
      var ok = got.active === want.active && got.pin.length === 1 && got.pin[0] === want.active
        && got.session === want.session && got.weekly === want.weekly
      console.log("HARNESS", (ok ? "PASS " : "FAIL ") + want.tag, JSON.stringify({ got: got, want: want }))
    }
  }

  Timer {
    interval: 6000
    running: true
    onTriggered: {
      var p = shell.panel
      function dump(tag) {
        console.log("HARNESS", tag, JSON.stringify({
          provider: p.provider ? p.provider.providerId : "",
          views: p.tokensViews, view: p.tokensView,
          rows: p.projectRows.map(function(r) { return r.name + " " + r.week + " " + r.share.toFixed(2) }),
          all: p.projectsSummary ? p.projectsSummary.projects.length : -1,
          models: p.models.length }))
      }
      dump("first tab")
      p.toggleTokensView(); dump("after p")
      p.toggleTokensView(); dump("after p again")
      p.selectProvider(p.providerIndex + 1); dump("next tab")
      if (!Quickshell.env("HARNESS_CSWAP")) { Qt.quit(); return }
      for (var i = 0; i < p.providers.length; i++)
        if (p.providers[i].providerId === "claude") p.selectProvider(i)
      // The stub's readings were taken on 10 Oct 2026; read at noon that day
      // they have not reset.
      p.barNowMs = Date.parse("2026-10-10T12:00:00Z")
      function seats(tag) {
        console.log("HARNESS", tag, JSON.stringify({
          auto: p.swapAuto, active: p.swapList.active, switching: p.switchingTo,
          message: p.swapMessage, error: p.swapMessageError,
          seats: p.swapSeats.map(function(s) { return s.number + " " + s.email + " " + (s.active ? "active" : "") }),
          bar: shell.bar(p), recordMs: p.barRecordMs }))
      }
      seats("accounts")
      // The active seat already names the account: the hero does not again.
      var lines = heroLines(p)
      console.log("HARNESS", (lines === 0 ? "PASS " : "FAIL ") + "hero without the account on the Claude tab with seats",
                  JSON.stringify({ heroLines: lines, account: p.accountLines }))
      // Read at 19:15 on 12 Oct, seat 1's week resets in 20h 45m, the
      // widest reading in the screenshot of 14 Nov 2026.
      var nowMs = p.nowMs
      p.nowMs = Date.parse("2026-10-12T19:15:00Z")
      grid(p)
      p.nowMs = nowMs
      for (var k = 0; k < p.providers.length; k++)
        if (p.providers[k].providerId !== "claude") {
          p.selectProvider(k)
          lines = heroLines(p)
          console.log("HARNESS", (lines > 0 && lines === p.accountLines.length ? "PASS " : "FAIL ")
                      + "hero with the account on the " + p.provider.providerId + " tab",
                      JSON.stringify({ heroLines: lines, account: p.accountLines.length }))
          break
        }
      for (var j = 0; j < p.providers.length; j++)
        if (p.providers[j].providerId === "claude") p.selectProvider(j)
      p.switchSeat(2); seats("click on the active seat")
      shell.expect = { tag: "pin and bar on seat 1 at cswap's answer", active: 1, session: 42, weekly: 63 }
      p.switchSeat(1); seats("click on seat 1")
      swapSteps.start()
    }
  }

  Timer {
    id: swapSteps
    interval: 1500
    property int step: 0
    onTriggered: {
      var p = shell.panel
      console.log("HARNESS", "after switch " + (step === 0 ? 1 : 3), JSON.stringify({
        switching: p.switchingTo, message: p.swapMessage, error: p.swapMessageError, bar: shell.bar(p) }))
      if (step === 0) {
        step = 1
        shell.expect = { tag: "pin and bar still on seat 1 after a refused switch", active: 1, session: 42, weekly: 63 }
        p.switchSeat(3)
        start()
      }
      else Qt.quit()
    }
  }
}
