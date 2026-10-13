<#
.SYNOPSIS
    Installe les correctifs modernes de Shogo: Mobile Armor Division (version GOG/Steam 2.2).

.DESCRIPTION
    Télécharge depuis les sources officielles (releases GitHub, empreintes SHA256 vérifiées)
    et installe dans le dossier du jeu :
      - dinputto8          : le jeu démarre sous Windows 10/11
      - dgVoodoo2 2.87.5   : rendu Direct3D moderne, résolution native, filtrage, antialiasing
      - Ultimate ASI Loader: charge les plugins .asi (installé en winmm.dll)
      - FOV fix AlphaYellow: champ de vision correct en 16:9
      - ShogoFPS           : jeu à vitesse réelle à haut FPS, souris fluide
    Puis règle dgVoodoo et autoexec.cfg et crée un raccourci sur le bureau.
    Tout est fait dans le dossier du jeu (téléchargements temporaires compris).
    Chaque fichier remplacé est sauvegardé ; -Uninstall remet tout comme avant.

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
    Write-Verbose 'TLS 1.2 deja actif ou non configurable'
}

$InstallerVersion = '1.0.0'
$OnWindows = ($env:OS -eq 'Windows_NT')
$BackupDirName = 'ShogoMods_Backup'
$ShortcutName = 'Shogo (ShogoFPS).lnk'

# ---------------------------------------------------------------------------
# Composants : URL figées sur un tag, empreintes vérifiées le 2026-10-13.
# ---------------------------------------------------------------------------
$Components = @(
    @{
        Id = 'dinputto8'; Label = 'dinputto8 1.1.100.0 (démarrage sous Windows 10/11)'; Kind = 'file'
        Url = 'https://github.com/elishacloud/dinputto8/releases/download/v1.1.100.0/dinput.dll'
        Sha256 = 'f96bb1101e23a6477043a3859cbf875a990eaa62ee6849f87e967b3dd963f781'
        Files = @(@{ Entry = ''; Dest = 'dinput.dll'; Sha256 = 'f96bb1101e23a6477043a3859cbf875a990eaa62ee6849f87e967b3dd963f781' })
    },
    @{
        Id = 'dgvoodoo2'; Label = 'dgVoodoo2 2.87.5 (rendu moderne)'; Kind = 'zip'
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
        Id = 'asiloader'; Label = 'Ultimate ASI Loader 9.7.4 (chargeur de plugins)'; Kind = 'zip'
        Url = 'https://github.com/ThirteenAG/Ultimate-ASI-Loader/releases/download/v9.7.4/Ultimate-ASI-Loader.zip'
        Sha256 = '952cebfc30d525afc2bdbaca954329d405ded3aa688a83027354dae14dfd5c5f'
        Files = @(@{ Entry = 'dinput8.dll'; Dest = 'winmm.dll'; Sha256 = 'd5a059aa467a7a7127c8f6169f79fa63ff0f55986ee9eb2fd9a281bebf2aa2e6' })
    },
    @{
        Id = 'fovfix'; Label = 'FOV fix AlphaYellow 1.3 (champ de vision 16:9)'; Kind = 'rar'
        Url = 'https://github.com/alphayellow1/AlphaYellowWidescreenFixes/releases/download/shogomobilearmordivision/Shogo.Mobile.Armor.Division.-.FOV.Fix.v1.3.rar'
        Sha256 = 'a42aea6f754e3db6b69f0ed9ff2992be81353d6e34a4643c8f62374a64d5eec6'
        Files = @(
            @{ Entry = 'ShogoMobileArmorDivisionFOVFix.asi'; Dest = 'ShogoMobileArmorDivisionFOVFix.asi'; Sha256 = 'edffb76ceb6f2491893f5942e7899fad86c5d2577b9fe1cf61b907317608dbe8' },
            @{ Entry = 'ShogoMobileArmorDivisionFOVFix.ini'; Dest = 'ShogoMobileArmorDivisionFOVFix.ini'; Sha256 = '9f1fa92923b4a121f5eee9e0e0bcd30d7b29e0561f555aafd6d7248b57eea611'; Config = $true }
        )
    }
)

# ---------------------------------------------------------------------------
# Affichage
# ---------------------------------------------------------------------------
function Write-Step([string]$Text) { Write-Host ''; Write-Host "== $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text) { Write-Host "   OK  $Text" -ForegroundColor Green }
function Write-Info([string]$Text) { Write-Host "       $Text" }
function Write-Warn([string]$Text) { Write-Host "   /!\ $Text" -ForegroundColor Yellow }

# ---------------------------------------------------------------------------
# Fichiers
# ---------------------------------------------------------------------------
function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

# Les fichiers lus par le jeu et les mods : ASCII, CRLF, sans BOM (un BOM désactive le FOV fix).
function Write-AsciiLines([string]$Path, [string[]]$Lines) {
    $text = ($Lines -join "`r`n") + "`r`n"
    [IO.File]::WriteAllText($Path, $text, (New-Object System.Text.ASCIIEncoding))
}

function Read-TextLines([string]$Path) {
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($l in [IO.File]::ReadAllLines($Path)) { $list.Add($l) }
    return , $list
}

# ---------------------------------------------------------------------------
# Manifeste : ce que l'installeur a ajouté, remplacé ou modifié.
# ---------------------------------------------------------------------------
$script:Manifest = $null

function Get-ManifestPath { return (Join-Path (Join-Path $GameDir $BackupDirName) 'manifest.json') }

function Read-Manifest {
    $path = Get-ManifestPath
    $entries = New-Object System.Collections.ArrayList
    if (Test-Path -LiteralPath $path) {
        $json = [IO.File]::ReadAllText($path) | ConvertFrom-Json
        foreach ($e in @($json.Entries)) {
            [void]$entries.Add(@{ Dest = [string]$e.Dest; Action = [string]$e.Action; Backup = [string]$e.Backup })
        }
    }
    $script:Manifest = $entries
}

function Save-Manifest {
    $dir = Join-Path $GameDir $BackupDirName
    if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir) }
    $obj = @{ Installer = $InstallerVersion; Entries = @($script:Manifest) }
    [IO.File]::WriteAllText((Get-ManifestPath), ($obj | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding $false))
}

function Find-ManifestEntry([string]$Dest) {
    foreach ($e in $script:Manifest) { if ($e.Dest -ieq $Dest) { return $e } }
    return $null
}

function Resolve-Dest([string]$Dest) {
    if ([IO.Path]::IsPathRooted($Dest)) { return $Dest }
    return (Join-Path $GameDir $Dest)
}

# Avant toute écriture : garde l'original une seule fois (jamais une version déjà modifiée par nous).
function Register-Change([string]$Dest, [string]$Action) {
    if ($null -ne (Find-ManifestEntry $Dest)) { return }
    $full = Resolve-Dest $Dest
    $backup = ''
    if (Test-Path -LiteralPath $full) {
        $bdir = Join-Path (Join-Path $GameDir $BackupDirName) 'originals'
        if (-not (Test-Path -LiteralPath $bdir)) { [void](New-Item -ItemType Directory -Path $bdir -Force) }
        $backup = Join-Path $BackupDirName (Join-Path 'originals' ([IO.Path]::GetFileName($Dest)))
        Copy-Item -LiteralPath $full -Destination (Join-Path $GameDir $backup) -Force
    } else {
        $Action = 'added'
    }
    [void]$script:Manifest.Add(@{ Dest = $Dest; Action = $Action; Backup = $backup })
    Save-Manifest
}

# ---------------------------------------------------------------------------
# Dossier du jeu
# ---------------------------------------------------------------------------
function Test-GameDir([string]$Dir) {
    if ([string]::IsNullOrWhiteSpace($Dir)) { return $false }
    return (Test-Path -LiteralPath (Join-Path $Dir 'Client.exe')) -and (Test-Path -LiteralPath (Join-Path $Dir 'SHOGO.REZ'))
}

function Find-GameDir {
    $candidates = New-Object System.Collections.Generic.List[string]
    if ($OnWindows) {
        foreach ($key in @('HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games\1207658659', 'HKLM:\SOFTWARE\GOG.com\Games\1207658659',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 610860')) {
            try {
                $item = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
                foreach ($name in @('path', 'InstallLocation')) {
                    if ($item.PSObject.Properties.Name -contains $name) { $candidates.Add([string]$item.$name) }
                }
            } catch {
                Write-Verbose "Pas de cle $key"
            }
        }
    }
    # Installeur décompressé dans le dossier du jeu ou à côté.
    $here = $PSScriptRoot
    for ($i = 0; $i -lt 3 -and $here; $i++) {
        $candidates.Add($here)
        $here = Split-Path -Parent $here
    }
    foreach ($c in $candidates) { if (Test-GameDir $c) { return (Resolve-Path -LiteralPath $c).Path } }

    # Dossiers contenant « shogo » sur les disques fixes, D: en premier.
    $found = New-Object System.Collections.Generic.List[string]
    $drives = @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } |
        Sort-Object -Property @{ Expression = { if ($_.Name -like 'D*') { 0 } else { 1 } } }, Name)
    foreach ($d in $drives) {
        Write-Info "Recherche du jeu sur $($d.Name)..."
        $dirs = Get-ChildItem -LiteralPath $d.RootDirectory.FullName -Directory -Recurse -Depth 3 -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like '*shogo*' }
        foreach ($dir in $dirs) {
            if ((Test-GameDir $dir.FullName) -and -not $found.Contains($dir.FullName)) { $found.Add($dir.FullName) }
        }
        if ($found.Count -gt 0) { break }
    }
    if ($found.Count -eq 1) { return $found[0] }
    if ($found.Count -gt 1) {
        Write-Warn 'Plusieurs installations trouvées :'
        for ($i = 0; $i -lt $found.Count; $i++) { Write-Info ("[{0}] {1}" -f ($i + 1), $found[$i]) }
        $choice = Read-Host 'Numéro de celle à utiliser'
        $n = 0
        if ([int]::TryParse($choice, [ref]$n) -and $n -ge 1 -and $n -le $found.Count) { return $found[$n - 1] }
    }
    $typed = Read-Host 'Chemin du dossier de Shogo (celui qui contient Client.exe)'
    $typed = $typed.Trim().Trim('"')
    if (Test-GameDir $typed) { return (Resolve-Path -LiteralPath $typed).Path }
    throw "Client.exe et SHOGO.REZ introuvables dans « $typed »."
}

function Assert-GameNotRunning {
    $running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
            ($_.ProcessName -ieq 'Client' -or $_.ProcessName -ieq 'Shogo') -and
            $_.Path -and $_.Path -like (Join-Path $GameDir '*')
        })
    if ($running.Count -gt 0) { throw 'Shogo tourne encore : ferme le jeu et son lanceur, puis relance l''installeur.' }
}

# ---------------------------------------------------------------------------
# Écran
# ---------------------------------------------------------------------------
function Get-DisplayMode {
    $mode = @{ Width = $ScreenWidth; Height = $ScreenHeight; Hz = $RefreshRate }
    if ($mode.Width -gt 0 -and $mode.Height -gt 0) { return $mode }
    if (-not $OnWindows) { throw 'Résolution inconnue : précise -ScreenWidth et -ScreenHeight.' }
    # EnumDisplaySettings donne de vrais pixels, sans la mise à l'échelle DPI de Windows.
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
    $cur = [ShogoModsDisplay]::Current()
    $mode.Width = $cur[0]; $mode.Height = $cur[1]
    if ($mode.Hz -le 0) { $mode.Hz = $cur[2] }
    if ($mode.Width -le 0 -or $mode.Height -le 0) { throw 'Impossible de lire la résolution de l''écran : précise -ScreenWidth et -ScreenHeight.' }
    return $mode
}

# ---------------------------------------------------------------------------
# Téléchargement et extraction
# ---------------------------------------------------------------------------
function Get-VerifiedDownload($Component, [string]$TempDir) {
    $name = [IO.Path]::GetFileName(([Uri]$Component.Url).AbsolutePath)
    $out = Join-Path $TempDir $name
    if (-not (Test-Path -LiteralPath $out) -or (Get-Sha256 $out) -ne $Component.Sha256) {
        Write-Info "Téléchargement de $name..."
        Invoke-WebRequest -Uri $Component.Url -OutFile $out -UseBasicParsing -UserAgent "ShogoMods/$InstallerVersion" -TimeoutSec 300
    }
    $hash = Get-Sha256 $out
    if ($hash -ne $Component.Sha256) {
        Remove-Item -LiteralPath $out -Force
        throw "Empreinte inattendue pour $name ($hash) : téléchargement corrompu ou fichier modifié à la source."
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
            if ($null -eq $entry) { throw "« $($f.Entry) » absent de $Archive." }
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
    # Windows PowerShell 5.1 transforme la sortie d'erreur d'un exécutable en erreur fatale sous 'Stop'.
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

# Le FOV fix n'existe qu'en RAR5 : tar de Windows (bsdtar, selon sa version), 7-Zip ou WinRAR.
function Expand-RarEntries([string]$Archive, $Files, [string]$OutDir) {
    $tools = New-Object System.Collections.Generic.List[object]
    if ($OnWindows) {
        $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
        if (Test-Path -LiteralPath $tar) { $tools.Add(@{ Exe = $tar; Args = @('-xf', $Archive, '-C', $OutDir) }) }
    }
    $bsd = Get-Command 'bsdtar' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($bsd) { $tools.Add(@{ Exe = $bsd.Source; Args = @('-xf', $Archive, '-C', $OutDir) }) }
    $sevenZip = New-Object System.Collections.Generic.List[string]
    foreach ($p in @("$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe")) {
        if ($p -and (Test-Path -LiteralPath $p)) { $sevenZip.Add($p) }
    }
    foreach ($n in @('7z', '7zz')) {
        $cmd = Get-Command $n -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) { $sevenZip.Add($cmd.Source) }
    }
    foreach ($s in $sevenZip) { $tools.Add(@{ Exe = $s; Args = @('e', '-y', "-o$OutDir", $Archive) }) }
    foreach ($p in @("$env:ProgramFiles\WinRAR\UnRAR.exe", "${env:ProgramFiles(x86)}\WinRAR\UnRAR.exe")) {
        if ($p -and (Test-Path -LiteralPath $p)) { $tools.Add(@{ Exe = $p; Args = @('e', '-y', $Archive, ($OutDir + [IO.Path]::DirectorySeparatorChar)) }) }
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
# Réglages
# ---------------------------------------------------------------------------
# dgVoodoo.conf : même clé possible dans plusieurs sections ([Glide] et [DirectX]) -> édition par section.
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

# autoexec.cfg : une commande console par ligne, "Clé" "valeur", noms insensibles à la casse.
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
# Désinstallation
# ---------------------------------------------------------------------------
function Invoke-Uninstall {
    Read-Manifest
    if ($script:Manifest.Count -eq 0) { Write-Warn 'Rien à désinstaller (aucun manifeste).'; return }
    Write-Step 'Restauration de l''état d''origine'
    foreach ($e in @($script:Manifest)) {
        $full = Resolve-Dest $e.Dest
        if ($e.Action -eq 'added') {
            if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Force }
            Write-Ok "supprimé : $($e.Dest)"
        } elseif ($e.Backup) {
            Copy-Item -LiteralPath (Join-Path $GameDir $e.Backup) -Destination $full -Force
            Write-Ok "restauré : $($e.Dest)"
        }
    }
    Remove-Item -LiteralPath (Join-Path $GameDir $BackupDirName) -Recurse -Force
    Write-Host ''
    Write-Host 'Désinstallation terminée.' -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Installation
# ---------------------------------------------------------------------------
function Install-Component($Component, [string]$TempDir, [string[]]$ManagedByOthers) {
    $label = $Component.Label
    $pending = @()
    foreach ($f in $Component.Files) {
        if ($ManagedByOthers -contains $f.Dest) { continue }
        $dest = Join-Path $GameDir $f.Dest
        if ((Test-Path -LiteralPath $dest) -and (Get-Sha256 $dest) -eq $f.Sha256) { continue }
        if ($f.ContainsKey('Config') -and (Test-Path -LiteralPath $dest)) { continue } # on garde le réglage existant, on l'éditera
        $pending += $f
    }
    if ($pending.Count -eq 0) { Write-Ok "$label : déjà en place"; return $true }

    $archive = Get-VerifiedDownload $Component $TempDir
    $xdir = Join-Path $TempDir $Component.Id
    if (Test-Path -LiteralPath $xdir) { Remove-Item -LiteralPath $xdir -Recurse -Force }
    [void](New-Item -ItemType Directory -Path $xdir)
    switch ($Component.Kind) {
        'file' { Copy-Item -LiteralPath $archive -Destination (Join-Path $xdir ([IO.Path]::GetFileName($pending[0].Dest))) }
        'zip' { Expand-ZipEntries $archive $pending $xdir }
        'rar' {
            if (-not (Expand-RarEntries $archive $Component.Files $xdir)) {
                Write-Warn "$label : impossible d'ouvrir l'archive .rar (ni tar de Windows, ni 7-Zip, ni WinRAR)."
                Write-Info 'Installe 7-Zip (https://www.7-zip.org) puis relance l''installeur, ou ignore ce correctif.'
                return $false
            }
        }
    }
    foreach ($f in $pending) {
        $name = if ($Component.Kind -eq 'file') { [IO.Path]::GetFileName($f.Dest) } else { [IO.Path]::GetFileName($f.Entry) }
        $src = Join-Path $xdir $name
        $hash = Get-Sha256 $src
        if ($hash -ne $f.Sha256) { throw "Empreinte inattendue pour $name extrait ($hash)." }
        Register-Change $f.Dest 'replaced'
        Copy-Item -LiteralPath $src -Destination (Join-Path $GameDir $f.Dest) -Force
    }
    Write-Ok "$label : installé"
    return $true
}

function Install-ShogoFps {
    $dist = Join-Path (Split-Path -Parent $PSScriptRoot) 'dist'
    $asi = Join-Path $dist 'ShogoFPS.asi'
    $ini = Join-Path $dist 'ShogoFPS.ini'
    if (-not (Test-Path -LiteralPath $asi)) { throw "ShogoFPS.asi introuvable dans $dist (garde le dossier dist à côté du dossier installer)." }
    $dest = Join-Path $GameDir 'ShogoFPS.asi'
    if ((Test-Path -LiteralPath $dest) -and (Get-Sha256 $dest) -eq (Get-Sha256 $asi)) {
        Write-Ok 'ShogoFPS : déjà à jour'
    } else {
        Register-Change 'ShogoFPS.asi' 'replaced'
        Copy-Item -LiteralPath $asi -Destination $dest -Force
        Write-Ok 'ShogoFPS : installé'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $GameDir 'ShogoFPS.ini'))) {
        Register-Change 'ShogoFPS.ini' 'added'
        Copy-Item -LiteralPath $ini -Destination (Join-Path $GameDir 'ShogoFPS.ini')
    } else {
        Write-Info 'ShogoFPS.ini existant conservé (tes réglages).'
    }
}

function Set-DgVoodooConfig($Mode, $Game) {
    $path = Join-Path $GameDir 'dgVoodoo.conf'
    if (-not (Test-Path -LiteralPath $path)) { Write-Warn 'dgVoodoo.conf absent, réglages ignorés.'; return }
    Register-Change 'dgVoodoo.conf' 'edited'
    $lines = Read-TextLines $path
    $native = '{0}x{1}' -f $Mode.Width, $Mode.Height
    $gameRes = '{0}x{1}' -f $Game.Width, $Game.Height
    # Peu de modes : le menu Affichage du jeu d'origine n'en accepte que 12.
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($r in @('640x480', '800x600', '1024x768', $gameRes, $native)) { if (-not $list.Contains($r)) { $list.Add($r) } }
    Set-IniValue $lines 'General' 'FullScreenMode' 'true'
    Set-IniValue $lines 'General' 'KeepWindowAspectRatio' 'true'
    Set-IniValue $lines 'General' 'CaptureMouse' 'true'
    Set-IniValue $lines 'DirectX' 'VRAM' '2048'
    Set-IniValue $lines 'DirectX' 'Filtering' '16'
    Set-IniValue $lines 'DirectX' 'Antialiasing' '4x'
    Set-IniValue $lines 'DirectX' 'AppControlledScreenMode' 'false'
    Set-IniValue $lines 'DirectX' 'DisableAltEnterToToggleScreenMode' 'false'
    Set-IniValue $lines 'DirectX' 'ForceVerticalSync' 'false'
    Set-IniValue $lines 'DirectX' 'dgVoodooWatermark' 'false'
    if ($Game.Upscaled) {
        # Le jeu tourne en 720p (ATH lisible), dgVoodoo rend la 3D à la résolution de l'écran.
        Set-IniValue $lines 'DirectX' 'Resolution' 'max'
        Set-IniValue $lines 'General' 'ScalingMode' 'stretched_ar'
    } else {
        Set-IniValue $lines 'DirectX' 'Resolution' 'unforced'
        Set-IniValue $lines 'General' 'ScalingMode' 'unspecified'
    }
    Set-IniValue $lines 'DirectXExt' 'DefaultEnumeratedResolutions' 'none'
    Set-IniValue $lines 'DirectXExt' 'ExtraEnumeratedResolutions' ($list -join ', ')
    Set-IniValue $lines 'DirectXExt' 'EnumeratedResolutionBitdepths' '16'
    Write-AsciiLines $path $lines
    Write-Ok ("dgVoodoo : plein écran, 3D en {0}, filtrage x16, antialiasing 4x, 2 Go de mémoire vidéo" -f $native)
}

function Set-FovConfig {
    $path = Join-Path $GameDir 'ShogoMobileArmorDivisionFOVFix.ini'
    if (-not (Test-Path -LiteralPath $path)) { return }
    $lines = Read-TextLines $path
    $before = $lines -join "`n"
    Set-IniValue $lines 'FOVFix' 'Enabled' 'true'
    $bytes = [IO.File]::ReadAllBytes($path)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    if ($hasBom -or $before -ne ($lines -join "`n")) {
        Register-Change 'ShogoMobileArmorDivisionFOVFix.ini' 'edited'
        if ($hasBom -and $lines.Count -gt 0) { $lines[0] = $lines[0].TrimStart([char]0xFEFF) }
        Write-AsciiLines $path $lines
    }
}

function Set-GameConfig($Mode, $Game) {
    $path = Join-Path $GameDir 'autoexec.cfg'
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Warn 'autoexec.cfg n''existe pas encore : lance Shogo une fois (puis quitte), et relance l''installeur pour régler la résolution.'
        return $false
    }
    Register-Change 'autoexec.cfg' 'edited'
    $lines = Read-TextLines $path
    Set-CfgValue $lines 'screenwidth' ([string]$Game.Width)
    Set-CfgValue $lines 'screenheight' ([string]$Game.Height)
    Set-CfgValue $lines 'MasterPaletteMode' '1.000000'
    Set-CfgValue $lines 'GlobalDetail' '2.000000'
    Set-CfgValue $lines 'inputrate' '10.000000'
    $cap = 141
    if ($Mode.Hz -gt 1) { $cap = [Math]::Max(60, [Math]::Min(200, $Mode.Hz - 3)) }
    Set-CfgValue $lines 'MaxFPS' ([string]$cap)
    $renderer = Get-CfgValue $lines 'RenderDll'
    Write-AsciiLines $path $lines
    Write-Ok ("Jeu : {0}x{1}, détails élevés, textures 16 bits, souris lissée, limite {2} FPS" -f $Game.Width, $Game.Height, $cap)
    if ($renderer -and $renderer -match 'soft') {
        Write-Warn 'Le jeu est réglé sur le rendu logiciel : dans Shogo.exe > Display, choisis le périphérique Direct3D (dgVoodoo).'
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
    $sc.Description = 'Shogo: Mobile Armor Division avec ShogoFPS'
    $sc.Save()
    Write-Ok "Raccourci « $([IO.Path]::GetFileNameWithoutExtension($ShortcutName)) » créé sur le bureau"
}

# ---------------------------------------------------------------------------
# Programme principal
# ---------------------------------------------------------------------------
trap {
    Write-Host ''
    Write-Host ('ERREUR : ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host 'Rien n''est cassé : les fichiers déjà remplacés sont sauvegardés dans ShogoMods_Backup.' -ForegroundColor Red
    exit 1
}

Write-Host "Correctifs modernes pour Shogo: Mobile Armor Division - installeur $InstallerVersion" -ForegroundColor White

if (-not (Test-GameDir $GameDir)) {
    if ($GameDir) { Write-Warn "« $GameDir » ne contient pas Client.exe et SHOGO.REZ." }
    $GameDir = Find-GameDir
} else {
    $GameDir = (Resolve-Path -LiteralPath $GameDir).Path
}
Write-Info "Dossier du jeu : $GameDir"
Assert-GameNotRunning

if ($Uninstall) {
    Invoke-Uninstall
    exit 0
}

Read-Manifest
$temp = Join-Path $GameDir 'ShogoMods_Temp'
if (-not (Test-Path -LiteralPath $temp)) { [void](New-Item -ItemType Directory -Path $temp) }

$managed = @()
if (Test-Path -LiteralPath (Join-Path $GameDir 'ShogoFRESH.rez')) {
    $managed = @('dinput.dll', 'DDraw.dll', 'D3DImm.dll', 'dgVoodooCpl.exe', 'dgVoodoo.conf')
    Write-Info 'ShogoFRESH détecté : il garde la main sur dinputto8 et dgVoodoo.'
}

$fovOk = $false
try {
    Write-Step 'Composants'
    foreach ($c in $Components) {
        if ($c.Id -eq 'fovfix' -and $NoFovFix) { continue }
        $ok = Install-Component $c $temp $managed
        if ($c.Id -eq 'fovfix') { $fovOk = $ok }
    }
    Install-ShogoFps
    if ($fovOk) { Set-FovConfig }

    Write-Step 'Réglages'
    $mode = Get-DisplayMode
    $game = @{ Width = $mode.Width; Height = $mode.Height; Upscaled = $false }
    if (-not $NativeResolution -and $managed.Count -eq 0 -and $mode.Height -gt 720) {
        $w = [int]([Math]::Round(720.0 * $mode.Width / $mode.Height / 2.0) * 2)
        $game = @{ Width = $w; Height = 720; Upscaled = $true }
    }
    Write-Info ("Écran : {0}x{1} à {2} Hz" -f $mode.Width, $mode.Height, $mode.Hz)
    if ($managed.Count -eq 0) { Set-DgVoodooConfig $mode $game }
    $cfgOk = Set-GameConfig $mode $game
    New-GameShortcut
} finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
Write-Host 'Installation terminée.' -ForegroundColor Green
if ($game.Upscaled) {
    Write-Info ("Le jeu tourne en {0}x{1} pour garder un ATH lisible ; dgVoodoo rend la 3D en {2}x{3}." -f $game.Width, $game.Height, $mode.Width, $mode.Height)
    Write-Info 'Pour tout en natif (ATH minuscule) : relance avec -NativeResolution.'
}
if (-not $cfgOk) { Write-Info 'Lance le jeu une fois, quitte-le, puis relance l''installeur pour finir les réglages.' }
Write-Info 'Sauvegardes des fichiers d''origine : ShogoMods_Backup dans le dossier du jeu. Désinstallation : Uninstall-ShogoMods.bat'
Write-Info 'Journal de ShogoFPS : ShogoFPS.log dans le dossier du jeu, après une partie.'
exit 0
