import QtQuick
import qs.Commons
import qs.Ui

// Visual color picker: a saturation/brightness square, a hue strip, a live
// preview, and an eyedropper that samples any pixel on screen (hyprpicker).
// Emits `picked("#rrggbb")` continuously while dragging.
Column {
  id: root

  property color value: "#000000"

  signal picked(string hex)

  // HSV working copy, so dragging doesn't fight the incoming binding.
  property real hue: 0
  property real sat: 0
  property real val: 0
  property bool dragging: false
  property bool canEyedrop: false

  readonly property color foreground: Color.foreground
  readonly property color chosen: Qt.hsva(hue, sat, val, 1)

  spacing: 10

  function hex(color) {
    function two(x) {
      var n = Math.round(x * 255).toString(16)
      return n.length < 2 ? "0" + n : n
    }
    return "#" + two(color.r) + two(color.g) + two(color.b)
  }

  function syncFromValue() {
    if (dragging) return
    // Greys have no hue; keep the strip where it was instead of jumping to red.
    if (value.hsvHue >= 0) hue = value.hsvHue
    sat = value.hsvSaturation
    val = value.hsvValue
  }

  function emitChosen() {
    picked(hex(chosen))
  }

  onValueChanged: syncFromValue()
  Component.onCompleted: syncFromValue()

  Row {
    spacing: 12

    // Saturation left to right, brightness bottom to top.
    Rectangle {
      id: square
      width: 240
      height: 132
      color: Qt.hsva(root.hue, 1, 1, 1)
      border.width: 1
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.2)

      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: "#ffffff" }
          GradientStop { position: 1.0; color: "#00ffffff" }
        }
      }
      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          GradientStop { position: 0.0; color: "#00000000" }
          GradientStop { position: 1.0; color: "#000000" }
        }
      }

      Rectangle {
        x: root.sat * (square.width - 1) - width / 2
        y: (1 - root.val) * (square.height - 1) - height / 2
        width: 14
        height: 14
        radius: 7
        color: root.chosen
        border.width: 2
        border.color: "#ffffff"
        Rectangle {
          anchors.fill: parent
          anchors.margins: -1
          radius: width / 2
          color: "transparent"
          border.width: 1
          border.color: Qt.rgba(0, 0, 0, 0.5)
        }
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.CrossCursor
        function apply(mx, my) {
          root.sat = Math.max(0, Math.min(1, mx / (square.width - 1)))
          root.val = 1 - Math.max(0, Math.min(1, my / (square.height - 1)))
          root.emitChosen()
        }
        onPressed: function(mouse) { root.dragging = true; apply(mouse.x, mouse.y) }
        onPositionChanged: function(mouse) { if (pressed) apply(mouse.x, mouse.y) }
        onReleased: root.dragging = false
        onCanceled: root.dragging = false
      }
    }

    Column {
      spacing: 10

      Rectangle {
        width: 64
        height: 64
        radius: 32
        color: root.chosen
        border.width: 1
        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
      }

      Button {
        visible: root.canEyedrop
        bordered: true
        iconText: "󰈊"
        text: eyedropper.running ? "Click…" : "Pick"
        tooltipText: "Pick a color from anywhere on screen"
        fontSize: Style.font.bodySmall
        onClicked: eyedropper.start(["/usr/bin/hyprpicker", "--format=hex", "--lowercase-hex", "--no-fancy"])
      }
    }
  }

  // Hue strip.
  Rectangle {
    id: strip
    width: square.width
    height: 14
    radius: 7
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.000; color: "#ff0000" }
      GradientStop { position: 0.167; color: "#ffff00" }
      GradientStop { position: 0.333; color: "#00ff00" }
      GradientStop { position: 0.500; color: "#00ffff" }
      GradientStop { position: 0.667; color: "#0000ff" }
      GradientStop { position: 0.833; color: "#ff00ff" }
      GradientStop { position: 1.000; color: "#ff0000" }
    }

    Rectangle {
      x: root.hue * (strip.width - 1) - width / 2
      y: -3
      width: 8
      height: 20
      radius: 4
      color: Qt.hsva(root.hue, 1, 1, 1)
      border.width: 2
      border.color: "#ffffff"
    }

    MouseArea {
      anchors.fill: parent
      anchors.margins: -5
      cursorShape: Qt.PointingHandCursor
      function apply(mx) {
        root.hue = Math.max(0, Math.min(1, (mx - 5) / (strip.width - 1)))
        root.emitChosen()
      }
      onPressed: function(mouse) { root.dragging = true; apply(mouse.x) }
      onPositionChanged: function(mouse) { if (pressed) apply(mouse.x) }
      onReleased: root.dragging = false
      onCanceled: root.dragging = false
    }
  }

  // Samples a pixel anywhere on screen; Esc cancels without output. No
  // --quiet: in hyprpicker it silences the picked color too.
  Bounded {
    id: eyedropper
    maxBytes: 4096
    timeoutMs: 120000
    onFinished: function(ok, text) {
      if (!ok) return
      // The picked color is the last thing printed, after any log lines.
      var matches = text.match(/#[0-9a-f]{6}/g)
      if (matches) root.picked(matches[matches.length - 1])
    }
  }
}
