# Combattimento nella scena integrata

Aprire `scenes/dev/integrated_landscape.tscn` e avviare la scena corrente.
Il gruppo di quattro predoni compare nel prato, senza sostituire terreno,
vegetazione o geometria del concept.

| Comando | Azione |
| --- | --- |
| 4 | Raggiungi il gruppo e prepara un incontro nuovo |
| R | Ricomincia l'incontro, ripristinando vita, stamina e nemici |
| Click sinistro ripetuto | Combo ciclica di tre colpi |
| Sinistro tenuto premuto | Caricato dopo 0,65 s; rilascio con fendente orizzontale e scatto, costo 30 stamina |
| Destro | Guardia frontale |
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

- `tools/check_charge_death.tscn`: carica, costo, rilascio, annullamento e morte.
- `tools/check_locomotion.tscn`: camminata, corsa, strafe e recupero.
- `tools/check_ragdoll_reactions.tscn`: contatti, resistenza, pausa e rilascio fisico.
- `tools/check_directional_combo.gd`: fixture storica della meccanica direzionale, non accettazione del player corrente.
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
Il player usa `scripts/states/attack.gd`, i timing di `scenes/player/player3.tscn` e la clip `atk_dash` per la carica. `DIRECTIONAL_COMBO.md` è storico.

Riserva hero 180, rigenerazione 30/s; colpi normali gratuiti. Carica: danno doppio, soglia 0,65 s, rilascio automatico a 1,30 s; sotto soglia o senza stamina colpo normale. Shift annulla la preparazione. Ragdoll dopo un possibile passo di cedimento, con resistenze articolate temporanee; non un sistema Euphoria completo.

### Misura storica — 19 settembre 2026

Questa misura precede carica, nuove reazioni e post-processing: non certifica il costo della revisione corrente.

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
