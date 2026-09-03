const assert = require("node:assert/strict")
const Model = require("../Model.js")

function output(name, label, hint = "") {
  return {
    uid: Model.deviceUid("output", name),
    nodeName: name,
    nodeId: name.length,
    name: label,
    description: label,
    formFactor: hint,
    type: "output",
    isConnected: true
  }
}

function input(name, label) {
  return {
    uid: Model.deviceUid("input", name),
    nodeName: name,
    nodeId: name.length,
    name: label,
    description: label,
    type: "input",
    isConnected: true
  }
}

const speakers = output("alsa_output.internal", "Built-in Audio Speakers")
const display = output("alsa_output.hdmi", "LG Display")
const headphones = output("bluez_output.airpods", "AirPods Pro")
const headset = output("bluez_output.jabra", "Jabra Link", "headset")
const internalMic = input("alsa_input.internal", "Built-in Microphone")
const usbMic = input("alsa_input.usb", "MV7 USB Microphone")

{
  const state = Model.defaultState()
  assert.equal(state.currentMode, "speaker")
  assert.equal(state.customMode, false)
  assert.deepEqual(state.deviceNames, {})
  assert.deepEqual(state.knownDevices, [])
  assert.equal(Model.inferredCategory(speakers), "speaker")
  assert.equal(Model.inferredCategory(display), "speaker")
  assert.equal(Model.inferredCategory(headphones), "headphone")
  assert.equal(Model.inferredCategory(headset), "headphone")
}

{
  const invalid = Model.loadState("not json")
  assert.equal(invalid.value, null)
  assert.equal(invalid.empty, false)
  assert.match(invalid.error, /Invalid audio-priority\.json/)

  const empty = Model.loadState(" \n")
  assert.equal(empty.value, null)
  assert.equal(empty.empty, true, "a blank file is reported as empty, not as corrupt")
  assert.equal(empty.error, "")

  const oversized = Model.loadState("x".repeat(Model.MAX_STATE_TEXT_LENGTH + 1))
  assert.equal(oversized.value, null)
  assert.match(oversized.error, /exceeds/)

  const dense = Model.defaultState()
  const denseFieldLength = 315
  dense.knownDevices = Array.from({ length: Model.MAX_STATE_ITEMS }, (_, index) => ({
    uid: "u" + index + "x".repeat(denseFieldLength - String(index).length - 1),
    name: "n".repeat(denseFieldLength),
    isInput: index % 2 === 0,
    lastSeen: "2".repeat(denseFieldLength)
  }))
  assert.ok((JSON.stringify(Model.normalizeState(dense), null, 2) + "\n").length
    > Model.MAX_STATE_TEXT_LENGTH)
  const serialized = Model.serializeState(dense)
  assert.equal(serialized.error, "")
  assert.ok(serialized.text.length <= Model.MAX_STATE_TEXT_LENGTH)
  assert.equal(Model.loadState(serialized.text).error, "")

  const normalized = Model.normalizeState({
    currentMode: "nonsense",
    customMode: 1,
    inputPriorities: ["a", "a", ""],
    deviceCategories: { a: "headphone", b: "invalid" },
    deviceNames: { a: "  Desk\n\u202e speakers\t ", b: "" }
  })
  assert.equal(normalized.currentMode, "speaker")
  assert.equal(normalized.customMode, false)
  assert.deepEqual(normalized.inputPriorities, ["a"])
  assert.deepEqual(normalized.deviceCategories, { a: "headphone" })
  assert.deepEqual(normalized.deviceNames, { a: "Desk speakers" })
}

{
  let state = Model.setDeviceName(Model.defaultState(), speakers.uid, "  Office  ")
  assert.equal(Model.friendlyName(state, speakers), "Office")
  assert.equal(Model.displayName(state, speakers), "Office")
  assert.equal(Model.displayName(state, display), display.name)

  state = Model.setDeviceName(state, speakers.uid, "x".repeat(Model.MAX_DEVICE_NAME_LENGTH + 10))
  assert.equal(Model.friendlyName(state, speakers).length, Model.MAX_DEVICE_NAME_LENGTH)

  state = Model.setDeviceName(state, speakers.uid, "<b>Desk</b> & speakers")
  assert.equal(Model.displayName(state, speakers), "<b>Desk</b> & speakers")

  state = Model.setDeviceName(state, speakers.uid, "   ")
  assert.equal(Model.friendlyName(state, speakers), "")
  assert.equal(Model.displayName(state, speakers), speakers.name)

  state = Model.setDeviceName(state, speakers.uid, "Desk")
  state = Model.forgetDevice(state, speakers.uid)
  assert.equal(Model.friendlyName(state, speakers), "")
}

{
  // Keys that collide with Object.prototype must behave like any other string.
  const hostile = Model.normalizeState({
    inputPriorities: ["constructor", "__proto__", "toString", "constructor"],
    knownDevices: [
      { uid: "constructor", name: "A" },
      { uid: "constructor", name: "B" },
      { uid: "hasOwnProperty", name: "C" }
    ],
    deviceCategories: { constructor: "headphone" }
  })
  assert.deepEqual(hostile.inputPriorities, ["constructor", "__proto__", "toString"])
  assert.deepEqual(hostile.knownDevices.map(device => device.uid + ":" + device.name), ["constructor:B", "hasOwnProperty:C"])
  assert.equal(Model.categoryFor(hostile, { uid: "constructor" }), "headphone")
  const sorted = Model.stablePrioritySort([{ uid: "x" }, { uid: "constructor" }], ["constructor"])
  assert.deepEqual(sorted.map(device => device.uid), ["constructor", "x"])
  const remembered = Model.rememberDevices(hostile, [{ uid: "constructor", name: "D", type: "output" }], "2026-09-01T00:00:00.000Z")
  assert.equal(remembered.knownDevices.length, 2)
  assert.equal(remembered.knownDevices[0].name, "D")
}

{
  let state = Model.rememberDevices(Model.defaultState(), [speakers, internalMic], "2026-09-01T00:00:00.000Z")
  assert.deepEqual(state.knownDevices, [
    { uid: speakers.uid, name: speakers.name, isInput: false, lastSeen: "2026-09-01T00:00:00.000Z" },
    { uid: internalMic.uid, name: internalMic.name, isInput: true, lastSeen: "2026-09-01T00:00:00.000Z" }
  ])
  const renamed = { ...speakers, name: "Laptop Speakers" }
  state = Model.rememberDevices(state, [renamed], "2026-09-02T00:00:00.000Z")
  assert.equal(state.knownDevices.length, 2)
  assert.equal(state.knownDevices[0].name, "Laptop Speakers")
  assert.equal(state.knownDevices[0].lastSeen, "2026-09-02T00:00:00.000Z")
}

{
  let state = Model.defaultState()
  state.speakerPriorities = [display.uid, speakers.uid]
  state.headphonePriorities = [headset.uid, headphones.uid]
  state.inputPriorities = [usbMic.uid, internalMic.uid]
  let lists = Model.buildDeviceLists(state, [speakers, display, headphones, headset, internalMic, usbMic])
  assert.deepEqual(lists.speakerDevices.map(device => device.uid), [display.uid, speakers.uid])
  assert.deepEqual(lists.headphoneDevices.map(device => device.uid), [headset.uid, headphones.uid])
  assert.deepEqual(lists.inputDevices.map(device => device.uid), [usbMic.uid, internalMic.uid])

  state = Model.setHidden(state, display, "speaker", true)
  state = Model.setNeverUse(state, headset.uid, true)
  lists = Model.buildDeviceLists(state, [speakers, display, headphones, headset, internalMic, usbMic])
  assert.deepEqual(lists.speakerDevices.map(device => device.uid), [speakers.uid])
  assert.deepEqual(lists.hiddenSpeakerDevices.map(device => device.uid), [display.uid])
  assert.deepEqual(lists.headphoneDevices.map(device => device.uid), [headphones.uid])
  assert.deepEqual(lists.hiddenHeadphoneDevices.map(device => device.uid), [headset.uid])
}

{
  let state = Model.rememberDevices(Model.defaultState(), [speakers, headphones, internalMic], "2026-09-01T00:00:00.000Z")
  const lists = Model.buildDeviceLists(state, [speakers])
  assert.equal(lists.speakerDevices[0].isConnected, true)
  assert.deepEqual(lists.headphoneDevices, [])
  assert.deepEqual(lists.inputDevices, [])
  assert.deepEqual(lists.rememberedDevices.map(device => device.uid), [headphones.uid, internalMic.uid])
  assert.equal(lists.rememberedDevices[0].category, "headphone")
  assert.equal(lists.rememberedDevices[0].lastSeen, "2026-09-01T00:00:00.000Z")
}

{
  let state = Model.defaultState()
  state.inputPriorities = [usbMic.uid, internalMic.uid]
  state.speakerPriorities = [display.uid, speakers.uid]
  state.headphonePriorities = [headphones.uid]
  let selected = Model.automaticSelection(state, [speakers, display, internalMic, usbMic])
  assert.equal(selected.input.uid, usbMic.uid)
  assert.equal(selected.output.uid, display.uid)

  selected = Model.automaticSelection(state, [speakers, display, headphones, internalMic, usbMic])
  assert.equal(selected.output.uid, display.uid, "startup honors the saved speaker mode even when headphones exist")

  state = Model.setCustomMode(state, true)
  selected = Model.automaticSelection(state, [speakers, display, internalMic, usbMic])
  assert.equal(selected.input, null)
  assert.equal(selected.output, null)
}

{
  let state = Model.defaultState()
  state.speakerPriorities = [display.uid, speakers.uid]
  state.headphonePriorities = [headset.uid, headphones.uid]
  state.inputPriorities = [usbMic.uid, internalMic.uid]
  const before = [speakers.uid, display.uid, internalMic.uid, usbMic.uid]
  let transition = Model.topologyTransition(state, before, [speakers, display, headphones, internalMic, usbMic])
  assert.equal(transition.state.currentMode, "headphone")
  assert.equal(transition.output.uid, headphones.uid)
  assert.equal(transition.input.uid, usbMic.uid)

  transition = Model.topologyTransition(transition.state,
    [speakers.uid, display.uid, headphones.uid, internalMic.uid, usbMic.uid],
    [speakers, display, internalMic, usbMic])
  assert.equal(transition.state.currentMode, "speaker")
  assert.equal(transition.output.uid, display.uid)
}

{
  let state = Model.defaultState()
  state = Model.setHidden(state, headphones, "headphone", true)
  const transition = Model.topologyTransition(state, [speakers.uid], [speakers, headphones])
  assert.equal(transition.state.currentMode, "speaker", "ignored headphones do not change mode")

  state = Model.setHidden(state, headphones, "headphone", false)
  state = Model.setNeverUse(state, headphones.uid, true)
  const neverTransition = Model.topologyTransition(state, [speakers.uid], [speakers, headphones])
  assert.equal(neverTransition.state.currentMode, "speaker", "Never Use headphones do not change mode")
}

{
  let state = Model.defaultState()
  state = Model.setCustomMode(state, true)
  const transition = Model.topologyTransition(state, [speakers.uid], [speakers, headphones, usbMic])
  assert.equal(transition.state.currentMode, "speaker", "Custom mode suppresses topology mode changes")
  assert.equal(transition.input, null)
  assert.equal(transition.output, null)

  state = Model.setMode(state, "headphone")
  assert.equal(state.customMode, false, "choosing an automatic mode exits Custom")
  const selected = Model.automaticSelection(state, [speakers, headphones, usbMic])
  assert.equal(selected.output.uid, headphones.uid)
  assert.equal(selected.input.uid, usbMic.uid)
}

{
  let state = Model.defaultState()
  const devices = [speakers, display]
  state = Model.reorder(state, devices, "output", "speaker", display.uid, 0)
  assert.deepEqual(state.speakerPriorities, [display.uid, speakers.uid])
  state = Model.promote(state, devices, speakers)
  assert.deepEqual(state.speakerPriorities, [speakers.uid, display.uid])
  state = Model.setCustomMode(state, true)
  state = Model.promote(state, devices, display)
  assert.deepEqual(state.speakerPriorities, [speakers.uid, display.uid], "Custom selection does not promote")
}

{
  let state = Model.defaultState()
  state = Model.setCategory(state, display.uid, "headphone")
  assert.equal(Model.categoryFor(state, display), "headphone")
  state = Model.setHiddenEntirely(state, display, true)
  assert.ok(state.hiddenSpeakers.includes(display.uid))
  assert.ok(state.hiddenHeadphones.includes(display.uid))
  state = Model.setNeverUse(state, display.uid, true)
  state.knownDevices = [{ uid: display.uid, name: display.name, isInput: false, lastSeen: "x" }]
  state.speakerPriorities = [display.uid]
  state.headphonePriorities = [display.uid]
  state = Model.forgetDevice(state, display.uid)
  assert.equal(state.knownDevices.length, 0)
  assert.equal(state.deviceCategories[display.uid], "headphone", "reference keeps category preferences when forgetting")
  assert.equal(state.hiddenSpeakers.includes(display.uid), true, "reference keeps ignore preferences when forgetting")
  assert.equal(state.neverUseDevices.includes(display.uid), true, "reference keeps Never Use when forgetting")
  assert.equal(state.speakerPriorities.includes(display.uid), true, "reference keeps stale priority entries when forgetting")
}

{
  let state = Model.defaultState()
  state.speakerPriorities = ["output:disconnected", display.uid, speakers.uid]
  state = Model.reorder(state, [display, speakers], "output", "speaker", speakers.uid, 0)
  assert.deepEqual(state.speakerPriorities, [speakers.uid, display.uid], "normal-mode reorder saves only displayed devices")
}

{
  assert.equal(Model.inferredCategory(output("a", "Rear Speakers")), "speaker", "'ear' does not match inside 'Rear'")
  assert.equal(Model.inferredCategory(output("a", "HP EliteBook Audio")), "speaker", "'elite' does not match inside 'EliteBook'")
  assert.equal(Model.inferredCategory(output("a", "Marshall Stanmore")), "speaker", "dual-line brands are not assumed to be headphones")
  assert.equal(Model.inferredCategory(output("a", "Nothing Ear (2)")), "headphone")
  assert.equal(Model.inferredCategory(output("a", "WH-1000XM5")), "headphone", "model numbers extend product-line terms")
  assert.equal(Model.inferredCategory(output("a", "Galaxy Buds2 Pro")), "headphone")
  assert.equal(Model.inferredCategory(output("a", "Jabra Elite 8")), "headphone")
  assert.equal(Model.inferredCategory({ ...output("a", "EVO4"), portName: "[Out] Headphones" }), "headphone", "the active port name informs the category")
}

{
  const status = Model.parseSinkStatus([
    "alsa_output.pci-0000_00_1f.3.analog-stereo\t1\t2\tanalog-output-headphones\tHeadphones",
    "alsa_output.usb-Audient_EVO4-00.HiFi__Headphones__sink\t1\t0\t[Out] Headphones\t",
    "speaker-tuning\t0\t0\t\t",
    "constructor\t1",
    "",
    "malformed"
  ].join("\n"))
  assert.deepEqual(status["alsa_output.pci-0000_00_1f.3.analog-stereo"],
    { available: true, portCount: 2, portName: "analog-output-headphones", portDescription: "Headphones" })
  assert.deepEqual(status["alsa_output.usb-Audient_EVO4-00.HiFi__Headphones__sink"],
    { available: true, portCount: 0, portName: "[Out] Headphones", portDescription: "" })
  assert.equal(status["speaker-tuning"].available, false)
  assert.equal(status.constructor.available, true)
  assert.equal(status.malformed, undefined)
  assert.equal(status.toString, undefined, "the status map has no prototype")
}

{
  // A laptop's speakers and headphone jack share one PipeWire node. The active
  // port turns it into two devices so the jack drives the Headphones mode.
  const nodeName = "alsa_output.pci-0000_00_1f.3.analog-stereo"
  const node = {
    type: "output", nodeName, nodeId: 41, description: "Built-in Audio Analog Stereo",
    nickname: "", props: { "device.bus": "pci" }, muted: false
  }
  const speakerStatus = Model.parseSinkStatus(nodeName + "\t1\t2\tanalog-output-speaker\tSpeaker")
  const jackStatus = Model.parseSinkStatus(nodeName + "\t1\t2\tanalog-output-headphones\tHeadphones")
  const state = Model.defaultState()
  const builtinSpeaker = Model.buildDevice(state, node, speakerStatus)
  const builtinJack = Model.buildDevice(state, node, jackStatus)
  assert.equal(builtinSpeaker.uid, "output:" + nodeName + "#analog-output-speaker")
  assert.equal(builtinSpeaker.name, "Analog Stereo · Speaker")
  assert.equal(builtinSpeaker.category, "speaker")
  assert.equal(builtinJack.uid, "output:" + nodeName + "#analog-output-headphones")
  assert.equal(builtinJack.name, "Analog Stereo · Headphones")
  assert.equal(builtinJack.category, "headphone")
  assert.equal(builtinJack.nodeName, nodeName, "routing still targets the shared node")
  assert.notEqual(Model.topologySignature([builtinSpeaker]), Model.topologySignature([builtinJack]))

  let transition = Model.topologyTransition(state, [builtinSpeaker.uid, internalMic.uid], [builtinJack, internalMic])
  assert.equal(transition.state.currentMode, "headphone", "plugging into the jack switches to Headphones")
  assert.equal(transition.output.uid, builtinJack.uid)
  transition = Model.topologyTransition(transition.state, [builtinJack.uid, internalMic.uid], [builtinSpeaker, internalMic])
  assert.equal(transition.state.currentMode, "speaker", "unplugging falls back to Speakers")
  assert.equal(transition.output.uid, builtinSpeaker.uid)

  assert.equal(Model.currentDeviceUid("output", nodeName, [builtinJack, internalMic]), builtinJack.uid)
  assert.equal(Model.currentDeviceUid("output", nodeName, []), "output:" + nodeName, "falls back to the plain uid before the inventory exists")
  assert.equal(Model.currentDeviceUid("input", "", [internalMic]), "")

  const singlePort = Model.buildDevice(state, { ...node, nodeName: "alsa_output.usb-Studio_Display.analog-stereo" },
    Model.parseSinkStatus("alsa_output.usb-Studio_Display.analog-stereo\t1\t1\tanalog-output\tAnalog Output"))
  assert.equal(singlePort.uid, "output:alsa_output.usb-Studio_Display.analog-stereo", "single-port sinks keep the plain uid")
  assert.equal(singlePort.name, "Analog Stereo")
  assert.equal(Model.buildDevice(state, { ...node, nodeName: "speaker-tuning" },
    Model.parseSinkStatus("speaker-tuning\t0\t0\t\t")), null, "unavailable sinks are dropped")
  assert.equal(Model.buildDevice(state, { type: "input", nodeName: "quickshell", nodeId: 9 }, {}), null)
  assert.equal(Model.buildDevice(state, { type: "output", nodeName: "unknown-sink", nodeId: 7 }, {}), null,
    "a sink the helper has not verified is rejected")
}

{
  const oversized = Array.from({ length: Model.MAX_STATE_ITEMS + 10 }, (_, index) => "device-" + index)
  const state = Model.normalizeState({ inputPriorities: oversized })
  assert.equal(state.inputPriorities.length, Model.MAX_STATE_ITEMS)
  assert.equal(Model.deviceUid("output", "x".repeat(Model.MAX_STRING_LENGTH + 1)).length,
    "output:".length + Model.MAX_STRING_LENGTH)
}

{
  const now = Date.parse("2026-09-02T12:00:00.000Z")
  assert.equal(Model.relativeLastSeen("2026-09-02T11:59:50.000Z", now), "now")
  assert.equal(Model.relativeLastSeen("2026-09-02T11:55:00.000Z", now), "5m ago")
  assert.equal(Model.relativeLastSeen("2026-09-02T08:00:00.000Z", now), "4h ago")
  assert.equal(Model.relativeLastSeen("2026-08-30T12:00:00.000Z", now), "3d ago")
  assert.equal(Model.relativeLastSeen("2026-08-01T12:00:00.000Z", now), "1mo ago")
}

{
  assert.equal(Model.EVENT_RETRY_BASE_MS, 3000)
  assert.equal(Model.nextEventRetryDelay(3000, 0), 6000, "an immediate exit doubles the delay")
  assert.equal(Model.nextEventRetryDelay(6000, 100), 12000)
  assert.equal(Model.nextEventRetryDelay(48000, 0), 60000, "the delay is capped")
  assert.equal(Model.nextEventRetryDelay(60000, 0), 60000)
  assert.equal(Model.nextEventRetryDelay(48000, 30000), 3000, "a long-lived stream resets the delay")
  assert.equal(Model.nextEventRetryDelay(0, 0), 6000, "a missing delay starts from the base")
  assert.equal(Model.nextEventRetryDelay(NaN, NaN), 6000)
}

console.log("ok — AudioPriorityBar state-machine parity")
