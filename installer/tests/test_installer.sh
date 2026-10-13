#!/usr/bin/env bash
# Functional test of Install-ShogoMods.ps1 with PowerShell 7 on Linux, against a fake
# game folder. Downloads the real components. Windows-only parts (display query,
# shortcut, Windows tar) are bypassed with parameters; .rar goes through 7z.
# Usage: PWSH=/path/to/pwsh installer/tests/test_installer.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
INST="$(dirname "$HERE")"
PWSH="${PWSH:-pwsh}"
WORK="$(mktemp -d)"
GAME="$WORK/Game Folder"   # no "shogo" in the name: the auto-search must not find test folders
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
ini_get() { # file section key
    awk -v s="[$2]" -v k="$3" 'BEGIN{IGNORECASE=1} {sub(/\r$/,"")} $0==s{ins=1;next} /^\[/{ins=0}
        ins && $0 ~ "^[ \t]*"k"[ \t]*=" {sub(/^[^=]*=[ \t]*/,""); print; exit}' "$1"
}
run() { (cd "$WORK" && POWERSHELL_TELEMETRY_OPTOUT=1 "$PWSH" -NoProfile -NonInteractive -File "$INST/Install-ShogoMods.ps1" \
        -GameDir "$GAME" -ScreenWidth 2560 -ScreenHeight 1440 -RefreshRate 144 "$@" > "$WORK/out.txt" 2>&1); echo $? > "$WORK/rc"; }

mkdir -p "$GAME"
printf 'MZ fake client' > "$GAME/Client.exe"
printf 'rez' > "$GAME/SHOGO.REZ"; printf 'rez' > "$GAME/SOUND.REZ"
printf 'original dinput' > "$GAME/dinput.dll"   # a pre-existing file must be backed up and restored
cat > "$GAME/autoexec.cfg" <<'EOF'
"renderdll" "d3d.ren"
"carddesc" "Primary Display Driver"
"screenwidth" "640"
"screenheight" "480"
"MaxFps" "30"
"maxfps" "0"
rangebind "##mouse" "##x-axis" 0.000000 0.000000 "Axis1"
"MusicEnable" "1.000000"
EOF
cp "$GAME/autoexec.cfg" "$WORK/autoexec.orig"

# --- install ---
run
check "install exit code 0" '[ "$(cat $WORK/rc)" = 0 ]'
grep -q "Installation terminée" "$WORK/out.txt" || { cat "$WORK/out.txt"; }
check "dinput.dll = dinputto8" '[ "$(sha "$GAME/dinput.dll")" = f96bb1101e23a6477043a3859cbf875a990eaa62ee6849f87e967b3dd963f781 ]'
check "DDraw.dll = dgVoodoo x86" '[ "$(sha "$GAME/DDraw.dll")" = 612a24408a090a3c6f3886557fa18034ee742e94ad0a40ebdf854d2816176c2e ]'
check "D3DImm.dll = dgVoodoo x86" '[ "$(sha "$GAME/D3DImm.dll")" = 93c534f2d17419ea78f15551f7e0aac78b3c503733a840914fa063708a5afe8e ]'
check "no D3D8/D3D9 copied" '[ ! -e "$GAME/D3D8.dll" ] && [ ! -e "$GAME/D3D9.dll" ]'
check "winmm.dll = ASI loader" '[ "$(sha "$GAME/winmm.dll")" = d5a059aa467a7a7127c8f6169f79fa63ff0f55986ee9eb2fd9a281bebf2aa2e6 ]'
check "FOV fix .asi" '[ "$(sha "$GAME/ShogoMobileArmorDivisionFOVFix.asi")" = edffb76ceb6f2491893f5942e7899fad86c5d2577b9fe1cf61b907317608dbe8 ]'
check "FOV ini ascii/crlf/no BOM, enabled" 'ascii_crlf_nobom "$GAME/ShogoMobileArmorDivisionFOVFix.ini" && [ "$(ini_get "$GAME/ShogoMobileArmorDivisionFOVFix.ini" FOVFix Enabled)" = true ]'
check "ShogoFPS.asi copied" 'cmp -s "$GAME/ShogoFPS.asi" "$INST/../dist/ShogoFPS.asi"'
check "ShogoFPS.ini copied" 'cmp -s "$GAME/ShogoFPS.ini" "$INST/../dist/ShogoFPS.ini"'
C="$GAME/dgVoodoo.conf"
check "dgVoodoo.conf ascii/crlf/no BOM" 'ascii_crlf_nobom "$C"'
check "dgVoodoo DirectX Resolution=max (Glide untouched)" '[ "$(ini_get "$C" DirectX Resolution)" = max ] && [ "$(ini_get "$C" Glide Resolution)" = unforced ]'
check "dgVoodoo DirectX AA 4x (Glide untouched)" '[ "$(ini_get "$C" DirectX Antialiasing)" = 4x ] && [ "$(ini_get "$C" Glide Antialiasing)" = appdriven ]'
check "dgVoodoo VRAM/filtering/watermark/screen mode" '[ "$(ini_get "$C" DirectX VRAM)" = 2048 ] && [ "$(ini_get "$C" DirectX Filtering)" = 16 ] && [ "$(ini_get "$C" DirectX dgVoodooWatermark)" = false ] && [ "$(ini_get "$C" DirectX AppControlledScreenMode)" = false ]'
check "dgVoodoo scaling stretched_ar" '[ "$(ini_get "$C" General ScalingMode)" = stretched_ar ]'
check "dgVoodoo enumerated modes (few, 16-bit)" '[ "$(ini_get "$C" DirectXExt DefaultEnumeratedResolutions)" = none ] && [ "$(ini_get "$C" DirectXExt ExtraEnumeratedResolutions)" = "640x480, 800x600, 1024x768, 1280x720, 2560x1440" ] && [ "$(ini_get "$C" DirectXExt EnumeratedResolutionBitdepths)" = 16 ]'
A="$GAME/autoexec.cfg"
check "autoexec ascii/crlf/no BOM" 'ascii_crlf_nobom "$A"'
check "autoexec resolution 1280x720" 'grep -qx $'"'"'"screenwidth" "1280"\r'"'"' "$A" && grep -qx $'"'"'"screenheight" "720"\r'"'"' "$A"'
check "autoexec single MaxFPS 141" '[ "$(grep -ci "maxfps" "$A")" = 1 ] && grep -qx $'"'"'"MaxFPS" "141"\r'"'"' "$A"'
check "autoexec keeps binds and renderer" 'grep -q "rangebind" "$A" && grep -q "\"renderdll\" \"d3d.ren\"" "$A"'
check "temp folder removed" '[ ! -e "$GAME/ShogoMods_Temp" ]'
check "manifest written" '[ -f "$GAME/ShogoMods_Backup/manifest.json" ]'
check "original dinput.dll backed up" '[ "$(cat "$GAME/ShogoMods_Backup/originals/dinput.dll")" = "original dinput" ]'

# --- second run: nothing to download, nothing changes ---
cp "$C" "$WORK/conf1"; cp "$A" "$WORK/auto1"
run
check "rerun exit code 0" '[ "$(cat $WORK/rc)" = 0 ]'
check "rerun reports components in place" '[ "$(grep -c "déjà en place" "$WORK/out.txt")" -ge 4 ]'
check "rerun keeps config stable" 'cmp -s "$C" "$WORK/conf1" && cmp -s "$A" "$WORK/auto1"'
check "rerun keeps first backup" '[ "$(cat "$GAME/ShogoMods_Backup/originals/dinput.dll")" = "original dinput" ]'

# --- native resolution variant ---
run -NativeResolution
check "native: dgVoodoo unforced + game 2560x1440" '[ "$(ini_get "$C" DirectX Resolution)" = unforced ] && grep -qx $'"'"'"screenwidth" "2560"\r'"'"' "$A"'

# --- uninstall ---
run -Uninstall
check "uninstall exit code 0" '[ "$(cat $WORK/rc)" = 0 ]'
check "uninstall restores dinput.dll" '[ "$(cat "$GAME/dinput.dll")" = "original dinput" ]'
check "uninstall restores autoexec.cfg" 'cmp -s "$GAME/autoexec.cfg" "$WORK/autoexec.orig"'
check "uninstall removes added files" 'for f in DDraw.dll D3DImm.dll dgVoodoo.conf dgVoodooCpl.exe winmm.dll ShogoFPS.asi ShogoFPS.ini ShogoMobileArmorDivisionFOVFix.asi ShogoMobileArmorDivisionFOVFix.ini ShogoMods_Backup; do [ ! -e "$GAME/$f" ] || exit 1; done'
check "game files untouched" '[ "$(cat "$GAME/Client.exe")" = "MZ fake client" ] && [ -f "$GAME/SHOGO.REZ" ]'

# --- wrong folder, and no game anywhere to fall back on ---
mv "$GAME" "$WORK/hidden"
(cd "$WORK" && POWERSHELL_TELEMETRY_OPTOUT=1 "$PWSH" -NoProfile -NonInteractive -File "$INST/Install-ShogoMods.ps1" \
    -GameDir "$WORK/nothing" -ScreenWidth 2560 -ScreenHeight 1440 < /dev/null > "$WORK/out2.txt" 2>&1); rc=$?
check "bad folder fails cleanly" '[ $rc -ne 0 ] && grep -q "ERREUR" "$WORK/out2.txt" && [ ! -e "$WORK/hidden/dinput.dll.bak" ]'

echo "$pass passed, $fail failed  (work dir: $WORK)"
[ "$fail" -eq 0 ]
