// The projects behind the tokens, from the summary of gwath's token counter
// (~/.local/state/gwath/tokens.json; `gwath tokens` counts each project's
// tokens day by day from the same transcripts the collectors read). The panel
// shows the projects one agent used most in the last 7 days; a click opens
// them all.
//
// Plain functions, so the file runs under node too (Projects.test.js).

// The summary, or null when there is none or the text is not one.
function parse(text) {
  try {
    var summary = JSON.parse(String(text || ""))
    return summary && Array.isArray(summary.projects) ? summary : null
  } catch (e) {
    return null
  }
}

// One agent's figures for a project: today, the last 7 and 30 days, everything.
function figures(project, providerId) {
  var a = project && project.agents ? project.agents[providerId] : null
  return {
    today: Number((a && a.today) || 0),
    week: Number((a && a.week) || 0),
    month: Number((a && a.month) || 0),
    all: Number((a && a.all) || 0)
  }
}

// The n projects of the agent with the most tokens in the last 7 days, the
// most first, each with its share of the first one (the bar behind its row).
function top(summary, providerId, n) {
  var rows = []
  var list = summary ? summary.projects : []
  for (var i = 0; i < list.length; i++) {
    var f = figures(list[i], providerId)
    if (!(f.week > 0)) continue
    rows.push({ name: String(list[i].name || list[i].path || ""), path: String(list[i].path || ""),
                today: f.today, week: f.week, month: f.month, all: f.all, share: 0 })
  }
  rows.sort(function(a, b) { return b.week - a.week || b.all - a.all })
  rows = rows.slice(0, Math.max(0, n))
  for (var j = 0; j < rows.length; j++) rows[j].share = rows[j].week / rows[0].week
  return rows
}

// How many projects the agent has ever been used in.
function count(summary, providerId) {
  var list = summary ? summary.projects : []
  var n = 0
  for (var i = 0; i < list.length; i++) if (figures(list[i], providerId).all > 0) n++
  return n
}

// When the summary was written: the time alone on its day, else the date too.
function stampText(summary, today) {
  var updated = String((summary && summary.updated) || "")
  return updated.slice(0, 10) === today ? updated.slice(11) : updated
}

function rowTooltip(row, summary, today, format) {
  if (!row) return ""
  return row.path
    + "\nToday " + format(row.today) + " · 7 days " + format(row.week)
    + " · 30 days " + format(row.month) + " · all " + format(row.all)
    + "\nAs of " + stampText(summary, today) + " · click for its days"
}

if (typeof module !== "undefined") {
  module.exports = {
    parse: parse,
    figures: figures,
    top: top,
    count: count,
    stampText: stampText,
    rowTooltip: rowTooltip
  }
}
