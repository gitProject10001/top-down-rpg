# Combattimento nella scena integrata

Aprire `scenes/dev/integrated_landscape.tscn` e avviare la scena corrente.
Il gruppo di quattro predoni compare nel prato, senza sostituire terreno,
vegetazione o geometria del concept.

| Comando | Azione |
| --- | --- |
| 4 | Raggiungi il gruppo e prepara un incontro nuovo |
| R | Ricomincia l'incontro, ripristinando vita, stamina e nemici |
| Click sinistro ripetuto | Catena finita di tre colpi |
| Sinistro tenuto premuto | Carica direzionale; muovere il mouse consente una finta |
| Destro | Guardia direzionale |
| Shift | Schivata; durante l'attacco resta memorizzata fino al recupero |
| O | Panoramica e ritorno alla camera di gioco |

F8 coincide con il comando **Ferma** dell'editor di Godot. O funziona anche
durante l'esecuzione dall'editor; F8 rimane un alias solo senza debugger.
La vista pulita di debug usa ora Shift+F3.

## Regole del gruppo

`PackDirector` riprende il principio dei turni di `rpg-3d`: due posti di attacco,
inizi distanziati e coda equa. `PackBrain` scrive gli stessi intenti del corpo
giocatore; animazioni, collisioni della lama, guardia, danno e stordimento restano
nella pipeline esistente. I combattenti in attesa cercano posizioni sui fianchi
e si separano tra loro, invece di convergere tutti sullo stesso punto.

Ogni predone ha quattro punti vita, una veste fredda distinta dall'eroe e un
segnale arancione a terra durante la preparazione del colpo. La guardia è
occasionale. Un colpo ricevuto interrompe il turno e libera spazio agli altri.
La morte di un nemico emette `enemy_died`, senza avviare la morte del giocatore.

La navigazione usa controlli locali contro pareti, dislivelli, acqua e bordi;
non è ancora una ricerca di percorso per labirinti. Il gruppo resta legato
alla zona dell'incontro. Nessun modello o texture è copiato da `rpg-3d`.

## Verifica

- `tools/check_directional_combo.gd`: eventi di input, tre contatti della lama,
  carica, finte, schivata, reset della catena, portata su capsule normali.
- `tools/check_pack_combat.tscn`: turni, separazione, attacchi reali, muri,
  dislivelli, acqua, morte e pausa per dialoghi.
- `tools/check_meadow_encounter.tscn`: posizionamento sul terreno della scena,
  movimento e danno del gruppo, morte, rigenerazione e costume dei predoni.
  `-- --full` mantiene anche castello e pareti del concept. Con un renderer
  reale salva `captures/meadow_group_combat.png` a 1152×648.
- `tools/check_overview_camera.gd`: sei passaggi panoramica/gioco, FOV 13 e 0,
  SDFGI e ripristino dell'inseguimento.

Per confronti artistici senza combattimento usare `-- --no-enemies`, oppure
disattivare `Combat Encounter Enabled` sul nodo della scena integrata.
I parametri del ritmo della combo sono descritti in `DIRECTIONAL_COMBO.md`.

### Risultato verificato — 19 settembre 2026

Scena completa, Forward+ / D3D12 su RTX 3070, 1152×648: quattro nemici in
movimento, tre turni per ciascuno durante la finestra di prova, massimo due
turni occupati, tre danni reali all'eroe; morte e ripartenza senza verifiche
fallite. Dopo il riscaldamento, 120 frame durante il combattimento danno:

| Misura | Mediana | 95° percentile |
| --- | ---: | ---: |
| Intervallo fra frame | 16,67 ms | 17,15 ms |
| GPU del viewport | 5,93 ms | 12,27 ms |

La misura usa il limite frame normale del progetto; il limitatore a 60 della
fixture di verifica viene disattivato prima di misurare il renderer.
È una misura della radura con il gruppo, non di ogni punto della mappa.
Log completo: `captures/meadow_encounter_render.log`.
