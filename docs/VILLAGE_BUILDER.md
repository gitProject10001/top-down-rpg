# Village Builder guidato

La prima versione realizza il confine fra scala villaggio e scala edificio.
Il villaggio produce lotti e richieste di edificio; l'House Builder costruisce
la casa. Stanze e arredo restano responsabilità dell'House Builder.

## Inizia dalla scena di esempio

Apri `scenes/dev/village_builder_playground.tscn`: contiene due strade, un perimetro,
due zone e undici case. È una scena separata dal tuo laboratorio delle case.
La camera della dimostrazione usa la direzione isometrica fissa del gioco.

Il pannello **Villaggio** ha cinque schede:

- **Area**: crea il villaggio e disegna il suo perimetro.
- **Strade**: disegna percorsi a segmenti e regola la larghezza.
- **Vincoli**: disegna aree non edificabili per piazze e spazi liberi. I quartieri
  opzionali cambiano tipo di casa e piani.
- **Gruppi**: attiva la disposizione per corti, disegna corti, blocca un gruppo
  e attiva il suolo automatico.
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
  ; connettività verificata rispetto alla strada di ingresso.
- Lotti rettangolari, distribuzione iniziale regolare, un solo perimetro. In caso
  di zone sovrapposte prevale la prima nell'albero della scena.
- I percorsi verso le porte sono proposte semplici, non un algoritmo di ricerca
  del percorso su terreno. L'occupazione impossibile viene scartata.
- Niente castelli, mura, arredo delle piazze, simulazione economica, GI o lightmap in
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


## Villaggio organico: esempio modificabile

Apri `scenes/dev/village_organic_example.tscn`. È generato dal Village Builder:
19 edifici di dimensioni diverse, otto corti e due strade principali a segmenti.
L’House Builder costruisce ogni edificio; materiali e dettaglio delle case restano
quelli esistenti. La composizione riprende gruppi e spazi aperti del riferimento,
non è una copia geometrica della mappa.

Seleziona Villaggio, apri **Gruppi** e usa **Usa disposizione per gruppi**. Disegna
il poligono dello spazio libero della corte; il generatore propone edifici lungo
il suo esterno, con distanze e dimensioni variabili. Le corti devono avere un centro
interno libero (preferisci poligoni convessi); gruppi troppo vicini o al confine
possono produrre meno case. Seleziona una corte e spostala, poi rigenera: i suoi
ID restano stabili. `Building Type` e `Storeys` sulla corte definiscono il gruppo;
i quartieri di tipo possono prevalere. **Blocca / sblocca gruppo selezionato**
conserva tutte le case di quella corte, oltre alla protezione delle modifiche manuali.
Spostare una corte bloccata non sposta le case bloccate: sblocca prima di rigenerare.

La generazione colloca prima le case, poi cerca percorsi dalle porte alla corte
e alle strade evitando gli edifici. Usa una griglia di lavoro con margine e
semplifica i segmenti visibili. Non è una simulazione storica della crescita:
le strade principali e le corti restano decisioni dell’utente. Le proposte senza
un percorso valido vengono scartate. Il collegamento tra strade principali e corti popolate viene validato dalla rete. Le case sono nodi Lotto con `group_id`, non figli trasformati
della corte: la trasformazione del gruppo viene applicata con la rigenerazione.

## Suolo e guide

**Attiva / disattiva suolo automatico** usa le texture dipinte già presenti nel
progetto: erba come base, terra e ghiaia su corti, strade e collegamenti alle porte.
**Genera / aggiorna** ricostruisce la maschera del suolo insieme al layout. La
maschera (256×256) e il materiale sono salvati nella scena; nessuna generazione
pesante viene eseguita durante il Play. Il suolo è un piano locale: per adesso
non scolpisce pendenze e non sostituisce un Terrain3D. La densità delle case e la
maschera dei materiali sono dati separati.

**Mostra / nascondi zone** controlla le guide dell’editor. Non nasconde erba o
strade del gioco. In Play, **Mostra zone / F8** attiva la vista di debug:
verde=perimetro, giallo=strade, blu=quartieri, rosso=esclusioni, arancio=corti.

## Play villaggio

Seleziona il villaggio e premi **▶ Play villaggio selezionato**: viene salvata
una copia temporanea del nodo corrente, comprese le modifiche non ancora salvate
nella scena. La prova usa il giocatore esistente e camera isometrica fissa del gioco.
WASD/stick per muoversi, F7 per allargare la vista, F8 per le zone. Il terreno con
collisione si adatta all’estensione del villaggio selezionato. Questa prova riguarda
gli esterni; l’interazione completa con gli interni resta nel Play casa.

La scena `village_organic_playable.tscn` riutilizza l’ultima copia selezionata;
per forzare l’esempio dal terminale passa `-- --organic-example`.

Verifiche aggiuntive:

```text
--headless --path . --script res://tools/check_organic_village.gd
--headless --path . res://scenes/dev/village_organic_playable.tscn -- --village-play-test --organic-example
```

Coprono salvataggio, seed, gruppi bloccati, corti libere, percorsi senza attraversare
case, maschera del suolo, copia per Play, movimento reale e toggle debug. Per
ricreare solo l’esempio: `--script res://tools/preview_organic_village.gd` (sovrascrive
la scena di esempio; non usarlo dopo averla personalizzata senza salvarne una copia).


## Percorsi condivisi, larghezze e anteprima

Ogni corte popolata ha un tratto condiviso dalla strada al proprio centro. Tutte
le case del gruppo usano quel tratto prima della diramazione verso la porta.
Il generatore allarga gli estremi quando c’è spazio; la larghezza si riduce se
invade una casa. Segmenti a larghezza variabile e raccordi arrotondati vengono
usati sia per la maschera del terreno sia per il controllo degli ingombri.

Nella scheda **Strade**:

1. Seleziona una corte (o un suo lotto), poi **Modifica percorso della corte
   selezionata**. Il builder crea un nodo `Percorso_*`, collegato alla corte tramite
   `group_id`. L’esempio include già `Percorso_CorteDelMercato`.
2. Trascina i punti della guida. L’inizio deve restare sulla strada e la fine
   si collega al centro della corte. Seleziona **Punto N** e modifica
   **Larghezza al punto**. La larghezza generale scala l’intero profilo.
   Inserire un punto interpola le larghezze vicine; undo/redo conserva il profilo.
3. **Anteprima / verifica percorsi** mostra in verde il nuovo ingombro; errori
   mostrano l’anteprima rossa e un messaggio con la strada o corte coinvolta.
   Il suolo applicato resta invariato durante queste modifiche.
4. **Applica percorsi e suolo** aggiorna collegamenti e materiale senza rigenerare
   le case. Supporta undo/redo. **Chiudi anteprima** nasconde la sovrapposizione.

Per tornare alla proposta automatica elimina il nodo `Percorso_*` e usa
**Genera / aggiorna lotti e case**. I percorsi delle case protette restano conservati. Le guide manuali sopravvivono alla generazione delle case; se il nuovo
layout rende impossibile il percorso, il builder segnala il conflitto.

**Usa strada selezionata come ingresso** sceglie la radice della rete; il primo
punto della strada identifica il lato di ingresso. In assenza di scelta viene
usata la prima strada nell’albero. Il Play posiziona il giocatore al primo punto
della strada scelta. F8 mostra in turchese anche i collegamenti condivisi. Tutte le strade e tutte le corti popolate devono
risultare collegate. Il controllo confronta corridoi con un margine per il giocatore,
non il solo contatto tra bordi. Non è una verifica del navmesh su terreno inclinato.

Test: `tools/check_village_network.gd` copre tratti comuni, strade scollegate,
percorsi manuali attraverso case, profili e raccordi. Il test dell’editor copre
creazione della guida, larghezze, anteprima, applicazione e undo del suolo.
Per far camminare il giocatore su tutti i collegamenti delle corti:

```text
--headless --path . res://scenes/dev/village_organic_playable.tscn -- --village-play-test --village-network-walk-test --organic-example
```

La prova posiziona il giocatore all’imbocco di ogni collegamento e lo guida fino
alla corte usando gli input di movimento reali; la rete delle strade principali
è controllata separatamente dal test geometrico.
