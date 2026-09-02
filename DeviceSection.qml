import QtQuick
import qs.Commons
import qs.Ui

Column {
  id: root

  property var service: null
  property var panelController: null
  property string title: ""
  property string category: "speaker"
  property string glyph: ""
  property var devices: []
  property string currentUid: ""
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.45)

  spacing: Style.spacing.md

  Row {
    width: parent.width
    spacing: Style.spacing.sm
    Text {
      text: root.glyph
      color: root.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.icon
      anchors.verticalCenter: parent.verticalCenter
    }
    PanelSectionHeader {
      text: root.title
      foreground: root.foreground
      fontFamily: Style.font.family
      anchors.verticalCenter: parent.verticalCenter
    }
    Text {
      text: String(root.devices.length)
      color: root.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  Text {
    visible: root.devices.length === 0
    width: parent.width
    text: root.service && root.service.editMode ? "No remembered devices" : "No connected devices"
    color: root.dim
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    font.italic: true
    leftPadding: Style.spacing.rowPaddingX
    topPadding: Style.spacing.sm
    bottomPadding: Style.spacing.sm
  }

  Repeater {
    model: root.devices
    DeviceRow {
      required property var modelData
      required property int index
      width: root.width
      service: root.service
      panelController: root.panelController
      device: modelData
      rowIndex: index
      totalCount: root.devices.length
      category: root.category
      selected: modelData.uid === root.currentUid && modelData.isConnected !== false
      foreground: root.foreground
      dim: root.dim
    }
  }
}
