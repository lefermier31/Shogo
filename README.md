# ShogoFPS

Frame-rate fix for **Shogo: Mobile Armor Division** (LithTech 1.0, GOG/Steam version 2.2).
With it the game can run at 144 fps and beyond at the right speed, with smooth mouse aim.

ShogoFPS is an `.asi` plugin loaded by Ultimate ASI Loader. It works **in memory only**: no game file is modified.

## What it fixes

| Original problem | Cause | Fix |
|---|---|---|
| Above ~100 fps the world speeds up: AI, projectiles, doors, cutscenes. Voice lines get cut off. With a 1 ms timer that is x1.44 at 144 fps and x2.4 at 240 fps. With Windows' default 15.6 ms timer it starts around 64 fps and reaches ~x1.8 at 144 fps. | The engine advances the local server once per frame, by at least 10 ms each time. | The server is only updated once 10 ms have elapsed, so the world runs at real speed. |
| Coarse timer. | The engine never asks Windows for a 1 ms timer. | `timeBeginPeriod(1)` for the game process. |
| Mouse aim stutters above ~64 fps. | The DirectInput loop times input with `GetTickCount`, which moves in 15.6 ms steps. | That read goes through a 1 ms clock kept slightly behind Windows' clock, which is what keeps the mouse from ever freezing. |

### Side effect on enemy smoothness

The server advances at most every 10 ms. The camera and your mech follow your frame rate, but server-driven objects (enemies, projectiles, doors) move at the server's rate:

| fps | World updates per second |
|---|---|
| up to ~90 | one per frame |
| 120 | ~60 |
| 141 | ~70 |
| 144 | ~72 |
| 165 | ~82 |
| 240 | ~80 |

The difference is most visible between 100 and 140 fps.

### What ShogoFPS does not fix

These issues live in the game code (`CShell.dll`). Fixing them means recompiling it, which is ShogoFRESH's territory:
- **keyboard** and joystick look up/down gets faster as fps rises;
- vertical push from explosions grows with fps (higher rocket jumps);
- some particle effects get denser at high fps.

## Automatic install (recommended)

The installer downloads each component from its official release page and checks its SHA256. It installs everything into the game folder, temporary downloads included, and configures the game for your display. It needs neither administrator rights nor ShogoFRESH.

1. Download this repository: **Code** → **Download ZIP**, then extract it anywhere.
2. Close Shogo if it is running, then double-click `installer\Install-ShogoMods.bat`.
3. The installer finds the game on its own: GOG registry first, then a search of your drives. Otherwise it asks for the folder that contains `Client.exe`.
4. If it reports that `autoexec.cfg` does not exist yet, start the game once with `Shogo.exe`, quit, and run the installer again.
5. Play with the **Shogo (ShogoFPS)** shortcut it puts on the desktop.

What gets installed and configured:

| Component | Role |
|---|---|
| dinputto8 1.1.100.0 | The game starts on Windows 10/11 |
| dgVoodoo2 2.87.5 | Modern Direct3D rendering: fullscreen, 3D at your display's resolution, 16x filtering, 4x antialiasing, 2 GB video memory, no watermark |
| Ultimate ASI Loader 9.7.4 | Loads `.asi` plugins (installed as `winmm.dll`) |
| AlphaYellow FOV fix 1.3 | Correct field of view in 16:9 |
| ShogoFPS | Real game speed at high fps, smooth mouse |
| `autoexec.cfg` | Resolution, high detail, 16-bit textures, `inputrate 10`, frame cap 3 fps below the refresh rate (141 on a 144 Hz display) |

**Resolution.** By default the game runs at 1280x720 while dgVoodoo renders the 3D at your display's resolution. The picture stays sharp and the 1998 HUD stays readable. For everything at native resolution (tiny HUD), run `Install-ShogoMods.bat -NativeResolution`.

**The FOV fix** is only published as a `.rar`. The installer opens it with Windows' built-in `tar` when that version can, otherwise with 7-Zip or WinRAR if installed. If none works, it says so and carries on without this fix.

**Backups.** Every file it replaces or edits is first saved to `ShogoMods_Backup` in the game folder. Running the installer again is safe, and `installer\Uninstall-ShogoMods.bat` puts everything back. If ShogoFRESH is installed, the installer leaves dinputto8 and dgVoodoo to it.

## Manual install

1. Install **Shogo** version 2.2:
   - **GOG** (installer 2.1.0.7 or 2.2.14). For the French dub, pick French in your GOG library.
   - **Steam**: the version sold there is 2.2 as well.
2. Install **dgVoodoo2** and **dinputto8**, or **[ShogoFRESH](https://github.com/KyodanCFG/ShogoFRESH/releases)**, which takes care of both.
3. Download **[Ultimate ASI Loader](https://github.com/ThirteenAG/Ultimate-ASI-Loader/releases)**, Win32 build, and copy its DLL into the game folder next to `Client.exe`, named `winmm.dll`.
4. Copy `ShogoFPS.asi` and `ShogoFPS.ini` from `dist/` into the game folder.
5. Start the game. A `ShogoFPS.log` file is created:
   - next to the DLL normally;
   - in `%LOCALAPPDATA%\ShogoFPS\` if the game is under `Program Files`, where Windows blocks writes;
   - in the folder set with `LogDir` in `ShogoFPS.ini`, if any.

   Its first line gives its exact path.

To uninstall, delete `ShogoFPS.asi`, `ShogoFPS.ini` and `ShogoFPS.log`. Delete `winmm.dll` too if no other `.asi` plugin uses it.

### Recommended settings

The automatic installer already takes care of what matters. These settings are for a manual install, or to go further.

**144 Hz G-Sync / FreeSync display**
- **ShogoFRESH launcher** (if you use it): untick **Frame rate cap**. It is ticked at 120 by default and rewrites `MaxFPS` on every launch, so don't edit `MaxFPS` by hand.
- **NVIDIA Control Panel** → Manage 3D settings → Program settings → `Client.exe`:
  - Max Frame Rate: **141**;
  - Vertical sync: **On**;
  - G-SYNC enabled.
- **dgVoodoo**: VSync off (the driver handles it).

**Without G-Sync**
- Keep a frame cap, whichever you like: the driver limiter, RTSS, or **Frame rate cap** at 200 in ShogoFRESH (the engine goes no higher anyway).
- Never go beyond ~500 fps: past that point even the 1 ms clock is not enough for the mouse.

**Game console**
- `inputrate 10` (ShogoFRESH's value, complements the mouse fix).

**Demos**
- To record a demo, set `ServerTickFix=0` while recording.

## Checking that it works (two 2-minute sessions)

1. In `ShogoFPS.ini`, set `DiagnoseOnly=1`. Start a mission, play for 2 minutes, then quit. In this mode ShogoFPS changes nothing in the game: it only measures.
2. Rename `ShogoFPS.log` to `ShogoFPS-diagnostic.log`. The file is rewritten on every launch.
3. Set `DiagnoseOnly=0` back, play 2 minutes at the same spot, then quit.
4. Send both logs.

### Key log lines

| Line | What it means |
|---|---|
| `ready: server tick fix ON, mouse fix ON` | Both fixes are in place. If one says `off`, the `scan:` or `mouse:` lines just above say why. |
| `mouse: fine clock active, 20 ms behind GetTickCount` | The mouse really is fixed. If you read `pass-through` instead, it is not (for example with `TimerResolution=0`). |
| `self-check ok (0/32 mismatches)` | The engine keeps its time where ShogoFPS expects it. A `self-check FAILED` turns update skipping off; the timer and mouse fixes stay on. |
| `game speed x1.000` | The world runs at real speed. In diagnose mode at 144 fps, expect ~`x1.44` if the `timer:` line shows a 1 ms step, ~`x1.8` if it shows 15 or 16 ms. |
| `unpatched engine would run x1.44 (timer step 1 ms)` | The speed the original game would have at this frame rate, with the timer shown. |
| `skipped`, `valve`, `frozen-clock`, `inactive` | Updates skipped (normal above ~100 fps), updates forced after 100 ms without one, updates paced while the window is in the background with `alwaysfocused 1`, and updates passed through unchanged while the window is inactive. |
| `mouse: ... 0% of reads with no time progress` | Smooth mouse. Without the fix, this goes over 50% at 144 fps. |

## Safety

ShogoFPS only activates inside `Client.exe`. It does nothing in other programs (the `Shogo.exe` launcher, the dedicated server…).

Before touching anything, it checks the executable's structure, without any hard-coded address:
- the engine's time constants;
- the anchor strings around the server update;
- the single call to that function, its calling convention, and the fields it uses.

If detection is ambiguous (or at the slightest doubt with `Strict=1`), it stays out and says so in the log.

While the game runs, it also checks that the engine keeps its time where expected. If not, it stops skipping updates.

## Building

On Linux (Debian/Ubuntu):

```sh
sudo dpkg --add-architecture i386 && sudo apt update
sudo apt install gcc-mingw-w64-i686 wine wine32:i386 python3
make            # builds dist/ShogoFPS.asi
make test       # 22 Wine tests, against a fake Client.exe that mimics the engine's mechanics
PWSH=pwsh installer/tests/test_installer.sh   # 34 installer tests (PowerShell 7, fake game folder)
```

## Credits

Original code under the MIT licence. It contains no Monolith code and no decompiled code.
ShogoFPS is not made or supported by Monolith Productions.
Shogo: Mobile Armor Division is a trademark of its respective owners.
