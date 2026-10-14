#!/usr/bin/env bash
# Runs ShogoFPS against the stand-in Client.exe under Wine.
# Needs: i686-w64-mingw32-gcc, wine (32-bit support), python3.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
WORK="$(mktemp -d)"
export WINEDEBUG=-all
export WINEPREFIX="${WINEPREFIX:-$WORK/prefix}"
CC=i686-w64-mingw32-gcc
CFLAGS="-O2 -mfpmath=387 -mno-sse"

fail=0
pass=0

# build_fake <dir> [extra flags]: a client.exe in its own folder, next to the plugin
build_fake() {
    local dir="$WORK/$1"; shift
    mkdir -p "$dir"
    cp "$ROOT/dist/ShogoFPS.asi" "$dir/" || { echo "build dist/ShogoFPS.asi first"; exit 1; }
    $CC $CFLAGS "$@" "$HERE/fake_client.c" -o "$dir/client.exe" -lwinmm || exit 1
}

# run <name> <exe path relative to WORK> <ini lines or -> -- <args...>
run() {
    local name="$1" exe="$2" ini="$3"; shift 4
    local dir="$WORK/$(dirname "$exe")"
    rm -f "$dir/ShogoFPS.log" "$dir/ShogoFPS.ini"
    [ "$ini" != "-" ] && printf '[ShogoFPS]\n%b\n' "$ini" > "$dir/ShogoFPS.ini"
    (cd "$dir" && timeout 300 wine "$(basename "$exe")" "$@" > "$WORK/$name.out" 2>&1)
    if [ -f "$dir/ShogoFPS.log" ]; then cp "$dir/ShogoFPS.log" "$WORK/$name.log"; else rm -f "$WORK/$name.log"; fi
}

# check <name> <python expression over r (RESULT dict) and log (str)>
check() {
    local name="$1" expr="$2"
    if python3 - "$WORK/$name.out" "$WORK/$name.log" "$expr" <<'EOF'
import sys, re, os
out, logf, expr = sys.argv[1:4]
txt = open(out).read()
m = re.search(r"RESULT (.*)", txt)
if not m:
    print("  no RESULT line:", txt.strip()[:300]); sys.exit(1)
r = {k: float(v) for k, v in (kv.split("=") for kv in m.group(1).split())}
log = open(logf).read() if os.path.exists(logf) else ""
ok = eval(expr)
if not ok:
    print("  RESULT", m.group(1))
    if log: print("  log tail:\n    " + "\n    ".join(log.strip().splitlines()[-10:]))
sys.exit(0 if ok else 1)
EOF
    then echo "PASS $name"; pass=$((pass+1)); else echo "FAIL $name  ($expr)"; fail=$((fail+1)); fi
}

build_fake std
build_fake decoy -DDECOY_CLAMP
build_fake badlayout -DBAD_LAYOUT
build_fake nofocus -DNO_FOCUS_ANCHOR
build_fake twocallers -DTWO_CALLERS
cp "$WORK/std/client.exe" "$WORK/std/other.exe"
$CC -O2 -shared "$HERE/fake_object.c" -o "$WORK/std/object.lto" || exit 1
build_fake notwin
$CC -O2 -shared -DNO_TWIN "$HERE/fake_object.c" -o "$WORK/notwin/object.lto" || exit 1

SPEED_OK='0.98 <= r["ratio"] <= 1.03 and r["errors"] == 0'
FAST='r["ratio"] > 2.2'
MOUSE_OK='r["ahead"] == 0 and r["backwards"] == 0 and r["still"] < 0.1 * r["reads"] and r["maxlag"] <= 26'

run baseline std/client.exe - -- --no-load --frames 1500 --frame-ms 4
check baseline "$FAST and r['errors'] == 0 and r['still'] > 0.5 * r['reads']"

run fix_250 std/client.exe - -- --frames 1500 --frame-ms 4
check fix_250 "$SPEED_OK and $MOUSE_OK and 'server tick fix ON, mouse fix ON' in log \
  and 'self-check ok (0/32' in log and 'fine clock active' in log and 'catch-up 0' in log"

run fix_60 std/client.exe - -- --frames 400 --frame-ms 16.667
check fix_60 "$SPEED_OK and 'skipped 0,' in log"

run fix_1000 std/client.exe - -- --frames 5000 --frame-ms 1
check fix_1000 "$SPEED_OK and r['ahead'] == 0 and r['backwards'] == 0"

run fix_jitter std/client.exe - -- --frames 1500 --jitter
check fix_jitter "$SPEED_OK and $MOUSE_OK"

run inactive std/client.exe - -- --frames 1000 --frame-ms 4 --inactive 200 600 --freeze
check inactive "r['errors'] == 0 and r['inactive_updates'] == r['inactive_frames'] == 400"

run frozen_alwaysfocused std/client.exe - -- --frames 2500 --frame-ms 4 --inactive 500 2000 --freeze --focus-lock
check frozen_alwaysfocused "r['errors'] == 0 and 0.9 <= r['span_speed'] <= 1.1 and re.search(r'frozen-clock [1-9]', log)"

run level_load std/client.exe - -- --frames 2000 --frame-ms 4 --load-at 800
check level_load "r['errors'] == 0 and re.search(r'game speed x(0\.9[89]|1\.0[0-2])', log)"

run pc24_7days std/client.exe - -- --frames 1500 --frame-ms 4 --pc24 --qpc-days 7
check pc24_7days "$SPEED_OK and $MOUSE_OK and 'fine clock active' in log and '24-bit' in log"

run pc24_13days std/client.exe - -- --frames 1500 --frame-ms 4 --pc24 --qpc-days 13
check pc24_13days "$SPEED_OK and $MOUSE_OK and 'fine clock active' in log and 'valve 0,' in log"

run diagnose std/client.exe 'DiagnoseOnly=1' -- --frames 1500 --frame-ms 4
check diagnose "$FAST and 'DIAGNOSE ONLY' in log and re.search(r'unpatched engine would run x2\.[3-6]', log) \
  and r['still'] > 0.5 * r['reads']"

run min_tick_16 std/client.exe 'MinTickMs=16' -- --frames 1500 --frame-ms 4
check min_tick_16 "$SPEED_OK and r['updates'] < 1500 * 4 / 16 + 20"

run strict std/client.exe 'Strict=1' -- --frames 1500 --frame-ms 4
check strict "$SPEED_OK and 'server tick fix ON, mouse fix ON' in log"

run timer_off std/client.exe 'TimerResolution=0' -- --frames 1500 --frame-ms 4
check timer_off "$SPEED_OK and r['ahead'] == 0"

run all_off std/client.exe 'ServerTickFix=0\nMouseFix=0' -- --frames 1500 --frame-ms 4
check all_off "$FAST and 'server tick fix off, mouse fix off' in log"

run decoy decoy/client.exe - -- --frames 1500 --frame-ms 4
check decoy "$FAST and 'clamp candidates' in log and 'mouse fix ON' in log and r['errors'] == 0"

run bad_layout badlayout/client.exe - -- --frames 1500 --frame-ms 4
check bad_layout "r['ratio'] > 2.0 and r['errors'] == 0 and 'self-check FAILED' in log and 'self-check ok' not in log"

run bad_layout_diag badlayout/client.exe 'DiagnoseOnly=1' -- --frames 1500 --frame-ms 4
check bad_layout_diag "'would be disabled (diagnose mode)' in log and 'self-check ok' not in log"

run no_focus_anchor nofocus/client.exe - -- --frames 1500 --frame-ms 4
check no_focus_anchor "$FAST and r['errors'] == 0 and \"anchor 'alwaysfocused' missing\" in log and 'mouse fix ON' in log"

run two_callers twocallers/client.exe - -- --frames 1500 --frame-ms 4
check two_callers "$FAST and r['errors'] == 0 and 'candidate update functions' in log"

LOGDIR_UNIX="$WORK/logs on D/shogo"
LOGDIR_WIN="$(winepath -w "$LOGDIR_UNIX" 2>/dev/null)"
run log_dir std/client.exe "LogDir=${LOGDIR_WIN//\\/\\\\}" -- --frames 600 --frame-ms 4  # run() expands \\ escapes
cp "$LOGDIR_UNIX/ShogoFPS.log" "$WORK/log_dir.log" 2>/dev/null
check log_dir "r['ratio'] < 1.03 and 'server tick fix ON' in log and os.path.exists(r'$LOGDIR_UNIX/ShogoFPS.log')"
rm -rf "$WORK/logs on D"

run other_process std/other.exe - -- --frames 600 --frame-ms 4
check other_process "$FAST and log == ''"

# No critical hits on the player: patched once the game code loads, enemies keep theirs.
run crit std/client.exe - -- --crit
check crit "r['crit_player'] == 10 and r['crit_ai'] == 40 and r['miss_player'] == 10 and r['miss_ai'] == 10 and 'critical hits on the player are off' in log"
run crit_off std/client.exe "NoPlayerCrits=0" -- --crit
check crit_off "r['crit_player'] == 40 and r['crit_ai'] == 40"
run crit_diag std/client.exe "DiagnoseOnly=1" -- --crit
check crit_diag "r['crit_player'] == 40 and 'DIAGNOSE ONLY, critical hits' in log"
run crit_notwin notwin/client.exe - -- --crit
check crit_notwin "r['crit_player'] == 40 and r['crit_ai'] == 40 and 'IsPlayer found 0 times' in log"

echo "$pass passed, $fail failed  (work dir: $WORK)"
[ "$fail" -eq 0 ]
