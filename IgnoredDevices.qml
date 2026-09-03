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
    text: "Ignored"
    iconText: root.expanded ? "󰅀" : "󰅂"
    leftAlign: true
    bordered: false
    horizontalPadding: Style.spacing.xs
    verticalPadding: Style.spacing.xs
    hasCursor: !!root.panelController && root.panelController.cursorActive
      && root.panelController.cursorId === "ignored-toggle"
    foreground: root.dim
    onHasCursorChanged: if (hasCursor && root.panelController) root.panelController.ensureCursorVisible(disclosure)
    onHovered: function(on) { if (on && root.panelController) root.panelController.selectTarget("ignored-toggle") }
    onClicked: if (root.panelController) root.panelController.ignoredExpanded = !root.panelController.ignoredExpanded
  }

  Repeater {
    model: root.expanded ? root.devices : []
    CursorSurface {
      id: ignoredRow
      required property var modelData
      width: root.width
      height: Math.max(Style.spacing.popupRowHeight, Style.space(32))
      hasCursor: !!root.panelController && root.panelController.cursorActive
        && root.panelController.cursorId === "ignored:" + modelData.uid
      foreground: root.foreground
      onHasCursorChanged: if (hasCursor && root.panelController) root.panelController.ensureCursorVisible(ignoredRow)

      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.rowPaddingX
        anchors.right: restore.left
        anchors.rightMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        text: (modelData.glyph || "󰈈") + "  "
          + (root.service ? root.service.displayName(modelData) : modelData.name)
        textFormat: Text.PlainText
        color: root.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }

      Button {
        id: restore
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.service && root.service.isNeverUse(modelData) ? "Allow Use" : "Stop Ignoring"
        bordered: true
        fontSize: Style.font.caption
        foreground: root.foreground
        onHovered: function(on) {
          if (on && root.panelController) root.panelController.selectTarget("ignored:" + modelData.uid)
        }
        onClicked: if (root.panelController) root.panelController.restoreIgnored(modelData)
      }
    }
  }
}
