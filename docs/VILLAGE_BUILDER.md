# Village Builder guidato

La prima versione realizza il confine fra scala villaggio e scala edificio.
Il villaggio produce lotti e richieste di edificio; l'House Builder costruisce
la casa. Stanze e arredo restano responsabilità dell'House Builder.

## Inizia dalla scena di esempio

Apri `scenes/dev/village_builder_playground.tscn`: contiene due strade, un perimetro,
due zone e undici case. È una scena separata dal tuo laboratorio delle case.
La camera della dimostrazione usa la direzione isometrica fissa del gioco.

Il pannello **Villaggio** ha quattro schede:

- **Area**: crea il villaggio e disegna il suo perimetro.
- **Strade**: disegna percorsi a segmenti e regola la larghezza.
- **Vincoli**: disegna aree non edificabili per piazze e spazi liberi. I quartieri
  opzionali cambiano tipo di casa e piani.
- **Densità**: scegli raggio e percentuale, attiva il pennello e trascina nella vista
  3D. Rosso indica 0%, verde 100%. Poi usa **Genera / aggiorna lotti e case**.

Tutto il perimetro è edificabile per default. Le aree non edificabili possono
sovrapporsi: si sommano come esclusioni e restano percorribili. Non creano ancora
pavimentazione o arredo per una piazza. I lotti sono gli ingombri delle singole
case generate e non possono sovrapporsi. I quartieri sovrapposti usano il primo
nell’albero. Tipo e piani predefiniti si impostano sul nodo Villaggio.

La densità è una probabilità deterministica applicata alle posizioni candidate
lungo le strade; 100% non forza case dove mancano spazio o accessi. Ogni pennellata
supporta undo/redo ed è salvata nella scena come griglia locale di 2 m, interpolata.
Esc annulla la pennellata in corso e termina il pennello. Le case personalizzate
restano protette anche con densità zero; un’esclusione che le interseca produce
un errore esplicito. I riempimenti blu dei quartieri e rossi delle esclusioni sono
visibili durante il disegno e nell’editor, senza comparire nel gioco.

Clicca per aggiungere vertici; **Invio** conferma e **Esc** annulla. Seleziona una
guida per trascinare i suoi punti. Puoi aggiungere un punto sul lato più lungo o
rimuovere l'ultimo. Le maniglie compaiono soltanto sulla guida selezionata nella
scheda attiva. Disegno, punti, parametri, generazione e blocchi supportano undo/redo.

**Disegna perimetro** attiva la modalità di disegno: muovi il mouse nella vista 3D
e clicca almeno tre vertici. Un mirino, punti numerati, contorno e riempimento
trasparente mostrano l'anteprima anche quando la guida provvisoria non è ancora
nell'albero salvato. **Conferma disegno** nel pannello equivale a Invio;
**Backspace** rimuove l'ultimo punto. Prima del primo clic è visibile il mirino.

Eliminando il villaggio, il pannello abbandona anche il relativo contesto: i nodi
conservati in memoria per undo non vengono considerati parte della scena. Per
ripartire usa **Crea villaggio → Area → Disegna perimetro**; undo della cancellazione
rende nuovamente selezionabile il villaggio precedente.

Il pannello della casa è separato e contiene **Casa / Aperture / Interni / Arredo**.
La selezione porta al pannello pertinente. In **Aperture** scegli una porta o
finestra dall'elenco: vengono mostrate soltanto le sue tre maniglie, senza quelle
delle dimensioni della casa. Negli interni si mostrano quelle del solo elemento
selezionato. Il pannello resta scorrevole.

## Cosa decide il generatore

Campiona posizioni sui due lati delle strade, controlla che ogni edificio rientri
nel perimetro, fuori dalle esclusioni, mantiene margini tra case e strade e assegna un seed
stabile per posizione. Le zone possono richiedere casa popolana, bottega o casa
benestante e da uno a tre piani. I profili iniziali variano stato delle superfici,
tetto e aperture; non sono ancora kit architettonici completi.

**Camera fissa:** l'orientamento della casa segue la strada, mentre la porta viene
scelta sulla facciata più rivolta alla camera. `Fixed Camera Yaw`, sul villaggio,
parte da 45° come il gioco; 0° corrisponde a una camera dal lato +Z. Gli ingressi
non vengono dunque obbligati a guardare la strada quando questo li nasconderebbe.
Un percorso largo 1,2 m collega strada e porta, aggirando la casa se necessario.
Il suo spazio viene riservato prima di collocare altre case. La verifica riguarda
orientamento delle facciate e accessi: non è ancora una verifica visiva di tutte
le possibili occlusioni provocate dagli edifici vicini.

Seleziona `Lotto → Edificio` per proseguire con l'House Builder, aggiungere interni,
porte o dettagli. Le case nascono come esterni: il Village Builder non rigenera
stanze e mobili. Una casa con contenuti personalizzati viene conservata.

## Modifiche e conflitti

Un lotto bloccato, spostato, o con una casa modificata viene conservato. Se sposti
una strada attraverso quella casa, escludi il lotto dal perimetro o interrompi
il suo percorso verso la strada, compare un errore e la proposta non viene applicata.
I lotti eliminati non ricompaiono alla generazione successiva; undo li ripristina.
Le modifiche alle guide sono separate dall'applicazione della nuova disposizione.

## Contratto fra generatori

`addons/house_builder/building_request.gd` è la risorsa di scambio: tipo, ingombro,
piani, seed e lato dell'ingresso. Produce un normale nodo House. Il codice delle
stanze e dell'arredo non è importato dal Village Builder. Il lotto conserva richiesta,
posa, percorso e riferimento alla zona. I nodi e gli ID vengono mantenuti durante
undo/redo; le revisioni sostituite sono conservate fino alla chiusura del villaggio.

## Limiti di questa fase

- Terreno piano, con le guide sul piano locale Y=0. Non modifica il terreno e non
  gestisce ancora fiumi, pendenze, ponti o terrazzamenti.
- Strade disegnate dall'utente, a segmenti rettilinei; nessuna rete viaria automatica
  o validazione della connettività dell'intero villaggio.
- Lotti rettangolari, distribuzione iniziale regolare, un solo perimetro. In caso
  di zone sovrapposte prevale la prima nell'albero della scena.
- I percorsi verso le porte sono proposte semplici, non un algoritmo di ricerca
  del percorso su terreno. L'occupazione impossibile viene scartata.
- Niente castelli, mura, piazze generate, simulazione economica, GI o lightmap in
  questo passaggio. Le risorse restano estendibili per le fasi successive.

## Verifiche

```text
--headless --path . --script res://tools/check_village_builder.gd
--headless --path . --editor res://scenes/dev/village_builder_playground.tscn -- --village-editor-test
--headless --path . --editor res://scenes/dev/house_builder_playground.tscn -- --house-editor-test
```

Coprono seed, contenimento, sovrapposizioni, porte verso camera, accessi liberi,
modifiche protette, conflitti, cancellazioni, serializzazione, disegno con eventi
dell'editor, punti, schede contestuali e undo/redo. `tools/preview_village_builder.gd`
ricrea la sola scena di esempio e produce `captures/village_builder/layout.png`.
Non eseguirlo su un esempio personalizzato senza salvarne prima una copia.

Per l'apertura contestuale dei pannelli viene usata l'API
[EditorDock di Godot 4.6](https://docs.godotengine.org/en/4.6/classes/class_editordock.html).
