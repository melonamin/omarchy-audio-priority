function deviceTargets(kind, devices) {
  var result = []
  var values = Array.isArray(devices) ? devices : []
  for (var i = 0; i < values.length; i++) {
    var device = values[i]
    if (!device || !device.uid) continue
    result.push({
      id: kind + ":" + device.uid,
      kind: kind,
      device: device,
      category: device.type === "input" ? "input" : String(device.category || "speaker"),
      index: i
    })
  }
  return result
}

function buildTargets(view) {
  var source = view || {}
  var result = [
    { id: "header", kind: "header" },
    { id: "mode:speaker", kind: "mode", mode: "speaker" },
    { id: "mode:headphone", kind: "mode", mode: "headphone" },
    { id: "mode:custom", kind: "mode", mode: "custom" },
    { id: "output-volume", kind: "output-volume" }
  ]

  if (source.showSpeakers !== false)
    result = result.concat(deviceTargets("device", source.speakers))
  if (source.showHeadphones === true)
    result = result.concat(deviceTargets("device", source.headphones))
  if (source.showInputVolume !== false)
    result.push({ id: "input-volume", kind: "input-volume" })
  result = result.concat(deviceTargets("device", source.inputs))

  var ignored = Array.isArray(source.ignored) ? source.ignored : []
  if (source.showIgnored === true && ignored.length > 0) {
    result.push({ id: "ignored-toggle", kind: "ignored-toggle" })
    if (source.ignoredExpanded === true)
      result = result.concat(deviceTargets("ignored", ignored))
  }

  result.push({ id: "edit", kind: "edit" })
  return result
}

function indexOfId(targets, id) {
  var values = Array.isArray(targets) ? targets : []
  for (var i = 0; i < values.length; i++)
    if (values[i] && values[i].id === id) return i
  return -1
}

function move(targets, id, delta) {
  var values = Array.isArray(targets) ? targets : []
  if (values.length === 0) return ""
  var current = indexOfId(values, id)
  if (current < 0) current = 0
  var next = Math.max(0, Math.min(values.length - 1, current + Number(delta || 0)))
  return values[next].id
}

function repair(targets, id, previousIndex) {
  var values = Array.isArray(targets) ? targets : []
  if (values.length === 0) return ""
  if (indexOfId(values, id) !== -1) return id
  var fallback = Math.max(0, Math.min(values.length - 1, Number(previousIndex || 0)))
  return values[fallback].id
}

function priorityDestination(key, count) {
  var text = String(key || "")
  if (!/^[0-9]$/.test(text) || Number(count) < 1) return -1
  var requested = text === "0" ? 9 : Number(text) - 1
  return Math.min(Math.max(0, Number(count) - 1), requested)
}

function actionsFor(device, category, ignored, neverUse) {
  if (!device) return []
  var actions = []
  if (device.type === "output") {
    actions.push({
      id: "category",
      label: category === "headphone" ? "Move to Speakers" : "Move to Headphones",
      danger: false
    })
  }
  actions.push({
    id: "ignore",
    label: ignored ? "Stop Ignoring" : (category === "input" ? "Ignore Microphone" : "Ignore Here"),
    danger: false
  })
  if (device.type === "output" && !ignored)
    actions.push({ id: "ignore-entirely", label: "Ignore Entirely", danger: false })
  if (device.isConnected === false)
    actions.push({ id: "forget", label: "Forget Device", danger: true })
  else
    actions.push({ id: "never", label: neverUse ? "Allow Use" : "Never Use", danger: !neverUse })
  return actions
}

if (typeof module !== "undefined") {
  module.exports = {
    buildTargets: buildTargets,
    indexOfId: indexOfId,
    move: move,
    repair: repair,
    priorityDestination: priorityDestination,
    actionsFor: actionsFor
  }
}
