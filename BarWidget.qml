import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "melonamin.audio-priority"

  readonly property var priorityService: {
    var host = bar && bar.shell ? bar.shell : null
    return host && typeof host.serviceFor === "function" ? host.serviceFor(moduleName) : null
  }
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true : false
  property bool micFlash: false
  property real wheelAccumulator: 0

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.anchorItem = button
    target.hostWidget = root
    target.service = root.priorityService
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  readonly property string serviceError: priorityService
    ? String(priorityService.setupError || priorityService.stateError || priorityService.routeError || "") : ""

  function outputGlyph() {
    if (!priorityService) return ""
    if (priorityService.stateError) return ""
    if (!priorityService.ready) return ""
    if (priorityService.outputMuted) return ""
    var volume = priorityService.outputVolume
    if (volume >= 0.67) return ""
    if (volume >= 0.34) return ""
    if (volume > 0) return ""
    return ""
  }

  function modeGlyph() {
    if (!priorityService) return ""
    if (priorityService.customMode) return ""
    return priorityService.currentMode === "headphone" ? "󰋋" : ""
  }

  function buttonText() {
    var parts = []
    if (priorityService && priorityService.inputMuted && micFlash) parts.push("󰍭")
    var mode = modeGlyph()
    if (mode) parts.push(mode)
    parts.push(outputGlyph())
    return parts.join(" ")
  }

  function tooltip() {
    if (!priorityService) return "Audio Priority service unavailable"
    if (serviceError) return serviceError
    var mode = priorityService.customMode ? "Custom" : (priorityService.currentMode === "headphone" ? "Headphones" : "Speakers")
    var output = priorityService.outputMuted ? "muted" : Math.round(priorityService.outputVolume * 100) + "%"
    var input = priorityService.inputMuted ? " · microphone muted" : ""
    return mode + " · " + output + input
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()
  onPriorityServiceChanged: injectPanel()

  Timer {
    interval: 700
    repeat: true
    running: !!root.priorityService && root.priorityService.inputMuted
    onTriggered: root.micFlash = !root.micFlash
    onRunningChanged: if (!running) root.micFlash = false
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.buttonText()
    active: root.serviceError !== ""
    tooltipText: root.tooltip()
    onPressed: root.togglePanel()
    onWheelMoved: function(delta) {
      if (!root.priorityService) return
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps === 0) return
      var value = root.priorityService.outputVolume + wheel.steps * 0.02
      root.priorityService.setOutputVolume(value)
      if (root.bar && root.bar.shell) {
        root.bar.shell.summon("omarchy.osd", JSON.stringify({
          icon: root.outputGlyph(),
          value: Math.round(Math.max(0, Math.min(1, value)) * 100)
        }))
      }
    }
  }
}
