import QtQuick
import Quickshell

// The agents panel loaded without a bar or a window (run.sh): once its records
// are in, it prints what TOKENS BY PROJECT would show on each tab, switches the
// view with p and back, and quits. HARNESS_PROJECTS names another summary file
// (one that does not exist: the panel must fall back to the models).
// HARNESS_CSWAP names the cswap the panel runs (run.sh gives the stub in
// tests/cswap-stub, which switches nothing): it prints ACCOUNTS, clicks seat 1,
// then seat 3 (which the stub refuses), and prints what the panel says.
ShellRoot {
  id: shell
  property var panel: null

  Component.onCompleted: {
    // A file outside the config folder needs its full path (run.sh gives it).
    var c = Qt.createComponent("file://" + Quickshell.env("HARNESS_PANEL"))
    if (c.status === Component.Error) { console.log("HARNESS error:", c.errorString()); Qt.quit(); return }
    var settings = {}
    var file = Quickshell.env("HARNESS_PROJECTS")
    if (file) settings.projectsFile = file
    var cswap = Quickshell.env("HARNESS_CSWAP")
    if (cswap) settings.cswapCommand = cswap
    panel = c.createObject(null, { settings: settings })
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
      function seats(tag) {
        console.log("HARNESS", tag, JSON.stringify({
          auto: p.swapAuto, active: p.swapList.active, switching: p.switchingTo,
          message: p.swapMessage, error: p.swapMessageError,
          seats: p.swapSeats.map(function(s) { return s.number + " " + s.email + " " + (s.active ? "active" : "") }) }))
      }
      seats("accounts")
      p.switchSeat(2); seats("click on the active seat")
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
        switching: p.switchingTo, message: p.swapMessage, error: p.swapMessageError }))
      if (step === 0) { step = 1; p.switchSeat(3); start() }
      else Qt.quit()
    }
  }
}
