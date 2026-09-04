#!/usr/bin/env bash
# Runs Service.qml under Quickshell the way the Omarchy shell hosts it, against
# a private PipeWire daemon and the fixture helpers, and drives it over IPC.
# The daemon has no session manager, so nothing ever has a default device and
# no real audio route can change while the test runs.
set -euo pipefail

plugin_dir=$(cd "$(dirname "$0")/.." && pwd)
shell_dir=$plugin_dir/tests/e2e
# Unix socket paths are capped at 108 bytes, so the private PipeWire instance
# lives under the runtime directory rather than inside the repository.
work=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/audio-priority-e2e.XXXXXX")
qs_pid=""
pw_pid=""

stop_process() {
  local pid=$1
  [[ -n $pid ]] || return 0
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

cleanup() {
  stop_process "$qs_pid"
  stop_process "$pw_pid"
  rm -rf "$work"
}
trap cleanup EXIT

fail() {
  echo "e2e: $*" >&2
  if [[ -s $work/qs.log ]]; then
    echo "--- quickshell log ---" >&2
    cat "$work/qs.log" >&2
  fi
  exit 1
}

# wait_for <description> <command...>: polls the command for up to ten seconds.
wait_for() {
  local what=$1
  shift
  for _ in $(seq 1 100); do
    if "$@" >/dev/null 2>&1; then return 0; fi
    sleep 0.1
  done
  fail "timed out waiting for $what"
}

status() { qs -p "$shell_dir" ipc call melonamin.audio-priority status 2>/dev/null; }
status_is() { status | jq -e "$1" >/dev/null; }
host_call() { qs -p "$shell_dir" ipc call audio-priority-e2e "$@" 2>/dev/null; }
state_mode_is_private() { [[ $(stat -c %a "$state_file") == 600 ]]; }

start_shell() {
  qs -p "$shell_dir" >"$work/qs.log" 2>&1 &
  qs_pid=$!
  wait_for "the service IPC" status_is 'type == "object"'
  local load_error
  load_error=$(host_call loadError)
  [[ -z $load_error ]] || fail "Service.qml failed to load: $load_error"
}

stop_shell() {
  stop_process "$qs_pid"
  qs_pid=""
  if grep -E 'WARN|ERROR' "$work/qs.log" >/dev/null; then
    fail "the Quickshell log is not clean"
  fi
}

export HOME=$work/home
export AUDIO_PRIORITY_TEST_DIR=$work/fixtures
export AUDIO_PRIORITY_PLUGIN_DIR=$plugin_dir
export PIPEWIRE_RUNTIME_DIR=$work/pipewire
# Headless: no window is ever created. The GTK platform theme would demand a
# display, so it is disabled along with the display variables themselves.
export QT_QPA_PLATFORM=offscreen
export QT_QPA_PLATFORMTHEME=
unset WAYLAND_DISPLAY DISPLAY
mkdir -p "$HOME" "$AUDIO_PRIORITY_TEST_DIR" "$PIPEWIRE_RUNTIME_DIR"
: >"$AUDIO_PRIORITY_TEST_DIR/calls"
printf 'old-sink\n' >"$AUDIO_PRIORITY_TEST_DIR/sink"
printf 'old-source\n' >"$AUDIO_PRIORITY_TEST_DIR/source"
cp "$plugin_dir/tests/fixtures/pactl-list-sinks.txt" "$AUDIO_PRIORITY_TEST_DIR/list-sinks"
printf 'alsa_output.pci-0000_00_1f.3.analog-stereo\t1\n' >"$AUDIO_PRIORITY_TEST_DIR/availability"

pipewire >"$work/pipewire.log" 2>&1 &
pw_pid=$!
wait_for "the private PipeWire socket" test -S "$PIPEWIRE_RUNTIME_DIR/pipewire-0"

state_file=$HOME/.config/omarchy/audio-priority.json

start_shell

# A fresh install writes the default state and reports ready with no devices.
wait_for "the state file" test -s "$state_file"
[[ $(stat -c %a "$HOME/.config/omarchy") == 700 ]] || fail "state directory is not private"
[[ $(stat -c %a "$state_file") == 600 ]] || fail "state file is not private"
jq -e '.version == 1 and .currentMode == "speaker" and .customMode == false' "$state_file" >/dev/null \
  || fail "default state was not written: $(cat "$state_file")"
wait_for "the service to become ready" status_is '.ready == true'
status_is '.mode == "speaker" and .devices == 0 and .error == null' \
  || fail "unexpected startup status: $(status)"
[[ ! -s $AUDIO_PRIORITY_TEST_DIR/calls ]] || fail "routing helpers ran with no devices: $(cat "$AUDIO_PRIORITY_TEST_DIR/calls")"

# An edit made outside the panel is picked up as soon as it lands.
jq '.currentMode = "headphone"' "$state_file" >"$work/edit.json"
mv "$work/edit.json" "$state_file"
wait_for "the external edit" status_is '.mode == "headphone"'
wait_for "external edit permissions" state_mode_is_private

# The service's own save is watched like any other change, but reloading it
# must not replace the in-memory state: exactly one state change per action.
before=$(host_call stateChanges)
host_call setMode speaker >/dev/null
wait_for "the mode change" status_is '.mode == "speaker"'
wait_for "the save" jq -e '.currentMode == "speaker"' "$state_file"
sleep 1
after=$(host_call stateChanges)
[[ $((after - before)) -eq 1 ]] \
  || fail "expected one state change for setMode, saw $((after - before)); the service reloaded its own save"

# A file emptied while running (an editor truncating before it writes) leaves
# the in-memory state alone and reports no error.
: >"$state_file"
sleep 1
status_is '.mode == "speaker" and .error == null' || fail "a truncated file disturbed the state: $(status)"

# Invalid JSON is reported and left untouched; a valid file clears the error.
printf '{ not json' >"$state_file"
wait_for "the parse error" status_is '.error != null and (.error | test("Invalid audio-priority.json"))'
status_is '.mode == "speaker"' || fail "invalid JSON replaced the state: $(status)"
[[ $(<"$state_file") == '{ not json' ]] || fail "the invalid file was overwritten"
printf '{"currentMode":"headphone"}\n' >"$state_file"
wait_for "recovery from invalid JSON" status_is '.error == null and .mode == "headphone"'

# The fixture's `pactl subscribe` exits at once, so relaunch attempts back off.
wait_for "event-stream backoff" status_is '.events == false and .eventRetryMs >= 6000'

stop_shell

# Destroying only the plugin service must terminate and reap the complete live
# event-stream process tree while the hosting Quickshell process stays running.
export AUDIO_PRIORITY_TEST_EVENTS_HOLD=1
rm -f "$AUDIO_PRIORITY_TEST_DIR/audio-event-pid"
start_shell
wait_for "the held audio event subscriber" test -s "$AUDIO_PRIORITY_TEST_DIR/audio-event-pid"
event_pactl_pid=$(<"$AUDIO_PRIORITY_TEST_DIR/audio-event-pid")
wait_for "the held subscriber child" pgrep -P "$event_pactl_pid"
event_leaf_pid=$(pgrep -P "$event_pactl_pid" | head -1)
event_script_pid=$(ps -o ppid= -p "$event_pactl_pid" | tr -d ' ')
event_timeout_pid=$(ps -o ppid= -p "$event_script_pid" | tr -d ' ')
[[ -n $event_script_pid && -n $event_timeout_pid ]] \
  || fail "could not identify the audio event process tree"
host_call destroyService >/dev/null
wait_for "the event subscriber teardown" test ! -e "/proc/$event_pactl_pid"
[[ ! -e /proc/$event_leaf_pid ]] || fail "event subscriber child survived service destruction"
[[ ! -e /proc/$event_script_pid ]] || fail "audio-events survived service destruction"
[[ ! -e /proc/$event_timeout_pid ]] || fail "timeout survived service destruction"
unset AUDIO_PRIORITY_TEST_EVENTS_HOLD
stop_shell

# Without a source directory in the manifest the service says so instead of
# discovering devices forever.
AUDIO_PRIORITY_E2E_NO_SOURCE_DIR=1 start_shell
wait_for "the setup error" status_is '.ready == false and (.error | test("source directory"))'
stop_shell

printf 'ok — service end to end under Quickshell\n'
