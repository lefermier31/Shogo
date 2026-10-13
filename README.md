# ShogoFPS

Correctif de fréquence d'images pour **Shogo: Mobile Armor Division** (LithTech 1.0, version 2.2 GOG/Steam).
Il permet de jouer à 144 FPS et plus sans que le jeu accélère, avec une visée souris fluide.

ShogoFPS est un plugin `.asi` chargé par Ultimate ASI Loader. Il agit **uniquement en mémoire** : aucun fichier du jeu n'est modifié.

## Ce que ça corrige

| Problème d'origine | Cause | Correctif |
|---|---|---|
| Au-delà de ~100 FPS, le monde accélère : IA, projectiles, portes, cinématiques. Les répliques se coupent. Avec un minuteur à 1 ms, c'est ×1,44 à 144 FPS et ×2,4 à 240 FPS. Avec le minuteur par défaut de Windows (15,6 ms), ça commence vers 64 FPS et monte à ~×1,8 à 144 FPS. | Le moteur fait avancer le serveur local une fois par image, d'au moins 10 ms à chaque fois. | Le serveur n'est mis à jour qu'une fois 10 ms écoulées. Le monde garde sa vitesse réelle. |
| Minuteur imprécis. | Le moteur ne demande jamais le minuteur Windows à 1 ms. | `timeBeginPeriod(1)` pour le processus du jeu. |
| Visée souris saccadée au-delà de ~64 FPS. | La boucle DirectInput mesure le temps avec `GetTickCount`, qui avance par pas de 15,6 ms. | Cette lecture passe par une horloge à 1 ms, toujours un peu en retard sur l'horloge Windows. C'est la condition pour ne jamais bloquer la souris. |

### Effet du correctif sur la fluidité des ennemis

Le serveur avance au plus toutes les 10 ms. La caméra et ton mecha suivent tes FPS, mais les objets gérés par le serveur (ennemis, projectiles, portes) bougent à la cadence du serveur :

| FPS | Mises à jour du monde par seconde |
|---|---|
| jusqu'à ~90 | une par image |
| 120 | ~60 |
| 141 | ~70 |
| 144 | ~72 |
| 165 | ~82 |
| 240 | ~80 |

L'écart se voit le plus entre 100 et 140 FPS.

### Ce que ShogoFPS ne corrige pas

Ces défauts sont dans le code de jeu (`CShell.dll`) et demandent de le recompiler, ce qui est le domaine de ShogoFRESH :
- la visée haut/bas **au clavier** et au joystick va plus vite quand les FPS montent ;
- la poussée verticale des explosions augmente avec les FPS (rocket jump plus haut) ;
- certains effets de particules sont plus denses à haut FPS.

## Installation automatique (recommandée)

L'installeur télécharge chaque composant depuis sa page officielle et vérifie son empreinte SHA256. Il installe tout dans le dossier du jeu (D: chez toi, téléchargements temporaires compris) et règle le jeu pour ton écran. Il n'a pas besoin des droits administrateur, ni de ShogoFRESH.

1. Télécharge ce dépôt : bouton **Code** → **Download ZIP**, puis décompresse-le où tu veux, par exemple sur D:.
2. Ferme Shogo s'il est ouvert, puis double-clique sur `installer\Install-ShogoMods.bat`.
3. L'installeur trouve le jeu tout seul (registre GOG, puis recherche sur les disques). Sinon, il te demande le dossier qui contient `Client.exe`.
4. S'il indique qu'`autoexec.cfg` n'existe pas encore : lance le jeu une fois avec `Shogo.exe`, quitte-le, puis relance l'installeur.
5. Joue avec le raccourci **Shogo (ShogoFPS)** créé sur le bureau.

Ce qui est installé et réglé :

| Composant | Rôle |
|---|---|
| dinputto8 1.1.100.0 | Le jeu démarre sous Windows 10/11 |
| dgVoodoo2 2.87.5 | Rendu Direct3D moderne : plein écran, 3D à la résolution de l'écran, filtrage x16, antialiasing 4x, 2 Go de mémoire vidéo, sans filigrane |
| Ultimate ASI Loader 9.7.4 | Charge les plugins `.asi` (installé sous le nom `winmm.dll`) |
| FOV fix AlphaYellow 1.3 | Champ de vision correct en 16:9 |
| ShogoFPS | Vitesse réelle à haut FPS, souris fluide |
| `autoexec.cfg` | Résolution, détails élevés, textures 16 bits, `inputrate 10`, limite à 141 FPS sur un écran 144 Hz |

**Résolution.** Par défaut, le jeu tourne en 1280x720 pendant que dgVoodoo rend la 3D à la résolution de ton écran : l'image reste nette et le HUD de 1998 garde une taille lisible. Pour tout en résolution native (HUD minuscule), lance `Install-ShogoMods.bat -NativeResolution`.

**Le correctif FOV** n'est publié qu'en `.rar`. L'installeur l'ouvre avec le `tar` de Windows s'il en est capable, sinon avec 7-Zip ou WinRAR s'ils sont installés. Si aucun ne marche, il le signale et continue sans ce correctif.

**Sauvegardes.** Chaque fichier remplacé ou modifié est d'abord sauvegardé dans `ShogoMods_Backup`, dans le dossier du jeu. Tu peux relancer l'installeur sans risque. `installer\Uninstall-ShogoMods.bat` remet tout comme avant. Si ShogoFRESH est installé, l'installeur lui laisse dinputto8 et dgVoodoo.

## Installation manuelle

1. Installe **Shogo** en version 2.2 :
   - **GOG** (installeur 2.1.0.7 ou 2.2.14) : pour la VF, choisis le français dans ta bibliothèque GOG ;
   - **Steam** : la version vendue est elle aussi en 2.2.
2. Installe **dgVoodoo2** et **dinputto8**, ou bien **[ShogoFRESH](https://github.com/KyodanCFG/ShogoFRESH/releases)**, qui s'en charge.
3. Télécharge **[Ultimate ASI Loader](https://github.com/ThirteenAG/Ultimate-ASI-Loader/releases)** en version Win32. Copie sa DLL dans le dossier du jeu, à côté de `Client.exe`, sous le nom `winmm.dll`.
4. Copie `ShogoFPS.asi` et `ShogoFPS.ini` (dossier `dist/`) dans le dossier du jeu.
5. Lance le jeu. Un journal `ShogoFPS.log` est créé :
   - à côté de la DLL en temps normal ;
   - dans `%LOCALAPPDATA%\ShogoFPS\` si le jeu est sous `Program Files`, où Windows bloque l'écriture ;
   - dans le dossier de ton choix si tu règles `LogDir` dans `ShogoFPS.ini`.

   La première ligne du journal donne son chemin exact.

Pour désinstaller, supprime `ShogoFPS.asi`, `ShogoFPS.ini` et `ShogoFPS.log`. Supprime aussi `winmm.dll` si aucun autre plugin `.asi` ne s'en sert.

### Réglages conseillés

L'installeur automatique fait déjà le nécessaire. Ces réglages servent à l'installation manuelle, ou pour aller plus loin.

**Écran 144 Hz G-Sync / FreeSync**
- **Lanceur ShogoFRESH** (si tu l'utilises) : décoche **Frame rate cap**. Il est coché à 120 par défaut et réécrit `MaxFPS` à chaque lancement, donc ne modifie pas `MaxFPS` à la main.
- **Panneau NVIDIA** → Gérer les paramètres 3D → Paramètres de programme → `Client.exe` :
  - Fréquence d'images maximale : **141** ;
  - Synchronisation verticale : **Activée** ;
  - G-SYNC actif.
- **dgVoodoo** : VSync désactivée (le pilote s'en charge).

**Sans G-Sync**
- Garde un plafond, au choix : le limiteur du pilote, RTSS, ou **Frame rate cap** à 200 dans ShogoFRESH (le moteur ne va de toute façon pas au-delà).
- Ne dépasse jamais ~500 FPS : au-delà, même l'horloge à 1 ms ne suffit plus à la souris.

**Console du jeu**
- `inputrate 10` (valeur de ShogoFRESH, complémentaire du correctif souris).

**Démos**
- Pour enregistrer une démo, mets `ServerTickFix=0` le temps de l'enregistrement.

## Vérifier que ça marche (2 parties de 2 minutes)

1. Dans `ShogoFPS.ini`, mets `DiagnoseOnly=1`. Lance une mission, joue 2 minutes puis quitte le jeu. Dans ce mode, ShogoFPS ne change rien au jeu : il mesure.
2. Renomme `ShogoFPS.log` en `ShogoFPS-diagnostic.log`. Le fichier est réécrit à chaque lancement.
3. Remets `DiagnoseOnly=0`, rejoue 2 minutes au même endroit et quitte.
4. Envoie-moi les deux journaux dans la conversation.

### Lignes importantes du journal

| Ligne | Ce qu'elle signifie |
|---|---|
| `ready: server tick fix ON, mouse fix ON` | Les deux correctifs sont posés. Si l'un est `off`, les lignes `scan:` ou `mouse:` juste au-dessus disent pourquoi. |
| `mouse: fine clock active, 20 ms behind GetTickCount` | La souris est réellement corrigée. Si tu lis `pass-through`, elle ne l'est pas (par exemple si `TimerResolution=0`). |
| `self-check ok (0/32 mismatches)` | Le moteur range son temps là où ShogoFPS l'attend. Un `self-check FAILED` désactive le saut des mises à jour ; le minuteur et la souris restent corrigés. |
| `game speed x1.000` | Le monde va à la vitesse réelle. En mode diagnostic, on attend ~`x1.44` à 144 FPS si la ligne `timer:` indique un pas de 1 ms, ~`x1.8` si elle indique 15 ou 16 ms. |
| `unpatched engine would run x1.44 (timer step 1 ms)` | Vitesse qu'aurait le jeu d'origine à ces FPS, avec le minuteur indiqué. |
| `skipped`, `valve`, `frozen-clock`, `inactive` | Mises à jour sautées (normal au-dessus de ~100 FPS), forcées après 100 ms sans mise à jour, cadencées pendant que la fenêtre est en arrière-plan avec `alwaysfocused 1`, et passées telles quelles fenêtre inactive. |
| `mouse: ... 0% of reads with no time progress` | Souris fluide. Sans le correctif, ce chiffre dépasse 50 % à 144 FPS. |

## Sécurité du correctif

ShogoFPS ne s'active que dans `Client.exe`. Il ne fait rien dans les autres programmes (lanceur `Shogo.exe`, serveur dédié…).

Avant de toucher quoi que ce soit, il vérifie la structure de l'exécutable, sans aucune adresse codée en dur :
- les constantes de temps du moteur ;
- les chaînes repères autour de la mise à jour du serveur ;
- l'appel unique à cette fonction, sa convention d'appel et les champs qu'elle utilise.

Si la détection est ambiguë (et au moindre doute avec `Strict=1`), il s'abstient et l'écrit dans le journal.

En cours de partie, il contrôle aussi que le moteur range son temps là où il l'attend. Sinon, il arrête de sauter des mises à jour.

## Compilation

Depuis Linux (Debian/Ubuntu) :

```sh
sudo dpkg --add-architecture i386 && sudo apt update
sudo apt install gcc-mingw-w64-i686 wine wine32:i386 python3
make            # produit dist/ShogoFPS.asi
make test       # 22 tests sous Wine, avec un faux Client.exe qui imite la mécanique du moteur
PWSH=pwsh installer/tests/test_installer.sh   # 34 tests de l'installeur (PowerShell 7, faux dossier de jeu)
```

## Mentions

Code original sous licence MIT. Il ne contient aucun code de Monolith ni aucun code décompilé.
ShogoFPS n'est ni fait ni soutenu par Monolith Productions.
Shogo: Mobile Armor Division est une marque de ses ayants droit.
