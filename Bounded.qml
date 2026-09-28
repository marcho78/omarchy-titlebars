import QtQuick
import Quickshell
import Quickshell.Io

// Runs one command in its own session with a byte budget and a deadline. Output
// is checked as it arrives; going over the budget or the deadline kills the
// whole process group. `finished(ok, text)` reports stdout on success, or the
// reason and any stderr on failure.
Item {
  id: root

  property int maxBytes: 64 * 1024
  property int timeoutMs: 15000
  // Called with each stdout chunk instead of collecting it (for long builds).
  property var onChunk: null

  readonly property bool running: proc.running

  signal finished(bool ok, string text)

  property string _out: ""
  property string _err: ""
  property int _seen: 0
  property string _failed: ""

  function start(argv) {
    if (proc.running) return false
    _out = ""
    _err = ""
    _seen = 0
    _failed = ""
    // setsid makes the command its own process group, so the group can be killed.
    proc.command = ["/usr/bin/setsid", "--wait"].concat(argv)
    proc.running = true
    deadline.restart()
    return true
  }

  function _fail(reason) {
    if (_failed) return
    _failed = reason
    if (proc.processId > 0) Quickshell.execDetached(["/usr/bin/kill", "-KILL", "--", "-" + proc.processId])
  }

  function _take(data, isError) {
    if (_failed) return
    _seen += data.length
    if (_seen > maxBytes) {
      _fail("printed more than " + maxBytes + " bytes")
      return
    }
    if (isError) _err += data
    else if (typeof onChunk === "function") onChunk(data)
    else _out += data
  }

  Timer {
    id: deadline
    interval: root.timeoutMs
    onTriggered: root._fail("took longer than " + Math.round(root.timeoutMs / 1000) + "s")
  }

  Process {
    id: proc
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(data) { root._take(data, false) }
    }
    stderr: SplitParser {
      splitMarker: ""
      onRead: function(data) { root._take(data, true) }
    }
    onExited: function(exitCode) {
      deadline.stop()
      var ok = exitCode === 0 && !root._failed
      var text = ok ? root._out : (root._failed || root._err.trim() || ("exit code " + exitCode))
      root._out = ""
      root.finished(ok, text)
    }
  }
}
