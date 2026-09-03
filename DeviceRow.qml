import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property var service: null
  property var panelController: null
  property var device: null
  property int rowIndex: 0
  property int totalCount: 1
  property string category: "speaker"
  property string targetKind: "device"
  property bool reorderEnabled: true
  property bool selected: false
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.45)
  property real dragStartY: 0
  property int dragTarget: rowIndex

  readonly property bool disconnected: !!device && device.isConnected === false
  readonly property bool ignored: !!service && !!device && service.isHidden(device, category)
  readonly property bool neverUse: !!service && !!device && service.isNeverUse(device)
  readonly property bool muted: !!service && !!device && service.deviceMuted(device)
  readonly property bool keyboardSelected: !!panelController && panelController.cursorActive
    && panelController.cursorId === targetKind + ":" + device.uid
  readonly property bool expanded: !!panelController && panelController.actionDeviceUid === device.uid
  readonly property bool renaming: expanded && panelController.renameDeviceUid === device.uid
  readonly property var actions: panelController ? panelController.actionsFor(device, category) : []
  readonly property int baseHeight: Math.max(Style.spacing.popupRowHeight + Style.spacing.sm, Style.space(36))
  readonly property int actionHeight: expanded ? actionColumn.implicitHeight + Style.spacing.lg : 0

  implicitHeight: baseHeight + actionHeight

  CursorSurface {
    anchors.fill: parent
    hasCursor: root.keyboardSelected
    current: root.selected
    currentFill: Util.alpha(Style.selectedStateColor(root.foreground, Color.accent),
      Math.max(Style.selectedFillAlpha, 0.18))
    foreground: root.foreground
    opacity: root.disconnected ? 0.62 : 1
  }

  onKeyboardSelectedChanged: if (keyboardSelected && panelController) panelController.ensureCursorVisible(root)

  Item {
    id: mainRow
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: root.baseHeight

    MouseArea {
      id: mainMouse
      anchors.fill: parent
      anchors.leftMargin: dragHandle.width
      anchors.rightMargin: menuButton.width
      hoverEnabled: true
      cursorShape: root.disconnected ? Qt.ArrowCursor : Qt.PointingHandCursor
      onEntered: if (root.panelController) root.panelController.selectTarget(root.targetKind + ":" + root.device.uid)
      onClicked: if (!root.disconnected && root.service) root.service.selectDevice(root.device)
    }

    Item {
      id: dragHandle
      width: Style.space(42)
      height: parent.height
      anchors.left: parent.left

      Text {
        anchors.centerIn: parent
        text: !root.reorderEnabled ? "" : (dragMouse.pressed ? "󰹹" : (root.selected ? "✓" : String(root.rowIndex + 1)))
        color: root.selected ? Color.accent : root.dim
        font.family: Style.font.family
        font.pixelSize: root.selected ? Style.font.body : Style.font.bodySmall
        font.bold: true
      }

      MouseArea {
        id: dragMouse
        anchors.fill: parent
        enabled: root.reorderEnabled && root.totalCount > 1
        hoverEnabled: true
        cursorShape: enabled ? Qt.SizeVerCursor : Qt.ArrowCursor
        preventStealing: true
        onEntered: if (root.panelController) root.panelController.selectTarget("device:" + root.device.uid)
        onPressed: function(mouse) {
          root.dragStartY = mouse.y
          root.dragTarget = root.rowIndex
        }
        onPositionChanged: function(mouse) {
          if (!pressed) return
          var offset = Math.round((mouse.y - root.dragStartY) / Math.max(1, root.baseHeight))
          root.dragTarget = Math.max(0, Math.min(root.totalCount - 1, root.rowIndex + offset))
        }
        onReleased: {
          if (root.service && root.dragTarget !== root.rowIndex)
            root.service.reorderDevice(root.device.type, root.category, root.device.uid, root.dragTarget)
          root.dragTarget = root.rowIndex
        }
      }
    }

    Text {
      id: glyph
      anchors.left: dragHandle.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(24)
      text: root.device ? root.device.glyph || (root.category === "input" ? "󰍬" : "󰓃") : ""
      color: root.neverUse ? root.dim : root.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.icon
    }

    Column {
      anchors.left: glyph.right
      anchors.leftMargin: Style.spacing.sm
      anchors.right: menuButton.left
      anchors.rightMargin: Style.spacing.sm
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.xxs

      Text {
        width: parent.width
        text: root.device
          ? (root.service ? root.service.displayName(root.device) : root.device.name)
          : "Unknown"
        textFormat: Text.PlainText
        color: root.neverUse || root.disconnected ? root.dim : root.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.strikeout: root.neverUse
        elide: Text.ElideRight
      }

      Text {
        visible: text !== ""
        width: parent.width
        text: {
          var parts = []
          if (root.disconnected) parts.push("Disconnected · " + (root.service ? root.service.lastSeenText(root.device) : ""))
          if (root.ignored) parts.push("Ignored")
          if (root.neverUse) parts.push("Never use")
          if (root.muted) parts.push("Muted")
          return parts.join(" · ")
        }
        color: root.muted ? Color.urgent : root.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: root.muted
        elide: Text.ElideRight
      }
    }

    PanelActionButton {
      id: menuButton
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.sm
      anchors.verticalCenter: parent.verticalCenter
      iconText: root.expanded ? "󰅖" : "󰇙"
      tooltipText: root.expanded ? "Close device actions" : "Device actions"
      foreground: root.foreground
      focusable: true
      onHovered: function(on) {
        if (on && root.panelController) root.panelController.selectTarget(root.targetKind + ":" + root.device.uid)
      }
      onClicked: if (root.panelController) root.panelController.toggleActionsFor(root.device, root.category)
    }
  }

  Column {
    id: actionColumn
    visible: root.expanded
    anchors.left: parent.left
    anchors.leftMargin: Style.spacing.rowPaddingX
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.rowPaddingX
    anchors.top: mainRow.bottom
    spacing: Style.spacing.sm

    Row {
      id: renameEditor
      visible: root.renaming
      width: parent.width
      spacing: Style.spacing.sm

      TextField {
        id: renameField
        width: Math.max(0, parent.width - saveRename.width - cancelRename.width - parent.spacing * 2)
        maximumLength: 80
        placeholderText: "Friendly name"
        foreground: root.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        horizontalPadding: Style.spacing.controlGap
        verticalPadding: Style.spacing.controlPaddingY
        onAccepted: if (root.panelController)
          root.panelController.commitRename(root.device, text)
        Keys.onEscapePressed: if (root.panelController) root.panelController.closeActions()
        onVisibleChanged: if (visible) {
          text = root.service ? root.service.friendlyName(root.device) : ""
          Qt.callLater(function() {
            renameField.forceActiveFocus()
            renameField.selectAll()
          })
        }
      }

      PanelActionButton {
        id: saveRename
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰄬"
        tooltipText: "Save name"
        foreground: root.foreground
        bordered: true
        onClicked: if (root.panelController)
          root.panelController.commitRename(root.device, renameField.text)
      }

      PanelActionButton {
        id: cancelRename
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰅖"
        tooltipText: "Cancel rename"
        foreground: root.dim
        bordered: true
        onClicked: if (root.panelController) root.panelController.closeActions()
      }
    }

    Repeater {
      model: root.expanded && !root.renaming ? root.actions : []
      Button {
        required property var modelData
        required property int index
        width: actionColumn.width
        text: modelData.label
        bordered: true
        focusable: true
        hasCursor: root.expanded && root.panelController && root.panelController.actionIndex === index
        fontSize: Style.font.bodySmall
        foreground: modelData.danger ? Color.urgent : root.foreground
        onHasCursorChanged: if (hasCursor && root.panelController) root.panelController.ensureCursorVisible(this)
        onHovered: function(on) { if (on && root.panelController) root.panelController.selectAction(index) }
        onClicked: if (root.panelController) root.panelController.runDeviceAction(root.device, root.category, modelData.id)
      }
    }
  }

}
