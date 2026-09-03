# AudioPriorityBar parity contract

Audio Priority is a native Omarchy port of
[tobi/AudioPriorityBar](https://github.com/tobi/AudioPriorityBar). It preserves
the reference application's routing state machine while translating lifecycle
and presentation into Omarchy's plugin model.

## State

The persisted fields correspond directly to `PriorityManager.swift`:

- `currentMode`: `speaker` or `headphone`
- `customMode`: manual selection with automatic routing disabled
- `inputPriorities`, `speakerPriorities`, `headphonePriorities`
- `deviceCategories`
- `hiddenMics`, `hiddenSpeakers`, `hiddenHeadphones`
- `neverUseDevices`
- `knownDevices`, including direction and last-seen time

## Routing transitions

1. Startup in automatic mode selects the highest-priority connected and
   allowed input plus the highest-priority output in the saved mode.
2. A topology change refreshes remembered devices and, in automatic mode,
   reevaluates both input and output.
3. A newly connected allowed headphone changes the mode to Headphones.
4. Losing the last allowed headphone changes Headphones back to Speakers when
   an allowed speaker is connected.
5. Entering Custom preserves the current defaults and suspends automatic
   routing. Leaving Custom immediately reapplies both priority lists.
6. Reordering, category changes, ignoring, and Never Use follow the reference
   application's immediate-selection behavior.
7. Disconnected devices retain their priority and remain manageable in the
   collapsed Remembered Devices section. Reordering or click-to-promote saves
   the connected list only, as the reference application's `savePriorities`
   does.

## Platform translations

- CoreAudio device UIDs become direction-qualified PipeWire node names, which
  remain stable across ordinary reconnects and profile recreation. A sink with
  more than one port is further qualified by its active port
  (`output:<node>#<port>`), because CoreAudio reports a laptop's speakers and
  headphone jack as separate devices while PipeWire switches the port of a
  single node.
- CoreAudio device-list notifications become PulseAudio change events from
  `pactl subscribe`, reduced to fixed-size notifications, debounced, and
  restarted periodically, with a slow timer as fallback.
- Sink availability is authoritative: a sink omitted by the helper is treated
  as unavailable until a later successful refresh reports it.
- The macOS menu-bar popover becomes an Omarchy bar widget and `KeyboardPanel`.
- Launch at Login is represented by enabling the plugin service. Quit is
  represented by disabling the plugin. Neither changes routing semantics.
- SF Symbols become Nerd Font glyphs supplied by Omarchy.
