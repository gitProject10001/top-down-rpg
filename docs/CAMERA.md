# Camera corrente

La scena integrata usa `scripts/village/iso_cam.gd`: prospettiva stretta a 13°, rotazione libera e rotazione durante il lock disattivate nella presentazione corrente. Il default dello script per altre scene resta ortografico.

## Inspector

- `Perspective Fov`: 0 = ortografica; valore positivo = prospettiva. Non è un angolo FOV fisico nullo.
- `Ortho Size`: estensione del piano di fuoco; la distanza si ricava da span / (2 × tan(FOV/2)). Il matching conserva la scala al fuoco.
- `Pitch Deg`, `Yaw Deg`: orientamento; `Free Rotate` e `Lock Rotate`: opt-in per altre presentazioni.
- `Interior Zoom Ratio` (0,72) e `Interior Zoom Speed`: avvicinamento morbido negli interni rilevati dallo stesso sistema del cutaway. Uscendo torna normale.
- La camera preserva lo spazio necessario fra player e bersaglio durante lock. O apre la panoramica; lo snap a pixel si applica soltanto in ortografica.

Il pannello P espone DOF opzionale basato sulla profondità della camera, con banda nitida anteriore/posteriore e fuoco sul personaggio. UI fuori dal viewport filtrato. Le modifiche del pannello sono temporanee.

Verifiche: `tools/check_camera_fov.gd`, `check_overview_camera.gd`, `check_interior_sheath.tscn`, `check_post_controls.tscn`. Le vecchie fixture di mapping direzionale non definiscono più il combattimento del player.
