#!/usr/bin/env bash
# Real picker/backend across file, folder and Save modes, using only guarded synthetic fixtures.
set -euo pipefail
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.."
[ -x target/debug/flea ] || cargo build --locked -q
root="$FIXTURE_ROOT/flea-pf-$$"
sandbox_make "$root"
trap 'sandbox_remove "$root"' EXIT
mkdir -p "$root/config" "$root/runtime"
chmod 700 "$root/runtime"
ln -s "$PWD/ui" "$root/config/flea"
ln -s "$(readlink -f ui/boot/Commons)" "$root/config/Commons"
ln -s "$(readlink -f ui/boot/Ui)" "$root/config/Ui"
run_probe() {
    local probe=$1 mode=$2 view=$3 phase request output status warnings
    phase="$root/$probe-$mode-$view"
    mkdir -p "$phase"/{home/Downloads/existing,state/flea,cache,data,tmp}
    printf 'keep\n' > "$phase/home/Downloads/keep.txt"
    printf '{"pickerView":"%s","places":{"favourites":[]}}\n' "$view" > "$phase/state/flea/ui.json"
    request=$(/usr/bin/python3 - "$phase/home/Downloads" "$mode" <<'PY'
import json,sys
folder,kind=sys.argv[1:]
print(json.dumps(dict(mode=kind if kind in ('save','savefiles') else 'open',
    directory=kind in ('folder','folders'),multiple=kind in ('files','folders'),
    folder=folder,name='download.zip',title='Folder creation regression',
    filters=[dict(label='Text documents',globs=['*.txt'],mimes=[])])))
PY
    )
    cp "tests/$probe.qml" "$root/config/shell.qml"
    status=0
    output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
        HOME="$phase/home" XDG_CONFIG_HOME="$root/config" XDG_STATE_HOME="$phase/state" XDG_CACHE_HOME="$phase/cache" \
        XDG_DATA_HOME="$phase/data" XDG_RUNTIME_DIR="$root/runtime" TMPDIR="$phase/tmp" FLEA_BIN="$PWD/target/debug/flea" \
        FLEA_PICKER="$request" FLEA_PICKER_REPLY="$phase/reply.json" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic \
        QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 timeout 25 qs -p "$root/config" 2>&1) || status=$?
    printf 'picker-folder: %s %s %s\n' "$probe" "$mode" "$view"
    printf '%s\n' "$output" | grep -E 'PICKERFOLDER|FOLDERSTATE' || true
    warnings=$(printf '%s\n' "$output" | grep -aE 'WARN|ERROR|TypeError|ReferenceError|Cannot assign' \
        | grep -vF '$HYPRLAND_INSTANCE_SIGNATURE is unset. Cannot connect to hyprland.' \
        | grep -vF 'This plugin does not support setting window masks' || true)
    if [[ "$status" != 0 && "$status" != 143 ]] || [[ -n "$warnings" ]] \
        || ! printf '%s\n' "$output" | grep -aqE '(PICKERFOLDER|FOLDERSTATE) DONE checks=[1-9][0-9]* failed=0'; then
        printf '%s\n' "$output"
        echo 'FAIL picker-folder: missing clean completion'
        exit 1
    fi
    [ "$probe" = picker-folder ] || return 0
    [[ -d "$phase/home/Downloads/Reports 雪" ]] || { echo 'FAIL directory not created'; exit 1; }
    [[ ! -e "$phase/home/Downloads/Reports 雪/download.zip" ]] || { echo 'FAIL save contents written'; exit 1; }
    [[ ! -e "$phase/home/Downloads/Reports 雪/Never created" ]] || { echo 'FAIL cancellation created a directory'; exit 1; }
    /usr/bin/python3 - "$phase/reply.json" "$mode" "$phase/home/Downloads/Reports 雪" <<'PY'
import json,sys,urllib.parse
reply=json.load(open(sys.argv[1]))
if sys.argv[2] in ('files','folder','folders','savefiles'):
    assert reply['response'] == 0, 'Current or retained selection must remain selectable'
    expected=sys.argv[3]
    if sys.argv[2] in ('files','folders'):
        expected=expected.rsplit('/',1)[0] + ('/keep.txt' if sys.argv[2]=='files' else '/existing')
    assert [urllib.parse.unquote(urllib.parse.urlsplit(uri).path) for uri in reply['uris']] == [expected], reply
else:
    assert reply['response'] == 1, 'Picker must remain cancellable after folder creation'
PY
}
for mode in save open files folder folders savefiles; do
    for view in list grid; do run_probe picker-folder "$mode" "$view"; done
done
run_probe picker-folder-state save list
printf 'picker-folder: 12 mode/view cases and state checks passed\n'
