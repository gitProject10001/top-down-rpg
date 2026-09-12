# Prima area aperta: 3 km²

## Authoring persistente (World Authoring)

Il plugin locale `addons/world_editor` aggiunge il pannello **World** all'editor.
Riaprire il progetto o abilitarlo da Project Settings > Plugins se l'editor
era già aperto durante l'installazione.

- Navigate: usare la navigazione 3D di Godot (tasto destro + WASD per volare).
  Le celle seguono il punto osservato dalla camera editor, limitato al mondo.
- Place tree: click sinistro sul terreno per un singolo albero.
- Paint forest: trascinare il sinistro, con Brush radius in metri.
- Erase trees: trascinare per rimuovere alberi generati e dipinti nella zona.
- Ctrl+Z / Ctrl+Shift+Z: annullare/ripristinare una pennellata.
- Ctrl+S: salvare la scena. Le modifiche persistono nel campo `world_edits`
  del WorldStream; le MultiMesh restano transitorie.

La mappa è una panoramica schematica della densità su tutti i 3 km², con
villaggio, rettangolo dell'anteprima e alberi aggiunti. Non è un rendering
di tutti gli alberi lontani. Un click sposta il centro di caricamento manuale,
non la camera; riattivare Follow editor camera per tornare al volo automatico.

Le operazioni ordinate consentono di cancellare una radura e ripiantarci alberi.
Il pennello agisce sul piano Y=0: niente rilievi in questa versione. Le aggiunte
manuali possono occupare anche strade e villaggio: è una scelta artistica.
I tronchi dipinti ricevono collisioni. La gomma non rimuove gli alberi originali
del villaggio né le rocce. Non spostare manualmente le MultiMesh generate.

Verificato via test il salvataggio in PackedScene, ricaricamento da disco e
ricostruzione dopo cancellazione/ripristino. La gestualità del plugin e l'undo
dall'interfaccia non sono stati provati tramite controllo desktop. Il test
headless segnala i warning refresh-rate di GPUTrail e un errore allocator
allo spegnimento dopo la doppia istanziazione; le asserzioni dati passano.

Le istruzioni sotto sul solo Editor Center descrivono la modalità manuale;
ora il follow camera del plugin è la modalità predefinita.

La scena del villaggio contiene un terreno di 1732.0508 metri per lato, circa
3 km². Nord è -Z, sud +Z. Il villaggio resta all'origine, con 32 metri di
esclusione per gli oggetti generati.

## Gioco

`scripts/village/world_stream.gd`, sul nodo `Pixel/View/WorldStream`, divide
la decorazione in celle da 64 metri. Carica un quadrato di 5 × 5 celle intorno
al player, una cella per frame. Una fascia aggiuntiva trattiene temporaneamente
le celle per evitare carica/scarica continuo ai confini. Gli oggetti lontani e
le loro collisioni vengono liberati. Mesh e materiali sono riutilizzati;
MultiMesh raggruppa tronchi, chiome e rocce per cella.

Il piano e la collisione del terreno sono permanenti: due triangoli e un box
non richiedono streaming su questa superficie piatta. Non è un sistema per
terreni con rilievi, salvataggi di oggetti modificati o streaming da disco.

## Editor

Selezionare `Pixel/View/WorldStream`. `Preview Enabled` mostra la stessa
generazione del gioco, limitata alla zona di anteprima. `Editor Center`
sceglie il centro XZ: per la foresta nord usare (0,-400), per sud (0,400).
Spostare poi la vista 3D in quella zona. La vista dell'editor non viene seguita
automaticamente. `Radius` controlla la zona caricata; `Rebuild preview`
ricostruisce l'anteprima. Disattivarla libera i nodi generati.

I nodi generati non hanno owner e non vengono salvati nella scena. Non editarli
a mano: cambiare i parametri del generatore. Stesso seed e stessa cella danno
gli stessi oggetti tornando in una zona. Cambiare seed o radius ricostruisce.

## Foreste e percorsi

La densità aumenta verso nord/sud e varia con noise, producendo gruppi e
radure. Una griglia perturbata evita sovrapposizioni troppo strette. Si riusano
tronco e chioma illustrata del villaggio; le rocce sono primitive geometriche
create in memoria. Nessun nuovo asset importato.

Due corridoi attraversano il mondo: uno sinuoso nord/sud e uno diagonale.
Lo shader li rende come terra battuta; il generatore esclude alberi e rocce
con un margine. Le formule sono in `trail_x` e nell'esclusione diagonale dello
script, replicate nello shader: vanno aggiornate insieme. Il raccordo artistico
con i sentieri dipinti resta semplice e potrà essere sostituito da curve dati.

## Riferimenti e limiti

Open World Database 0.6h è stato letto nel laboratorio: comprende persistenza,
monitoraggio nodi e networking, oltre allo streaming. Non è stato importato.
Dal paper sono pertinenti distribuzione spaziale e separazione fra struttura
grande e dettaglio locale; qui non serve un generatore di dungeon.

Verificati rendering Forward+, caricamento iniziale di 25 celle, spostamento
a Z=-400 con scaricamento dell'origine e ritorno con 25 celle. Non è ancora
un benchmark su tutto il mondo o una prova di cammino completa. Le chiome
riusate sono pensate per la camera isometrica attuale. Non ci sono barriere
al bordo del terreno né persistenza degli oggetti generati.
# Rilievo locale e dock (11 settembre 2026)

Aggiornamento visivo: `cliff_rocks.gd` genera blocchi rocciosi sfaccettati e
detriti con seed fisso, in una sola mesh transitoria. Nessun asset esterno.
La collisione resta quella del terreno: i dettagli rocciosi sono decorativi.
ImporterMesh genera LOD nativi su prato, pareti e rocce, usati dal renderer
anche nell'editor; ultimo test: rispettivamente 5, 1 e 2 livelli aggiuntivi.
Non è un sistema di streaming delle altezze: la zona dettagliata resta residente.
Il colore piatto e la disposizione ancora regolare sono una prima iterazione,
non una riproduzione della qualità pittorica della reference.

Il dock World usa ora uno ScrollContainer verticale: i controlli non impongono
l'altezza dell'intero pannello. Gli strumenti sono in `addons/world_editor`;
il runtime resta in `scripts/village`, senza dipendenze da EditorPlugin.
L'addon è locale al progetto, NON ancora un pacchetto riutilizzabile: risolve
i nodi della scena attraverso percorsi espliciti.

Ground non è più un piano: `terrain.gd` genera una zona dettagliata di 128 m
con passo di 1 m, circondata da quattro rettangoli piatti fino ai bordi del mondo.
Nell'Inspector di Ground, Plateau Center, Height e Radius definiscono un
pianoro (default x=60,z=-60, alto 6 m) con accesso da sud. Questi parametri
sono salvati nella scena; mesh e collisione sono ricostruite. Il bordo della
zona dettagliata è piano, senza sovrapposizione di un collider a quota zero.
Non è ancora un terreno ad altezze interamente suddiviso in chunk.

Gli alberi generati e dipinti seguono height_at; la generazione evita pendii
forti. Il pennello interseca il campo di altezza anche nell'editor. Le pareti
usano colori rocciosi su triangoli sfaccettati: blockout, non arte finale.
Non sono implementati sculpt, fiumi, pareti modulari o navigazione AI sui rilievi.

Verifica automatica: import editor senza errori; raycast fisici lungo pianoro
e rampa coerenti con le quote; CharacterBody3D di prova percorre la rampa fino
in cima; cattura render ispezionata. Questo non equivale a un test manuale
del giocatore o del dock ridimensionato.
