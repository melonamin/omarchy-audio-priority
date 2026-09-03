import QtQuick
import qs.Commons
import qs.Ui

Column {
  id: root

  property var service: null
  property var panelController: null
  property var devices: []
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.45)
  property bool expanded: false

  spacing: Style.spacing.sm

  Button {
    id: disclosure
    width: parent.width
    text: "Remembered devices"
    iconText: root.expanded ? "󰅀" : "󰅂"
    leftAlign: true
    bordered: false
    horizontalPadding: Style.spacing.xs
    verticalPadding: Style.spacing.xs
    hasCursor: !!root.panelController && root.panelController.cursorActive
      && root.panelController.cursorId === "remembered-toggle"
    foreground: root.dim
    onHasCursorChanged: if (hasCursor && root.panelController) root.panelController.ensureCursorVisible(disclosure)
    onHovered: function(on) { if (on && root.panelController) root.panelController.selectTarget("remembered-toggle") }
    onClicked: if (root.panelController)
      root.panelController.rememberedExpanded = !root.panelController.rememberedExpanded
  }

  Repeater {
    model: root.expanded ? root.devices : []
    DeviceRow {
      required property var modelData
      required property int index
      width: root.width
      service: root.service
      panelController: root.panelController
      device: modelData
      rowIndex: index
      totalCount: root.devices.length
      category: modelData.type === "input" ? "input" : modelData.category
      targetKind: "remembered"
      reorderEnabled: false
      foreground: root.foreground
      dim: root.dim
    }
  }
}
