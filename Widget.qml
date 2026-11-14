import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Live network throughput: ↓ download and ↑ upload per second, summed over the
// interfaces that carry a default route (or the ones named in settings).
// Counters come from /proc/net/dev and routes from /proc/net/route and
// /proc/net/ipv6_route, all read in-process through FileView, so polling
// spawns nothing. Each bar instance (one per monitor) keeps its own samples.
//
// Click: Omarchy network panel · Right-click: speed test.
// IPC: omarchy-shell mulm.netspeed get
BarWidget {
  id: root
  moduleName: "mulm.netspeed"

  readonly property int intervalMs: Math.max(500, Number(setting("intervalMs", 1000)) || 1000)
  readonly property bool bits: String(setting("unit", "Bytes")) === "Bits"
  readonly property var pinned: String(setting("interface", "")).split(",").map(s => s.trim()).filter(s => s !== "")

  property var routed: []      // interfaces with a default route
  property var counters: ({})  // iface -> { rx, tx } from the last sample
  property real lastMs: 0
  property real down: 0        // bytes/s
  property real up: 0
  property real totalRx: 0     // bytes since boot on the tracked interfaces
  property real totalTx: 0
  property var history: []     // [{ t, down, up }] over the last minute
  property int tick: 0

  readonly property var tracked: pinned.length ? pinned : routed
  readonly property real peakDown: history.reduce((m, s) => Math.max(m, s.down), 0)
  readonly property real peakUp: history.reduce((m, s) => Math.max(m, s.up), 0)

  // ---------- parsing ----------
  function parseDev(text) {
    var out = {}
    var lines = String(text || "").split("\n")
    for (var i = 2; i < lines.length; i++) {
      var colon = lines[i].indexOf(":")
      if (colon < 0) continue
      var name = lines[i].slice(0, colon).trim()
      var f = lines[i].slice(colon + 1).trim().split(/\s+/)
      if (name === "" || f.length < 9) continue
      out[name] = { rx: Number(f[0]) || 0, tx: Number(f[8]) || 0 }
    }
    return out
  }

  // Default routes: /proc/net/route has destination 00000000; ipv6_route has
  // an all-zero destination with prefix length 00 and the device last.
  function parseRoutes(v4, v6) {
    var seen = {}
    String(v4 || "").split("\n").slice(1).forEach(function(line) {
      var f = line.trim().split(/\s+/)
      if (f.length > 7 && f[1] === "00000000" && f[7] === "00000000") seen[f[0]] = true
    })
    String(v6 || "").split("\n").forEach(function(line) {
      var f = line.trim().split(/\s+/)
      if (f.length === 10 && /^0{32}$/.test(f[0]) && f[1] === "00" && f[9] !== "lo") seen[f[9]] = true
    })
    return Object.keys(seen).sort()
  }

  function sample(text) {
    var now = Date.now()
    var cur = parseDev(text)
    var names = tracked.length ? tracked : Object.keys(cur).filter(n => n !== "lo")
    var dt = (now - lastMs) / 1000
    var drx = 0, dtx = 0, rx = 0, tx = 0
    names.forEach(function(n) {
      var c = cur[n]
      if (!c) return
      rx += c.rx
      tx += c.tx
      var p = counters[n]
      // An interface that just appeared or whose counters reset adds nothing.
      if (p && c.rx >= p.rx) drx += c.rx - p.rx
      if (p && c.tx >= p.tx) dtx += c.tx - p.tx
    })
    if (lastMs > 0 && dt > 0.2) {
      down = drx / dt
      up = dtx / dt
      var keep = history.filter(s => now - s.t < 60000)
      keep.push({ t: now, down: down, up: up })
      history = keep
    }
    counters = cur
    lastMs = now
    totalRx = rx
    totalTx = tx
  }

  // ---------- formatting ----------
  // Fixed width (3 figures + 2-letter unit) so the bar never shifts.
  function rateParts(bytesPerSec) {
    var base = bits ? 1000 : 1024
    var units = bits ? ["Kb", "Mb", "Gb", "Tb"] : ["KB", "MB", "GB", "TB"]
    var v = (bits ? bytesPerSec * 8 : bytesPerSec) / base
    var i = 0
    while (v >= 999.5 && i < units.length - 1) { v /= base; i++ }
    return { num: v < 9.95 ? v.toFixed(1) : String(Math.round(v)), unit: units[i] }
  }
  function barRate(bytesPerSec) {
    var p = rateParts(bytesPerSec)
    return ("   " + p.num).slice(-3) + p.unit
  }
  function rate(bytesPerSec) {
    var p = rateParts(bytesPerSec)
    return p.num + " " + p.unit + "/s"
  }
  function size(bytes) {
    var units = ["B", "KB", "MB", "GB", "TB"], v = bytes, i = 0
    while (v >= 1024 && i < units.length - 1) { v /= 1024; i++ }
    return (i === 0 ? String(v) : v.toFixed(v < 10 ? 2 : 1)) + " " + units[i]
  }
  // Interface names reach a shared tooltip; keep them to plain characters.
  function safeName(n) { return String(n).replace(/[^A-Za-z0-9._@-]/g, "?").slice(0, 32) }

  readonly property string barText: vertical ? "⇅" : "↓" + barRate(down) + " ↑" + barRate(up)
  readonly property string tooltip: {
    var names = tracked.length ? tracked.map(safeName).join(", ") : "all interfaces"
    return "Network — " + names
      + "\n↓ " + rate(down) + "   ↑ " + rate(up)
      + "\nPeak, last minute: ↓ " + rate(peakDown) + "   ↑ " + rate(peakUp)
      + "\nSince boot: ↓ " + size(totalRx) + "   ↑ " + size(totalTx)
      + "\nClick: network panel · Right-click: speed test"
  }

  // ---------- sources ----------
  FileView {
    id: devFile
    path: "/proc/net/dev"
    printErrors: false
    onLoaded: root.sample(text())
  }
  // blockAllReads: text() right after reload() waits for the fresh contents.
  FileView { id: routeFile; path: "/proc/net/route"; blockAllReads: true; printErrors: false }
  FileView { id: route6File; path: "/proc/net/ipv6_route"; blockAllReads: true; printErrors: false }

  function refreshRoutes() {
    routeFile.reload()
    route6File.reload()
    var r = parseRoutes(routeFile.text(), route6File.text())
    if (JSON.stringify(r) !== JSON.stringify(routed)) routed = r
  }

  Timer {
    interval: root.intervalMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      // Routes change rarely (Wi-Fi ↔ Ethernet, VPN); re-read them every ~5 s.
      if (root.tick++ % Math.max(1, Math.round(5000 / root.intervalMs)) === 0) root.refreshRoutes()
      devFile.reload()
    }
  }

  ShellIpc {
    target: root.moduleName
    function get(): string {
      return JSON.stringify({ interfaces: root.tracked, down: Math.round(root.down), up: Math.round(root.up),
                              totalRx: root.totalRx, totalTx: root.totalTx })
    }
  }

  // ---------- bar ----------
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText
    horizontalMargin: 7
    dimmed: root.down < 1024 && root.up < 1024
    tooltipText: root.tooltip
    onPressed: function(b) {
      if (b === Qt.RightButton) Quickshell.execDetached(["omarchy-shell", "omarchy.network", "speedTest"])
      else if (b === Qt.LeftButton) Quickshell.execDetached(["omarchy-shell", "omarchy.network", "toggle"])
    }
  }
}
