import QtQuick

// Opens the Title Bars panel once after the plugin is first enabled, so a new
// install is set up with one click in the panel instead of terminal steps.
// bin/titlebars decides: only when nothing is set up and it hasn't asked before.
Item {
  id: root

  property var shell: null

  readonly property string pluginId: "marcho78.titlebars"
  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")

  Bounded {
    id: offer
    maxBytes: 1024
    timeoutMs: 20000
    onFinished: function(ok, text) {
      if (ok && text.trim() === "yes" && root.shell && typeof root.shell.summon === "function")
        root.shell.summon(root.pluginId, "{}")
    }
  }

  Component.onCompleted: offer.start(["/usr/bin/python3", "-I", pluginDir + "/bin/titlebars", "offer-setup"])
}
