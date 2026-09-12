# Tetto in rilievo e prove di illuminazione

Le due istanze di `hearth_cottage_authored` nella scena giocabile usano ora
`assets/models/roof_relief/cottage_relief.res`. Solo la superficie 3 è sostituita;
pareti, travi, camino, finestra e collisioni sono conservati.

Il tetto comprende 320 tegole chiuse, con spessore di circa 6,5 cm verticali,
bordi smussati/scheggiati, file sovrapposte e piccole variazioni deterministiche.
Sono 15.374 triangoli per tetto, raccolti in una singola superficie e un materiale,
senza centinaia di nodi o generazione durante il gioco. È un campione per le due
casette, non una sostituzione di tutti i tetti del villaggio; per grandi quantità
di edifici servirà una versione LOD più economica.

Il campione comprende 7 tegole con fratture geometriche sul bordo esposto e
8 tegole ruotate/traslate, incluse alcune sul bordo del timpano. Le fratture
mantengono il fondo chiuso e la parte superiore sotto la fila successiva.
Le trasformazioni sono rigide e ruotano anche le normali; UV e maschere AO
rimangono solidali alla tegola. Gli indirizzi riga/colonna sono deterministici,
senza cambiare il seed o i colori delle altre tegole. Le travi originali restano
conservate; qualche tegola sporgente interrompe la cornice. Le sette fratture
hanno fondi neri arretrati (14 triangoli aggiuntivi), con pigmento e specularità
azzerati: restano neri in tutte le illuminazioni e nascondono il supporto sottostante.

`shaders/pixelart/roof_clay.gdshader` usa pigmento per vertice e una texture
procedurale di argilla, senza bitmap con ombre o riflessi dipinti. Albedo,
rugosità variabile, micro-normali e risposta dielettrica sono indipendenti
dall'ora. Le ombre di sovrapposizione vengono dalla mesh e dalle luci; SSAO
della scena aggiunge contatto. Non usa parallax né una AO map dipinta.

### Leggibilità alla distanza di gioco

Le fughe laterali sono larghe circa 2,4 cm invece di 6 mm, con labbro inferiore
alzato di altri 3 cm. UV2 contiene coordinate locali di ogni tegola; il materiale
calcola una maschera di occlusione per le fughe e la zona sotto la fila successiva.
Il canale alfa del colore dei vertici contiene l'occlusione dei fianchi e del fondo,
non trasparenza. `cavity_strength` regola l'intensità senza cambiare il pigmento.
La maschera è antialiasata con le derivate dello shader e influenza soprattutto
la luce ambientale, con un contributo stilizzato del 35% sulla luce diretta.
Non viene quantizzata la luce in bande e non viene applicata una palette globale.

La verifica usa orientamento e dimensione della camera del gioco, ricentrata sulla
casetta, a 1152×648. Il rilievo conserva 320 tegole / 15.360 triangoli: l'aumento
di leggibilità non aggiunge geometria. Se è presente lo snapshot locale in
`captures/roof_readability`, il preview produce anche un confronto prima/dopo
ritagliato a dimensione nativa, senza ingrandimento.

## Provare nel gioco

Premere **F6** per alternare mattino (08), mezzogiorno (12), tramonto (18) e
notte (22). Sono quattro preset artistici ripetibili, non un ciclo astronomico.
All'avvio rimane l'illuminazione originale della scena; i preset si attivano
solo con F6. Cambiano sole/luna, luce di riempimento e luce ambientale.
Materiali ed esposizione rimangono identici. Di notte il tetto è volutamente
più scuro: coerenza fisica non significa luminosità costante.

## Rigenerare e verificare

Da questa cartella di progetto, con Godot 4.6:

```powershell
& 'C:/Users/jonny/Desktop/game/godot/Godot_v4.6.3-stable_win64_console.exe' --headless --path . --script res://tools/build_relief_roof.gd
& 'C:/Users/jonny/Desktop/game/godot/Godot_v4.6.3-stable_win64_console.exe' --path . --script res://tools/preview_roof_lighting.gd --resolution 1280x720
```

Il generatore conserva la mesh sorgente in `cottage_source.res` e produce una
mesh riutilizzabile con seed fisso. Il preview carica la scena vera, verifica
l'integrazione del materiale e che le altre superfici siano intatte, simula F6,
poi fotografa le quattro luci con inquadratura ravvicinata e scala di gioco.
Produce `captures/roof_lighting/four_hours.png`, otto scatti singoli e il
confronto originale `before_12.png`. La cartella captures è ignorata da Git.

La camera di confronto viene centrata sulla casetta per ispezionarla; non
modifica la camera salvata né la posizione iniziale del giocatore.

## Ombre e antialiasing del gioco

Il SubViewport `Pixel/View` usa esplicitamente MSAA 4× (`msaa_3d = 2`).
Prima aveva MSAA disattivato: le impostazioni AA del viewport principale non
configuravano automaticamente questo viewport. TAA resta disattivato qui,
perché nel confronto sfumava le tegole e il terreno.

La mappa direzionale del sole passa da 4096 a 8192. Restano quattro cascata e
60 m di distanza: la prova con due cascata perdeva ombre nella scena corrente.
`light_angular_distance = 0` elimina la penombra PCSS, mantenendo il filtraggio
PCF con `shadow_blur = 0.85`. La luce di riempimento iniziale passa da 0.48
a 0.24, l'ambientale da 0.48 a 0.408. I preset F6 riducono rispettivamente
riempimento del 20% e ambientale del 5%, conservando leggibilità notturna.
Geometria, shader del tetto ed esposizione non vengono modificati da questa revisione.

`tools/preview_shadow_quality.gd` confronta baseline, MSAA e MSAA+TAA nella
scena vera, inclusa la luce iniziale e quattro orari. Con `-- --quick` isola
anche atlante, antialiasing e cascata. `tools/analyze_shadow_capture.py` produce
ritagli affiancati a risoluzione nativa e misura la differenza RGB sul tetto
compensando 11 spostamenti della camera di un pixel. Nel test: baseline 0.133,
MSAA 0.137, temporale 0.347 su scala 0–255. È un controllo locale dopo
assestamento, non una misura del ghosting durante movimento continuo.

Le catture sono in `captures/shadow_quality/`. La risoluzione 8192 aumenta
memoria e costo della mappa delle ombre; non è stato svolto un benchmark FPS
di una sessione completa. Per hardware più limitato il primo parametro da
ridurre è `rendering/lights_and_shadows/directional_shadow/size` a 4096.
