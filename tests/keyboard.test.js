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
    "header", "mode:speaker", "mode:headphone", "mode:custom", "output-volume",
    "device:output:speaker", "input-volume", "device:input:microphone", "edit"
  ])
  assert.equal(Keyboard.move(targets, "output-volume", 1), "device:output:speaker")
  assert.equal(Keyboard.move(targets, "header", -1), "header")
  assert.equal(Keyboard.move(targets, "edit", 1), "edit")
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
    ignored: [headphones]
  })
  assert.ok(targets.some(target => target.id === "ignored-toggle"))
  assert.ok(targets.some(target => target.id === "ignored:output:headphones"))
  assert.equal(Keyboard.repair(targets, "device:missing", 5), targets[5].id)
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
    ["category", "ignore", "ignore-entirely", "never"]
  )
  assert.deepEqual(
    Keyboard.actionsFor(microphone, "input", false, false).map(action => action.id),
    ["ignore", "never"]
  )
  const disconnected = { ...speaker, isConnected: false }
  assert.deepEqual(
    Keyboard.actionsFor(disconnected, "speaker", true, false).map(action => action.id),
    ["category", "ignore", "forget"]
  )
}

console.log("ok — Omarchy keyboard cursor model")
