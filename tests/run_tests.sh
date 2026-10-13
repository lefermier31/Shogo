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

build_fake() { # $1 = output name, rest = extra flags
    local out="$1"; shift
    $CC $CFLAGS "$@" "$HERE/fake_client.c" -o "$WORK/$out" -lwinmm || exit 1
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
    if log: print("  log tail:\n    " + "\n    ".join(log.strip().splitlines()[-8:]))
sys.exit(0 if ok else 1)
EOF
    then echo "PASS $name"; pass=$((pass+1)); else echo "FAIL $name  ($expr)"; fail=$((fail+1)); fi
}

cp "$ROOT/dist/ShogoFPS.asi" "$WORK/" || { echo "build dist/ShogoFPS.asi first"; exit 1; }
build_fake client.exe
mkdir -p "$WORK/decoy" && cp "$WORK/ShogoFPS.asi" "$WORK/decoy/"
build_fake decoy/client.exe -DDECOY_CLAMP

SPEED_OK='0.98 <= r["ratio"] <= 1.03 and r["errors"] == 0'
FAST='r["ratio"] > 2.2'

run baseline client.exe - -- --no-load --frames 1500 --frame-ms 4
check baseline "$FAST and r['errors'] == 0"

run fix_250 client.exe - -- --frames 1500 --frame-ms 4
check fix_250 "$SPEED_OK and 'server tick fix ON, mouse fix ON' in log and 'self-check ok' in log \
  and r['ahead'] == 0 and r['backwards'] == 0 and r['still'] < 0.1 * r['reads']"

run fix_60 client.exe - -- --frames 400 --frame-ms 16.667
check fix_60 "$SPEED_OK and 'skipped 0,' in log"

run fix_1000 client.exe - -- --frames 5000 --frame-ms 1
check fix_1000 "$SPEED_OK and r['ahead'] == 0 and r['backwards'] == 0"

run fix_jitter client.exe - -- --frames 1500 --jitter
check fix_jitter "$SPEED_OK"

run fix_inactive client.exe - -- --frames 1000 --frame-ms 4 --inactive 200 600
check fix_inactive "r['errors'] == 0 and r['inactive_updates'] == r['inactive_frames'] == 400"

run diagnose client.exe 'DiagnoseOnly=1' -- --frames 1500 --frame-ms 4
check diagnose "$FAST and 'DIAGNOSE ONLY' in log and re.search(r'unpatched engine would run x2\.[3-6]', log) \
  and r['still'] > 0.3 * r['reads']"

run min_tick_16 client.exe 'MinTickMs=16' -- --frames 1500 --frame-ms 4
check min_tick_16 "$SPEED_OK and r['updates'] < 1500 * 4 / 16 + 20"

run strict client.exe 'Strict=1' -- --frames 1500 --frame-ms 4
check strict "$SPEED_OK and 'server tick fix ON, mouse fix ON' in log"

run all_off client.exe 'ServerTickFix=0\nMouseFix=0' -- --frames 1500 --frame-ms 4
check all_off "$FAST and 'server tick fix off, mouse fix off' in log"

run decoy decoy/client.exe - -- --frames 1500 --frame-ms 4
check decoy "$FAST and 'clamp candidates' in log and 'mouse fix ON' in log and r['errors'] == 0"

cp "$WORK/client.exe" "$WORK/other.exe"
run other_process other.exe - -- --frames 600 --frame-ms 4
check other_process "$FAST and log == ''"

echo "$pass passed, $fail failed  (work dir: $WORK)"
[ "$fail" -eq 0 ]
