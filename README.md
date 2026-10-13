# ShogoFPS

Correctif de fréquence d'images pour **Shogo: Mobile Armor Division** (LithTech 1.0, version 2.2 GOG/Steam).
Il permet de jouer à 144 FPS et plus sans que le jeu accélère, avec une visée souris fluide.

ShogoFPS est un plugin `.asi` chargé par Ultimate ASI Loader. Il agit **uniquement en mémoire** : aucun fichier du jeu n'est modifié.

## Ce que ça corrige

| Problème d'origine | Cause | Correctif |
|---|---|---|
| Au-delà de ~100 FPS, le monde accélère : IA, projectiles, portes, cinématiques (×1,44 à 144 FPS, ×2,4 à 240 FPS). Les répliques se coupent. | Le moteur fait avancer le serveur local une fois par image, d'au moins 10 ms. | Le serveur n'est mis à jour qu'une fois 10 ms écoulées. Le monde garde sa vitesse réelle, à environ 72-100 mises à jour par seconde, comme en multijoueur. |
| Accélération possible dès ~64 FPS sur certains PC. | Le moteur ne demande jamais le minuteur Windows à 1 ms. | `timeBeginPeriod(1)` pour le processus du jeu. |
| Visée souris saccadée au-delà de ~64 FPS. | La boucle DirectInput mesure le temps avec `GetTickCount`, qui avance par pas de 15,6 ms. | Cette lecture passe par une horloge à 1 ms, toujours un peu en retard sur l'horloge Windows (condition pour ne pas bloquer la souris). |

**Ce que ShogoFPS ne corrige pas** : ces défauts sont dans le code de jeu (`CShell.dll`) et demandent de le recompiler, ce qui est le domaine de ShogoFRESH.
- La visée haut/bas **au clavier** et au joystick va plus vite quand les FPS montent.
- La poussée verticale des explosions augmente avec les FPS (rocket jump plus haut).
- Certains effets de particules sont plus denses à haut FPS.
- À 144 FPS, les objets gérés par le serveur (ennemis, projectiles) bougent à ~72 Hz pendant que la caméra tourne à 144 Hz.

## Installation

1. Installe **Shogo GOG** (2.1.0.7 ou 2.2.14). Pour la VF, choisis le français dans ta bibliothèque GOG.
2. *(Recommandé)* Installe **[ShogoFRESH](https://github.com/KyodanCFG/ShogoFRESH)**. Il apporte dgVoodoo2, dinputto8, le widescreen, la musique, etc. Sans lui, il faut au minimum dgVoodoo2 et dinputto8 à la main.
3. Télécharge **[Ultimate ASI Loader](https://github.com/ThirteenAG/Ultimate-ASI-Loader/releases)**, version Win32 (`winmm-Win32.zip`). Copie le `winmm.dll` qu'il contient dans le dossier du jeu, à côté de `Client.exe`.
4. Copie `ShogoFPS.asi` et `ShogoFPS.ini` (dossier `dist/`) dans le dossier du jeu.
5. Lance le jeu comme d'habitude. Un fichier `ShogoFPS.log` apparaît à côté de la DLL.

Pour désinstaller, supprime `ShogoFPS.asi`, `ShogoFPS.ini` et `ShogoFPS.log`. Supprime aussi `winmm.dll` si aucun autre plugin `.asi` ne s'en sert.

### Réglages conseillés (écran 144 Hz G-Sync)

- **ShogoFRESH** : désactive son limiteur de FPS (ou laisse `MaxFPS 0`). Celui du moteur est imprécis et plafonné à 200.
- **Panneau NVIDIA** → Gérer les paramètres 3D → Paramètres de programme → `Client.exe` :
  - Fréquence d'images maximale : **141** ;
  - Synchronisation verticale : **Activée** ;
  - G-SYNC actif.
- **dgVoodoo** : VSync désactivée (le pilote s'en charge).
- **Console du jeu** : `inputrate 10` (valeur de ShogoFRESH, complémentaire du correctif souris).

## Vérifier que ça marche (2 parties de 2 minutes)

1. Dans `ShogoFPS.ini`, mets `DiagnoseOnly=1`, lance une mission et joue 2 minutes. ShogoFPS ne change rien au jeu, il mesure.
2. Remets `DiagnoseOnly=0` et rejoue 2 minutes au même endroit.
3. Envoie les deux `ShogoFPS.log` (le fichier est réécrit à chaque lancement, copie-le entre les deux parties).

Lignes importantes du journal :
- `ready: server tick fix ON, mouse fix ON` : les deux correctifs sont actifs. Si l'un est `off`, les lignes `scan:` ou `mouse:` juste au-dessus disent pourquoi.
- `game speed x1.000` : le monde va à la vitesse réelle. En mode diagnostic à 144 FPS, on attend environ `x1.44`.
- `unpatched engine would run x1.44` : estimation de la vitesse qu'aurait le jeu d'origine à ce nombre de FPS.
- `mouse: ... 2% of reads with no time progress` : souris fluide. Sans le correctif, ce chiffre dépasse 50 % à 144 FPS.

## Sécurité du correctif

ShogoFPS ne s'active que dans `Client.exe` et ne fait rien dans les autres programmes (lanceur `Shogo.exe`, serveur dédié…).

Avant de toucher quoi que ce soit, il vérifie que l'exécutable a la structure attendue, sans adresse codée en dur :
- les constantes de temps du moteur ;
- les chaînes repères autour de la mise à jour du serveur ;
- l'appel unique à cette fonction ;
- les champs qu'elle utilise.

Au moindre doute, il s'abstient et l'écrit dans le journal. En cours de partie, il contrôle aussi que le moteur range son temps là où il l'attend. Sinon il se désactive : le jeu tourne alors exactement comme sans lui.

## Compilation

Depuis Linux :

```sh
sudo apt install gcc-mingw-w64-i686 wine wine32:i386
make            # produit dist/ShogoFPS.asi
make test       # 12 tests sous Wine, avec un faux Client.exe qui imite la mécanique du moteur
```

## Mentions

Code original sous licence MIT. Il ne contient aucun code de Monolith ni aucun code décompilé.
ShogoFPS n'est ni fait ni soutenu par Monolith Productions.
Shogo: Mobile Armor Division est une marque de ses ayants droit.
