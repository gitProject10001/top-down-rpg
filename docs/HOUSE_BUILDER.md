# Generatore di case nell'editor

L'addon **Hearth House Builder** è abilitato in questo progetto. Apre il pannello
**Hearth Case** nell'editor 3D. La scena `scenes/dev/house_builder_playground.tscn` è un
laboratorio con una casa parametrica; il villaggio e le casette esistenti non
sono stati sostituiti. `rpg-3d/GladeKit` è stato consultato, non modificato.

## Uso

1. Apri la scena di laboratorio oppure il villaggio. Se Godot era già aperto,
   verifica che **Hearth House Builder** sia attivo in Progetto → Impostazioni
   progetto → Estensioni. Il pannello si chiama **Hearth Case**.
2. Premi **Disegna casa** e trascina col sinistro sul terreno. Il volume arancione
   indica l'ingombro. Rilasciando viene creata una casa completa. Il primo punto
   determina la quota della base; non viene modificato il terreno.
3. Torna a **Seleziona / gizmo** e seleziona la casa. Le quattro maniglie laterali
   regolano larghezza/lunghezza, quella sopra le pareti l'altezza delle pareti,
   quella sul colmo l'altezza del tetto. Il ridimensionamento è simmetrico rispetto
   al centro. Per spostare/ruotare usa i normali strumenti Godot (W/E).
4. **Posiziona finestra** o **Posiziona porta**: clicca una parete della casa
   generata. Ogni clic inserisce un elemento; le aperture troppo vicine sono rifiutate.
5. **Sposta apertura**: trascina l'elemento sulla parete. Oppure sposta la sua
   maniglia in modalità selezione. Le porte restano a terra; le finestre cambiano quota.
   La maniglia laterale cambia la larghezza e quella superiore l'altezza, con
   scatti da 5 cm. Il centro delle finestre resta fermo; le porte crescono dal suolo.
   I limiti della parete e le aperture vicine impediscono ridimensionamenti invalidi.
6. **Rimuovi apertura** cancella l'elemento cliccato. Esc annulla il gesto e torna
   alla selezione; il tasto destro annulla il gesto e lascia navigare la camera.
   Ctrl+Z / Ctrl+Shift+Z annullano/ripristinano creazione, dimensioni e aperture.
7. Salva normalmente la scena. Vengono salvati i parametri e le aperture; il
   risultato si ricostruisce anche nel gioco, senza dipendere dall'EditorPlugin.

La creazione di case mette il pennello del pannello World in modalità Navigate,
per evitare che lo stesso trascinamento dipinga anche alberi o terreno.
Il pannello scorre verticalmente quando lo spazio disponibile è ridotto.

## Casa a L

Seleziona una casa e premi **Aggiungi ala a L** nel pannello. Le due nuove
maniglie regolano sporgenza e larghezza dell'ala. Nell'Inspector, **Ala laterale**
permette di scegliere destra/sinistra e davanti/dietro. **Rimuovi ala** torna
alla pianta rettangolare; i parametri e le aperture dell'ala restano memorizzati.
I comandi e le maniglie supportano undo/redo e annullamento del trascinamento.

La larghezza effettiva dell'ala è limitata dalla casa principale; la pendenza
del tetto è comune ai due volumi. Il raccordo taglia le tegole lungo le linee
di incontro e rimuove la geometria interna. Le collisioni seguono i due volumi:
l'angolo rientrante resta libero. Porte e finestre si posizionano anche sull'ala;
le pareti inglobate non accettano nuove aperture. Aperture già presenti che
vengono coperte sono conservate e segnalate per consentire di riposizionarle.

Esempio pronto: `scenes/dev/house_builder_l_playground.tscn`.
La rigenerazione completa della casa a L di esempio richiede circa 0,45–0,50 s sulla
macchina di sviluppo: durante il trascinamento l'aggiornamento è ancora discreto.

## Comportamento

- L'intonaco usa macchie procedurali continue nello spazio locale, senza ripetere
  il riquadro dell'atlante. `house_seed` controlla macchie e variazioni del tetto;
  `weathered` disattiva anche le macchie di intonaco consumato. Legno e pietra
  continuano a usare l'atlante originale.
- Le rotture del tetto hanno una distribuzione casuale riproducibile e due forme,
  senza la precedente progressione diagonale periodica.
- Pianta rettangolare, un piano, tetto a due falde. Larghezza 1,8–20 m,
  lunghezza 1,8–24 m, pareti 1,8–8 m, rialzo del tetto 0,5–6 m.
- Le tegole mantengono la propria dimensione: allungando la casa aumentano le file
  e le colonne, senza stirare una texture. Materiale, rotture nere e tegole spostate
  derivano dal tetto rifinito nel villaggio. `weathered` disattiva i danni.
- Porte e finestre sono registrate con parete, posizione orizzontale relativa,
  quota e dimensioni. Seguono ridimensionamenti e rotazione; le travi si interrompono
  in corrispondenza delle aperture. Dopo restringimenti estremi, eventuali aperture
  sovrapposte sono segnalate nell'albero: spostale o rimuovile.
- Le pareti hanno uno spessore di 24 cm. Le aperture tagliano entrambe le facce,
  fondazione e travi, con imbotti, davanzali e componenti arretrati. Il taglio
  avviene dopo il raccordo dei volumi, anche sulle facciate comuni. Le collisioni
  seguono la mesh delle pareti e dei componenti, anziché occupare tutto l'edificio.
- La geometria generata è interna al nodo `HearthHouse`, senza centinaia di nodi
  tegola e senza risorse di editor richieste nel runtime. Aggiornamenti aggregati
  ogni 100 ms durante il trascinamento, rigenerazione definitiva al salvataggio.

## Limiti della prima versione

Le porte generate hanno ora ante animate e collisione mobile. Le finestre hanno
vetri scuri. La struttura interna è sperimentale nella scena giocabile descritta
sotto; non è ancora un editor libero di planimetrie applicato a tutte le case a L.
È supportata una sola ala perpendicolare agganciata alla casa. Non ci sono ancora
abbaini, muri curvi, più ali o fusione libera tra edifici indipendenti.
La pianta nasce allineata agli assi del mondo, poi si può ruotare.
Su pendii serve sistemare il terreno o la quota della casa. La geometria delle
tegole cresce con la superficie: non è ancora presente un LOD per interi quartieri.

## File e verifiche

### Prova giocabile degli interni

Nel pannello **Hearth Case**, premi **▶ Prova interni (Play)**, oppure apri
`scenes/dev/house_interior_playable.tscn` e premi F6. Usa WASD/stick per muoverti,
E/Y per aprire o chiudere la porta vicina. F7 confronta lo zoom normale (17,5 m,
come nel villaggio) con 12 m. La scena riusa player3, skin, HUD, camera a 48°,
pixel snap e MSAA del gioco. Il postprocess disabilitato nel villaggio resta disabilitato.

Il workflow attuale è descritto in [HOUSE_AUTHORING.md](HOUSE_AUTHORING.md): interni
salvati nell'House Builder, generazione di stanze e arredo, modifica manuale e Play
della casa selezionata. I parametri descritti sotto riguardano il vecchio prototipo,
ancora disponibile con `--house-play-test` per regressione.

Il prototipo ha due piani, tre stanze vuote per piano, scala con gradini visivi e collisione a
rampa. Nessun arredamento. Nel nodo radice dell'Inspector puoi cambiare larghezza,
profondità, altezza dei piani, numero dei piani (1–2), posizione dei due divisori
e spessore dei muri; riavvia la prova per rigenerare la struttura.

Entrando, il tetto e i piani superiori vengono nascosti, le pareti davanti al
personaggio vengono sezionate visivamente e l'esterno diventa quasi nero.
Le collisioni restano intatte; il piano visibile segue l'altezza dei piedi.
Uscendo torna la visualizzazione esterna. Le luci calde sono luci di prova,
senza mobili o lampade decorative. Le porte aprono dalla parte opposta al giocatore
e rifiutano la chiusura quando si trova nel vano.

Test completo con il giocatore reale, senza teletrasporto: porta chiusa, ingresso,
porta interna e stanza, salita, discesa, uscita e chiusura:
`--path . res://scenes/dev/house_interior_playable.tscn -- --house-play-test`.
Le catture vengono salvate in `captures/house_interior/`.

- `addons/house_builder/plugin.gd`: pannello, rettangolo, posizionamento e undo.
- `gizmo.gd`: maniglie di dimensioni e aperture.
- `house.gd`: parametri, facciate, aperture, selezione e collisione.
- `roof_mesh.gd`: generazione delle tegole senza I/O.
- `mesh_join.gd`: taglio delle mesh nel raccordo, conservando UV, colori e normali.

Verifiche eseguite in Godot 4.6.3:

```powershell
& 'C:/Users/jonny/Desktop/game/godot/Godot_v4.6.3-stable_win64_console.exe' --headless --path . --script res://tools/check_house_builder.gd
& 'C:/Users/jonny/Desktop/game/godot/Godot_v4.6.3-stable_win64_console.exe' --headless --path . --editor res://scenes/dev/house_builder_playground.tscn -- --house-editor-test
& 'C:/Users/jonny/Desktop/game/godot/Godot_v4.6.3-stable_win64_console.exe' --path . --script res://tools/preview_house_builder.gd --resolution 1152x648
```

Il primo verifica dimensioni estreme, mesh finite, ray picking su casa ruotata,
salvataggio e ricaricamento. Il secondo simula eventi sul plugin reale e sulla
cronologia dell'editor, inclusi undo/redo di rettangolo, finestra e spostamento,
maniglia di larghezza e annullamento della maniglia del tetto. Il terzo produce
le scene di laboratorio e le catture, incluso il dettaglio delle aperture, in `captures/house_builder`.

