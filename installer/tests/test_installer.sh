#!/usr/bin/env bash
# Functional test of Install-ShogoMods.ps1 with PowerShell 7 on Linux, against fake game
# folders. Downloads the real components. Windows-only parts (display query, shortcut,
# Windows tar, 7-Zip/WinRAR lookup in Program Files) are bypassed with parameters; the .rar
# is opened by bsdtar, which must be installed (Debian's 7z has no RAR codec).
# Usage: PWSH=/path/to/pwsh installer/tests/test_installer.sh   (KEEP_WORK=1 keeps the work dir)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
INST="$(dirname "$HERE")"
PWSH="$(command -v "${PWSH:-pwsh}")"
WORK="$(mktemp -d)"
trap '[ "${KEEP_WORK:-0}" = 1 ] || rm -rf "$WORK"' EXIT
GAME="$WORK/Game Folder"   # no "shogo" in the names: nothing here must look like a real install
fail=0; pass=0

ok()   { echo "PASS $1"; pass=$((pass+1)); }
ko()   { echo "FAIL $1"; fail=$((fail+1)); }
check() { if eval "$2"; then ok "$1"; else ko "$1"; fi; }
sha()  { sha256sum "$1" | cut -d' ' -f1; }
ascii_crlf_nobom() { # no BOM, only CRLF line ends, pure ASCII
    [ "$(head -c 3 "$1" | od -An -tx1 | tr -d ' \n')" != "efbbbf" ] &&
    ! LC_ALL=C grep -q -P '[^\x00-\x7F]' "$1" &&
    [ "$(grep -c $'\r$' "$1")" -eq "$(wc -l < "$1")" ]
}
crlf_nobom() {
    [ "$(head -c 3 "$1" | od -An -tx1 | tr -d ' \n')" != "efbbbf" ] &&
    [ "$(grep -c $'\r$' "$1")" -eq "$(wc -l < "$1")" ]
}
ini_get() { # file section key
    awk -v s="[$2]" -v k="$3" 'BEGIN{IGNORECASE=1} {sub(/\r$/,"")} $0==s{ins=1;next} /^\[/{ins=0}
        ins && $0 ~ "^[ \t]*"k"[ \t]*=" {sub(/^[^=]*=[ \t]*/,""); print; exit}' "$1"
}
cfg_line() { LC_ALL=C grep -qxaF "$2"$'\r' "$1"; }   # exact autoexec.cfg line
all_absent() { local d="$1"; shift; for f in "$@"; do [ ! -e "$d/$f" ] || return 1; done; }

SCREEN_ARGS="-ScreenWidth 2560 -ScreenHeight 1440 -RefreshRate 144"
# run_in <game dir> <script> [args...]: output in $WORK/out.txt, exit code in $WORK/rc.
# RUN_PATH replaces PATH for PowerShell only; EXPECT_FAIL=1 hides the output of a failure.
run_in() {
    local g="$1" script="$2"; shift 2
    # shellcheck disable=SC2086
    (cd "$WORK" && env POWERSHELL_TELEMETRY_OPTOUT=1 ${RUN_PATH:+PATH="$RUN_PATH"} "$PWSH" -NoProfile -NonInteractive \
        -File "$script" -GameDir "$g" -NoSearch $SCREEN_ARGS "$@" < /dev/null > "$WORK/out.txt" 2>&1)
    echo $? > "$WORK/rc"
    if [ "$(cat "$WORK/rc")" != 0 ] && [ "${EXPECT_FAIL:-0}" != 1 ]; then sed 's/^/    | /' "$WORK/out.txt"; fi
}
run() { run_in "$GAME" "$INST/Install-ShogoMods.ps1" "$@"; }
rc0() { [ "$(cat "$WORK/rc")" = 0 ]; }

# The game writes autoexec.cfg in ANSI (cp1252): this 0xE9 byte must survive the edits.
ANSI_NAME="\"NetPlayerName\" \"S$(printf '\351')bastien\""
new_game() { # dir: a fake game folder
    mkdir -p "$1"
    printf 'MZ fake client' > "$1/Client.exe"
    printf 'rez' > "$1/SHOGO.REZ"; printf 'rez' > "$1/SOUND.REZ"
    printf '%s\r\n' '"renderdll" "d3d.ren"' '"carddesc" "Primary Display Driver"' '"screenwidth" "640"' \
        '"screenheight" "480"' '"MaxFps" "30"' '"maxfps" "0"' '"GlobalDetail" "1.000000"' "$ANSI_NAME" \
        'rangebind "##mouse" "##x-axis" 0.000000 0.000000 "Axis1"' '"MusicEnable" "1.000000"' > "$1/autoexec.cfg"
}

new_game "$GAME"
printf 'original dinput' > "$GAME/dinput.dll"   # a pre-existing file must be backed up and restored
cp "$GAME/autoexec.cfg" "$WORK/autoexec.orig"

# --- install ---
run
check "install exit code 0" 'rc0 && grep -q "Installation complete" "$WORK/out.txt"'
check "dinput.dll = dinputto8" '[ "$(sha "$GAME/dinput.dll")" = f96bb1101e23a6477043a3859cbf875a990eaa62ee6849f87e967b3dd963f781 ]'
check "DDraw.dll = dgVoodoo x86" '[ "$(sha "$GAME/DDraw.dll")" = 612a24408a090a3c6f3886557fa18034ee742e94ad0a40ebdf854d2816176c2e ]'
check "D3DImm.dll = dgVoodoo x86" '[ "$(sha "$GAME/D3DImm.dll")" = 93c534f2d17419ea78f15551f7e0aac78b3c503733a840914fa063708a5afe8e ]'
check "no D3D8/D3D9 copied" 'all_absent "$GAME" D3D8.dll D3D9.dll'
check "winmm.dll = ASI loader" '[ "$(sha "$GAME/winmm.dll")" = d5a059aa467a7a7127c8f6169f79fa63ff0f55986ee9eb2fd9a281bebf2aa2e6 ]'
check "FOV fix .asi" '[ "$(sha "$GAME/ShogoMobileArmorDivisionFOVFix.asi")" = edffb76ceb6f2491893f5942e7899fad86c5d2577b9fe1cf61b907317608dbe8 ]'
check "FOV ini ascii/crlf/no BOM, enabled" 'ascii_crlf_nobom "$GAME/ShogoMobileArmorDivisionFOVFix.ini" && [ "$(ini_get "$GAME/ShogoMobileArmorDivisionFOVFix.ini" FOVFix Enabled)" = true ]'
check "ShogoFPS.asi copied" 'cmp -s "$GAME/ShogoFPS.asi" "$INST/../dist/ShogoFPS.asi"'
check "ShogoFPS.ini copied" 'cmp -s "$GAME/ShogoFPS.ini" "$INST/../dist/ShogoFPS.ini"'
C="$GAME/dgVoodoo.conf"
check "dgVoodoo.conf ascii/crlf/no BOM" 'ascii_crlf_nobom "$C"'
check "dgVoodoo DirectX Resolution max at 144 Hz (Glide untouched)" '[ "$(ini_get "$C" DirectX Resolution)" = "max, refrate:144" ] && [ "$(ini_get "$C" Glide Resolution)" = unforced ]'
check "dgVoodoo DirectX AA 4x (Glide untouched)" '[ "$(ini_get "$C" DirectX Antialiasing)" = 4x ] && [ "$(ini_get "$C" Glide Antialiasing)" = appdriven ]'
check "dgVoodoo VRAM/filtering/watermark/screen mode" '[ "$(ini_get "$C" DirectX VRAM)" = 256 ] && [ "$(ini_get "$C" DirectX Filtering)" = 16 ] && [ "$(ini_get "$C" DirectX dgVoodooWatermark)" = false ] && [ "$(ini_get "$C" DirectX AppControlledScreenMode)" = false ]'
check "dgVoodoo frame cap 141" '[ "$(ini_get "$C" GeneralExt FPSLimit)" = 141 ]'
check "dgVoodoo scaling stretched_ar" '[ "$(ini_get "$C" General ScalingMode)" = stretched_ar ]'
check "dgVoodoo enumerated modes (3, 16-bit)" '[ "$(ini_get "$C" DirectXExt DefaultEnumeratedResolutions)" = none ] && [ "$(ini_get "$C" DirectXExt ExtraEnumeratedResolutions)" = "640x480, 1280x720, 2560x1440" ] && [ "$(ini_get "$C" DirectXExt EnumeratedResolutionBitdepths)" = 16 ]'
A="$GAME/autoexec.cfg"
check "autoexec crlf/no BOM" 'crlf_nobom "$A"'
check "autoexec keeps ANSI bytes" 'cfg_line "$A" "$ANSI_NAME"'
check "autoexec resolution 1280x720" 'cfg_line "$A" "\"screenwidth\" \"1280\"" && cfg_line "$A" "\"screenheight\" \"720\""'
check "autoexec single MaxFPS 0 (engine limiter off)" '[ "$(grep -aci "maxfps" "$A")" = 1 ] && cfg_line "$A" "\"MaxFPS\" \"0\""'
check "autoexec detail raised to 2" 'cfg_line "$A" "\"GlobalDetail\" \"2.000000\""'
check "autoexec keeps binds and renderer" 'grep -aq "rangebind" "$A" && grep -aq "\"renderdll\" \"d3d.ren\"" "$A"'
check "temp folder removed" '[ ! -e "$GAME/ShogoMods_Temp" ]'
check "manifest written, no leftover .tmp" '[ -f "$GAME/ShogoMods_Backup/manifest.json" ] && [ ! -e "$GAME/ShogoMods_Backup/manifest.json.tmp" ]'
check "manifest records binary hashes" 'grep -q d5a059aa467a7a7127c8f6169f79fa63ff0f55986ee9eb2fd9a281bebf2aa2e6 "$GAME/ShogoMods_Backup/manifest.json"'
check "original dinput.dll backed up" '[ "$(cat "$GAME/ShogoMods_Backup/originals/dinput.dll")" = "original dinput" ]'

# --- second run: nothing to download, nothing changes ---
cp "$C" "$WORK/conf1"; cp "$A" "$WORK/auto1"
run
check "rerun exit code 0" 'rc0'
check "rerun: components in place, no download" '[ "$(grep -c "already in place" "$WORK/out.txt")" -ge 4 ] && ! grep -q "Downloading" "$WORK/out.txt"'
check "rerun keeps config stable" 'cmp -s "$C" "$WORK/conf1" && cmp -s "$A" "$WORK/auto1"'
check "rerun keeps first backup" '[ "$(cat "$GAME/ShogoMods_Backup/originals/dinput.dll")" = "original dinput" ]'

# --- custom details (3) and the player's ShogoFPS.ini are kept ---
sed -i 's/"GlobalDetail" "2.000000"/"GlobalDetail" "3.000000"/' "$A"
printf '[ShogoFPS]\r\nMinTickMs=12\r\n' > "$GAME/ShogoFPS.ini"
run
check "custom detail 3 kept" 'cfg_line "$A" "\"GlobalDetail\" \"3.000000\""'
check "player ShogoFPS.ini kept" 'grep -q "MinTickMs=12" "$GAME/ShogoFPS.ini"'

# --- -NoFovFix turns an installed FOV fix off ---
run -NoFovFix
check "-NoFovFix: Enabled=false, asi left" '[ "$(ini_get "$GAME/ShogoMobileArmorDivisionFOVFix.ini" FOVFix Enabled)" = false ] && [ -f "$GAME/ShogoMobileArmorDivisionFOVFix.asi" ]'
run
check "without -NoFovFix: enabled again" '[ "$(ini_get "$GAME/ShogoMobileArmorDivisionFOVFix.ini" FOVFix Enabled)" = true ]'

# --- native resolution variant ---
run -NativeResolution
check "native: dgVoodoo 2560x1440@144, game 2560x1440" '[ "$(ini_get "$C" DirectX Resolution)" = "2560x1440@144" ] && cfg_line "$A" "\"screenwidth\" \"2560\"" && [ "$(ini_get "$C" DirectXExt ExtraEnumeratedResolutions)" = "640x480, 2560x1440" ]'

# --- 1080 lines is not a whole multiple of 720: native, no upscale ---
SCREEN_ARGS="-ScreenWidth 1920 -ScreenHeight 1080 -RefreshRate 60" run
check "1080p 60 Hz: native, cap 60" 'cfg_line "$A" "\"screenwidth\" \"1920\"" && [ "$(ini_get "$C" DirectX Resolution)" = "1920x1080@60" ] && [ "$(ini_get "$C" GeneralExt FPSLimit)" = 60 ]'
# --- 2160p: x3 ---
SCREEN_ARGS="-ScreenWidth 3840 -ScreenHeight 2160 -RefreshRate 240" run
check "2160p 240 Hz: game 1280x720, cap 237" 'cfg_line "$A" "\"screenwidth\" \"1280\"" && [ "$(ini_get "$C" DirectX Resolution)" = "max, refrate:240" ] && [ "$(ini_get "$C" GeneralExt FPSLimit)" = 237 ]'
run

# --- uninstall ---
printf 'log' > "$GAME/ShogoFPS.log"
run -Uninstall
check "uninstall exit code 0" 'rc0'
check "uninstall restores dinput.dll" '[ "$(cat "$GAME/dinput.dll")" = "original dinput" ]'
check "uninstall restores autoexec.cfg, keeps the current one aside" 'cmp -s "$A" "$WORK/autoexec.orig" && [ -f "$A.before-uninstall" ]'
check "uninstall removes added files, logs, backups" 'all_absent "$GAME" DDraw.dll D3DImm.dll dgVoodoo.conf dgVoodooCpl.exe winmm.dll ShogoFPS.asi ShogoFPS.ini ShogoFPS.log ShogoMobileArmorDivisionFOVFix.asi ShogoMobileArmorDivisionFOVFix.ini ShogoMods_Backup ShogoMods_Temp'
check "game files untouched" '[ "$(cat "$GAME/Client.exe")" = "MZ fake client" ] && [ -f "$GAME/SHOGO.REZ" ]'
rm -f "$A.before-uninstall"

# --- a DLL replaced by another program after the install is left alone ---
run
printf 'other dgvoodoo' > "$GAME/DDraw.dll"
run -Uninstall
check "uninstall keeps a DLL changed since" 'rc0 && [ "$(cat "$GAME/DDraw.dll")" = "other dgvoodoo" ] && grep -q "DDraw.dll: replaced by another program" "$WORK/out.txt"'
check "backup folder kept for it, the rest undone" '[ -f "$GAME/ShogoMods_Backup/manifest.json" ] && [ ! -e "$GAME/winmm.dll" ] && [ "$(cat "$GAME/dinput.dll")" = "original dinput" ]'
run -Uninstall
check "second uninstall is harmless" 'rc0 && [ "$(cat "$GAME/DDraw.dll")" = "other dgvoodoo" ] && [ "$(cat "$GAME/dinput.dll")" = "original dinput" ] && cmp -s "$A" "$WORK/autoexec.orig"'
rm -rf "$GAME/ShogoMods_Backup" "$GAME/DDraw.dll" "$A.before-uninstall"

# --- backups without a manifest: stop before touching anything ---
mkdir -p "$GAME/ShogoMods_Backup/originals"; printf 'x' > "$GAME/ShogoMods_Backup/originals/dinput.dll"
EXPECT_FAIL=1 run
check "orphan backup: refuses, nothing changed" '! rc0 && grep -q "manifest is missing" "$WORK/out.txt" && grep -q "Nothing was changed" "$WORK/out.txt" && [ ! -e "$GAME/winmm.dll" ]'
rm -rf "$GAME/ShogoMods_Backup"

# --- damaged manifest: stop with a clear message ---
mkdir -p "$GAME/ShogoMods_Backup"; printf '{"Entries": [' > "$GAME/ShogoMods_Backup/manifest.json"
EXPECT_FAIL=1 run
check "damaged manifest: refuses" '! rc0 && grep -q "manifest.json is damaged" "$WORK/out.txt" && [ ! -e "$GAME/winmm.dll" ]'
rm -rf "$GAME/ShogoMods_Backup"

# --- ShogoFRESH present: only the ASI loader and ShogoFPS ---
FRESH="$WORK/Fresh Folder"
new_game "$FRESH"
printf 'fresh' > "$FRESH/ShogoFRESH.rez"
printf 'fresh dinput' > "$FRESH/dinput.dll"
for f in DDraw.dll D3DImm.dll dgVoodoo.conf; do printf "fresh $f" > "$FRESH/$f"; done
cp "$FRESH/autoexec.cfg" "$WORK/fresh_auto"
run_in "$FRESH" "$INST/Install-ShogoMods.ps1"
check "ShogoFRESH: install ok, components left to it" 'rc0 && [ "$(grep -c "left to ShogoFRESH" "$WORK/out.txt")" = 2 ]'
check "ShogoFRESH: its files untouched" '[ "$(cat "$FRESH/DDraw.dll")" = "fresh DDraw.dll" ] && [ "$(cat "$FRESH/dgVoodoo.conf")" = "fresh dgVoodoo.conf" ] && [ "$(cat "$FRESH/dinput.dll")" = "fresh dinput" ]'
check "ShogoFRESH: ASI loader + ShogoFPS, no FOV fix, autoexec untouched" '[ -f "$FRESH/winmm.dll" ] && [ -f "$FRESH/ShogoFPS.asi" ] && [ ! -e "$FRESH/ShogoMobileArmorDivisionFOVFix.asi" ] && cmp -s "$FRESH/autoexec.cfg" "$WORK/fresh_auto"'
run_in "$FRESH" "$INST/Install-ShogoMods.ps1" -Uninstall
check "ShogoFRESH: uninstall removes only ours" 'all_absent "$FRESH" winmm.dll ShogoFPS.asi ShogoMods_Backup && [ "$(cat "$FRESH/DDraw.dll")" = "fresh DDraw.dll" ]'

# --- ours first, then ShogoFRESH: its dinput.dll (same bytes as ours) stays on uninstall ---
LATE="$WORK/Late Folder"
new_game "$LATE"
run_in "$LATE" "$INST/Install-ShogoMods.ps1" -NoFovFix
printf 'fresh' > "$LATE/ShogoFRESH.rez"
run_in "$LATE" "$INST/Install-ShogoMods.ps1" -Uninstall
check "ShogoFRESH added later: its files stay" 'rc0 && [ -f "$LATE/dinput.dll" ] && [ -f "$LATE/DDraw.dll" ] && grep -q "dinput.dll: left in place, ShogoFRESH uses it" "$WORK/out.txt" && [ ! -e "$LATE/winmm.dll" ]'

# --- FOV fix gone from its release page (404, as v1.2 is today): the rest installs ---
mkdir -p "$WORK/copy404/installer"; ln -s "$INST/../dist" "$WORK/copy404/dist"
sed 's/FOV\.Fix\.v1\.3\.rar/FOV.Fix.v1.2.rar/' "$INST/Install-ShogoMods.ps1" > "$WORK/copy404/installer/Install-ShogoMods.ps1"
G404="$WORK/Folder 404"
new_game "$G404"
run_in "$G404" "$WORK/copy404/installer/Install-ShogoMods.ps1"
check "FOV 404: warning, install complete" 'rc0 && grep -q "goes on without this fix" "$WORK/out.txt" && [ -f "$G404/ShogoFPS.asi" ] && [ ! -e "$G404/ShogoMobileArmorDivisionFOVFix.asi" ] && [ "$(ini_get "$G404/dgVoodoo.conf" GeneralExt FPSLimit)" = 141 ]'

# --- no tool able to open the .rar: the rest installs ---
mkdir -p "$WORK/nobin"
GNR="$WORK/Folder NoRar"
new_game "$GNR"
RUN_PATH="$WORK/nobin" run_in "$GNR" "$INST/Install-ShogoMods.ps1"
check "no RAR tool: warning, install complete" 'rc0 && grep -q "cannot extract the .rar archive" "$WORK/out.txt" && [ -f "$GNR/ShogoFPS.asi" ] && [ ! -e "$GNR/ShogoMobileArmorDivisionFOVFix.asi" ]'

# --- no autoexec.cfg yet ---
GNA="$WORK/Folder NoCfg"
new_game "$GNA"; rm "$GNA/autoexec.cfg"
run_in "$GNA" "$INST/Install-ShogoMods.ps1" -NoFovFix
check "no autoexec.cfg: install ok, asks to start the game once" 'rc0 && grep -q "autoexec.cfg does not exist yet" "$WORK/out.txt" && [ ! -e "$GNA/autoexec.cfg" ]'

# --- wrong folder with -NoSearch: clean failure, no search ---
EXPECT_FAIL=1 run_in "$WORK/nothing" "$INST/Install-ShogoMods.ps1"
check "bad folder fails cleanly" '! rc0 && grep -q "not found in" "$WORK/out.txt" && grep -q "Nothing was changed" "$WORK/out.txt" && ! grep -q "Looking for the game" "$WORK/out.txt"'

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
