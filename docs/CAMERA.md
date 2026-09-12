# Camera: prospettiva leggera

La camera `IsoCam` usa di default l'ortografica fissa, anche durante il lock-on.
La prospettiva stretta resta selezionabile: FOV verticale 20 gradi,
pitch della scena 48 gradi.
Questa nota sostituisce le precedenti descrizioni della camera come esclusivamente ortografica.

Nell'Inspector dello script:
- `Free Rotate`: abilita la rotazione manuale (default spento).
- `Lock Rotate`: abilita la rotazione automatica durante il lock (default spento).
- `Perspective Enabled`: attiva la prospettiva; disattivare ripristina l'ortografica.
- `Perspective Fov`: intensita della prospettiva.
- `Match Perspective Framing`: mantiene l'inquadratura al piano di fuoco.
- `Ortho Size`: estensione verticale al piano di fuoco, anche in prospettiva con matching.
- `Distance`: distanza manuale se il matching e disattivato.

Con estensione 17,5 m e FOV 20 gradi, distanza = 17,5 / (2 tan(10 gradi)) = 49,62 m.
Il lock-on continua a modificare l'inquadratura; in prospettiva questo cambia la distanza.
Lo snap di camera e personaggi e escluso in prospettiva, dove la dimensione mondiale
di un pixel varia con la profondita. Il vecchio snap resta disponibile in ortografica.

Test: `tools/check_perspective_camera.gd` verifica proiezione, FOV, distanza,
quattro orientamenti e ritorno all'ortografica. Non verifica il combattimento end-to-end.

`PlayerIntent.screen_relative_directions` converte input laterali dello schermo
nelle direzioni locali del combattente, confrontando asse destro del modello e camera.
La stessa mappatura invertibile alimenta l'HUD. Alto/basso rimangono overhead/affondo.
Vicino al profilo la soglia 0,15 mantiene l'ultimo lato: non esiste una corrispondenza
laterale univoca quando l'asse destro del corpo punta nella profondita dello schermo.
La regola di mirroring dei colpi in arrivo rimane nel sistema di parata, invariata.
`tools/check_fixed_camera.gd` verifica camera fissa anche in lock, orbit opzionale,
orientamenti opposti del personaggio e round-trip input/HUD. Serve ancora una prova
giocata per valutare leggibilita delle animazioni e cambi di orientamento durante il colpo.
