import QtQuick
import QtQuick.Controls
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui
import "KeyboardModel.js" as Keyboard

Panel {
  id: root
  moduleName: "melonamin.audio-priority"
  manageIpc: false

  property var service: null
  property Item anchorItem: null
  property Item hostWidget: null
  property bool cursorActive: false
  property string cursorId: "header"
  property int cursorOrdinal: 0
  property bool ignoredExpanded: false
  property string actionDeviceUid: ""
  property string actionCategory: ""
  property int actionIndex: -1

  readonly property int serviceRevision: service ? service.revision : 0
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var ignoredDevices: {
    var revision = serviceRevision
    if (!service) return []
    return (service.hiddenSpeakerDevices || [])
      .concat(service.hiddenHeadphoneDevices || [])
      .concat(service.hiddenInputDevices || [])
  }
  readonly property var cursorTargets: {
    var revision = serviceRevision
    return Keyboard.buildTargets({
      showSpeakers: !!service && (service.currentMode === "speaker" || service.customMode),
      showHeadphones: !!service && (service.currentMode === "headphone" || service.customMode),
      showInputVolume: !!service && service.hasInput,
      speakers: service ? service.speakerDevices : [],
      headphones: service ? service.headphoneDevices : [],
      inputs: service ? service.inputDevices : [],
      showIgnored: !!service && !service.editMode,
      ignoredExpanded: ignoredExpanded,
      ignored: ignoredDevices
    })
  }
  readonly property var activeActionTarget: {
    var revision = serviceRevision
    if (!actionDeviceUid) return null
    for (var i = 0; i < cursorTargets.length; i++) {
      var target = cursorTargets[i]
      if (target.kind === "device" && target.device.uid === actionDeviceUid) return target
    }
    return null
  }
  readonly property var activeActions: activeActionTarget
    ? actionsFor(activeActionTarget.device, activeActionTarget.category) : []

  function modeName() {
    if (!service) return "UNAVAILABLE"
    if (service.customMode) return "CUSTOM · AUTO-SWITCHING OFF"
    return (service.currentMode === "headphone" ? "HEADPHONES" : "SPEAKERS") + " · AUTOMATIC"
  }

  function heroGlyph() {
    if (!service) return ""
    if (service.customMode) return ""
    return service.currentMode === "headphone" ? "󰋋" : ""
  }

  function activateMode(mode) {
    if (!service) return
    if (mode === "custom") service.setCustomMode(true)
    else service.setMode(mode)
  }

  function targetById(id) {
    var index = Keyboard.indexOfId(cursorTargets, id)
    return index >= 0 ? cursorTargets[index] : null
  }

  function currentTarget() {
    return targetById(cursorId)
  }

  function selectTarget(id) {
    var index = Keyboard.indexOfId(cursorTargets, id)
    if (index < 0) return
    cursorActive = true
    cursorId = id
    cursorOrdinal = index
  }

  function repairCursor() {
    cursorId = Keyboard.repair(cursorTargets, cursorId, cursorOrdinal)
    cursorOrdinal = Math.max(0, Keyboard.indexOfId(cursorTargets, cursorId))
    if (actionDeviceUid && !activeActionTarget) closeActions()
  }

  function moveCursor(delta) {
    var next = Keyboard.move(cursorTargets, cursorId, delta)
    if (next) selectTarget(next)
  }

  function adjustCursor(delta) {
    var target = currentTarget()
    if (!target || !service) return
    if (target.kind === "output-volume") service.setOutputVolume(service.outputVolume + delta * 0.05)
    else if (target.kind === "input-volume") service.setInputVolume(service.inputVolume + delta * 0.05)
  }

  function activateCursor() {
    var target = currentTarget()
    if (!target || !service) return
    if (target.kind === "header") service.toggleAllMuted()
    else if (target.kind === "mode") activateMode(target.mode)
    else if (target.kind === "output-volume") service.toggleOutputMute()
    else if (target.kind === "input-volume") service.toggleInputMute()
    else if (target.kind === "device" && target.device.isConnected !== false) service.selectDevice(target.device)
    else if (target.kind === "ignored-toggle") ignoredExpanded = !ignoredExpanded
    else if (target.kind === "ignored") restoreIgnored(target.device)
    else if (target.kind === "edit") service.setEditMode(!service.editMode)
  }

  function deviceListFor(target) {
    if (!service || !target || target.kind !== "device") return []
    if (target.device.type === "input") return service.inputDevices
    return target.category === "headphone" ? service.headphoneDevices : service.speakerDevices
  }

  function moveSelectedToPriority(key) {
    var target = currentTarget()
    if (!service || !target || target.kind !== "device") return
    var list = deviceListFor(target)
    var destination = Keyboard.priorityDestination(key, list.length)
    if (destination < 0) return
    service.reorderDevice(target.device.type, target.category, target.device.uid, destination)
  }

  function nudgeSelected(delta) {
    var target = currentTarget()
    if (!service || !target || target.kind !== "device") return
    var list = deviceListFor(target)
    if (list.length < 2) return
    var destination = Math.max(0, Math.min(list.length - 1, target.index + delta))
    if (destination !== target.index)
      service.reorderDevice(target.device.type, target.category, target.device.uid, destination)
  }

  function actionsFor(device, category) {
    if (!service || !device) return []
    return Keyboard.actionsFor(
      device,
      category,
      service.isHidden(device, category),
      service.isNeverUse(device)
    )
  }

  function openActionsFor(device, category) {
    if (!device) return
    selectTarget("device:" + device.uid)
    actionDeviceUid = device.uid
    actionCategory = category
    actionIndex = 0
  }

  function toggleActionsFor(device, category) {
    if (actionDeviceUid === device.uid) closeActions()
    else openActionsFor(device, category)
  }

  function closeActions() {
    actionDeviceUid = ""
    actionCategory = ""
    actionIndex = -1
  }

  function moveAction(delta) {
    if (activeActions.length === 0) return
    actionIndex = Math.max(0, Math.min(activeActions.length - 1, actionIndex + delta))
  }

  function selectAction(index) {
    actionIndex = Math.max(0, Math.min(activeActions.length - 1, Number(index)))
  }

  function activateAction() {
    if (!activeActionTarget || actionIndex < 0 || actionIndex >= activeActions.length) return
    runDeviceAction(activeActionTarget.device, activeActionTarget.category, activeActions[actionIndex].id)
  }

  function runDeviceAction(device, category, actionId) {
    if (!service || !device) return
    if (actionId === "category")
      service.setCategory(device, category === "headphone" ? "speaker" : "headphone")
    else if (actionId === "ignore")
      service.setHidden(device, category, !service.isHidden(device, category))
    else if (actionId === "ignore-entirely") service.setHiddenEntirely(device, true)
    else if (actionId === "never") service.setNeverUse(device, !service.isNeverUse(device))
    else if (actionId === "forget") service.forgetDevice(device)
    closeActions()
  }

  // Restoring from the ignored list clears every ignore for the device, so a
  // device that was ignored entirely does not stay hidden in its other category.
  function restoreIgnored(device) {
    if (!service || !device) return
    if (service.isNeverUse(device)) service.setNeverUse(device, false)
    else service.setHiddenEntirely(device, false)
  }

  function shortcutHint() {
    if (actionDeviceUid) return "J/K NAVIGATE · ENTER APPLY · ESC BACK"
    var target = currentTarget()
    if (target && target.kind === "device")
      return "1–9/0 PRIORITY · SHIFT J/K MOVE · A ACTIONS · ENTER SELECT"
    if (target && (target.kind === "output-volume" || target.kind === "input-volume"))
      return "H/L ADJUST · ENTER MUTE"
    if (target && target.kind === "header") return "ENTER DISABLE AUDIO"
    return "J/K NAVIGATE · S/P/C MODE · E EDIT"
  }

  function resetScroll() {
    var flick = scroll.contentItem
    if (flick && flick.contentY !== undefined) flick.contentY = 0
  }

  function ensureCursorVisible(item) {
    if (!item || !scroll) return
    var flick = scroll.contentItem
    if (!flick || flick.contentY === undefined) return
    var margin = Style.space(6)
    var maximum = Math.max(0, (flick.contentHeight || 0) - flick.height)
    if (maximum <= Style.space(24)) { flick.contentY = 0; return }
    var point = item.mapToItem(flick.contentItem || flick, 0, 0)
    var top = point.y
    var bottom = top + (item.height || 0)
    var viewTop = flick.contentY
    var viewBottom = viewTop + flick.height
    if (top < viewTop + margin) flick.contentY = Math.max(0, Math.min(maximum, top - margin))
    else if (bottom > viewBottom - margin)
      flick.contentY = Math.max(0, Math.min(maximum, bottom + margin - flick.height))
  }

  onCursorTargetsChanged: Qt.callLater(repairCursor)
  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      cursorId = "header"
      cursorOrdinal = 0
      ignoredExpanded = false
      closeActions()
      Qt.callLater(function() {
        resetScroll()
        keyCatcher.forceActiveFocus()
      })
    }
  }

  PwNodePeakMonitor {
    id: inputPeakMonitor
    node: root.service ? root.service.defaultSource : null
    enabled: root.opened && !!root.service && root.service.hasInput
  }

  KeyboardPanel {
    id: popup
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(430))
    contentHeight: popup.fittedContentHeight(content.implicitHeight, Style.space(680))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (root.actionDeviceUid) {
          if (dy !== 0) root.moveAction(dy)
          return
        }
        if (!root.cursorActive) {
          root.cursorActive = true
          return
        }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.adjustCursor(dx)
      }
      onActivateRequested: {
        if (!root.cursorActive) return
        if (root.actionDeviceUid) root.activateAction()
        else root.activateCursor()
      }
      onCloseRequested: {
        if (root.actionDeviceUid) root.closeActions()
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (!root.service) return
        if (root.actionDeviceUid) {
          if (text === "a" || text === "A") root.closeActions()
          return
        }
        if (text === "s" || text === "S") { root.selectTarget("mode:speaker"); root.activateMode("speaker") }
        else if (text === "p" || text === "P") { root.selectTarget("mode:headphone"); root.activateMode("headphone") }
        else if (text === "c" || text === "C") { root.selectTarget("mode:custom"); root.activateMode("custom") }
        else if (text === "e" || text === "E") root.service.setEditMode(!root.service.editMode)
        else if (text === "a" || text === "A") {
          var target = root.currentTarget()
          if (target && target.kind === "device") root.openActionsFor(target.device, target.category)
        }
        else if (text === "J") root.nudgeSelected(1)
        else if (text === "K") root.nudgeSelected(-1)
        else if (/^[0-9]$/.test(text)) root.moveSelectedToPriority(text)
      }

      ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: content.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        Binding {
          target: scroll.contentItem
          property: "interactive"
          value: content.implicitHeight > scroll.height
        }

        Column {
          id: content
          width: scroll.availableWidth
          spacing: Style.spacing.panelGap

          Item {
            id: hero
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, masterToggle.implicitHeight)

            Text {
              id: heroIcon
              text: root.heroGlyph()
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              opacity: root.service && root.service.anyAudible ? 1 : 0.5
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            ToggleSwitch {
              id: masterToggle
              checked: !!root.service && root.service.anyAudible
              hasCursor: root.cursorActive && root.cursorId === "header"
              foreground: root.foreground
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(hero)
              onHovered: function(on) { if (on) root.selectTarget("header") }
              onToggled: if (root.service) root.service.toggleAllMuted()

              PanelToolTip {
                visible: masterToggle.containsMouse
                text: root.service && root.service.anyAudible ? "Disable audio" : "Enable audio"
                fontFamily: root.fontFamily
              }
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: masterToggle.left
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: "Audio Priority"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                text: root.modeName()
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
              }
            }
          }

          Text {
            visible: !root.service || !root.service.ready || root.service.setupError !== ""
              || root.service.stateError !== "" || root.service.availabilityError !== ""
              || root.service.routeError !== ""
            width: parent.width
            text: !root.service ? "Audio Priority service unavailable."
              : (root.service.setupError || root.service.stateError || root.service.availabilityError
                || root.service.routeError || "Discovering PipeWire devices…")
            textFormat: Text.PlainText
            color: root.service && root.service.ready ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Row {
            width: parent.width
            spacing: Style.spacing.md
            Button {
              id: speakersButton
              width: (parent.width - parent.spacing * 2) * 0.36
              text: "Speakers"
              iconText: ""
              selected: !!root.service && !root.service.customMode && root.service.currentMode === "speaker"
              hasCursor: root.cursorActive && root.cursorId === "mode:speaker"
              bordered: true
              foreground: root.foreground
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(speakersButton)
              onHovered: function(on) { if (on) root.selectTarget("mode:speaker") }
              onClicked: root.activateMode("speaker")
            }
            Button {
              id: headphonesButton
              width: (parent.width - parent.spacing * 2) * 0.39
              text: "Headphones"
              iconText: "󰋋"
              selected: !!root.service && !root.service.customMode && root.service.currentMode === "headphone"
              hasCursor: root.cursorActive && root.cursorId === "mode:headphone"
              bordered: true
              foreground: root.foreground
              onHovered: function(on) { if (on) root.selectTarget("mode:headphone") }
              onClicked: root.activateMode("headphone")
            }
            Button {
              id: customButton
              width: (parent.width - parent.spacing * 2) * 0.25
              text: "Custom"
              iconText: ""
              selected: !!root.service && root.service.customMode
              hasCursor: root.cursorActive && root.cursorId === "mode:custom"
              bordered: true
              foreground: root.foreground
              onHovered: function(on) { if (on) root.selectTarget("mode:custom") }
              onClicked: root.activateMode("custom")
            }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.spacing.md
            Item {
              width: parent.width
              implicitHeight: Math.max(outputTitle.implicitHeight, outputPercent.implicitHeight)
              PanelSectionHeader { id: outputTitle; text: "OUTPUT"; foreground: root.foreground; fontFamily: root.fontFamily; anchors.left: parent.left }
              Text {
                id: outputPercent
                text: root.service ? Math.round((outputSlider.dragging ? outputSlider.liveValue : root.service.outputVolume) * 100) + "%" : "—"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                opacity: root.service && root.service.outputMuted ? 0.5 : 1
              }
            }
            CursorSurface {
              id: outputSliderRow
              width: parent.width
              height: outputSlider.implicitHeight + Style.spacing.controlGap
              hasCursor: root.cursorActive && root.cursorId === "output-volume"
              foreground: root.foreground
              outline: true
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(outputSliderRow)
              PanelSlider {
                id: outputSlider
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                bar: root.bar
                minimum: 0
                maximum: 1
                step: 0.05
                value: root.service ? root.service.outputVolume : 0
                enabled: !!root.service && root.service.hasOutput
                opacity: root.service && root.service.outputMuted ? 0.5 : 1
                onMoved: function(value) { if (root.service) root.service.setOutputVolume(value) }
                onRightClicked: if (root.service) root.service.toggleOutputMute()
              }
              HoverHandler { onHoveredChanged: if (hovered) root.selectTarget("output-volume") }
            }
          }

          DeviceSection {
            visible: !!root.service && (root.service.currentMode === "speaker" || root.service.customMode)
            width: parent.width
            service: root.service
            panelController: root
            title: "SPEAKERS"
            category: "speaker"
            glyph: ""
            devices: root.service ? root.service.speakerDevices : []
            currentUid: root.service ? root.service.currentOutputUid : ""
            foreground: root.foreground
            dim: root.dim
          }

          DeviceSection {
            visible: !!root.service && (root.service.currentMode === "headphone" || root.service.customMode)
            width: parent.width
            service: root.service
            panelController: root
            title: "HEADPHONES"
            category: "headphone"
            glyph: "󰋋"
            devices: root.service ? root.service.headphoneDevices : []
            currentUid: root.service ? root.service.currentOutputUid : ""
            foreground: root.foreground
            dim: root.dim
          }

          PanelSeparator { visible: !!root.service && root.service.hasInput; foreground: root.foreground }

          Column {
            visible: !!root.service && root.service.hasInput
            width: parent.width
            spacing: Style.spacing.md
            Item {
              width: parent.width
              implicitHeight: Math.max(inputTitle.implicitHeight, inputPercent.implicitHeight)
              PanelSectionHeader { id: inputTitle; text: "INPUT"; foreground: root.foreground; fontFamily: root.fontFamily; anchors.left: parent.left }
              Text {
                id: inputPercent
                text: root.service ? Math.round((inputSlider.dragging ? inputSlider.liveValue : root.service.inputVolume) * 100) + "%" : "—"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                opacity: root.service && root.service.inputMuted ? 0.5 : 1
              }
            }
            CursorSurface {
              id: inputSliderRow
              width: parent.width
              height: inputControls.implicitHeight + Style.spacing.controlGap
              hasCursor: root.cursorActive && root.cursorId === "input-volume"
              foreground: root.foreground
              outline: true
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(inputSliderRow)
              Column {
                id: inputControls
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                spacing: Style.space(5)
                PanelSlider {
                  id: inputSlider
                  width: parent.width
                  bar: root.bar
                  minimum: 0
                  maximum: 1
                  step: 0.05
                  value: root.service ? root.service.inputVolume : 0
                  enabled: !!root.service && root.service.hasInput
                  opacity: root.service && root.service.inputMuted ? 0.5 : 1
                  onMoved: function(value) { if (root.service) root.service.setInputVolume(value) }
                  onRightClicked: if (root.service) root.service.toggleInputMute()
                }
                Rectangle {
                  width: parent.width
                  height: Math.max(Style.space(5), Style.spacing.xs)
                  color: Util.alpha(root.foreground, 0.18)
                  opacity: root.service && root.service.inputMuted ? 0.35 : 1
                  Rectangle {
                    height: parent.height
                    width: parent.width * Math.max(0, Math.min(1, inputPeakMonitor.peak))
                    color: root.foreground
                    Behavior on width { NumberAnimation { duration: 70 } }
                  }
                }
              }
              HoverHandler { onHoveredChanged: if (hovered) root.selectTarget("input-volume") }
            }
          }

          DeviceSection {
            visible: !!root.service
            width: parent.width
            service: root.service
            panelController: root
            title: "MICROPHONES"
            category: "input"
            glyph: "󰍬"
            devices: root.service ? root.service.inputDevices : []
            currentUid: root.service ? root.service.currentInputUid : ""
            foreground: root.foreground
            dim: root.dim
          }

          IgnoredDevices {
            visible: !!root.service && !root.service.editMode && root.ignoredDevices.length > 0
            width: parent.width
            service: root.service
            panelController: root
            devices: root.ignoredDevices
            expanded: root.ignoredExpanded
            foreground: root.foreground
            dim: root.dim
          }

          Text {
            width: parent.width
            text: root.shortcutHint()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 0.45
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          PanelSeparator { foreground: root.foreground }

          Row {
            width: parent.width
            spacing: Style.spacing.md
            Text {
              width: Math.max(0, parent.width - editButton.width - parent.spacing)
              anchors.verticalCenter: parent.verticalCenter
              text: root.service
                ? (root.service.connectedDevices.length + " CONNECTED · " + root.service.state.knownDevices.length + " REMEMBERED")
                : "SERVICE UNAVAILABLE"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 0.7
              elide: Text.ElideRight
            }
            Button {
              id: editButton
              text: root.service && root.service.editMode ? "Done" : "Edit"
              iconText: root.service && root.service.editMode ? "󰄬" : "󰏫"
              selected: !!root.service && root.service.editMode
              hasCursor: root.cursorActive && root.cursorId === "edit"
              bordered: true
              foreground: root.foreground
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(editButton)
              onHovered: function(on) { if (on) root.selectTarget("edit") }
              onClicked: if (root.service) root.service.setEditMode(!root.service.editMode)
            }
          }
        }
      }
    }
  }
}
