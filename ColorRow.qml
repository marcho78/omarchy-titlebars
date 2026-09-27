import QtQuick
import qs.Commons
import qs.Ui

// One title bar color: a theme swatch, which keeps following the theme, or a
// custom color from the visual picker behind the rainbow swatch.
Item {
  id: root

  property string label: ""
  property string value: ""
  property color current: "transparent"
  property var palette: ({})
  property var roles: []
  property bool pickerOpen: false

  signal picked(string value)
  signal pickerToggled()

  readonly property bool isHex: value.charAt(0) === "#"
  readonly property color foreground: Color.foreground
  property string hoveredRole: ""

  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: parent.width
    spacing: 7

    Row {
      spacing: 8

      Rectangle {
        width: 14
        height: 14
        radius: 7
        anchors.verticalCenter: parent.verticalCenter
        color: root.current
        border.width: 1
        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.3)
      }
      Text {
        id: labelText
        textFormat: Text.PlainText
        text: root.label
        color: root.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
      Text {
        textFormat: Text.PlainText
        text: root.hoveredRole || (root.isHex ? "custom " + root.value : root.value.replace(/_/g, " "))
        color: root.foreground
        opacity: 0.5
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        anchors.baseline: labelText.baseline
      }
    }

    Row {
      spacing: 5

      Repeater {
        model: root.roles.filter(function(role) { return !!root.palette[role] })
        Rectangle {
          required property string modelData
          readonly property bool chosen: !root.isHex && root.value === modelData
          width: 18
          height: 18
          radius: 9
          color: "#" + root.palette[modelData]
          border.width: chosen ? 2 : 1
          border.color: chosen ? Color.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, swatchHover.hovered ? 0.6 : 0.2)

          HoverHandler {
            id: swatchHover
            cursorShape: Qt.PointingHandCursor
            onHoveredChanged: root.hoveredRole = hovered ? parent.modelData.replace(/_/g, " ") : ""
          }
          TapHandler { onTapped: root.picked(parent.modelData) }
        }
      }

      // Custom color: rainbow until one is picked, then that color.
      Item {
        width: 18
        height: 18

        Rectangle {
          anchors.fill: parent
          radius: 9
          visible: !root.isHex
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "#ff4d4d" }
            GradientStop { position: 0.25; color: "#ffd84d" }
            GradientStop { position: 0.5; color: "#4dff88" }
            GradientStop { position: 0.75; color: "#4d9dff" }
            GradientStop { position: 1.0; color: "#d44dff" }
          }
        }
        Rectangle {
          anchors.fill: parent
          radius: 9
          visible: root.isHex
          color: root.current
        }
        Rectangle {
          anchors.fill: parent
          radius: 9
          color: "transparent"
          border.width: root.isHex || root.pickerOpen ? 2 : 1
          border.color: root.isHex || root.pickerOpen ? Color.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, customHover.hovered ? 0.6 : 0.2)
        }

        HoverHandler {
          id: customHover
          cursorShape: Qt.PointingHandCursor
          onHoveredChanged: root.hoveredRole = hovered ? "custom color…" : ""
        }
        TapHandler { onTapped: root.pickerToggled() }
      }
    }

    Rectangle {
      visible: root.pickerOpen
      width: parent.width
      height: pickerColumn.implicitHeight + 24
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
      border.width: 1
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

      Column {
        id: pickerColumn
        x: 12
        y: 12
        spacing: 10

        ColorPicker {
          id: picker
          value: root.current
          onPicked: function(hex) { root.picked(hex) }
        }

        Row {
          spacing: 8
          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Hex"
            color: root.foreground
            opacity: 0.55
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          TextField {
            width: 104
            anchors.verticalCenter: parent.verticalCenter
            text: picker.hex(root.current)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            verticalPadding: 3
            onEditingFinished: {
              var value = text.trim().toLowerCase()
              if (/^#([0-9a-f]{6}|[0-9a-f]{8})$/.test(value)) root.picked(value)
              else text = picker.hex(root.current)
            }
          }
        }
      }
    }
  }
}
