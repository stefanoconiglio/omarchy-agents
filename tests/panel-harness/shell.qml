import QtQuick
import Quickshell

// The agents panel loaded without a bar or a window (run.sh): once its records
// are in, it prints what TOKENS BY PROJECT would show on each tab, switches the
// view with p and back, and quits. HARNESS_PROJECTS names another summary file
// (one that does not exist: the panel must fall back to the models).
ShellRoot {
  id: shell
  property var panel: null

  Component.onCompleted: {
    // A file outside the config folder needs its full path (run.sh gives it).
    var c = Qt.createComponent("file://" + Quickshell.env("HARNESS_PANEL"))
    if (c.status === Component.Error) { console.log("HARNESS error:", c.errorString()); Qt.quit(); return }
    var file = Quickshell.env("HARNESS_PROJECTS")
    panel = c.createObject(null, { settings: file ? { projectsFile: file } : {} })
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
      Qt.quit()
    }
  }
}
