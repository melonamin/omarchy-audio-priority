#!/usr/bin/env bash
set -euo pipefail

plugin_dir=$(cd "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/audio-priority-test.XXXXXX")
cleanup() { rm -rf "$test_dir"; }
trap cleanup EXIT

export AUDIO_PRIORITY_TEST_DIR=$test_dir
export AUDIO_PRIORITY_TEST_BIN=$plugin_dir/tests/fixtures/bin
touch "$test_dir/calls"
printf 'old-sink\n' >"$test_dir/sink"
printf 'old-source\n' >"$test_dir/source"
cp "$plugin_dir/tests/fixtures/pactl-list-sinks.txt" "$test_dir/list-sinks"
printf '%s\t%s\n' \
  'alsa_output.pci-0000_00_1f.3.analog-stereo' 1 \
  'alsa_output.usb-Apple_Inc._Studio_Display-02.analog-stereo' 1 \
  'alsa_output.usb-Audient_EVO4-00.HiFi__Headphones__sink' 1 \
  'speaker-tuning' 0 >"$test_dir/availability"

/usr/bin/bash -n \
  "$plugin_dir/scripts/route-device" \
  "$plugin_dir/scripts/sink-status" \
  "$plugin_dir/scripts/audio-events"
[[ -x $plugin_dir/scripts/state-store ]]

# sink-status merges Omarchy's availability with the active port of every sink,
# including ports whose names contain spaces and sinks that list no ports.
diff -u <(printf '%s\n' \
  $'alsa_output.pci-0000_00_1f.3.analog-stereo\t1\t2\tanalog-output-headphones\tHeadphones' \
  $'alsa_output.usb-Apple_Inc._Studio_Display-02.analog-stereo\t1\t1\tanalog-output\tAnalog Output' \
  $'alsa_output.usb-Audient_EVO4-00.HiFi__Headphones__sink\t1\t0\t[Out] Headphones\t' \
  $'speaker-tuning\t0\t0\t\t') \
  <("$plugin_dir/scripts/sink-status")

if AUDIO_PRIORITY_TEST_AVAILABILITY_FAIL=1 "$plugin_dir/scripts/sink-status" >/dev/null 2>&1; then
  echo "sink-status accepted a failed availability helper" >&2
  exit 1
fi

: >"$test_dir/availability"
if "$plugin_dir/scripts/sink-status" | /usr/bin/awk -F '\t' '$2 != 0 { exit 1 }'; then
  :
else
  echo "sink-status trusted a sink missing from availability output" >&2
  exit 1
fi
printf '%s\t%s\n' \
  'alsa_output.pci-0000_00_1f.3.analog-stereo' 1 \
  'alsa_output.usb-Apple_Inc._Studio_Display-02.analog-stereo' 1 \
  'alsa_output.usb-Audient_EVO4-00.HiFi__Headphones__sink' 1 \
  'speaker-tuning' 0 >"$test_dir/availability"

[[ $(AUDIO_PRIORITY_TEST_EVENTS=1 "$plugin_dir/scripts/audio-events") == changed ]]

"$plugin_dir/scripts/route-device" output 41 test.output
"$plugin_dir/scripts/route-device" input 42 test.input

if "$plugin_dir/scripts/route-device" output 41 -option-like-name >/dev/null 2>&1; then
  echo "route-device accepted an option-like node name" >&2
  exit 1
fi

diff -u <(printf 'output\t41\ttest.output\ninput\t42\ttest.input\n') "$test_dir/calls"
[[ $(<"$test_dir/sink") == test.output ]]
[[ $(<"$test_dir/source") == test.input ]]

if AUDIO_PRIORITY_TEST_KEEP_DEFAULT=1 "$plugin_dir/scripts/route-device" output 43 rejected.output \
  >"$test_dir/rejected.out" 2>"$test_dir/rejected.err"; then
  echo "route verification accepted a rejected default" >&2
  exit 1
fi
grep -F 'PipeWire kept test.output instead of rejected.output' "$test_dir/rejected.err" >/dev/null

if AUDIO_PRIORITY_TEST_OVERSIZED_DEFAULT=1 "$plugin_dir/scripts/route-device" output 44 oversized.output \
    >/dev/null 2>&1; then
  echo "route verification accepted oversized helper output" >&2
  exit 1
fi

state_home=$test_dir/state-home
mkdir -p "$state_home"
HOME=$state_home "$plugin_dir/scripts/state-store" read >"$test_dir/empty-state"
[[ ! -s $test_dir/empty-state ]]
[[ $(stat -c %a "$state_home/.config/omarchy") == 700 ]]
[[ $(stat -c %a "$state_home/.config/omarchy/audio-priority.json") == 600 ]]
state_request='{"text":"{\"currentMode\":\"speaker\"}\n"}'
printf '%s\n' "$state_request" \
  | HOME=$state_home "$plugin_dir/scripts/state-store" write
diff -u <(printf '{"currentMode":"speaker"}\n') \
  <(HOME=$state_home "$plugin_dir/scripts/state-store" read)
if /usr/bin/python3 -c 'import json; print(json.dumps({"text": "x" * 262145}))' \
    | HOME=$state_home "$plugin_dir/scripts/state-store" write >/dev/null 2>&1; then
  echo "state-store accepted an oversized write" >&2
  exit 1
fi
diff -u <(printf '{"currentMode":"speaker"}\n') \
  <(HOME=$state_home "$plugin_dir/scripts/state-store" read)

# A read never follows a swapped final component. A write safely replaces the
# symlink through the verified directory descriptor without touching its target.
mv "$state_home/.config/omarchy/audio-priority.json" "$state_home/real-state"
ln -s "$state_home/real-state" "$state_home/.config/omarchy/audio-priority.json"
if HOME=$state_home "$plugin_dir/scripts/state-store" read >/dev/null 2>&1; then
  echo "state-store followed a symlinked state file" >&2
  exit 1
fi
printf '%s\n' "$state_request" \
  | HOME=$state_home "$plugin_dir/scripts/state-store" write
[[ ! -L $state_home/.config/omarchy/audio-priority.json ]]
[[ $(<"$state_home/real-state") == '{"currentMode":"speaker"}' ]]

# A hard link is rejected before permissions are changed on the opened file.
rm "$state_home/.config/omarchy/audio-priority.json"
printf 'protected\n' >"$state_home/protected"
chmod 0644 "$state_home/protected"
ln "$state_home/protected" "$state_home/.config/omarchy/audio-priority.json"
if HOME=$state_home "$plugin_dir/scripts/state-store" read >/dev/null 2>&1; then
  echo "state-store accepted a hard-linked state file" >&2
  exit 1
fi
[[ $(stat -c %a "$state_home/protected") == 644 ]]

# Repeated concurrent swaps may make an operation fail closed, but they must
# never redirect an atomic write through the attacker-controlled symlink.
rm "$state_home/.config/omarchy/audio-priority.json"
printf 'race target\n' >"$state_home/race-target"
(
  for index in $(seq 1 200); do
    rm -f "$state_home/.config/omarchy/audio-priority.json"
    ln -s "$state_home/race-target" "$state_home/.config/omarchy/audio-priority.json" 2>/dev/null || true
    rm -f "$state_home/.config/omarchy/audio-priority.json"
    printf '{}\n' >"$state_home/.config/omarchy/race-$index"
    mv -f "$state_home/.config/omarchy/race-$index" "$state_home/.config/omarchy/audio-priority.json"
  done
) &
race_pid=$!
for _ in $(seq 1 100); do
  printf '%s\n' "$state_request" \
    | HOME=$state_home "$plugin_dir/scripts/state-store" write >/dev/null 2>&1 || true
done
wait "$race_pid"
[[ $(<"$state_home/race-target") == 'race target' ]]
if find "$state_home/.config/omarchy" -maxdepth 1 -name '.audio-priority.*.tmp' | grep -q .; then
  echo "state-store left a temporary file behind" >&2
  exit 1
fi

parent_home=$test_dir/parent-home
mkdir -p "$parent_home/config-target"
ln -s "$parent_home/config-target" "$parent_home/.config"
if HOME=$parent_home "$plugin_dir/scripts/state-store" read >/dev/null 2>&1; then
  echo "state-store followed a symlinked parent directory" >&2
  exit 1
fi

omarchy-plugin-validate "$plugin_dir"

shell_dir=${OMARCHY_SHELL_DIR:-}
for candidate in "$HOME/.local/share/omarchy/shell" /usr/share/omarchy/shell; do
  [[ -n $shell_dir ]] && break
  [[ -d $candidate ]] && shell_dir=$candidate
done
[[ -n $shell_dir ]] || { echo "Omarchy shell sources not found; set OMARCHY_SHELL_DIR" >&2; exit 1; }
qmllint -I "$shell_dir" \
  "$plugin_dir/BarWidget.qml" \
  "$plugin_dir/Panel.qml" \
  "$plugin_dir/Service.qml" \
  "$plugin_dir/DeviceSection.qml" \
  "$plugin_dir/DeviceRow.qml" \
  "$plugin_dir/IgnoredDevices.qml" \
  "$plugin_dir/RememberedDevices.qml" \
  "$plugin_dir/tests/e2e/shell.qml"

printf 'ok — routing and sink-status helpers, manifest, and QML validation\n'
