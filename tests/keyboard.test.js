const assert = require("node:assert/strict")
const Keyboard = require("../KeyboardModel.js")

const speaker = { uid: "output:speaker", type: "output", category: "speaker", isConnected: true }
const headphones = { uid: "output:headphones", type: "output", category: "headphone", isConnected: true }
const microphone = { uid: "input:microphone", type: "input", category: "input", isConnected: true }

{
  const targets = Keyboard.buildTargets({
    showSpeakers: true,
    showHeadphones: false,
    speakers: [speaker],
    headphones: [headphones],
    inputs: [microphone]
  })
  assert.deepEqual(targets.map(target => target.id), [
    "device:output:speaker", "device:input:microphone"
  ])
  assert.equal(Keyboard.move(targets, "device:output:speaker", 1), "device:input:microphone")
  assert.equal(Keyboard.move(targets, "device:output:speaker", -1), "device:output:speaker")
  assert.equal(Keyboard.move(targets, "device:input:microphone", 1), "device:input:microphone")
}

{
  const targets = Keyboard.buildTargets({
    showSpeakers: true,
    showHeadphones: true,
    speakers: [speaker],
    headphones: [headphones],
    inputs: [microphone],
    showIgnored: true,
    ignoredExpanded: true,
    ignored: [headphones],
    showRemembered: true,
    rememberedExpanded: true,
    remembered: [{ ...microphone, uid: "input:old", isConnected: false }]
  })
  assert.deepEqual(targets.map(target => target.id), [
    "device:output:speaker",
    "device:output:headphones",
    "device:input:microphone",
    "ignored:output:headphones",
    "remembered:input:old"
  ])
  assert.equal(Keyboard.repair(targets, "device:missing", 3), "ignored:output:headphones")
}

{
  assert.equal(Keyboard.priorityDestination("1", 12), 0)
  assert.equal(Keyboard.priorityDestination("9", 12), 8)
  assert.equal(Keyboard.priorityDestination("0", 12), 9)
  assert.equal(Keyboard.priorityDestination("8", 3), 2)
  assert.equal(Keyboard.priorityDestination("x", 3), -1)
  assert.equal(Keyboard.priorityDestination("1", 0), -1)
}

{
  assert.deepEqual(
    Keyboard.actionsFor(speaker, "speaker", false, false).map(action => action.id),
    ["rename", "category", "ignore", "ignore-entirely", "never"]
  )
  assert.deepEqual(
    Keyboard.actionsFor(microphone, "input", false, false).map(action => action.id),
    ["rename", "ignore", "never"]
  )
  const disconnected = { ...speaker, isConnected: false }
  assert.deepEqual(
    Keyboard.actionsFor(disconnected, "speaker", true, false).map(action => action.id),
    ["rename", "category", "ignore", "forget"]
  )
}

console.log("ok — Omarchy keyboard cursor model")
