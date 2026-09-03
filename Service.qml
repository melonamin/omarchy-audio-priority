import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var pluginRegistry: null

  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id) : "melonamin.audio-priority"
  readonly property string sourceDir: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir) : ""
  readonly property string testBinDir: manifest && manifest.__testBinDir
    ? String(manifest.__testBinDir) : ""
  readonly property string home: Quickshell.env("HOME")
  readonly property string runtimeDir: String(Quickshell.env("XDG_RUNTIME_DIR") || "")
  property string omarchyPath: String(Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy")
  readonly property string configDir: home + "/.config/omarchy"
  readonly property string statePath: configDir + "/audio-priority.json"
  readonly property var childEnvironment: {
    var env = {
      "HOME": home,
      "LANG": "C",
      "LC_ALL": "C",
      "PATH": "/usr/bin:/bin",
      "OMARCHY_PATH": omarchyPath
    }
    if (runtimeDir) {
      env["XDG_RUNTIME_DIR"] = runtimeDir
      env["PIPEWIRE_RUNTIME_DIR"] = runtimeDir
      env["PULSE_SERVER"] = "unix:" + runtimeDir + "/pulse/native"
    }
    if (testBinDir) {
      env["AUDIO_PRIORITY_TEST_BIN"] = testBinDir
      env["AUDIO_PRIORITY_TEST_DIR"] = String(Quickshell.env("AUDIO_PRIORITY_TEST_DIR") || "")
      env["AUDIO_PRIORITY_TEST_KEEP_DEFAULT"] = String(Quickshell.env("AUDIO_PRIORITY_TEST_KEEP_DEFAULT") || "0")
    }
    return env
  }
  readonly property var pipewireNodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var defaultSink: Pipewire.defaultAudioSink
  readonly property var defaultSource: Pipewire.defaultAudioSource

  property var state: Model.defaultState()
  property bool stateReady: false
  property bool stateMissing: false
  property bool directoryReady: false
  property bool pendingSave: false
  property bool stateReloadPending: false
  property bool inventoryReady: false
  property string inventorySignature: ""
  property var connectedDevices: []
  property var previousConnectedUids: []
  property var sinkStatus: ({})
  property bool statusRefreshPending: false
  property int revision: 0
  property string stateError: ""
  property string availabilityError: ""
  property string routeError: ""
  property string lastSwitchReason: ""
  property var queuedOutput: null
  property var queuedInput: null
  // The text most recently handed to the state file. The file is watched, and
  // the atomic rename of our own save arrives as a change like any other; the
  // reload it triggers is skipped so it can never clobber a newer in-memory
  // state with the older one that was still being written.
  property string lastWrittenText: ""
  // Delay before the PulseAudio event stream is relaunched after it exits.
  property int eventRetryDelay: Model.EVENT_RETRY_BASE_MS
  property real eventStartedAt: 0
  // Without the plugin's source directory no helper script can run, so the
  // service would otherwise sit at "discovering devices" forever.
  readonly property string setupError: manifest && !sourceDir
    ? "Plugin manifest has no source directory; helper scripts cannot run" : ""
  readonly property var deviceLists: {
    var ignored = revision
    return Model.buildDeviceLists(state, connectedDevices)
  }
  readonly property var inputDevices: deviceLists.inputDevices || []
  readonly property var speakerDevices: deviceLists.speakerDevices || []
  readonly property var headphoneDevices: deviceLists.headphoneDevices || []
  readonly property var hiddenInputDevices: deviceLists.hiddenInputDevices || []
  readonly property var hiddenSpeakerDevices: deviceLists.hiddenSpeakerDevices || []
  readonly property var hiddenHeadphoneDevices: deviceLists.hiddenHeadphoneDevices || []
  readonly property var rememberedDevices: deviceLists.rememberedDevices || []
  readonly property string currentOutputUid: Model.currentDeviceUid("output",
    defaultSink && defaultSink.name ? String(defaultSink.name) : "", connectedDevices)
  readonly property string currentInputUid: Model.currentDeviceUid("input",
    defaultSource && defaultSource.name ? String(defaultSource.name) : "", connectedDevices)
  readonly property real outputVolume: defaultSink && defaultSink.audio
    ? Number(defaultSink.audio.volume || 0) : 0
  readonly property bool outputMuted: defaultSink && defaultSink.audio
    ? defaultSink.audio.muted === true : false
  readonly property real inputVolume: defaultSource && defaultSource.audio
    ? Number(defaultSource.audio.volume || 0) : 0
  readonly property bool inputMuted: defaultSource && defaultSource.audio
    ? defaultSource.audio.muted === true : false
  readonly property bool hasOutput: !!(defaultSink && defaultSink.audio)
  readonly property bool hasInput: !!(defaultSource && defaultSource.audio)
  readonly property bool anyAudible: (hasOutput && !outputMuted) || (hasInput && !inputMuted)
  readonly property string currentMode: state.currentMode
  readonly property bool customMode: state.customMode === true
  readonly property bool busy: outputRoute.running || inputRoute.running
  readonly property bool ready: stateReady && inventoryReady && !availabilityError

  function pluginScript(name) {
    return sourceDir + "/scripts/" + name
  }

  function boundedCommand(seconds, script, args) {
    return ["/usr/bin/timeout", "-k", "1s", String(seconds) + "s", pluginScript(script)]
      .concat(args || [])
  }

  function startRuntime() {
    if (!sourceDir) return
    audioEvents.command = boundedCommand(21600, "audio-events", [])
    audioEvents.running = true
    directoryInit.command = boundedCommand(4, "prepare-state", [configDir, statePath])
    directoryInit.running = true
  }

  function nodeProperties(node) {
    try { return node && node.ready && node.properties ? node.properties : {} }
    catch (_error) { return {} }
  }

  function isAudioSource(node) {
    if (!node || node.isStream) return false
    if (node.isSink) return false
    if (node.audio) return true
    var type = String(node.type || "")
    return type.indexOf("Audio/Source") !== -1
      || type.indexOf("AudioSource") !== -1
      || type.indexOf("Source") !== -1
  }

  function snapshotNode(node, type) {
    if (!node) return null
    var muted = false
    try { muted = !!(node.audio && node.audio.muted) } catch (_error) { muted = false }
    return Model.buildDevice(state, {
      type: type,
      nodeName: String(node.name || ""),
      nodeId: Number(node.id),
      description: String(node.description || ""),
      nickname: String(node.nickname || node.nick || ""),
      props: nodeProperties(node),
      muted: muted
    }, sinkStatus)
  }

  function snapshotInventory() {
    var result = []
    var seen = Object.create(null)
    for (var i = 0; i < pipewireNodes.length && result.length < Model.MAX_STATE_ITEMS; i++) {
      var node = pipewireNodes[i]
      if (!node || node.isStream) continue
      var type = node.isSink ? "output" : (isAudioSource(node) ? "input" : "")
      if (!type) continue
      var device = snapshotNode(node, type)
      if (!device || seen[device.uid] || !isFinite(device.nodeId)) continue
      seen[device.uid] = true
      result.push(device)
    }
    return result
  }

  function nativeNodeFor(device) {
    if (!device) return null
    for (var i = 0; i < pipewireNodes.length; i++) {
      var node = pipewireNodes[i]
      if (node && String(node.name || "") === String(device.nodeName || "")) return node
    }
    return null
  }

  function currentUids(devices) {
    var result = []
    for (var i = 0; i < devices.length; i++) result.push(devices[i].uid)
    return result
  }

  function sameState(a, b) {
    return JSON.stringify(a) === JSON.stringify(b)
  }

  function replaceState(next, save) {
    var normalized = Model.normalizeState(next)
    var changed = !sameState(state, normalized)
    state = normalized
    if (changed && save !== false) persistState()
    revision++
    return changed
  }

  function refreshTopology() {
    if (!stateReady) return
    var nextDevices = snapshotInventory()
    var nextSignature = Model.topologySignature(nextDevices)
    if (inventoryReady && nextSignature === inventorySignature) return
    var now = new Date().toISOString()
    var remembered = Model.rememberDevices(state, nextDevices, now)
    var selection = null
    if (!inventoryReady) {
      replaceState(remembered, true)
      connectedDevices = nextDevices
      previousConnectedUids = currentUids(nextDevices)
      inventorySignature = nextSignature
      inventoryReady = true
      selection = Model.automaticSelection(state, nextDevices)
      applySelection(selection, "startup")
    } else {
      var transition = Model.topologyTransition(remembered, previousConnectedUids, nextDevices)
      replaceState(transition.state, true)
      connectedDevices = nextDevices
      previousConnectedUids = currentUids(nextDevices)
      inventorySignature = nextSignature
      applySelection(transition, "topology")
    }
    revision++
  }

  function scheduleTopologyRefresh() {
    topologyDebounce.restart()
  }

  // Re-reads sink availability and active ports, then refreshes the topology.
  // A request that arrives while the helper is running is remembered so the
  // final state is never missed.
  function refreshAvailability() {
    if (!sourceDir) return
    if (availabilityProc.running) { statusRefreshPending = true; return }
    availabilityProc.running = true
  }

  function applySelection(selection, reason) {
    if (!selection) return
    if (selection.input) requestInput(selection.input, reason)
    if (selection.output) requestOutput(selection.output, reason)
  }

  function requestOutput(device, reason) {
    if (!device || device.isConnected === false || !device.nodeName) return
    if (device.uid === currentOutputUid && !outputRoute.running) return
    if (outputRoute.running) { queuedOutput = { device: device, reason: reason }; return }
    var nativeNode = nativeNodeFor(device)
    if (nativeNode) Pipewire.preferredDefaultAudioSink = nativeNode
    lastSwitchReason = String(reason || "manual")
    routeError = ""
    outputRoute.command = boundedCommand(12, "route-device",
      ["output", String(device.nodeId), device.nodeName])
    outputRoute.running = true
  }

  function requestInput(device, reason) {
    if (!device || device.isConnected === false || !device.nodeName) return
    if (device.uid === currentInputUid && !inputRoute.running) return
    if (inputRoute.running) { queuedInput = { device: device, reason: reason }; return }
    var nativeNode = nativeNodeFor(device)
    if (nativeNode) Pipewire.preferredDefaultAudioSource = nativeNode
    lastSwitchReason = String(reason || "manual")
    routeError = ""
    inputRoute.command = boundedCommand(12, "route-device",
      ["input", String(device.nodeId), device.nodeName])
    inputRoute.running = true
  }

  function reevaluate(reason) {
    applySelection(Model.automaticSelection(state, connectedDevices), reason || "configuration")
  }

  function setMode(mode) {
    replaceState(Model.setMode(state, mode), true)
    reevaluate("mode")
  }

  function setCustomMode(enabled) {
    replaceState(Model.setCustomMode(state, enabled), true)
    if (!enabled) reevaluate("custom-disabled")
  }

  function selectDevice(device) {
    if (!device || device.isConnected === false) return
    if (!state.customMode) {
      var category = device.type === "output" ? Model.categoryFor(state, device) : ""
      var list = device.type === "input" ? inputDevices
        : (category === "headphone" ? headphoneDevices : speakerDevices)
      replaceState(Model.promote(state, list, device), true)
    }
    if (device.type === "input") requestInput(device, "manual")
    else requestOutput(device, "manual")
  }

  function reorderDevice(type, category, uid, destination) {
    var list = type === "input" ? inputDevices
      : (category === "headphone" ? headphoneDevices : speakerDevices)
    replaceState(Model.reorder(state, list, type, category, uid, destination), true)
    var refreshed = Model.buildDeviceLists(state, connectedDevices)
    var reordered = type === "input" ? refreshed.inputDevices
      : (category === "headphone" ? refreshed.headphoneDevices : refreshed.speakerDevices)
    var top = reordered.length > 0 ? reordered[0] : null
    if (!top || top.isConnected === false) return
    if (type === "input") requestInput(top, "priority")
    else if (category === "headphone" || state.currentMode === "speaker") requestOutput(top, "priority")
  }

  function setCategory(device, category) {
    replaceState(Model.setCategory(state, device.uid, category), true)
    connectedDevices = snapshotInventory()
    if (!state.customMode) reevaluate("category")
    revision++
  }

  function setHidden(device, category, hidden) {
    replaceState(Model.setHidden(state, device, category, hidden), true)
    if (!state.customMode && hidden) reevaluate("ignore")
  }

  function setHiddenEntirely(device, hidden) {
    replaceState(Model.setHiddenEntirely(state, device, hidden), true)
    if (!state.customMode && hidden) reevaluate("ignore")
  }

  function setNeverUse(device, enabled) {
    replaceState(Model.setNeverUse(state, device.uid, enabled), true)
    if (!state.customMode) reevaluate("never-use")
  }

  function forgetDevice(device) {
    if (!device || device.isConnected !== false) return false
    replaceState(Model.forgetDevice(state, device.uid), true)
    return true
  }

  function isHidden(device, category) {
    var key = Model.hiddenKey(device.type, category || Model.categoryFor(state, device))
    return state[key].indexOf(device.uid) !== -1
  }

  function isNeverUse(device) {
    return state.neverUseDevices.indexOf(device.uid) !== -1
  }

  function setOutputVolume(value) {
    if (!defaultSink || !defaultSink.audio) return
    defaultSink.audio.volume = Math.max(0, Math.min(1, Number(value)))
    revision++
  }

  function setInputVolume(value) {
    if (!defaultSource || !defaultSource.audio) return
    defaultSource.audio.volume = Math.max(0, Math.min(1, Number(value)))
    revision++
  }

  function toggleOutputMute() {
    if (!hasOutput) return
    defaultSink.audio.muted = !defaultSink.audio.muted
    revision++
  }

  function toggleInputMute() {
    if (!hasInput) return
    defaultSource.audio.muted = !defaultSource.audio.muted
    revision++
  }

  function toggleAllMuted() {
    var mute = anyAudible
    if (hasOutput) defaultSink.audio.muted = mute
    if (hasInput) defaultSource.audio.muted = mute
    revision++
  }

  function deviceMuted(device) {
    var node = nativeNodeFor(device)
    try { return !!(node && node.audio && node.audio.muted) }
    catch (_error) { return false }
  }

  function lastSeenText(device) {
    if (!device || device.isConnected !== false) return ""
    return Model.relativeLastSeen(device.lastSeen)
  }

  function initializeState() {
    stateMissing = false
    stateReady = true
    state = Model.defaultState()
    revision++
    persistState()
    refreshAvailability()
  }

  function consumeStateText(text) {
    var content = String(text || "")
    if (stateReady && content === lastWrittenText) return
    var loaded = Model.loadState(content)
    if (loaded.empty) {
      // At startup an empty file holds nothing worth protecting, so start from
      // defaults. Later on, an editor that truncates before it writes shows the
      // same empty file for a moment; the in-memory state is kept and the next
      // save restores the file.
      if (stateReady) return
      stateMissing = true
      if (directoryReady) initializeState()
      return
    }
    if (!loaded.value) {
      stateError = loaded.error
      return
    }
    var reloaded = stateReady && inventoryReady
    state = loaded.value
    stateReady = true
    stateError = ""
    revision++
    // The file is watched, so an edit made outside the panel is honored: the
    // priorities it contains are applied to the current inventory right away.
    if (reloaded) reevaluate("state-file")
    refreshAvailability()
  }

  function revalidateStateFile() {
    stateReloadPending = true
    if (!stateRevalidate.running) stateRevalidate.running = true
  }

  // The write is deferred to the next event-loop pass. Quickshell's FileView
  // drops a write that is started from inside its own load handler (the
  // handler runs before the finished load lets go of the operation slot), and
  // the deferral also collapses several changes made in one pass into one
  // write.
  function persistState() {
    if (!stateReady) return
    pendingSave = true
    if (!directoryReady) return
    Qt.callLater(writeState)
  }

  function writeState() {
    if (!stateReady || !directoryReady) return
    var serialized = Model.serializeState(state)
    if (serialized.error) {
      pendingSave = false
      stateError = serialized.error
      return
    }
    lastWrittenText = serialized.text
    stateFile.setText(lastWrittenText)
  }

  onPipewireNodesChanged: scheduleTopologyRefresh()
  onDefaultSinkChanged: revision++
  onDefaultSourceChanged: revision++
  onSourceDirChanged: if (sourceDir) Qt.callLater(startRuntime)

  Timer {
    id: topologyDebounce
    interval: 180
    repeat: false
    onTriggered: root.refreshAvailability()
  }

  // Port switches (a headphone jack) do not add or remove PipeWire nodes, so
  // PulseAudio change events drive refreshes. The slow timer is only a safety
  // net in case the event stream is unavailable, matching the built-in audio
  // panel's cadence.
  Timer {
    interval: 15000
    repeat: true
    running: true
    onTriggered: root.refreshAvailability()
  }

  // The stream is relaunched when it exits. A stream that keeps dying at once
  // (pactl missing, no PulseAudio socket) backs off up to a minute between
  // attempts instead of respawning every few seconds forever; one that ran for
  // a while before exiting starts over at the shortest delay.
  Process {
    id: audioEvents
    running: false
    clearEnvironment: true
    environment: root.childEnvironment
    stdout: SplitParser {
      onRead: function(line) { if (String(line) === "changed") root.scheduleTopologyRefresh() }
    }
    onStarted: root.eventStartedAt = Date.now()
    onExited: {
      audioEventsRestart.interval = root.eventRetryDelay
      root.eventRetryDelay = Model.nextEventRetryDelay(root.eventRetryDelay, Date.now() - root.eventStartedAt)
      audioEventsRestart.restart()
    }
  }

  Timer {
    id: audioEventsRestart
    interval: Model.EVENT_RETRY_BASE_MS
    repeat: false
    onTriggered: audioEvents.running = true
  }

  Process {
    id: availabilityProc
    command: root.boundedCommand(6, "sink-status", [])
    clearEnvironment: true
    environment: root.childEnvironment
    stdout: StdioCollector { id: availabilityOutput; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.sinkStatus = Model.parseSinkStatus(availabilityOutput.text)
        root.availabilityError = ""
        root.refreshTopology()
      } else {
        root.availabilityError = "Could not verify audio output availability"
      }
      if (root.statusRefreshPending) {
        root.statusRefreshPending = false
        root.refreshAvailability()
      }
    }
  }

  Process {
    id: outputRoute
    clearEnvironment: true
    environment: root.childEnvironment
    stderr: StdioCollector { id: outputRouteError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.routeError = String(outputRouteError.text || "Could not change audio output").trim()
      root.revision++
      var queued = root.queuedOutput
      root.queuedOutput = null
      if (queued) root.requestOutput(queued.device, queued.reason)
    }
  }

  Process {
    id: inputRoute
    clearEnvironment: true
    environment: root.childEnvironment
    stderr: StdioCollector { id: inputRouteError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.routeError = String(inputRouteError.text || "Could not change audio input").trim()
      root.revision++
      var queued = root.queuedInput
      root.queuedInput = null
      if (queued) root.requestInput(queued.device, queued.reason)
    }
  }

  Process {
    id: directoryInit
    running: false
    clearEnvironment: true
    environment: root.childEnvironment
    stderr: StdioCollector { id: directoryInitError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.stateError = String(directoryInitError.text || "Could not prepare " + root.configDir).trim()
        return
      }
      root.directoryReady = true
      if (root.stateMissing) root.initializeState()
      else if (root.pendingSave) root.persistState()
    }
  }

  Process {
    id: stateRevalidate
    command: root.boundedCommand(4, "prepare-state", [root.configDir, root.statePath])
    clearEnvironment: true
    environment: root.childEnvironment
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.stateReloadPending = false
        root.stateError = "audio-priority.json failed ownership, type, or permission checks"
        return
      }
      if (root.stateReloadPending) {
        root.stateReloadPending = false
        stateFile.reload()
      }
    }
  }

  // The file watch is set up when the path is assigned and silently does
  // nothing if the directory does not exist yet, so the path waits for the
  // directory: on a fresh install the config directory is created by the
  // process above, and a watch created before that would never fire.
  FileView {
    id: stateFile
    path: root.directoryReady ? root.statePath : ""
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.consumeStateText(text())
    onFileChanged: root.revalidateStateFile()
    onLoadFailed: function(error) {
      if (error === FileViewError.FileNotFound && !root.stateReady) {
        root.stateMissing = true
        if (root.directoryReady) root.initializeState()
        return
      }
      root.stateError = "audio-priority.json: " + FileViewError.toString(error)
    }
    onSaved: { root.pendingSave = false; root.stateError = "" }
    onSaveFailed: function(error) {
      root.pendingSave = false
      root.stateError = "audio-priority.json save failed: " + FileViewError.toString(error)
    }
  }

  IpcHandler {
    target: root.pluginId

    function status(): string {
      return JSON.stringify({
        ready: root.ready,
        mode: root.customMode ? "custom" : root.currentMode,
        output: root.currentOutputUid,
        input: root.currentInputUid,
        devices: root.connectedDevices.length,
        busy: root.busy,
        events: audioEvents.running,
        eventRetryMs: audioEvents.running ? 0 : audioEventsRestart.interval,
        error: root.setupError || root.stateError || root.availabilityError || root.routeError || null
      })
    }

    function refresh(): string {
      root.refreshAvailability()
      return "refreshing"
    }
  }
}
