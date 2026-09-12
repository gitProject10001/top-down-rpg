# Terreno: come è fatto e come cresce

## Campionamento e transizioni attuali

Il prato usa quattro regioni agli angoli del dipinto originale. Ogni vertice
della griglia triangolare sceglie una regione, una rotazione e un piccolo offset.
Le coordinate restano dentro la regione: nessuno specchiamento che duplichi i
ciuffi in rosette. Tre campioni si fondono con pesi continui. `grass_metres`
ora vale 2.5: controlla le celle del campionamento, non la dimensione del mondo.

Un campo di noise deformato distribuisce terra e pietrisco; un dettaglio più
fine rompe i bordi delle transizioni. `wear_amount` (0.85), `wear_metres` (22)
e `gravel_amount` (0.55) controllano copertura e dimensione delle zone.
`use_road_mask` è ora attivo nella scena: mostra strada e diramazione in ghiaia
già disegnate nell'SVG. Sono percorsi di esempio, da raccordare artisticamente
ai sentieri del villaggio. Le note precedenti sotto descrivono le iterazioni
storiche quando divergono da questi valori.

## Aggiornamento del prato

Il prato esterno campiona ora una regione di sola erba del dipinto originale
(`ground_painting.png`, UV da 0.025 a 0.245 su entrambi gli assi), invece
della colonna erba dell'atlante descritta sotto. La distribuzione rimane
stocastica su triangoli, con coordinate specchiate continue e pesi che
favoriscono un campione locale senza amplificarne il contrasto.
`grass_metres` vale 7; `grass_grade` usa lo stesso moltiplicatore del dipinto
centrale (0.62, 0.59, 0.55). L'atlante rimane usato per terra e ghiaia.
Il ritaglio limita la varietà delle forme vegetali disponibili; terra e ghiaia
possono ancora richiedere una rifinitura artistica.

Il terreno è un quad piatto di due triangoli con un box sotto. Tutto il dettaglio sta nel materiale, `shaders/pixelart/ground_clear.gdshader`, e il materiale lavora in coordinate mondo: non gli interessa quanto è grande il quad.

## Il problema che risolve

Il villaggio poggia su un'immagine dipinta a mano, `ground_painting.png`: un incrocio, terra battuta, ciuffi d'erba. Quella pittura copre 32 metri ed è il livello di qualità da tenere. Fuori da quel rettangolo il materiale precedente metteva rumore procedurale colorato, che a qualsiasi distanza si leggeva come una scacchiera di quadrati oliva.

Adesso fuori dalla pittura c'è **lo stesso tipo di materiale**, preso da un atlante dipinto e steso all'infinito senza ripetizioni visibili.

## Come la texture si estende senza ripetersi

Lo schema è quello di Heitz & Neyret 2018, che conserva l'istogramma:

1. La posizione XZ mondo viene inclinata su un **reticolo triangolare**. Ogni punto cade dentro un triangolo.
2. Ognuno dei tre vertici del triangolo porta il proprio **spostamento e la propria rotazione** casuali dentro l'immagine sorgente, quindi due triangoli non leggono mai la stessa zona.
3. I tre campioni si fondono per peso baricentrico, ma **a varianza conservata**: si sottrae la media della texture, si divide per la radice della somma dei pesi al quadrato, si riaggiunge la media. Una media pesata normale spegnerebbe le pennellate proprio dove i triangoli si incontrano, ed è il motivo per cui il tiling stocastico fatto ingenuamente viene molle.
4. Si campiona con `textureGrad`, non con `texture`. La `fract()` sulle UV fa esplodere la derivata implicita a ogni avvolgimento, e il selettore di mip la trasforma in una griglia di cuciture sfocate.

Il reticolo triangolare non ha un asse privilegiato, quindi non c'è niente su cui l'occhio possa agganciarsi. Era esattamente il difetto del rumore a griglia quadrata che ha sostituito.

**La correzione di varianza si spegne con la distanza.** Abbastanza lontano ogni campione finisce su un mip alto, che *è* la media della texture: la divisione non ha più niente da salvare e si limita ad amplificare gli ultimi scarti per un fattore che oscilla fra 1 sul vertice e radice di 3 al centro del triangolo. Quella modulazione si vedeva come una ragnatela di triangoli su tutto il campo. Oltre una certa impronta la fusione torna a essere una media semplice, che a quella distanza è indistinguibile.

## L'atlante dei livelli

`assets/textures/hearth_painted/terrain_layers.png` è una riga di tre colonne: **erba | terra | pietrisco**. Ogni colonna è alta tre volte la sua larghezza, quindi un tassello quadrato di mondo corrisponde a un terzo dell'altezza della colonna: sbagliare questo rapporto allunga ogni filo d'erba di 3 a 1.

L'atlante non è la pittura, e lasciato grezzo risulta più chiaro e più giallo del villaggio a cui deve stare accanto. Tre gradazioni lo riportano in palette:

| uniform | default | mappa la colonna su |
|---|---|---|
| `grass_grade` | `(0.35, 0.50, 0.59)` | la media dei pixel a dominante verde della pittura |
| `dirt_grade` | `(0.50, 0.70, 0.88)` | la media dei sentieri della pittura |
| `gravel_grade` | `(0.62, 0.74, 0.90)` | solo la luminosità: il pietrisco tiene il suo grigio |

Tutte e tre le medie sono misurate **dopo** la gradazione `0.62/0.59/0.55` che riceve la pittura stampata. È questo che rende invisibile il bordo dove la stampa finisce.

Queste tre uniform **non hanno il suggerimento `source_color`**, ed è deliberato: sono moltiplicatori, non colori. Con quel suggerimento Godot le leggerebbe come sRGB e le convertirebbe, trasformando uno 0.35 in un 0.1 e mandando in ombra tutto il campo mentre la stampa resta illuminata.

Le costanti `GRASS_MEAN`, `DIRT_MEAN` e `GRAVEL_MEAN` nello shader sono le medie lineari vere delle tre colonne. Non sono direzione artistica: la fusione a varianza conservata ha bisogno della media esatta o sposta il risultato fuori tinta. Vanno rimisurate se l'atlante viene ridipinto.

## Variazione a grande scala

Due campi fbm a bassa frequenza, entrambi a ottave ruotate perché nessuno dei due abbia un asse:

- `macro_metres` (90 m) e `macro_strength` decidono quanto l'erba legge secca o rigogliosa, spostandola fra `dry_tint` e `lush_tint`. Lo spostamento è misurato **rispetto al punto medio dei due colori**, non rispetto al bianco: tingere ovunque verso la loro media non è una variazione, è una dominante gialla costante su tutto il mondo.
- `wear_metres` (46 m) e `wear_amount` decidono dove la terra affiora sotto l'erba, mescolando la colonna terra.

## Strade ed erba

`assets/textures/hearth_painted/terrain_roads.svg` è una mappa di controllo, non un albedo. Tre canali indipendenti:

| canale | effetto |
|---|---|
| R | strada di terra battuta |
| G | pietrisco |
| B | erba più rigogliosa, senza superficie di strada |

Il nero non tocca niente. Ogni canale sfuma la propria superficie fra 0.05 e 0.95, e lo shader sfrangia i bordi con rumore perché una curva disegnata non si legga come una curva disegnata. Strada e pietrisco sono campionati dallo stesso atlante con lo stesso tiling stocastico, quindi una strada è una superficie dipinta e non una decalcomania marrone appoggiata sopra.

I bordi morbidi sono **disegnati, non filtrati**: ogni tracciato nell'SVG è ripassato tre volte, prima largo e smorto, così il canale scende a rampa verso il ciglio.

`road_mask_center` è il centro XZ in coordinate mondo, `road_mask_size` l'estensione in metri. Con l'SVG fornito (viewBox 0–100) ed estensione 100 m, il punto (50,50) del disegno è l'origine del mondo e l'angolo in alto a sinistra è (-50,-50). Allargando la maschera lo stesso disegno copre più terreno: l'estensione della maschera e la scala della texture della strada sono indipendenti. Fuori dall'estensione la maschera non ha effetto.

La maschera è disattivata per default. Si accende con `use_road_mask` sul materiale del Ground.

**La maschera deve importare senza perdita.** `terrain_roads.svg.import` ha `compress/mode=0`. Con la compressione VRAM i tre canali si sporcano a vicenda e verde e blu spariscono quasi del tutto. Per questo i file `.import` ora sono tracciati da git: vedi `.gitignore`.

È una superficie colorata. Non scava il terreno, non crea ciuffi e non aggiunge collisioni.

## Far crescere il mondo

`scripts/village/terrain.gd` sta sul nodo `Pixel/View/Ground` ed espone **una sola manopola**, `extent`, in metri per lato. Cambiandola si ridimensionano insieme il quad e il suo collisore, e il collisore resta affondato in modo che la sua faccia superiore sia la superficie visibile. `floor_thickness` regola solo quanto è spesso quel box.

Prima servivano due modifiche, mesh e forma di collisione, e dimenticare la seconda faceva camminare il giocatore nel vuoto appena passato il vecchio bordo: un difetto che si manifesta solo quando qualcuno si allontana abbastanza da trovarlo.

Il materiale non va toccato. In particolare **non va aumentato `painting_size`** per coprire più terreno: allargherebbe anche il disegno dei sentieri del villaggio. Verificato a 100, 400 e 3200 metri; 3200 è il lato del quadrato che fa i dieci chilometri quadrati.

Il terreno resta piatto e senza barriere ai bordi. Il materiale presuppone superfici prevalentemente orizzontali: pareti ripide richiederanno una proiezione adatta.

## Cosa non è ancora fatto

1. **Streaming a chunk.** Un quad solo, di qualunque dimensione, resta una draw call e un collisore: va bene fino alle poche centinaia di metri che si vedono da una camera isometrica, e non va bene per dieci chilometri quadrati. Il passo successivo è caricare riquadri attorno al giocatore, e può aspettare proprio perché niente di quanto c'è qui dovrà cambiare quando arriverà: un chunk è questo stesso materiale su un quad più piccolo, spostato.
2. Curve modificabili dentro Godot che producano la maschera già supportata dal materiale.
3. Distribuzione di alberi con seed stabile per chunk, escludendo strade, edifici e pendii.
4. Distanze di dettaglio per vegetazione, collisioni e ombre, misurando memoria e frame time prima di popolare tutta l'estensione.

## Verifica

Le catture di controllo si producono con `.godot/terrain_shots.gd`, che è materiale di lavoro sotto `.godot` e non una dipendenza del gioco:

```bash
Godot_v4.6.3-stable_win64_console.exe --path . --script res://.godot/terrain_shots.gd -- <tag> <estensione>
```

Scrive sei viste a scale diverse, incluse due con la maschera accesa. Le scale che contano sono tre: da vicino si guarda se le pennellate sono nitide, a media distanza se si vede il bordo della stampa dipinta, da lontano se compare una ripetizione o un reticolo.
