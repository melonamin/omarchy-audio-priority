var STATE_VERSION = 1

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

// Lookup tables keyed by strings from the state file or PipeWire use a
// prototype-free object so keys such as "constructor" cannot hit Object.prototype.
function lookup() {
  return Object.create(null)
}

function uniqueStrings(value) {
  var source = Array.isArray(value) ? value : []
  var result = []
  var seen = lookup()
  for (var i = 0; i < source.length; i++) {
    var item = String(source[i] || "")
    if (!item || seen[item]) continue
    seen[item] = true
    result.push(item)
  }
  return result
}

function stringMap(value, allowedValues) {
  var source = value && typeof value === "object" && !Array.isArray(value) ? value : {}
  var result = {}
  for (var key in source) {
    var name = String(key || "")
    var item = String(source[key] || "")
    if (!name || (allowedValues && allowedValues.indexOf(item) === -1)) continue
    result[name] = item
  }
  return result
}

function defaultState() {
  return {
    version: STATE_VERSION,
    currentMode: "speaker",
    customMode: false,
    inputPriorities: [],
    speakerPriorities: [],
    headphonePriorities: [],
    deviceCategories: {},
    hiddenMics: [],
    hiddenSpeakers: [],
    hiddenHeadphones: [],
    neverUseDevices: [],
    knownDevices: []
  }
}

function normalizeKnownDevices(value) {
  var source = Array.isArray(value) ? value : []
  var result = []
  var byUid = lookup()
  for (var i = 0; i < source.length; i++) {
    var raw = source[i]
    if (!raw || typeof raw !== "object") continue
    var uid = String(raw.uid || "")
    if (!uid) continue
    var device = {
      uid: uid,
      name: String(raw.name || "Unknown"),
      isInput: raw.isInput === true,
      lastSeen: String(raw.lastSeen || "")
    }
    if (byUid[uid] !== undefined) result[byUid[uid]] = device
    else {
      byUid[uid] = result.length
      result.push(device)
    }
  }
  return result
}

function normalizeState(value) {
  var source = value && typeof value === "object" && !Array.isArray(value) ? value : {}
  return {
    version: STATE_VERSION,
    currentMode: source.currentMode === "headphone" ? "headphone" : "speaker",
    customMode: source.customMode === true,
    inputPriorities: uniqueStrings(source.inputPriorities),
    speakerPriorities: uniqueStrings(source.speakerPriorities),
    headphonePriorities: uniqueStrings(source.headphonePriorities),
    deviceCategories: stringMap(source.deviceCategories, ["speaker", "headphone"]),
    hiddenMics: uniqueStrings(source.hiddenMics),
    hiddenSpeakers: uniqueStrings(source.hiddenSpeakers),
    hiddenHeadphones: uniqueStrings(source.hiddenHeadphones),
    neverUseDevices: uniqueStrings(source.neverUseDevices),
    knownDevices: normalizeKnownDevices(source.knownDevices)
  }
}

function loadState(text) {
  var source = String(text || "")
  if (source.trim() === "") return { value: null, error: "", empty: true }
  try {
    var parsed = JSON.parse(source)
    return { value: normalizeState(parsed), error: "", empty: false }
  } catch (error) {
    return { value: null, error: "Invalid audio-priority.json: " + String(error.message || error), empty: false }
  }
}

function includes(list, value) {
  return Array.isArray(list) && list.indexOf(value) !== -1
}

// A sink whose card exposes several ports (a laptop's speaker and headphone
// jack share one node) is identified per active port, so plugging in wired
// headphones appears as a distinct device the way CoreAudio reports it.
function deviceUid(direction, nodeName, port) {
  var type = direction === "input" ? "input" : "output"
  var uid = type + ":" + String(nodeName || "")
  var qualifier = String(port || "")
  return qualifier ? uid + "#" + qualifier : uid
}

// The uid of the connected device backing a PipeWire node. Multi-port sinks
// carry a port qualifier that only the inventory knows, so the plain node uid
// is the fallback until the inventory is available.
function currentDeviceUid(direction, nodeName, connectedDevices) {
  var name = String(nodeName || "")
  if (!name) return ""
  var type = direction === "input" ? "input" : "output"
  var devices = Array.isArray(connectedDevices) ? connectedDevices : []
  for (var i = 0; i < devices.length; i++) {
    var device = devices[i]
    if (device && device.type === type && device.nodeName === name) return device.uid
  }
  return deviceUid(type, name)
}

function deviceBlob(device) {
  var fields = [
    device.name,
    device.nodeName,
    device.description,
    device.nickname,
    device.formFactor,
    device.iconName,
    device.productName,
    device.portName,
    device.portDescription,
    device.bus
  ]
  return fields.join(" ").toLowerCase()
}

function friendlyDeviceLabel(text) {
  var label = String(text || "").trim()
  label = label.replace(/^sof-soundwire\s+/i, "")
  label = label.replace(/^built-?in audio\s+/i, "")
  label = label.replace(/\s+Output$/i, "")
  label = label.replace(/\s+Input$/i, "")
  label = label.replace(/\bMicrophones\b/g, "Microphone")
  return label || "Unknown"
}

function deviceGlyph(device, category) {
  if (!device) return "󰓃"
  if (device.type === "input") {
    var inputBlob = deviceBlob(device)
    if (inputBlob.indexOf("headset") !== -1 || inputBlob.indexOf("headphone") !== -1) return "󰋋"
    if (inputBlob.indexOf("bluetooth") !== -1 || inputBlob.indexOf("bluez") !== -1) return "󰂯"
    if (inputBlob.indexOf("webcam") !== -1 || inputBlob.indexOf("camera") !== -1) return "󰄀"
    return "󰍬"
  }
  if (category === "headphone" || inferredCategory(device) === "headphone") return "󰋋"
  var blob = deviceBlob(device)
  if (blob.indexOf("bluetooth") !== -1 || blob.indexOf("bluez") !== -1) return "󰂯"
  if (blob.indexOf("hdmi") !== -1 || blob.indexOf("display") !== -1) return "󰍹"
  return "󰓃"
}

// Parses scripts/sink-status output: one sink per line as
// name, available, port count, active port name, active port description.
function parseSinkStatus(raw) {
  var result = lookup()
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (!line.trim()) continue
    var parts = line.split("\t")
    if (parts.length < 2 || !parts[0]) continue
    result[parts[0]] = {
      available: parts[1].trim() !== "0",
      portCount: Math.max(0, Number(parts[2]) || 0),
      portName: String(parts[3] || "").trim(),
      portDescription: String(parts[4] || "").trim()
    }
  }
  return result
}

function topologySignature(devices) {
  var rows = []
  var values = Array.isArray(devices) ? devices : []
  for (var i = 0; i < values.length; i++) {
    var device = values[i]
    rows.push([
      device.uid, device.nodeId, device.name, device.description,
      device.formFactor, device.portName
    ].join("\u001f"))
  }
  rows.sort()
  return rows.join("\u001e")
}

// Builds the device record the state machine works with from a PipeWire node
// (already reduced to plain values) plus the sink status the helper reported.
// Returns null when the node is not a usable device.
function buildDevice(state, node, sinkStatus) {
  if (!node) return null
  var type = node.type === "input" ? "input" : "output"
  var nodeName = String(node.nodeName || "")
  if (!nodeName || (type === "input" && nodeName === "quickshell")) return null
  var props = node.props && typeof node.props === "object" ? node.props : {}
  var status = type === "output" && sinkStatus ? sinkStatus[nodeName] : null
  if (status && status.available === false) return null
  var portName = status ? status.portName : ""
  var portDescription = status ? status.portDescription : ""
  var multiPort = !!status && status.portCount > 1
  var description = String(node.description || props["node.description"] || nodeName)
  var nickname = String(node.nickname || props["node.nick"] || "")
  var name = friendlyDeviceLabel(description || nickname || nodeName)
  if (multiPort && (portDescription || portName)) name += " · " + (portDescription || portName)
  var device = {
    uid: deviceUid(type, nodeName, multiPort ? portName : ""),
    name: name,
    type: type,
    isConnected: true,
    nodeId: Number(node.nodeId),
    nodeName: nodeName,
    description: description,
    nickname: nickname,
    formFactor: String(props["device.form-factor"] || props["device.form_factor"] || ""),
    iconName: String(props["device.icon-name"] || ""),
    productName: String(props["device.product.name"] || ""),
    portName: portName || String(props["api.alsa.path"] || ""),
    portDescription: portDescription,
    bus: String(props["device.bus"] || props["device.api"] || ""),
    muted: node.muted === true
  }
  device.category = type === "output" ? categoryFor(state, device) : "input"
  device.glyph = deviceGlyph(device, device.category)
  return device
}

// Short generic words match only as whole words so "ear" does not classify a
// "Rear" output and "elite" does not classify an EliteBook. Product-line terms
// match as substrings because model numbers extend them ("WH-1000XM5").
// Brands that sell both speakers and headphones are deliberately absent.
var HEADPHONE_WORDS = [
  "headphone", "headphones", "headset", "earphone", "earphones", "earbud",
  "earbuds", "buds", "ear", "pods", "beats", "elite", "poly", "astro", "akg",
  "handsfree", "hands-free", "head-mounted"
]
var HEADPHONE_TERMS = [
  "airpods", "earpods", "powerbeats", "beatsx", "beats fit", "beats solo",
  "beats studio", "wh-1000", "wf-1000", "linkbuds", "inzone", "galaxy buds",
  "buds pro", "buds live", "buds fe", "quietcomfort", "qc ultra", "qc45",
  "qc35", "soundsport", "sport earbuds", "momentum", "hd 4", "hd 5", "pxc",
  "jabra", "evolve", "jbl tune", "jbl live", "jbl tour", "jbl reflect",
  "skullcandy", "nothing ear", "oneplus buds", "pixel buds", "huawei freebuds",
  "oppo enco", "technics eah", "b&w px", "denon perl", "focal bathys",
  "hifiman", "shure aonic", "audio-technica ath", "beyerdynamic",
  "plantronics", "steelseries", "hyperx", "logitech g pro", "1more", "tozo",
  "fiio", "moondrop"
]
var HEADPHONE_WORD_PATTERN = new RegExp("(^|[^a-z0-9])(" + HEADPHONE_WORDS.join("|") + ")(?![a-z0-9])")

function inferredCategory(device) {
  var blob = deviceBlob(device)
  if (HEADPHONE_WORD_PATTERN.test(blob)) return "headphone"
  for (var i = 0; i < HEADPHONE_TERMS.length; i++)
    if (blob.indexOf(HEADPHONE_TERMS[i]) !== -1) return "headphone"
  return "speaker"
}

function categoryFor(state, device) {
  var saved = state.deviceCategories[device.uid]
  return saved === "speaker" || saved === "headphone" ? saved : inferredCategory(device)
}

function priorityKey(type, category) {
  if (type === "input") return "inputPriorities"
  return category === "headphone" ? "headphonePriorities" : "speakerPriorities"
}

function hiddenKey(type, category) {
  if (type === "input") return "hiddenMics"
  return category === "headphone" ? "hiddenHeadphones" : "hiddenSpeakers"
}

function stablePrioritySort(devices, priorities) {
  var order = lookup()
  for (var i = 0; i < priorities.length; i++) order[priorities[i]] = i
  return devices.map(function(device, index) {
    return { device: device, index: index }
  }).sort(function(a, b) {
    var ai = order[a.device.uid]
    var bi = order[b.device.uid]
    ai = ai === undefined ? Number.MAX_SAFE_INTEGER : ai
    bi = bi === undefined ? Number.MAX_SAFE_INTEGER : bi
    return ai === bi ? a.index - b.index : ai - bi
  }).map(function(row) { return row.device })
}

function rememberDevices(state, connectedDevices, now) {
  var next = normalizeState(state)
  var timestamp = String(now || new Date().toISOString())
  var knownIndex = lookup()
  for (var i = 0; i < next.knownDevices.length; i++) knownIndex[next.knownDevices[i].uid] = i
  var devices = Array.isArray(connectedDevices) ? connectedDevices : []
  for (i = 0; i < devices.length; i++) {
    var device = devices[i]
    if (!device || !device.uid) continue
    var stored = {
      uid: String(device.uid),
      name: String(device.name || "Unknown"),
      isInput: device.type === "input",
      lastSeen: timestamp
    }
    if (knownIndex[stored.uid] === undefined) {
      knownIndex[stored.uid] = next.knownDevices.length
      next.knownDevices.push(stored)
    } else next.knownDevices[knownIndex[stored.uid]] = stored
  }
  return next
}

function disconnectedDevice(stored) {
  return {
    uid: stored.uid,
    name: stored.name,
    type: stored.isInput ? "input" : "output",
    isConnected: false,
    nodeId: -1,
    nodeName: "",
    lastSeen: stored.lastSeen
  }
}

function buildDeviceLists(stateValue, connectedDevices, editMode) {
  var state = normalizeState(stateValue)
  var live = Array.isArray(connectedDevices) ? connectedDevices.filter(function(device) {
    return !!device && !!device.uid && device.isConnected !== false
  }) : []
  var connected = lookup()
  for (var i = 0; i < live.length; i++) connected[live[i].uid] = true
  var all = live.slice()
  if (editMode) {
    for (i = 0; i < state.knownDevices.length; i++) {
      var stored = state.knownDevices[i]
      if (!connected[stored.uid]) all.push(disconnectedDevice(stored))
    }
  }

  var inputs = all.filter(function(device) { return device.type === "input" })
  var outputs = all.filter(function(device) { return device.type === "output" })
  var speakers = outputs.filter(function(device) { return categoryFor(state, device) === "speaker" })
  var headphones = outputs.filter(function(device) { return categoryFor(state, device) === "headphone" })

  function never(device) { return includes(state.neverUseDevices, device.uid) }
  function hidden(device, type, category) { return includes(state[hiddenKey(type, category)], device.uid) }
  var result = {
    inputDevices: [], speakerDevices: [], headphoneDevices: [],
    hiddenInputDevices: [], hiddenSpeakerDevices: [], hiddenHeadphoneDevices: []
  }
  if (editMode) {
    result.inputDevices = stablePrioritySort(inputs, state.inputPriorities)
    result.speakerDevices = stablePrioritySort(speakers, state.speakerPriorities)
    result.headphoneDevices = stablePrioritySort(headphones, state.headphonePriorities)
    return result
  }

  result.inputDevices = stablePrioritySort(inputs.filter(function(device) {
    return !hidden(device, "input", "") && !never(device)
  }), state.inputPriorities)
  result.speakerDevices = stablePrioritySort(speakers.filter(function(device) {
    return !hidden(device, "output", "speaker") && !never(device)
  }), state.speakerPriorities)
  result.headphoneDevices = stablePrioritySort(headphones.filter(function(device) {
    return !hidden(device, "output", "headphone") && !never(device)
  }), state.headphonePriorities)

  var regularHiddenInputs = inputs.filter(function(device) { return hidden(device, "input", "") && !never(device) })
  var neverInputs = inputs.filter(never)
  result.hiddenInputDevices = regularHiddenInputs.concat(neverInputs)
  var regularHiddenSpeakers = speakers.filter(function(device) { return hidden(device, "output", "speaker") && !never(device) })
  var neverSpeakers = speakers.filter(never)
  result.hiddenSpeakerDevices = regularHiddenSpeakers.concat(neverSpeakers)
  var regularHiddenHeadphones = headphones.filter(function(device) { return hidden(device, "output", "headphone") && !never(device) })
  var neverHeadphones = headphones.filter(never)
  result.hiddenHeadphoneDevices = regularHiddenHeadphones.concat(neverHeadphones)
  return result
}

function firstConnected(devices) {
  for (var i = 0; i < devices.length; i++) if (devices[i].isConnected !== false) return devices[i]
  return null
}

function automaticSelection(stateValue, connectedDevices) {
  var state = normalizeState(stateValue)
  if (state.customMode) return { input: null, output: null }
  var lists = buildDeviceLists(state, connectedDevices, false)
  return {
    input: firstConnected(lists.inputDevices),
    output: firstConnected(state.currentMode === "headphone" ? lists.headphoneDevices : lists.speakerDevices)
  }
}

function topologyTransition(stateValue, previousConnectedUids, connectedDevices) {
  var state = normalizeState(stateValue)
  if (state.customMode) return { state: state, input: null, output: null }
  var previous = lookup()
  var old = Array.isArray(previousConnectedUids) ? previousConnectedUids : []
  for (var i = 0; i < old.length; i++) previous[String(old[i])] = true
  var lists = buildDeviceLists(state, connectedDevices, false)
  var newHeadphone = false
  for (i = 0; i < lists.headphoneDevices.length; i++) {
    var candidate = lists.headphoneDevices[i]
    if (candidate.isConnected !== false && !previous[candidate.uid]) { newHeadphone = true; break }
  }
  var hasHeadphones = firstConnected(lists.headphoneDevices) !== null
  var hasSpeakers = firstConnected(lists.speakerDevices) !== null
  if (newHeadphone && state.currentMode !== "headphone") state.currentMode = "headphone"
  else if (!hasHeadphones && hasSpeakers && state.currentMode === "headphone") state.currentMode = "speaker"
  var selection = automaticSelection(state, connectedDevices)
  return { state: state, input: selection.input, output: selection.output }
}

function moveUid(list, uid, destination) {
  var next = uniqueStrings(list)
  var from = next.indexOf(uid)
  if (from !== -1) next.splice(from, 1)
  var target = Math.max(0, Math.min(next.length, Number(destination)))
  next.splice(target, 0, uid)
  return next
}

function reorder(stateValue, devices, type, category, uid, destination) {
  var state = normalizeState(stateValue)
  var key = priorityKey(type, category)
  var visibleOrder = []
  var values = Array.isArray(devices) ? devices : []
  for (var i = 0; i < values.length; i++) if (values[i] && values[i].uid) visibleOrder.push(values[i].uid)
  state[key] = moveUid(visibleOrder, uid, destination)
  return state
}

function promote(stateValue, devices, device) {
  var state = normalizeState(stateValue)
  if (state.customMode || !device) return state
  var category = device.type === "output" ? categoryFor(state, device) : ""
  return reorder(state, devices, device.type, category, device.uid, 0)
}

function setMode(stateValue, mode) {
  var state = normalizeState(stateValue)
  state.currentMode = mode === "headphone" ? "headphone" : "speaker"
  state.customMode = false
  return state
}

function setCustomMode(stateValue, enabled) {
  var state = normalizeState(stateValue)
  state.customMode = enabled === true
  return state
}

function setCategory(stateValue, uid, category) {
  var state = normalizeState(stateValue)
  if (uid) state.deviceCategories[String(uid)] = category === "headphone" ? "headphone" : "speaker"
  return state
}

function setMembership(list, uid, enabled) {
  var next = uniqueStrings(list)
  var index = next.indexOf(uid)
  if (enabled && index === -1) next.push(uid)
  if (!enabled && index !== -1) next.splice(index, 1)
  return next
}

function setHidden(stateValue, device, category, hidden) {
  var state = normalizeState(stateValue)
  var key = hiddenKey(device.type, category || categoryFor(state, device))
  state[key] = setMembership(state[key], device.uid, hidden)
  return state
}

function setHiddenEntirely(stateValue, device, hidden) {
  var state = normalizeState(stateValue)
  if (device.type === "input") return setHidden(state, device, "", hidden)
  state.hiddenSpeakers = setMembership(state.hiddenSpeakers, device.uid, hidden)
  state.hiddenHeadphones = setMembership(state.hiddenHeadphones, device.uid, hidden)
  return state
}

function setNeverUse(stateValue, uid, enabled) {
  var state = normalizeState(stateValue)
  state.neverUseDevices = setMembership(state.neverUseDevices, String(uid || ""), enabled)
  return state
}

function forgetDevice(stateValue, uid) {
  var state = normalizeState(stateValue)
  var key = String(uid || "")
  state.knownDevices = state.knownDevices.filter(function(device) { return device.uid !== key })
  return state
}

var EVENT_RETRY_BASE_MS = 3000
var EVENT_RETRY_MAX_MS = 60000
// A stream that stayed up this long before exiting is treated as healthy and
// relaunched at the base delay rather than the backed-off one.
var EVENT_HEALTHY_RUN_MS = 30000

// Delay to wait before the next relaunch of the event stream, given the delay
// used for this one and how long the stream ran. Immediate exits double the
// delay up to the cap.
function nextEventRetryDelay(previousMs, ranMs) {
  var previous = Math.max(EVENT_RETRY_BASE_MS, Number(previousMs) || 0)
  if (Number(ranMs) >= EVENT_HEALTHY_RUN_MS) return EVENT_RETRY_BASE_MS
  return Math.min(EVENT_RETRY_MAX_MS, previous * 2)
}

function relativeLastSeen(iso, nowMs) {
  var seen = Date.parse(String(iso || ""))
  var now = nowMs === undefined ? Date.now() : Number(nowMs)
  if (!isFinite(seen) || !isFinite(now)) return "unknown"
  var seconds = Math.max(0, Math.floor((now - seen) / 1000))
  if (seconds < 60) return "now"
  if (seconds < 3600) return Math.floor(seconds / 60) + "m ago"
  if (seconds < 86400) return Math.floor(seconds / 3600) + "h ago"
  if (seconds < 604800) return Math.floor(seconds / 86400) + "d ago"
  if (seconds < 2592000) return Math.floor(seconds / 604800) + "w ago"
  return Math.floor(seconds / 2592000) + "mo ago"
}

if (typeof module !== "undefined") {
  module.exports = {
    STATE_VERSION: STATE_VERSION,
    defaultState: defaultState,
    normalizeState: normalizeState,
    loadState: loadState,
    deviceUid: deviceUid,
    currentDeviceUid: currentDeviceUid,
    friendlyDeviceLabel: friendlyDeviceLabel,
    deviceGlyph: deviceGlyph,
    parseSinkStatus: parseSinkStatus,
    topologySignature: topologySignature,
    buildDevice: buildDevice,
    inferredCategory: inferredCategory,
    categoryFor: categoryFor,
    priorityKey: priorityKey,
    hiddenKey: hiddenKey,
    stablePrioritySort: stablePrioritySort,
    rememberDevices: rememberDevices,
    buildDeviceLists: buildDeviceLists,
    automaticSelection: automaticSelection,
    topologyTransition: topologyTransition,
    reorder: reorder,
    promote: promote,
    setMode: setMode,
    setCustomMode: setCustomMode,
    setCategory: setCategory,
    setHidden: setHidden,
    setHiddenEntirely: setHiddenEntirely,
    setNeverUse: setNeverUse,
    forgetDevice: forgetDevice,
    EVENT_RETRY_BASE_MS: EVENT_RETRY_BASE_MS,
    EVENT_RETRY_MAX_MS: EVENT_RETRY_MAX_MS,
    nextEventRetryDelay: nextEventRetryDelay,
    relativeLastSeen: relativeLastSeen
  }
}
