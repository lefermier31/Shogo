<#
.SYNOPSIS
    Installs the modern fixes for Shogo: Mobile Armor Division (GOG/Steam version 2.2).

.DESCRIPTION
    Downloads from the official sources (GitHub releases, SHA256 checked) and installs
    into the game folder:
      - dinputto8          : the game starts on Windows 10/11
      - dgVoodoo2 2.87.5   : modern Direct3D rendering, native resolution, filtering, antialiasing
      - Ultimate ASI Loader: loads .asi plugins (installed as winmm.dll)
      - AlphaYellow FOV fix: correct field of view in 16:9
      - ShogoFPS           : real game speed at high fps, smooth mouse
    Then configures dgVoodoo and autoexec.cfg and creates a desktop shortcut.
    Everything happens in the game folder (temporary downloads included).
    Every replaced file is backed up; -Uninstall puts everything back.
    If ShogoFRESH is installed, dinputto8, dgVoodoo, the field of view and the game
    settings are left to it: only the ASI loader and ShogoFPS are added.

.EXAMPLE
    Install-ShogoMods.bat
    Install-ShogoMods.bat -GameDir "D:\GOG Games\Shogo"
    Install-ShogoMods.bat -NativeResolution
    Uninstall-ShogoMods.bat
#>
[CmdletBinding()]
param(
    [string]$GameDir = '',
    [switch]$Uninstall,
    [switch]$NativeResolution,
    [switch]$NoFovFix,
    [switch]$NoShortcut,
    [switch]$NoSearch,
    [int]$ScreenWidth = 0,
    [int]$ScreenHeight = 0,
    [int]$RefreshRate = 0
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {
    Write-Verbose 'TLS 1.2 already enabled or not configurable'
}

$InstallerVersion = '1.1.0'
$OnWindows = ($env:OS -eq 'Windows_NT')
$BackupDirName = 'ShogoMods_Backup'
$TempDirName = 'ShogoMods_Temp'
$ShortcutName = 'Shogo (ShogoFPS).lnk'
$FovIni = 'ShogoMobileArmorDivisionFOVFix.ini'
# Files ShogoFRESH installs and updates itself.
$FreshFiles = @('dinput.dll', 'DDraw.dll', 'D3DImm.dll', 'dgVoodooCpl.exe', 'dgVoodoo.conf')
$script:Started = $false

# ---------------------------------------------------------------------------
# Components: URLs pinned to a tag, hashes checked on 2026-10-13.
# ---------------------------------------------------------------------------
$Components = @(
    @{
        Id = 'dinputto8'; Label = 'dinputto8 1.1.100.0 (starts on Windows 10/11)'; Kind = 'file'
        Url = 'https://github.com/elishacloud/dinputto8/releases/download/v1.1.100.0/dinput.dll'
        Sha256 = 'f96bb1101e23a6477043a3859cbf875a990eaa62ee6849f87e967b3dd963f781'
        Files = @(@{ Entry = ''; Dest = 'dinput.dll'; Sha256 = 'f96bb1101e23a6477043a3859cbf875a990eaa62ee6849f87e967b3dd963f781' })
    },
    @{
        Id = 'dgvoodoo2'; Label = 'dgVoodoo2 2.87.5 (modern rendering)'; Kind = 'zip'
        Url = 'https://github.com/dege-diosg/dgVoodoo2/releases/download/v2.87.5/dgVoodoo2_87_5.zip'
        Sha256 = '5ffde6927f7355ca3fdd5d785b581256a8e6539fa13e395a891ade6ba1040850'
        Files = @(
            @{ Entry = 'MS/x86/DDraw.dll'; Dest = 'DDraw.dll'; Sha256 = '612a24408a090a3c6f3886557fa18034ee742e94ad0a40ebdf854d2816176c2e' },
            @{ Entry = 'MS/x86/D3DImm.dll'; Dest = 'D3DImm.dll'; Sha256 = '93c534f2d17419ea78f15551f7e0aac78b3c503733a840914fa063708a5afe8e' },
            @{ Entry = 'dgVoodooCpl.exe'; Dest = 'dgVoodooCpl.exe'; Sha256 = '87fb878166dcaef3e75ff170de030527c73f5c9b164c5943da13f8a97b0b75c6' },
            @{ Entry = 'dgVoodoo.conf'; Dest = 'dgVoodoo.conf'; Sha256 = '45cc0eb8e6ed4f067aca1b2e4ac1268dfbd164bbbd06d264c53e8a60642c4dbf'; Config = $true }
        )
    },
    @{
        Id = 'asiloader'; Label = 'Ultimate ASI Loader 9.7.4 (plugin loader)'; Kind = 'zip'
        Url = 'https://github.com/ThirteenAG/Ultimate-ASI-Loader/releases/download/v9.7.4/Ultimate-ASI-Loader.zip'
        Sha256 = '952cebfc30d525afc2bdbaca954329d405ded3aa688a83027354dae14dfd5c5f'
        Files = @(@{ Entry = 'dinput8.dll'; Dest = 'winmm.dll'; Sha256 = 'd5a059aa467a7a7127c8f6169f79fa63ff0f55986ee9eb2fd9a281bebf2aa2e6' })
    },
    @{
        Id = 'fovfix'; Label = 'AlphaYellow FOV fix 1.3 (16:9 field of view)'; Kind = 'rar'
        Url = 'https://github.com/alphayellow1/AlphaYellowWidescreenFixes/releases/download/shogomobilearmordivision/Shogo.Mobile.Armor.Division.-.FOV.Fix.v1.3.rar'
        Sha256 = 'a42aea6f754e3db6b69f0ed9ff2992be81353d6e34a4643c8f62374a64d5eec6'
        Files = @(
            @{ Entry = 'ShogoMobileArmorDivisionFOVFix.asi'; Dest = 'ShogoMobileArmorDivisionFOVFix.asi'; Sha256 = 'edffb76ceb6f2491893f5942e7899fad86c5d2577b9fe1cf61b907317608dbe8' },
            @{ Entry = 'ShogoMobileArmorDivisionFOVFix.ini'; Dest = 'ShogoMobileArmorDivisionFOVFix.ini'; Sha256 = '9f1fa92923b4a121f5eee9e0e0bcd30d7b29e0561f555aafd6d7248b57eea611'; Config = $true }
        )
    }
)

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
function Write-Step([string]$Text) { Write-Host ''; Write-Host "== $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text) { Write-Host "   OK  $Text" -ForegroundColor Green }
function Write-Info([string]$Text) { Write-Host "       $Text" }
function Write-Warn([string]$Text) { Write-Host "   /!\ $Text" -ForegroundColor Yellow }

# ---------------------------------------------------------------------------
# Files
# ---------------------------------------------------------------------------
function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

# Latin-1 maps every byte to one character and back, so the game's ANSI text (accented
# player names...) survives an edit. No BOM is ever written (a BOM disables the FOV fix);
# a UTF-8 BOM found on reading is dropped. Lines end with CRLF.
$ConfigEncoding = [Text.Encoding]::GetEncoding(28591)

function Write-ConfigLines([string]$Path, [string[]]$Lines) {
    $text = ($Lines -join "`r`n") + "`r`n"
    [IO.File]::WriteAllText($Path, $text, $ConfigEncoding)
}

function Read-TextLines([string]$Path) {
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($l in [IO.File]::ReadAllLines($Path, $ConfigEncoding)) { $list.Add($l) }
    return , $list
}

# An antivirus can delete a file right after it is written: say so instead of a raw path error.
function Assert-FileWritten([string]$Path, [string]$Sha256) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$([IO.Path]::GetFileName($Path)) disappeared right after being written (antivirus?). Add an exclusion for the game folder, then run the installer again."
    }
    if ($Sha256 -and (Get-Sha256 $Path) -ne $Sha256) {
        throw "$([IO.Path]::GetFileName($Path)) changed right after being written (antivirus?). Add an exclusion for the game folder, then run the installer again."
    }
}

# ---------------------------------------------------------------------------
# Manifest: what the installer added, replaced or edited.
#   Action: added (did not exist), replaced (whole file swapped), edited (settings changed)
#   Backup: copy of the original, kept once and never overwritten
#   Hash  : SHA256 of the file the installer wrote (binaries only)
# ---------------------------------------------------------------------------
$script:Manifest = $null

function Get-BackupDir { return (Join-Path $GameDir $BackupDirName) }
function Get-ManifestPath { return (Join-Path (Get-BackupDir) 'manifest.json') }

function Read-Manifest {
    $path = Get-ManifestPath
    $entries = New-Object System.Collections.ArrayList
    $json = $null
    $found = $false
    # manifest.json.tmp alone: a save was interrupted before the rename, and it is complete.
    foreach ($p in @($path, "$path.tmp")) {
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $found = $true
        try {
            $json = [IO.File]::ReadAllText($p) | ConvertFrom-Json
            break
        } catch {
            Write-Verbose "Unreadable: $p"
        }
    }
    if ($found -and $null -eq $json) {
        throw "$BackupDirName\manifest.json is damaged, so the installer cannot tell what it changed. Nothing was changed. The original files are in $BackupDirName\originals."
    }
    if ($null -ne $json) {
        foreach ($e in @($json.Entries)) {
            $hash = ''
            if ($e.PSObject.Properties['Hash']) { $hash = [string]$e.Hash }
            [void]$entries.Add(@{ Dest = [string]$e.Dest; Action = [string]$e.Action; Backup = [string]$e.Backup; Hash = $hash })
        }
    }
    $script:Manifest = $entries
}

# Original files backed up but no manifest: starting over would back up modified files as
# "originals" and lose the real ones.
function Test-OrphanBackup {
    if ($script:Manifest.Count -gt 0) { return $false }
    $odir = Join-Path (Get-BackupDir) 'originals'
    return (Test-Path -LiteralPath $odir) -and @(Get-ChildItem -LiteralPath $odir -Force).Count -gt 0
}

function Save-Manifest {
    $dir = Get-BackupDir
    if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir) }
    $path = Get-ManifestPath
    $tmp = "$path.tmp"
    $obj = @{ Installer = $InstallerVersion; Entries = @($script:Manifest) }
    [IO.File]::WriteAllText($tmp, ($obj | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding $false))
    if (Test-Path -LiteralPath $path) { [IO.File]::Replace($tmp, $path, [NullString]::Value) } else { [IO.File]::Move($tmp, $path) }
}

function Find-ManifestEntry([string]$Dest) {
    foreach ($e in $script:Manifest) { if ($e.Dest -ieq $Dest) { return $e } }
    return $null
}

function Resolve-Dest([string]$Dest) {
    if ([IO.Path]::IsPathRooted($Dest)) { return $Dest }
    return (Join-Path $GameDir $Dest)
}

# Before any write: keep the original once (never a version we already changed).
function Register-Change([string]$Dest, [string]$Action) {
    if ($null -ne (Find-ManifestEntry $Dest)) { return }
    $full = Resolve-Dest $Dest
    $backup = ''
    if (Test-Path -LiteralPath $full) {
        $bdir = Join-Path (Get-BackupDir) 'originals'
        if (-not (Test-Path -LiteralPath $bdir)) { [void](New-Item -ItemType Directory -Path $bdir -Force) }
        $backup = Join-Path $BackupDirName (Join-Path 'originals' ([IO.Path]::GetFileName($Dest)))
        $bfull = Join-Path $GameDir $backup
        # A backup already there is older than this run (interrupted run): it is the real original.
        if (-not (Test-Path -LiteralPath $bfull)) { Copy-Item -LiteralPath $full -Destination $bfull }
    } else {
        $Action = 'added'
    }
    [void]$script:Manifest.Add(@{ Dest = $Dest; Action = $Action; Backup = $backup; Hash = '' })
    Save-Manifest
}

# Remember what we wrote, so the uninstall leaves alone a file another tool replaced since.
function Set-ManifestHash([string]$Dest, [string]$Hash) {
    $e = Find-ManifestEntry $Dest
    if ($null -ne $e -and $e.Action -ne 'edited' -and $e.Hash -ne $Hash) {
        $e.Hash = $Hash
        Save-Manifest
    }
}

# ---------------------------------------------------------------------------
# Game folder
# ---------------------------------------------------------------------------
function Test-GameDir([string]$Dir) {
    if ([string]::IsNullOrWhiteSpace($Dir)) { return $false }
    try {
        # Join-Path throws on a drive that does not exist (unplugged disk, stale registry key).
        return (Test-Path -LiteralPath (Join-Path $Dir 'Client.exe') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $Dir 'SHOGO.REZ') -PathType Leaf)
    } catch {
        return $false
    }
}

function Get-RegistryGameDirs {
    $dirs = New-Object System.Collections.Generic.List[string]
    if (-not $OnWindows) { return , $dirs }
    # The GOG id differs between editions: look at every GOG game.
    foreach ($root in @('HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games', 'HKLM:\SOFTWARE\GOG.com\Games')) {
        try {
            foreach ($k in @(Get-ChildItem -LiteralPath $root -ErrorAction Stop)) {
                $p = $k.GetValue('path')
                if ($p) { $dirs.Add([string]$p) }
            }
        } catch {
            Write-Verbose "No key $root"
        }
    }
    foreach ($key in @('HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 610860',
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 610860')) {
        try {
            $p = (Get-Item -LiteralPath $key -ErrorAction Stop).GetValue('InstallLocation')
            if ($p) { $dirs.Add([string]$p) }
        } catch {
            Write-Verbose "No key $key"
        }
    }
    return , $dirs
}

function Find-GameDir {
    # Registry, then the installer extracted inside or next to the game folder.
    $candidates = Get-RegistryGameDirs
    $here = $PSScriptRoot
    for ($i = 0; $i -lt 3 -and $here; $i++) {
        $candidates.Add($here)
        $here = Split-Path -Parent $here
    }
    foreach ($c in $candidates) { if (Test-GameDir $c) { return (Resolve-Path -LiteralPath $c).Path } }

    # Folders named like *shogo* on every fixed drive. A copy or an old backup may be among
    # them, so the choice is always confirmed.
    $found = New-Object System.Collections.Generic.List[string]
    $drives = @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } | Sort-Object -Property Name)
    foreach ($d in $drives) {
        Write-Info "Looking for the game on $($d.Name)..."
        $dirs = Get-ChildItem -LiteralPath $d.RootDirectory.FullName -Directory -Recurse -Depth 3 -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like '*shogo*' }
        foreach ($dir in $dirs) {
            if (-not (Test-GameDir $dir.FullName)) { continue }
            $known = $false
            foreach ($f in $found) { if ($f -ieq $dir.FullName) { $known = $true } }
            if (-not $known) { $found.Add($dir.FullName) }
        }
    }
    if ($found.Count -eq 1) {
        Write-Info "Shogo found in: $($found[0])"
        $answer = Read-Host 'Install into this folder? (Y/N)'
        if ($answer -match '^\s*(y|yes|o|oui)?\s*$') { return $found[0] }
    } elseif ($found.Count -gt 1) {
        Write-Info 'Shogo found in several folders:'
        for ($i = 0; $i -lt $found.Count; $i++) { Write-Info ("[{0}] {1}" -f ($i + 1), $found[$i]) }
        $choice = Read-Host ('Number of the folder to use (1-{0}), or Enter to type another path' -f $found.Count)
        $n = 0
        if ([int]::TryParse($choice, [ref]$n) -and $n -ge 1 -and $n -le $found.Count) { return $found[$n - 1] }
    }
    for ($try = 1; $try -le 3; $try++) {
        $typed = Read-Host 'Path of the Shogo folder (the one containing Client.exe)'
        $typed = $typed.Trim().Trim('"')
        if (Test-GameDir $typed) { return (Resolve-Path -LiteralPath $typed).Path }
        Write-Warn "Client.exe and SHOGO.REZ not found in '$typed'."
    }
    throw 'Game folder not found. Run again with -GameDir "<folder containing Client.exe>".'
}

function Assert-GameNotRunning {
    $prefix = $GameDir.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $unknown = $false
    foreach ($p in @(Get-Process -Name 'Client', 'Shogo' -ErrorAction SilentlyContinue)) {
        $path = $null
        try { $path = $p.Path } catch { $path = $null }
        # StartsWith, not -like: a folder name such as "Shogo [GOG]" would read as a wildcard.
        if ($path -and $path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Shogo is still running: close the game and its launcher, then run the installer again.'
        }
        if (-not $path) { $unknown = $true }
    }
    if ($unknown) {
        # Started as administrator: its path cannot be read from here.
        Write-Warn 'A Client.exe or Shogo.exe started as administrator is running. If it is Shogo, close it now.'
        [void](Read-Host 'Press Enter to continue')
    }
}

# Two installers at once would overwrite each other's backups and manifest.
function Lock-Installer {
    $script:InstallerMutex = New-Object System.Threading.Mutex($false, 'Local\ShogoMods-Installer')
    $own = $false
    try {
        $own = $script:InstallerMutex.WaitOne(0)
    } catch {
        $own = ($_.Exception.GetBaseException() -is [System.Threading.AbandonedMutexException])
    }
    if (-not $own) { throw 'The installer is already running in another window: wait for it to finish.' }
}

# ---------------------------------------------------------------------------
# Display
# ---------------------------------------------------------------------------
function Get-CurrentDisplayMode {
    # EnumDisplaySettings returns physical pixels, unaffected by Windows DPI scaling.
    if (-not ('ShogoModsDisplay' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ShogoModsDisplay {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion; public short dmDriverVersion; public short dmSize; public short dmDriverExtra;
        public int dmFields; public int dmPositionX; public int dmPositionY; public int dmDisplayOrientation;
        public int dmDisplayFixedOutput; public short dmColor; public short dmDuplex; public short dmYResolution;
        public short dmTTOption; public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels; public int dmBitsPerPel; public int dmPelsWidth; public int dmPelsHeight;
        public int dmDisplayFlags; public int dmDisplayFrequency; public int dmICMMethod; public int dmICMIntent;
        public int dmMediaType; public int dmDitherType; public int dmReserved1; public int dmReserved2;
        public int dmPanningWidth; public int dmPanningHeight;
    }
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern bool EnumDisplaySettingsW(string deviceName, int modeNum, ref DEVMODE devMode);
    public static int[] Current() {
        DEVMODE dm = new DEVMODE();
        dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        if (!EnumDisplaySettingsW(null, -1, ref dm)) return new int[] { 0, 0, 0 };
        return new int[] { dm.dmPelsWidth, dm.dmPelsHeight, dm.dmDisplayFrequency };
    }
}
'@
    }
    return [ShogoModsDisplay]::Current()
}

function Get-DisplayMode {
    $mode = @{ Width = $ScreenWidth; Height = $ScreenHeight; Hz = $RefreshRate }
    if ($OnWindows -and ($mode.Width -le 0 -or $mode.Height -le 0 -or $mode.Hz -le 1)) {
        $cur = $null
        try {
            $cur = Get-CurrentDisplayMode
        } catch {
            Write-Verbose ('Display query failed: ' + $_.Exception.Message)
        }
        if ($null -ne $cur) {
            if ($mode.Width -le 0 -or $mode.Height -le 0) { $mode.Width = $cur[0]; $mode.Height = $cur[1] }
            if ($mode.Hz -le 1) { $mode.Hz = $cur[2] }
        }
    }
    if ($mode.Width -le 0 -or $mode.Height -le 0) {
        throw 'Cannot read the display resolution. Run again with -ScreenWidth <width> -ScreenHeight <height> -RefreshRate <Hz>.'
    }
    return $mode
}

# ---------------------------------------------------------------------------
# Download and extraction
# ---------------------------------------------------------------------------
function Get-VerifiedDownload($Component, [string]$TempDir) {
    $name = [IO.Path]::GetFileName(([Uri]$Component.Url).AbsolutePath)
    $out = Join-Path $TempDir $name
    if (-not (Test-Path -LiteralPath $out) -or (Get-Sha256 $out) -ne $Component.Sha256) {
        Write-Info "Downloading $name..."
        Invoke-WebRequest -Uri $Component.Url -OutFile $out -UseBasicParsing -UserAgent "ShogoMods/$InstallerVersion" -TimeoutSec 300
    }
    if (-not (Test-Path -LiteralPath $out)) {
        throw "$name disappeared right after the download (antivirus?). Add an exclusion for the game folder, or try again later."
    }
    $hash = Get-Sha256 $out
    if ($hash -ne $Component.Sha256) {
        Remove-Item -LiteralPath $out -Force
        throw "Unexpected SHA256 for $name ($hash): corrupted download or file changed at the source."
    }
    return $out
}

function Expand-ZipEntries([string]$Archive, $Files, [string]$OutDir) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        foreach ($f in $Files) {
            $entry = $null
            foreach ($e in $zip.Entries) { if ($e.FullName -ieq $f.Entry) { $entry = $e; break } }
            if ($null -eq $entry) { throw "'$($f.Entry)' missing from $Archive." }
            $target = Join-Path $OutDir ([IO.Path]::GetFileName($f.Entry))
            $in = $entry.Open()
            try {
                $fs = [IO.File]::Create($target)
                try { $in.CopyTo($fs) } finally { $fs.Dispose() }
            } finally { $in.Dispose() }
        }
    } finally { $zip.Dispose() }
}

function Invoke-Native([string]$Exe, [string[]]$Arguments) {
    # Windows PowerShell 5.1 turns a native program's stderr into a terminating error under 'Stop'.
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $Exe @Arguments 2>&1 | Out-Null
        return $LASTEXITCODE
    } catch {
        return -1
    } finally {
        $ErrorActionPreference = $old
    }
}

function Get-SevenZipPaths {
    $paths = New-Object System.Collections.Generic.List[string]
    if ($OnWindows) {
        $dirs = New-Object System.Collections.Generic.List[string]
        foreach ($root in @($env:ProgramW6432, $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
            if ($root) { $dirs.Add((Join-Path $root '7-Zip')) }
        }
        foreach ($key in @('HKLM:\SOFTWARE\7-Zip', 'HKCU:\SOFTWARE\7-Zip', 'HKLM:\SOFTWARE\WOW6432Node\7-Zip')) {
            try {
                $item = Get-Item -LiteralPath $key -ErrorAction Stop
                foreach ($v in @('Path64', 'Path')) {
                    $p = $item.GetValue($v)
                    if ($p) { $dirs.Add([string]$p) }
                }
            } catch {
                Write-Verbose "No key $key"
            }
        }
        foreach ($d in $dirs) {
            $exe = Join-Path $d '7z.exe'
            if ((Test-Path -LiteralPath $exe) -and -not $paths.Contains($exe)) { $paths.Add($exe) }
        }
    }
    foreach ($n in @('7z', '7zz')) {
        $cmd = Get-Command $n -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd -and -not $paths.Contains($cmd.Source)) { $paths.Add($cmd.Source) }
    }
    return , $paths
}

# The FOV fix only ships as RAR5: Windows tar (bsdtar, depending on its version), 7-Zip or WinRAR.
function Expand-RarEntries([string]$Archive, $Files, [string]$OutDir) {
    $tools = New-Object System.Collections.Generic.List[object]
    if ($OnWindows) {
        $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
        if (Test-Path -LiteralPath $tar) { $tools.Add(@{ Exe = $tar; Args = @('-xf', $Archive, '-C', $OutDir) }) }
    }
    $bsd = Get-Command 'bsdtar' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($bsd) { $tools.Add(@{ Exe = $bsd.Source; Args = @('-xf', $Archive, '-C', $OutDir) }) }
    foreach ($s in (Get-SevenZipPaths)) { $tools.Add(@{ Exe = $s; Args = @('e', '-y', "-o$OutDir", $Archive) }) }
    if ($OnWindows) {
        foreach ($root in @($env:ProgramW6432, $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
            if (-not $root) { continue }
            $p = Join-Path $root 'WinRAR\UnRAR.exe'
            if (Test-Path -LiteralPath $p) { $tools.Add(@{ Exe = $p; Args = @('e', '-y', $Archive, ($OutDir + [IO.Path]::DirectorySeparatorChar)) }) }
        }
    }
    foreach ($t in $tools) {
        [void](Invoke-Native $t.Exe $t.Args)
        $complete = $true
        foreach ($f in $Files) {
            $x = Join-Path $OutDir $f.Entry
            if (-not (Test-Path -LiteralPath $x) -or (Get-Sha256 $x) -ne $f.Sha256) { $complete = $false }
        }
        if ($complete) { return $true }
    }
    return $false
}

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------
# dgVoodoo.conf: the same key can exist in several sections ([Glide] and [DirectX]), so edit per section.
function Set-IniValue($Lines, [string]$Section, [string]$Key, [string]$Value) {
    $start = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i].Trim() -ieq "[$Section]") { $start = $i; break }
    }
    if ($start -lt 0) {
        $Lines.Add('')
        $Lines.Add("[$Section]")
        $start = $Lines.Count - 1
    }
    $end = $Lines.Count
    for ($i = $start + 1; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i].TrimStart().StartsWith('[')) { $end = $i; break }
    }
    $pattern = '^(\s*' + [regex]::Escape($Key) + '\s*=\s*).*$'
    for ($i = $start + 1; $i -lt $end; $i++) {
        if ($Lines[$i] -match $pattern) {
            $Lines[$i] = $Matches[1] + $Value
            return
        }
    }
    $insert = $end
    while ($insert -gt $start + 1 -and [string]::IsNullOrWhiteSpace($Lines[$insert - 1])) { $insert-- }
    $Lines.Insert($insert, ('{0,-37}= {1}' -f $Key, $Value))
}

# autoexec.cfg: one console command per line, "Key" "value", case-insensitive names.
function Set-CfgValue($Lines, [string]$Key, [string]$Value) {
    $pattern = '^\s*"?' + [regex]::Escape($Key) + '"?\s'
    $newLine = '"{0}" "{1}"' -f $Key, $Value
    $done = $false
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -imatch $pattern) {
            if ($done) { $Lines.RemoveAt($i); $i-- } else { $Lines[$i] = $newLine; $done = $true }
        }
    }
    if (-not $done) { $Lines.Add($newLine) }
}

function Get-CfgValue($Lines, [string]$Key) {
    $pattern = '^\s*"?' + [regex]::Escape($Key) + '"?\s+"?([^"]*)"?'
    foreach ($l in $Lines) { if ($l -imatch $pattern) { return $Matches[1].Trim() } }
    return $null
}

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------
function Invoke-Uninstall {
    Read-Manifest
    $fresh = Test-Path -LiteralPath (Join-Path $GameDir 'ShogoFRESH.rez')
    $kept = New-Object System.Collections.ArrayList
    if ($script:Manifest.Count -gt 0) {
        Write-Step 'Restoring the original state'
        $script:Started = $true
    } else {
        if (Test-OrphanBackup) {
            Write-Warn "No manifest, but $BackupDirName\originals holds original files: copy them back by hand if needed."
        } else {
            Write-Warn 'Nothing to uninstall (no manifest).'
        }
        return
    }
    # Logs go with the plugin that writes them.
    $logs = @{}
    foreach ($pair in @(@('ShogoFPS.asi', 'ShogoFPS.log'), @('ShogoMobileArmorDivisionFOVFix.asi', 'ShogoMobileArmorDivisionFOVFix.log'))) {
        if ($null -ne (Find-ManifestEntry $pair[0])) { $logs[$pair[0]] = $pair[1] }
    }
    foreach ($e in @($script:Manifest)) {
        $full = Resolve-Dest $e.Dest
        if ($fresh -and $FreshFiles -contains $e.Dest) {
            Write-Warn "$($e.Dest): left in place, ShogoFRESH uses it."
            [void]$kept.Add($e)
            continue
        }
        if ($e.Hash -and (Test-Path -LiteralPath $full) -and (Get-Sha256 $full) -ne $e.Hash) {
            Write-Warn "$($e.Dest): replaced by another program since the install, left in place."
            [void]$kept.Add($e)
            continue
        }
        if ($e.Action -eq 'added') {
            if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Force }
            Write-Ok "removed: $($e.Dest)"
        } elseif ($e.Backup) {
            $bfull = Join-Path $GameDir $e.Backup
            if ($e.Action -eq 'edited' -and (Test-Path -LiteralPath $full) -and (Get-Sha256 $full) -ne (Get-Sha256 $bfull)) {
                # The game rewrites autoexec.cfg on exit: keep the settings made since the install.
                Copy-Item -LiteralPath $full -Destination ($full + '.before-uninstall') -Force
                Write-Info "Current $($e.Dest) saved as $($e.Dest).before-uninstall"
            }
            Copy-Item -LiteralPath $bfull -Destination $full -Force
            Remove-Item -LiteralPath $bfull -Force
            Write-Ok "restored: $($e.Dest)"
        }
    }
    foreach ($owner in @($logs.Keys)) {
        $p = Join-Path $GameDir $logs[$owner]
        if ($null -eq (Find-KeptEntry $kept $owner) -and (Test-Path -LiteralPath $p)) { Remove-Item -LiteralPath $p -Force }
    }
    $temp = Join-Path $GameDir $TempDirName
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
    if ($kept.Count -eq 0) {
        if (Test-Path -LiteralPath (Get-BackupDir)) { Remove-Item -LiteralPath (Get-BackupDir) -Recurse -Force }
    } else {
        # Only what was left in place stays listed, so running the uninstall again is safe.
        $script:Manifest = $kept
        Save-Manifest
        Write-Info "$BackupDirName kept: it holds the originals of the files left in place."
    }
    Write-Host ''
    Write-Host 'Uninstall complete.' -ForegroundColor Green
}

function Find-KeptEntry($Kept, [string]$Dest) {
    foreach ($e in $Kept) { if ($e.Dest -ieq $Dest) { return $e } }
    return $null
}

# ---------------------------------------------------------------------------
# Installation
# ---------------------------------------------------------------------------
# Step 1: download, check and extract into the temporary folder. The game folder is not touched.
function Get-ComponentPlan($Component, [string]$TempDir, [string[]]$ManagedByOthers) {
    $label = $Component.Label
    $plan = @{ Component = $Component; Pending = @(); Dir = '' }
    $managedCount = 0
    foreach ($f in $Component.Files) {
        if ($ManagedByOthers -contains $f.Dest) { $managedCount++; continue }
        $dest = Join-Path $GameDir $f.Dest
        if ((Test-Path -LiteralPath $dest) -and (Get-Sha256 $dest) -eq $f.Sha256) { continue }
        if ($f.ContainsKey('Config') -and (Test-Path -LiteralPath $dest)) { continue } # keep the existing settings file, it gets edited
        $plan.Pending += $f
    }
    if ($plan.Pending.Count -eq 0) {
        if ($managedCount -eq $Component.Files.Count) { Write-Ok "${label}: left to ShogoFRESH" } else { Write-Ok "${label}: already in place" }
        return $plan
    }

    $archive = Get-VerifiedDownload $Component $TempDir
    $xdir = Join-Path $TempDir $Component.Id
    if (Test-Path -LiteralPath $xdir) { Remove-Item -LiteralPath $xdir -Recurse -Force }
    [void](New-Item -ItemType Directory -Path $xdir)
    switch ($Component.Kind) {
        'file' { Copy-Item -LiteralPath $archive -Destination (Join-Path $xdir ([IO.Path]::GetFileName($plan.Pending[0].Dest))) }
        'zip' { Expand-ZipEntries $archive $plan.Pending $xdir }
        'rar' {
            if (-not (Expand-RarEntries $archive $Component.Files $xdir)) {
                throw 'cannot extract the .rar archive (no capable Windows tar, 7-Zip or WinRAR, or an antivirus removed the files). Install 7-Zip (https://www.7-zip.org) and run the installer again.'
            }
        }
    }
    foreach ($f in $plan.Pending) {
        $src = Join-Path $xdir (Get-PlanFileName $Component $f)
        if (-not (Test-Path -LiteralPath $src)) { throw "$(Split-Path -Leaf $src) missing after extraction (antivirus?)." }
        $hash = Get-Sha256 $src
        if ($hash -ne $f.Sha256) { throw "Unexpected SHA256 for extracted $(Split-Path -Leaf $src) ($hash)." }
    }
    $plan.Dir = $xdir
    Write-Ok "${label}: downloaded and checked"
    return $plan
}

function Get-PlanFileName($Component, $File) {
    if ($Component.Kind -eq 'file') { return [IO.Path]::GetFileName($File.Dest) }
    return [IO.Path]::GetFileName($File.Entry)
}

# Step 2: copy into the game folder, backing up what gets replaced.
function Install-ComponentFiles($Plan) {
    if ($Plan.Pending.Count -eq 0) { return }
    foreach ($f in $Plan.Pending) {
        $src = Join-Path $Plan.Dir (Get-PlanFileName $Plan.Component $f)
        $dest = Join-Path $GameDir $f.Dest
        Register-Change $f.Dest 'replaced'
        Copy-Item -LiteralPath $src -Destination $dest -Force
        Assert-FileWritten $dest $f.Sha256
        if (-not $f.ContainsKey('Config')) { Set-ManifestHash $f.Dest $f.Sha256 }
    }
    Write-Ok "$($Plan.Component.Label): installed"
}

function Install-ShogoFps([string]$Asi, [string]$Ini) {
    $dest = Join-Path $GameDir 'ShogoFPS.asi'
    $hash = Get-Sha256 $Asi
    if ((Test-Path -LiteralPath $dest) -and (Get-Sha256 $dest) -eq $hash) {
        Write-Ok 'ShogoFPS: already up to date'
    } else {
        Register-Change 'ShogoFPS.asi' 'replaced'
        Copy-Item -LiteralPath $Asi -Destination $dest -Force
        Assert-FileWritten $dest $hash
        Write-Ok 'ShogoFPS: installed'
    }
    Set-ManifestHash 'ShogoFPS.asi' $hash
    if (-not (Test-Path -LiteralPath (Join-Path $GameDir 'ShogoFPS.ini'))) {
        Register-Change 'ShogoFPS.ini' 'added'
        Copy-Item -LiteralPath $Ini -Destination (Join-Path $GameDir 'ShogoFPS.ini')
    } else {
        Write-Info 'Existing ShogoFPS.ini kept (your settings).'
    }
}

function Set-DgVoodooConfig($Mode, $Game, [int]$Cap) {
    $path = Join-Path $GameDir 'dgVoodoo.conf'
    if (-not (Test-Path -LiteralPath $path)) { Write-Warn 'dgVoodoo.conf missing, settings skipped.'; return $false }
    Register-Change 'dgVoodoo.conf' 'edited'
    $lines = Read-TextLines $path
    $native = '{0}x{1}' -f $Mode.Width, $Mode.Height
    $gameRes = '{0}x{1}' -f $Game.Width, $Game.Height
    # Few modes: the original game's Display menu only holds 12, maybe for several outputs.
    # 640x480 stays for the engine's fallback mode.
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($r in @('640x480', $gameRes, $native)) { if (-not $list.Contains($r)) { $list.Add($r) } }
    Set-IniValue $lines 'General' 'FullScreenMode' 'true'
    Set-IniValue $lines 'General' 'KeepWindowAspectRatio' 'true'
    Set-IniValue $lines 'General' 'CaptureMouse' 'true'
    # dgVoodoo paces the frames: the engine's own limiter sleeps in whole Windows timer steps
    # (stuck at 64 fps without a 1 ms timer, ~125-140 fps for a 141 target with one).
    Set-IniValue $lines 'GeneralExt' 'FPSLimit' ([string]$Cap)
    Set-IniValue $lines 'DirectX' 'VRAM' '256'
    Set-IniValue $lines 'DirectX' 'Filtering' '16'
    Set-IniValue $lines 'DirectX' 'Antialiasing' '4x'
    Set-IniValue $lines 'DirectX' 'AppControlledScreenMode' 'false'
    Set-IniValue $lines 'DirectX' 'DisableAltEnterToToggleScreenMode' 'false'
    Set-IniValue $lines 'DirectX' 'ForceVerticalSync' 'false'
    Set-IniValue $lines 'DirectX' 'dgVoodooWatermark' 'false'
    # The refresh rate is forced so fullscreen keeps the desktop's (144 Hz rather than 60).
    if ($Game.Upscaled) {
        # The game runs at a whole fraction of the display (readable HUD), dgVoodoo renders the 3D at full resolution.
        $res = 'max'
        if ($Mode.Hz -gt 1) { $res = 'max, refrate:{0}' -f $Mode.Hz }
        Set-IniValue $lines 'DirectX' 'Resolution' $res
        Set-IniValue $lines 'General' 'ScalingMode' 'stretched_ar'
    } else {
        $res = 'unforced'
        if ($Mode.Hz -gt 1) { $res = '{0}@{1}' -f $native, $Mode.Hz }
        Set-IniValue $lines 'DirectX' 'Resolution' $res
        Set-IniValue $lines 'General' 'ScalingMode' 'unspecified'
    }
    Set-IniValue $lines 'DirectXExt' 'DefaultEnumeratedResolutions' 'none'
    Set-IniValue $lines 'DirectXExt' 'ExtraEnumeratedResolutions' ($list -join ', ')
    Set-IniValue $lines 'DirectXExt' 'EnumeratedResolutionBitdepths' '16'
    Write-ConfigLines $path $lines
    Write-Ok ("dgVoodoo: fullscreen, 3D at {0}, 16x filtering, 4x antialiasing, {1} fps cap" -f $native, $Cap)
    return $true
}

function Set-FovEnabled([bool]$Enabled) {
    $path = Join-Path $GameDir $FovIni
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    $value = 'false'
    if ($Enabled) { $value = 'true' }
    $lines = Read-TextLines $path
    $before = $lines -join "`n"
    Set-IniValue $lines 'FOVFix' 'Enabled' $value
    $bytes = [IO.File]::ReadAllBytes($path)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    if ($hasBom -or $before -ne ($lines -join "`n")) {
        Register-Change $FovIni 'edited'
        Write-ConfigLines $path $lines
    }
    return $true
}

function Set-GameConfig($Game, [int]$EngineCap) {
    $path = Join-Path $GameDir 'autoexec.cfg'
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Warn 'autoexec.cfg does not exist yet: start Shogo once (then quit) and run the installer again to set the resolution.'
        return $false
    }
    $lines = Read-TextLines $path
    # Already set by a previous run but back at 640x480 or software: the game fell back.
    $prevWidth = Get-CfgValue $lines 'screenwidth'
    $renderer = Get-CfgValue $lines 'RenderDll'
    $fellBack = $null -ne (Find-ManifestEntry 'autoexec.cfg') -and $prevWidth -eq '640' -and $Game.Width -ne 640
    Register-Change 'autoexec.cfg' 'edited'
    Set-CfgValue $lines 'screenwidth' ([string]$Game.Width)
    Set-CfgValue $lines 'screenheight' ([string]$Game.Height)
    Set-CfgValue $lines 'MasterPaletteMode' '1.000000'
    # High detail, unless the player chose custom details (3).
    $detail = Get-CfgValue $lines 'GlobalDetail'
    $d = 0.0
    if ($null -eq $detail -or -not [double]::TryParse($detail, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d) -or $d -lt 2) {
        Set-CfgValue $lines 'GlobalDetail' '2.000000'
    }
    Set-CfgValue $lines 'inputrate' '10.000000'
    # 0 = the engine's limiter is off; the cap is dgVoodoo's.
    Set-CfgValue $lines 'MaxFPS' ([string]$EngineCap)
    Write-ConfigLines $path $lines
    Write-Ok ("Game: {0}x{1}, high detail, 16-bit textures, smoothed mouse" -f $Game.Width, $Game.Height)
    $soft = $renderer -and $renderer -match 'soft'
    if ($fellBack -or $soft) {
        Write-Warn ("Last time the game could not use Direct3D at {0}x{1}: it fell back to 640x480 or to software rendering." -f $Game.Width, $Game.Height)
        Write-Info ("In the game, open Options > Display, pick the Direct3D renderer at {0}x{1}, then quit the game normally." -f $Game.Width, $Game.Height)
    }
    return $true
}

function New-GameShortcut {
    if ($NoShortcut -or -not $OnWindows) { return }
    $rez = New-Object System.Collections.Generic.List[string]
    foreach ($n in @('SHOGO.REZ', 'SOUND.REZ')) { if (Test-Path -LiteralPath (Join-Path $GameDir $n)) { $rez.Add($n) } }
    foreach ($p in @(Get-ChildItem -LiteralPath $GameDir -Filter 'SHOGOP*.REZ' -File | Sort-Object -Property Name)) { $rez.Add($p.Name) }
    if (Test-Path -LiteralPath (Join-Path $GameDir 'Custom')) { $rez.Add('Custom') }
    $arguments = (($rez | ForEach-Object { '-rez "{0}"' -f $_ }) -join ' ') + ' +DisableMovies 1 +EnableTripBuf 1'
    $lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) $ShortcutName
    Register-Change $lnk 'added'
    $shell = New-Object -ComObject WScript.Shell
    $sc = $shell.CreateShortcut($lnk)
    $sc.TargetPath = Join-Path $GameDir 'Client.exe'
    $sc.Arguments = $arguments
    $sc.WorkingDirectory = $GameDir
    $sc.IconLocation = (Join-Path $GameDir 'Client.exe') + ',0'
    $sc.Description = 'Shogo: Mobile Armor Division with ShogoFPS'
    $sc.Save()
    Write-Ok "Desktop shortcut '$([IO.Path]::GetFileNameWithoutExtension($ShortcutName))' created"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
trap {
    Write-Host ''
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    if (-not $script:Started) {
        Write-Host 'Nothing was changed in the game folder.' -ForegroundColor Red
    } elseif ($Uninstall) {
        Write-Host "Uninstall incomplete: run Uninstall-ShogoMods.bat again. The original files are still in $BackupDirName." -ForegroundColor Red
    } else {
        Write-Host 'Installation incomplete: run the installer again to finish it, or Uninstall-ShogoMods.bat to go back.' -ForegroundColor Red
        Write-Host "The original files are backed up in $BackupDirName." -ForegroundColor Red
    }
    exit 1
}

Write-Host "Modern fixes for Shogo: Mobile Armor Division - installer $InstallerVersion" -ForegroundColor White

if (-not (Test-GameDir $GameDir)) {
    if ($GameDir) { Write-Warn "'$GameDir' does not contain Client.exe and SHOGO.REZ." }
    if ($NoSearch) { throw "Client.exe and SHOGO.REZ not found in '$GameDir'." }
    $GameDir = Find-GameDir
} else {
    $GameDir = (Resolve-Path -LiteralPath $GameDir).Path
}
Write-Info "Game folder: $GameDir"
Assert-GameNotRunning
Lock-Installer

if ($Uninstall) {
    Invoke-Uninstall
    exit 0
}

# Everything that can fail on its own is checked before the first change.
$distDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'dist'
$distAsi = Join-Path $distDir 'ShogoFPS.asi'
$distIni = Join-Path $distDir 'ShogoFPS.ini'
foreach ($f in @($distAsi, $distIni)) {
    if (-not (Test-Path -LiteralPath $f)) { throw "$(Split-Path -Leaf $f) not found in $distDir. Extract the whole ZIP: the dist folder must stay next to the installer folder." }
}
Read-Manifest
if (Test-OrphanBackup) {
    throw "$BackupDirName\originals holds original files but its manifest is missing. To keep them safe, nothing was changed: move the $BackupDirName folder elsewhere (keep it), then run the installer again."
}
$mode = Get-DisplayMode
$cap = 141
if ($mode.Hz -gt 1) { $cap = [Math]::Max(60, [Math]::Min(240, $mode.Hz - 3)) }

$fresh = Test-Path -LiteralPath (Join-Path $GameDir 'ShogoFRESH.rez')
$managed = @()
if ($fresh) {
    # ShogoFRESH's game code only loads through its launcher (ShogoFRESH.rez), and it already
    # widens the field of view: no FOV fix, no shortcut, no game settings.
    $managed = $FreshFiles
    $NoFovFix = $true
    $NoShortcut = $true
    Write-Info 'ShogoFRESH detected: it keeps control of dinputto8, dgVoodoo, the field of view and the game settings.'
}

# Whole fractions of the display only (x2, x3): the 2D HUD scales without uneven pixels.
$game = @{ Width = $mode.Width; Height = $mode.Height; Upscaled = $false }
$k = [Math]::Floor([double]$mode.Height / 720)
if (-not $NativeResolution -and -not $fresh -and $k -ge 2) {
    $game = @{ Width = [int]([Math]::Round($mode.Width / $k / 2.0) * 2); Height = [int][Math]::Round($mode.Height / $k); Upscaled = $true }
}

$temp = Join-Path $GameDir $TempDirName
$cfgOk = $true
try {
    if (-not (Test-Path -LiteralPath $temp)) { [void](New-Item -ItemType Directory -Path $temp) }
    Write-Step 'Downloads'
    $plans = New-Object System.Collections.Generic.List[object]
    $fovOk = $false
    foreach ($c in $Components) {
        if ($c.Id -eq 'fovfix' -and $NoFovFix) { continue }
        try {
            $plans.Add((Get-ComponentPlan $c $temp $managed))
            if ($c.Id -eq 'fovfix') { $fovOk = $true }
        } catch {
            # The FOV fix is optional, and its author replaces old releases: go on without it.
            if ($c.Id -ne 'fovfix') { throw }
            Write-Warn ("$($c.Label): " + $_.Exception.Message)
            Write-Info 'The installation goes on without this fix (run with -NoFovFix to stop trying it).'
        }
    }

    Write-Step 'Installing'
    $script:Started = $true
    foreach ($p in $plans) { Install-ComponentFiles $p }
    Install-ShogoFps $distAsi $distIni
    if ($NoFovFix) {
        if (Set-FovEnabled $false) {
            if ($fresh) { Write-Ok 'FOV fix: turned off (ShogoFRESH already widens the field of view)' } else { Write-Ok 'FOV fix: turned off' }
        }
    } elseif ($fovOk) {
        [void](Set-FovEnabled $true)
    }

    Write-Step 'Settings'
    $hzText = 'unknown refresh rate'
    if ($mode.Hz -gt 1) { $hzText = '{0} Hz' -f $mode.Hz }
    Write-Info ("Display: {0}x{1}, {2}" -f $mode.Width, $mode.Height, $hzText)
    if ($fresh) {
        Write-Info ("Settings left to the ShogoFRESH launcher. In it, set the frame rate cap to {0}." -f $cap)
    } else {
        $engineCap = $cap
        if (Set-DgVoodooConfig $mode $game $cap) { $engineCap = 0 }
        $cfgOk = Set-GameConfig $game $engineCap
    }
    try {
        New-GameShortcut
    } catch {
        Write-Warn ('Desktop shortcut not created: ' + $_.Exception.Message)
        Write-Info ('Start the game with Client.exe instead.')
    }
} finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
Write-Host 'Installation complete.' -ForegroundColor Green
if ($fresh) {
    Write-Info 'Play through the ShogoFRESH launcher: it loads ShogoFRESH.rez, and ShogoFPS loads with the game.'
}
if ($game.Upscaled) {
    Write-Info ("The game runs at {0}x{1} to keep the HUD readable; dgVoodoo renders the 3D at {2}x{3}." -f $game.Width, $game.Height, $mode.Width, $mode.Height)
    Write-Info 'For everything at native resolution (tiny HUD), run again with -NativeResolution.'
}
if ($mode.Hz -le 1) { Write-Info ('Refresh rate unknown: frame cap {0} fps. Run again with -RefreshRate <Hz> to change it.' -f $cap) }
if (-not $cfgOk) { Write-Info 'Start the game once, quit it, then run the installer again to finish the settings.' }
Write-Info "Original files are backed up in $BackupDirName in the game folder. To uninstall: Uninstall-ShogoMods.bat"
Write-Info 'ShogoFPS log: ShogoFPS.log in the game folder, after playing.'
exit 0
