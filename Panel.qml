import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Styles.js" as Styles

// Title Bars settings: restyle the window title bars with a live preview.
// Open it from Omarchy menu > Style > Title Bars, `titlebars settings`, or
//   omarchy-shell shell summon marcho78.titlebars '{}'
//
// Changes are written to ~/.config/omarchy/titlebars.json (only the values
// that differ from defaults.json) and Hyprland reloads to apply them.
Item {
  id: root

  // ---- plugin lifecycle ------------------------------------------------------

  property var shell: null
  property bool closingFromHost: false

  readonly property string pluginId: "marcho78.titlebars"
  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string home: Quickshell.env("HOME")
  // Every file under $HOME is read and written by bin/titlebars, which checks
  // ownership, refuses symlinks and oversized files, and validates settings.
  readonly property var titlebars: ["/usr/bin/python3", "-I", pluginDir + "/bin/titlebars"]

  // Payload may name a page to show, e.g. { "page": "colors" }, or a color
  // to edit, e.g. { "color": "close" }.
  function open(payloadJson) {
    closingFromHost = false
    try {
      var payload = JSON.parse(String(payloadJson || "{}"))
      if (payload && pages.some(function(p) { return p.id === payload.page })) page = payload.page
      if (payload && colorChoices.some(function(c) { return c.role === payload.color })) {
        page = "colors"
        pickerRole = payload.color
      }
    } catch (e) { /* ignore a bad payload */ }
    var alreadyOpen = window.visible
    window.visible = true
    // Opening it again brings the panel back, even from minimized or another workspace.
    if (alreadyOpen) Quickshell.execDetached(["/usr/bin/hyprctl", "dispatch", 'hl.dsp.focus({ window = "title:^Title Bars$" })'])
    reload()
    refreshApps()
  }

  // Host-initiated close (`shell hide`).
  function close() {
    closingFromHost = true
    window.visible = false
    closingFromHost = false
  }

  // User-initiated close (Esc, the window's close button): tell the shell so
  // its open-panel state stays in sync.
  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else window.visible = false
  }

  // ---- settings --------------------------------------------------------------

  property var defaults: null
  property var schema: ({ choices: {}, ranges: {} })
  property var user: ({})
  property var palette: ({})
  property var status: ({})
  property bool eyedropper: false
  property string problem: ""

  readonly property bool ready: defaults !== null
  readonly property var settings: ready ? Styles.merge(defaults, user, schema) : ({})
  readonly property var colors: ready ? Styles.colorsFor(settings, defaults, palette) : ({})
  readonly property var buttons: ready ? Styles.buttons(settings, colors) : []
  readonly property bool customized: Object.keys(user).length > 0
  // The gear needs our hyprbars patch; `titlebars build` records whether it applied.
  readonly property bool gearAvailable: status.gear === true
  readonly property var gear: ready && gearAvailable ? Styles.settingsButton(settings, colors) : null

  function range(key) {
    return (schema.ranges && schema.ranges[key]) || [0, 100]
  }

  // Store only what differs from the defaults so plugin updates can improve them.
  function set(key, value) {
    var next = JSON.parse(JSON.stringify(user))
    if (JSON.stringify(value) === JSON.stringify(defaults[key])) delete next[key]
    else next[key] = value
    user = next
    saveTimer.restart()
  }

  // Picking a color means choosing your own colors over the theme's.
  function setColor(role, value) {
    var next = JSON.parse(JSON.stringify(user))
    if (settings.followTheme !== false) next.followTheme = false
    var chosen = next.colors || {}
    if (value === defaults.colors[role]) delete chosen[role]
    else chosen[role] = value
    if (Object.keys(chosen).length > 0) next.colors = chosen
    else delete next.colors
    user = next
    saveTimer.restart()
  }

  function resetAll() {
    user = ({})
    saveTimer.restart()
  }

  function reload() {
    if (!loader.start(titlebars.concat(["load"]))) reloadPending = true
  }

  property bool reloadPending: false
  property bool savePending: false

  // bin/titlebars validates, stores, and reloads Hyprland.
  function save() {
    if (!saver.start(titlebars.concat(["save", JSON.stringify(user)]))) savePending = true
  }

  Timer {
    id: saveTimer
    interval: 300
    onTriggered: root.save()
  }

  Bounded {
    id: loader
    maxBytes: 256 * 1024
    timeoutMs: 20000
    onFinished: function(ok, text) {
      if (ok) {
        try {
          var state = JSON.parse(text)
          root.schema = state.schema
          root.palette = state.palette || ({})
          root.status = state.status || ({})
          root.eyedropper = state.eyedropper === true
          root.problem = state.problem || ""
          if (!saveTimer.running && !saver.running) root.user = state.user || ({})
          root.defaults = state.defaults
        } catch (e) {
          root.problem = "Couldn't read the settings."
        }
      } else {
        root.problem = "Couldn't read the settings: " + text
      }
      if (root.reloadPending) {
        root.reloadPending = false
        root.reload()
      }
    }
  }

  Bounded {
    id: saver
    maxBytes: 16 * 1024
    timeoutMs: 20000
    onFinished: function(ok, text) {
      root.problem = ok ? "" : "Couldn't save: " + text
      if (root.savePending) {
        root.savePending = false
        root.save()
      } else if (!ok) {
        root.reload()
      }
    }
  }

  // ---- setup ------------------------------------------------------------------------

  property bool settingUp: false
  property string setupMessage: ""
  readonly property bool statusKnown: status.built !== undefined
  readonly property bool unsupported: statusKnown && status.supported === false && status.built !== true
  readonly property bool needsSetup: statusKnown && !unsupported && (status.built !== true || status.hooked !== true)

  function startSetup() {
    settingUp = true
    setupMessage = "Building hyprbars for your Hyprland version. This takes a minute or two..."
    setup.start(titlebars.concat(["setup"]))
  }

  Bounded {
    id: setup
    maxBytes: 1024 * 1024
    // Cloning plus compiling; slow machines need the headroom.
    timeoutMs: 45 * 60 * 1000
    onChunk: function(data) {
      var lines = data.split("\n").filter(function(line) { return line.trim() !== "" })
      if (lines.length) root.setupMessage = lines[lines.length - 1].slice(0, 300)
    }
    onFinished: function(ok, text) {
      root.settingUp = false
      if (!ok) root.setupMessage = "Setup failed: " + text.slice(-600)
      root.reload()
    }
  }

  // ---- fonts and open apps -------------------------------------------------------

  property var fonts: [{ value: "", label: "Omarchy font" }]
  property var openApps: []

  function refreshApps() {
    apps.start(["/usr/bin/hyprctl", "clients", "-j"])
  }

  Bounded {
    id: fontList
    maxBytes: 1024 * 1024
    timeoutMs: 15000
    Component.onCompleted: start(["/usr/bin/fc-list", ":", "family"])
    onFinished: function(ok, text) {
      if (!ok) return
      var names = {}
      text.split("\n").slice(0, 5000).forEach(function(line) {
        var name = line.split(",")[0].trim()
        // Same rules bin/titlebars applies to titleFont.
        if (name && name.length <= 128 && !/[\u0000-\u001f\u007f]/.test(name)) names[name] = true
      })
      root.fonts = [{ value: "", label: "Omarchy font" }].concat(Object.keys(names).sort().map(function(name) {
        return { value: name, label: name }
      }))
    }
  }

  Bounded {
    id: apps
    maxBytes: 2 * 1024 * 1024
    timeoutMs: 5000
    onFinished: function(ok, text) {
      if (!ok) return
      try {
        var classes = {}
        JSON.parse(text).forEach(function(client) {
          var name = client && typeof client["class"] === "string" ? client["class"] : ""
          // Only names that are also valid noBarApps entries.
          if (/^[A-Za-z0-9._-]{1,128}$/.test(name) && name !== "org.quickshell") classes[name] = true
        })
        root.openApps = Object.keys(classes).sort().slice(0, 64)
      } catch (e) {
        root.openApps = []
      }
    }
  }

  // ---- pages -------------------------------------------------------------------------

  property string page: "buttons"
  property string pickerRole: ""
  property bool resetConfirmOpen: false

  readonly property var pages: [
    { id: "buttons", label: "Buttons", glyph: "󰖯" },
    { id: "title", label: "Title", glyph: "" },
    { id: "colors", label: "Colors", glyph: "󰏘" },
    { id: "bar", label: "Bar", glyph: "" },
    { id: "behavior", label: "Behavior", glyph: "󰒓" }
  ]

  readonly property var styleChoices: [
    { id: "dots", label: "Traffic lights" },
    { id: "labeled", label: "Labeled" },
    { id: "mono", label: "Mono" },
    { id: "symbols", label: "Symbols" },
    { id: "nerd", label: "Icons" }
  ]

  readonly property var colorChoices: [
    { role: "bar", label: "Title bar" },
    { role: "title", label: "Title" },
    { role: "titleInactive", label: "Inactive title" },
    { role: "close", label: "Close" },
    { role: "maximize", label: "Maximize" },
    { role: "minimize", label: "Minimize" },
    { role: "icon", label: "Button symbols" },
    { role: "inactiveButton", label: "Inactive buttons" }
  ]

  readonly property var swatchRoles: [
    "background", "darker_background", "lighter_background", "muted", "dark_foreground",
    "foreground", "bright_foreground", "accent", "red", "orange", "yellow", "green",
    "cyan", "blue", "magenta"
  ]

  // PanelSlider takes its colors from a bar object.
  readonly property QtObject sliderBar: QtObject {
    readonly property color foreground: Color.foreground
    readonly property color background: Color.background
    readonly property color urgent: Color.urgent
    readonly property string fontFamily: Style.font.family
    readonly property string position: "top"
    readonly property bool vertical: false
    readonly property int barSize: 26
  }

  component SectionLabel: PanelSectionHeader {
    width: parent ? parent.width : 0
    topPadding: 10
    foreground: Color.foreground
    fontFamily: Style.font.family
  }

  component Caption: Text {
    width: parent ? parent.width : 0
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    color: Color.foreground
    opacity: 0.55
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  component SliderRow: Column {
    id: sliderRow
    property string key: ""
    property string label: ""
    readonly property var bounds: root.range(key)
    width: parent ? parent.width : 0
    spacing: 6

    Item {
      width: parent.width
      height: rowLabel.implicitHeight
      Text {
        id: rowLabel
        textFormat: Text.PlainText
        text: sliderRow.label
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
      Text {
        anchors.right: parent.right
        textFormat: Text.PlainText
        text: Math.round(slider.dragging ? slider.liveValue : (root.settings[sliderRow.key] || 0)) + " px"
        color: Color.foreground
        opacity: 0.6
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }

    PanelSlider {
      id: slider
      width: parent.width
      bar: root.sliderBar
      minimum: sliderRow.bounds[0]
      maximum: sliderRow.bounds[1]
      step: 1
      integer: true
      value: root.settings[sliderRow.key] || 0
      onMoved: function(v) { root.set(sliderRow.key, Math.round(v)) }
      onReleased: function(v) { root.set(sliderRow.key, Math.round(v)) }
    }
  }

  // ---- window -----------------------------------------------------------------------------

  FloatingWindow {
    id: window
    title: "Title Bars"
    color: Color.background
    implicitWidth: 820
    implicitHeight: 660
    minimumSize: Qt.size(720, 560)

    onVisibleChanged: {
      if (!visible && !root.closingFromHost && root.shell && typeof root.shell.hide === "function")
        root.shell.hide(root.pluginId)
    }

    FocusScope {
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.requestClose()

      // Live preview: an unfocused and a focused window.
      Rectangle {
        id: previewArea
        width: parent.width
        height: 196
        color: Color.background
        clip: true

        // A soft backdrop in the theme's colors, so the windows read like a desktop.
        Rectangle {
          anchors.fill: parent
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.darker(Color.accent, 2.4) }
            GradientStop { position: 1.0; color: Qt.darker(Color.accent, 1.3) }
          }
        }

        Preview {
          visible: root.ready
          x: 22
          y: 26
          width: (previewArea.width - 66) / 2
          height: previewArea.height - 52
          active: false
          title: "Files — ~/Documents"
          settings: root.settings
          colors: root.colors
          buttons: root.buttons
          gear: root.gear
          palette: root.palette
          lines: [
            { text: "~/Documents ❯ ls", accent: true },
            { text: "notes.md  plans.md  receipts/", dim: true },
            { text: "~/Documents ❯", accent: true }
          ]
        }

        Preview {
          visible: root.ready
          x: previewArea.width / 2 + 11
          y: 26
          width: (previewArea.width - 66) / 2
          height: previewArea.height - 52
          active: true
          title: "Terminal — ~/projects"
          settings: root.settings
          colors: root.colors
          buttons: root.buttons
          gear: root.gear
          palette: root.palette
          lines: [
            { text: "~/projects ❯ titlebars status", accent: true },
            { text: "hyprbars:  built for this Hyprland" },
            { text: "loaded:    yes" },
            { text: "~/projects ❯", accent: true }
          ]
        }

        Rectangle {
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: 6
          width: hint.implicitWidth + 12
          height: hint.implicitHeight + 4
          color: Qt.rgba(0, 0, 0, 0.45)
          Text {
            id: hint
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: "Live preview · hover the buttons"
            color: "#ffffff"
            opacity: 0.8
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }

      // Page list, on/off switch, and reset.
      Column {
        id: nav
        anchors.top: previewArea.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.margins: 14
        width: 176
        spacing: 4

        Repeater {
          model: root.pages
          Button {
            required property var modelData
            width: nav.width
            leftAlign: true
            iconText: modelData.glyph
            text: modelData.label
            selected: root.page === modelData.id
            onClicked: {
              root.page = modelData.id
              if (modelData.id === "behavior") root.refreshApps()
            }
          }
        }
      }

      Column {
        anchors.left: nav.left
        anchors.right: nav.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14
        spacing: 8

        Row {
          spacing: 10
          ToggleSwitch {
            anchors.verticalCenter: parent.verticalCenter
            checked: root.settings.enabled !== false
            onToggled: root.set("enabled", !(root.settings.enabled !== false))
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.settings.enabled !== false ? "Title bars on" : "Title bars off"
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
        }

        Button {
          width: parent.width
          bordered: true
          iconText: "󰑓"
          text: "Reset to default"
          enabled: root.customized
          opacity: enabled ? 1 : 0.4
          onClicked: root.resetConfirmOpen = true
        }
      }

      Rectangle {
        anchors.top: previewArea.bottom
        anchors.bottom: parent.bottom
        anchors.left: nav.right
        anchors.leftMargin: 14
        width: 1
        color: Color.foreground
        opacity: 0.1
      }

      Flickable {
        id: content
        anchors.top: previewArea.bottom
        anchors.bottom: parent.bottom
        anchors.left: nav.right
        anchors.right: parent.right
        anchors.leftMargin: 29
        anchors.rightMargin: 22
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        contentHeight: pageColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: pageColumn
          width: content.width - 12
          spacing: 10

          // First run: build hyprbars and hook it into Hyprland.
          Rectangle {
            visible: root.needsSetup || root.settingUp || root.unsupported || root.problem !== ""
            width: parent.width
            height: setupColumn.implicitHeight + 24
            color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.1)
            border.width: 1
            border.color: Color.accent

            Column {
              id: setupColumn
              x: 12
              y: 12
              width: parent.width - 24
              spacing: 8

              Text {
                width: parent.width
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: root.settingUp ? root.setupMessage
                  : root.problem !== "" ? root.problem
                  : root.unsupported ? "This Title Bars release doesn't support your Hyprland version yet. Update the plugin with omarchy plugin update marcho78.titlebars; your previous build keeps working until you log out."
                  : "Title bars aren't set up yet. Setup builds the hyprbars plugin for your Hyprland version and adds it to your Hyprland config."
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
              Button {
                visible: root.needsSetup && !root.settingUp
                bordered: true
                text: "Set up title bars"
                onClicked: root.startSetup()
              }
              Caption {
                visible: root.needsSetup && !root.settingUp && root.setupMessage !== ""
                text: root.setupMessage
              }
            }
          }

          // ---- Buttons
          Column {
            visible: root.page === "buttons"
            width: parent.width
            spacing: 10

            SectionLabel { text: "Style"; topPadding: 0 }
            Flow {
              width: parent.width
              spacing: 8
              Repeater {
                model: root.ready ? root.styleChoices : []
                StyleCard {
                  required property var modelData
                  styleId: modelData.id
                  label: modelData.label
                  selected: root.settings.style === modelData.id
                  settings: root.settings
                  colors: root.colors
                  onClicked: root.set("style", modelData.id)
                }
              }
            }

            SectionLabel { text: "Position" }
            ButtonGroup {
              options: [{ value: "left", label: "Left" }, { value: "right", label: "Right" }]
              value: root.settings.buttons || "right"
              onChanged: function(v) { root.set("buttons", v) }
            }

            SectionLabel { text: "Order" }
            ButtonGroup {
              options: [{ value: "standard", label: "−  □  ×   Standard" }, { value: "mac", label: "×  −  □   macOS" }]
              value: root.settings.order || "standard"
              onChanged: function(v) { root.set("order", v) }
            }

            SectionLabel { text: "Show" }
            Row {
              spacing: 22
              Repeater {
                model: [
                  { key: "showMinimize", label: "Minimize" },
                  { key: "showMaximize", label: "Maximize" },
                  { key: "showClose", label: "Close" }
                ]
                Row {
                  required property var modelData
                  spacing: 8
                  ToggleSwitch {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: root.settings[parent.modelData.key] !== false
                    onToggled: root.set(parent.modelData.key, root.settings[parent.modelData.key] === false)
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: parent.modelData.label
                    color: Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                  }
                }
              }
            }

            SliderRow { key: "buttonSize"; label: "Button size" }
            SliderRow { key: "buttonSpacing"; label: "Space between buttons" }
          }

          // ---- Title
          Column {
            visible: root.page === "title"
            width: parent.width
            spacing: 10

            Toggle {
              width: parent.width
              label: "Show window titles"
              description: "Turn off for a clean bar with just the buttons."
              checked: root.settings.title !== false
              onClicked: root.set("title", !(root.settings.title !== false))
            }

            SectionLabel { text: "Alignment" }
            ButtonGroup {
              options: [{ value: "center", label: "Center" }, { value: "left", label: "Left" }]
              value: root.settings.titleAlign || "center"
              onChanged: function(v) { root.set("titleAlign", v) }
            }

            SectionLabel { text: "Font" }
            SearchableDropdown {
              width: Math.min(parent.width, 360)
              showLabel: false
              options: root.fonts
              value: root.settings.titleFont || ""
              triggerLabel: root.settings.titleFont ? root.settings.titleFont : "Omarchy font (" + Style.font.family + ")"
              placeholderText: "Search fonts..."
              onChanged: function(v) { root.set("titleFont", v) }
            }

            SliderRow { key: "titleSize"; label: "Size" }

            SectionLabel { text: "Weight" }
            ButtonGroup {
              options: [
                { value: "light", label: "Light" },
                { value: "normal", label: "Normal" },
                { value: "medium", label: "Medium" },
                { value: "semibold", label: "Semibold" },
                { value: "bold", label: "Bold" }
              ]
              value: root.settings.titleWeight || "medium"
              onChanged: function(v) { root.set("titleWeight", v) }
            }

            Toggle {
              width: parent.width
              label: "Dim unfocused titles"
              description: "Makes the focused window easier to spot."
              checked: root.settings.dimInactive !== false
              onClicked: root.set("dimInactive", !(root.settings.dimInactive !== false))
            }
          }

          // ---- Colors
          Column {
            visible: root.page === "colors"
            width: parent.width
            spacing: 12

            Toggle {
              width: parent.width
              label: "Follow theme"
              description: "Use your Omarchy theme's colors and change with it. Turn off to pick your own."
              checked: root.settings.followTheme !== false
              onClicked: root.set("followTheme", !(root.settings.followTheme !== false))
            }

            Caption {
              text: root.settings.followTheme !== false
                ? "Showing your theme's colors. Pick a swatch or open the rainbow picker to change one; that turns Follow theme off."
                : "Theme swatches keep updating when you switch themes; custom colors stay as picked."
            }

            Repeater {
              model: root.ready ? root.colorChoices : []
              ColorRow {
                required property var modelData
                width: parent.width
                label: modelData.label
                value: root.settings.followTheme !== false ? root.defaults.colors[modelData.role] : root.settings.colors[modelData.role]
                current: root.colors[modelData.role] || "transparent"
                palette: root.palette
                roles: root.swatchRoles
                pickerOpen: root.pickerRole === modelData.role
                eyedropper: root.eyedropper
                onPickerToggled: root.pickerRole = root.pickerRole === modelData.role ? "" : modelData.role
                onPicked: function(v) { root.setColor(modelData.role, v) }
              }
            }
          }

          // ---- Bar
          Column {
            visible: root.page === "bar"
            width: parent.width
            spacing: 10

            SliderRow { key: "barHeight"; label: "Height" }
            SliderRow { key: "barPadding"; label: "Space at the edges" }

            Toggle {
              width: parent.width
              label: "Border around the title bar"
              description: "Omarchy's window border wraps the title bar too, so they read as one window."
              checked: root.settings.borderAroundBar !== false
              onClicked: root.set("borderAroundBar", !(root.settings.borderAroundBar !== false))
            }

            SectionLabel { text: "Double-click the title bar to" }
            ButtonGroup {
              options: [
                { value: "maximize", label: "Maximize" },
                { value: "minimize", label: "Minimize" },
                { value: "none", label: "Do nothing" }
              ]
              value: root.settings.doubleClick || "maximize"
              onChanged: function(v) { root.set("doubleClick", v) }
            }
          }

          // ---- Behavior
          Column {
            visible: root.page === "behavior"
            width: parent.width
            spacing: 10

            Toggle {
              width: parent.width
              label: "Minimize shortcuts"
              description: "Super+M minimizes the focused window; Super+Alt+M brings back the last one. Clicking an app in a dock also restores it."
              checked: root.settings.shortcuts !== false
              onClicked: root.set("shortcuts", !(root.settings.shortcuts !== false))
            }

            Toggle {
              width: parent.width
              label: "Settings button"
              description: root.gearAvailable
                ? "A small gear on the other side of the bar opens these settings. When off, find them in Omarchy menu › Style › Title Bars."
                : "Needs a hyprbars rebuild: run titlebars build --force."
              checked: root.settings.settingsButton !== false
              onClicked: root.set("settingsButton", !(root.settings.settingsButton !== false))
            }

            SectionLabel { text: "Apps without title bars" }
            Caption {
              text: "For apps that draw their own window buttons. Click an open app to add it, or type window classes separated by commas."
            }

            TextField {
              id: appsField
              width: parent.width
              placeholderText: "e.g. chromium, org.gnome.Nautilus"
              text: (root.settings.noBarApps || []).join(", ")
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              onEditingFinished: {
                root.set("noBarApps", text.split(",").map(function(app) { return app.trim() }).filter(function(app) { return app !== "" }))
              }
            }

            Flow {
              width: parent.width
              spacing: 6
              Repeater {
                model: root.openApps.filter(function(app) { return (root.settings.noBarApps || []).indexOf(app) < 0 })
                Button {
                  required property string modelData
                  bordered: true
                  iconText: "+"
                  text: modelData
                  fontSize: Style.font.bodySmall
                  onClicked: root.set("noBarApps", (root.settings.noBarApps || []).concat([modelData]))
                }
              }
            }
          }
        }
      }

      ConfirmDialog {
        anchors.fill: parent
        z: 10
        opened: root.resetConfirmOpen
        message: "Reset title bars to the default look?"
        confirmText: "Reset"
        onCanceled: root.resetConfirmOpen = false
        onConfirmed: {
          root.resetConfirmOpen = false
          root.resetAll()
        }
      }
    }
  }
}
