import QtQuick
import qs.Commons
import "Styles.js" as Styles

// One choice on the Buttons page: the three buttons drawn in a style. Styles
// that reveal glyphs on hover do so when the card is hovered.
Item {
  id: root

  property string styleId: "dots"
  property string label: ""
  property bool selected: false
  property var settings: ({})
  property var colors: ({})

  signal clicked()

  implicitWidth: 100
  implicitHeight: 68

  readonly property color foreground: Color.foreground
  readonly property var sample: {
    var copy = JSON.parse(JSON.stringify(settings))
    copy.style = styleId
    copy.showMinimize = copy.showMaximize = copy.showClose = true
    return Styles.buttons(copy, colors)
  }

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: hover.hovered ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06) : "transparent"
    border.width: root.selected ? 2 : 1
    border.color: root.selected ? Color.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, hover.hovered ? 0.35 : 0.14)
  }

  Rectangle {
    x: 8
    y: 8
    width: parent.width - 16
    height: 24
    color: root.colors.bar || Color.background

    Row {
      anchors.centerIn: parent
      spacing: 6

      Repeater {
        model: root.sample
        Item {
          required property var modelData
          width: modelData.size
          height: modelData.size

          Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: parent.modelData.fill || "transparent"
          }
          Text {
            anchors.centerIn: parent
            visible: !parent.modelData.glyphsOnHover || hover.hovered
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

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 8
    textFormat: Text.PlainText
    text: root.label
    color: root.selected ? Color.accent : root.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  HoverHandler {
    id: hover
    cursorShape: Qt.PointingHandCursor
  }
  TapHandler { onTapped: root.clicked() }
}
