import QtQuick
import Quickshell
import Quickshell.Io

// Hosts Service.qml the way Omarchy's shell does, for tests/e2e.sh: the
// component is created from the plugin directory and the manifest is injected
// afterwards. The test driver talks to the service through its own IPC target
// and to this host through "audio-priority-e2e".
ShellRoot {
  id: root

  readonly property string pluginDir: String(Quickshell.env("AUDIO_PRIORITY_PLUGIN_DIR") || "")
  readonly property bool withoutSourceDir: String(Quickshell.env("AUDIO_PRIORITY_E2E_NO_SOURCE_DIR") || "") === "1"
  property var service: null
  property int stateChanges: 0
  property string loadError: ""

  Component.onCompleted: {
    var component = Qt.createComponent("file://" + pluginDir + "/Service.qml")
    if (component.status !== Component.Ready) {
      loadError = component.errorString()
      return
    }
    var instance = component.createObject(serviceHost)
    if (!instance) {
      loadError = "createObject returned null"
      return
    }
    instance.omarchyPath = "/usr/share/omarchy"
    var manifest = { id: "melonamin.audio-priority" }
    if (!withoutSourceDir) {
      manifest.__sourceDir = pluginDir
      manifest.__testBinDir = pluginDir + "/tests/fixtures/bin"
    }
    instance.manifest = manifest
    instance.stateChanged.connect(function() { root.stateChanges++ })
    service = instance
  }

  Item {
    id: serviceHost
    visible: false
  }

  IpcHandler {
    target: "audio-priority-e2e"

    function loadError(): string { return root.loadError }
    function stateChanges(): int { return root.stateChanges }
    function setMode(mode: string): string {
      root.service.setMode(mode)
      return "ok"
    }
  }
}
