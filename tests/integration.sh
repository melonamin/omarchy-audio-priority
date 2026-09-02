#!/usr/bin/env bash
set -euo pipefail

plugin_dir=$(cd "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d "$plugin_dir/.audio-priority-test.XXXXXX")
cleanup() { rm -rf "$test_dir"; }
trap cleanup EXIT

export AUDIO_PRIORITY_TEST_DIR=$test_dir
export PATH="$plugin_dir/tests/fixtures/bin:$PATH"
touch "$test_dir/calls"
printf 'old-sink\n' >"$test_dir/sink"
printf 'old-source\n' >"$test_dir/source"
cp "$plugin_dir/tests/fixtures/pactl-list-sinks.txt" "$test_dir/list-sinks"
printf 'alsa_output.pci-0000_00_1f.3.analog-stereo\t1\nspeaker-tuning\t0\n' >"$test_dir/availability"

# sink-status merges Omarchy's availability with the active port of every sink,
# including ports whose names contain spaces and sinks that list no ports.
diff -u <(printf '%s\n' \
  $'alsa_output.pci-0000_00_1f.3.analog-stereo\t1\t2\tanalog-output-headphones\tHeadphones' \
  $'alsa_output.usb-Apple_Inc._Studio_Display-02.analog-stereo\t1\t1\tanalog-output\tAnalog Output' \
  $'alsa_output.usb-Audient_EVO4-00.HiFi__Headphones__sink\t1\t0\t[Out] Headphones\t' \
  $'speaker-tuning\t0\t0\t\t') \
  <("$plugin_dir/scripts/sink-status")

"$plugin_dir/scripts/route-device" output 41 test.output
"$plugin_dir/scripts/route-device" input 42 test.input

diff -u <(printf 'output\t41\ttest.output\ninput\t42\ttest.input\n') "$test_dir/calls"
[[ $(<"$test_dir/sink") == test.output ]]
[[ $(<"$test_dir/source") == test.input ]]

if AUDIO_PRIORITY_TEST_KEEP_DEFAULT=1 "$plugin_dir/scripts/route-device" output 43 rejected.output \
  >"$test_dir/rejected.out" 2>"$test_dir/rejected.err"; then
  echo "route verification accepted a rejected default" >&2
  exit 1
fi
grep -F 'PipeWire kept test.output instead of rejected.output' "$test_dir/rejected.err" >/dev/null

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
  "$plugin_dir/IgnoredDevices.qml"

printf 'ok — routing and sink-status helpers, manifest, and QML validation\n'
