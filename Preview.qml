import QtQuick
import qs.Commons

// A mock window with its title bar drawn the way hyprbars will draw it for the
// current settings: same geometry, colors, glyphs, and hover behavior.
Item {
  id: root

  property var settings: ({})
  property var colors: ({})
  property var buttons: []
  property var gear: null
  property var palette: ({})
  property bool active: true
  property string title: ""
  property var lines: []

  readonly property int borderWidth: 2
  readonly property color borderColor: active ? Color.accent : "#aa595959"
  readonly property bool barShown: settings.enabled !== false
  readonly property int barHeight: barShown ? settings.barHeight || 0 : 0
  readonly property bool wrapBar: settings.borderAroundBar !== false
  readonly property bool buttonsRight: settings.buttons !== "left"
  readonly property int padding: settings.barPadding || 0
  readonly property int spacing: settings.buttonSpacing || 0
  // hyprbars reserves padding + one spacing + each button with its spacing.
  readonly property real buttonsWidth: buttons.reduce(function(sum, b) { return sum + b.size + spacing }, spacing)
  readonly property var weights: ({ light: Font.Light, normal: Font.Normal, medium: Font.Medium, semibold: Font.DemiBold, bold: Font.Bold })

  // Window frame. Without borderAroundBar the bar sits above the border.
  Rectangle {
    id: frame
    anchors.fill: parent
    anchors.topMargin: root.wrapBar ? 0 : root.barHeight
    color: root.palette.background ? "#" + root.palette.background : Color.background
    border.width: root.borderWidth
    border.color: root.borderColor

    Column {
      x: root.borderWidth + 12
      y: (root.wrapBar ? root.borderWidth + root.barHeight : root.borderWidth) + 10
      width: frame.width - x - root.borderWidth - 8
      spacing: 3
      clip: true

      Repeater {
        model: root.lines
        Text {
          required property var modelData
          width: parent.width
          elide: Text.ElideRight
          textFormat: Text.PlainText
          text: modelData.text
          color: modelData.accent ? Color.accent : (root.palette.foreground ? "#" + root.palette.foreground : Color.foreground)
          opacity: modelData.dim ? 0.55 : 0.9
          font.family: "monospace"
          font.pixelSize: 10
        }
      }
    }
  }

  Rectangle {
    id: bar
    visible: root.barShown
    x: root.wrapBar ? root.borderWidth : 0
    y: root.wrapBar ? root.borderWidth : 0
    width: root.wrapBar ? root.width - 2 * root.borderWidth : root.width
    height: root.barHeight
    color: root.colors.bar || Color.background
    clip: true

    Text {
      id: titleText
      visible: root.settings.title !== false
      textFormat: Text.PlainText
      text: root.title
      elide: Text.ElideRight
      color: (root.active || !root.settings.dimInactive ? root.colors.title : root.colors.titleInactive) || Color.foreground
      font.family: root.settings.titleFont || "monospace"
      font.pixelSize: root.settings.titleSize || 12
      font.weight: root.weights[root.settings.titleWeight] || Font.Normal
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, Math.max(0, bar.width - 2 * root.padding - root.buttonsWidth * (root.settings.titleAlign === "left" ? 1 : 2)))
      // Centered across the whole bar, or after the padding (and any left buttons).
      x: root.settings.titleAlign === "left"
        ? root.padding + (root.buttonsRight ? 0 : root.buttonsWidth)
        : (bar.width - width) / 2
    }

    // Settings gear, on the side opposite the buttons.
    Item {
      visible: root.gear !== null
      width: root.gear ? root.gear.size : 0
      height: width
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: root.buttonsRight ? parent.left : undefined
      anchors.right: root.buttonsRight ? undefined : parent.right
      anchors.leftMargin: root.padding
      anchors.rightMargin: root.padding
      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: root.gear ? root.gear.glyph : ""
        color: root.gear ? root.gear.color : "transparent"
        font.family: "sans"
        font.pixelSize: root.gear ? root.gear.glyphSize : 1
      }
    }

    Row {
      id: buttonRow
      anchors.verticalCenter: parent.verticalCenter
      anchors.right: root.buttonsRight ? parent.right : undefined
      anchors.left: root.buttonsRight ? undefined : parent.left
      anchors.rightMargin: root.padding
      anchors.leftMargin: root.padding
      spacing: root.spacing

      HoverHandler { id: buttonHover }

      Repeater {
        model: root.buttons
        Item {
          required property var modelData
          width: modelData.size
          height: modelData.size

          Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: (root.active ? parent.modelData.fill : parent.modelData.inactiveFill) || "transparent"
          }

          // hyprbars shows every glyph while any button is hovered.
          Text {
            anchors.centerIn: parent
            visible: !parent.modelData.glyphsOnHover || buttonHover.hovered
            textFormat: Text.PlainText
            text: parent.modelData.glyph
            color: parent.modelData.glyphColor || "transparent"
            font.family: "sans"
            font.pixelSize: parent.modelData.glyphSize
          }
        }
      }
    }
  }
}
