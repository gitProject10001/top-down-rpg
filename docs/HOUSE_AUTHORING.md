# House Builder: interni modificabili

Piano aggiornabile per forme, componenti agganciati, interni e castelli:
[Roadmap dei generatori architettonici](ARCHITECTURE_GENERATOR_ROADMAP.md).

Checkpoint iniziale: `e0a6b08`. GI e lightmap sono rimandati.

Il pannello ora separa **Casa**, **Aperture**, **Interni** e **Arredo**. La selezione
di una casa, stanza o mobile apre il contesto pertinente. Le maniglie dell'edificio
sono visibili in Casa; in Aperture scegli dall'elenco la singola porta o finestra
da modificare. Negli interni vengono mostrate solo le maniglie del nodo selezionato.
Il [Village Builder](VILLAGE_BUILDER.md) ha un pannello separato per area, strade e lotti.

## Profili architettonici: primo incremento

Apri `scenes/dev/architecture_profiles_example.tscn` per confrontare una casa
compatta, un corpo allungato e una variante con lunghezza manuale di 14 m.
Sono preset di proporzioni; materiali e resa restano quelli attuali.

Seleziona la casa nel tab **Casa**, scegli il profilo e usa:

- **Cambia profilo · conserva modifiche**: aggiorna solo le dimensioni ancora
  uguali all'ultimo valore ereditato. Su una casa legacy conserva tutte le dimensioni.
- **Usa proporzioni del profilo**: adotta esplicitamente larghezza, profondità,
  altezza delle pareti e altezza del tetto. Aperture e dettagli restano conservati.

Entrambe le operazioni supportano undo/redo. Il testo nel pannello mostra profilo
attivo e dimensioni ereditate/manuali. Un valore riportato esattamente alla precedente
proporzione del profilo viene considerato ereditato. Assegnare la risorsa direttamente
nell'Inspector cambia l'associazione; usa i pulsanti per applicarne le proporzioni.
Le risorse sono in `addons/house_builder/profiles/`. Il ruolo dell'edificio è
separato dal profilo; nuovi ruoli non implicano ancora nuovi generatori di stanze.

## Passaggio 1: dati dell'editor

Seleziona una casa e premi **Interni: crea / mostra**. `InteriorPlan` contiene
piani persistenti e nodi per stanze, muri, scale e oggetti. Aggiungi elementi
dal pannello, spostali/ruotali con W/E e ridimensionali con le maniglie azzurre.
L'Inspector espone dimensioni, porta del muro, scena dell'oggetto e blocco manuale.
Puoi anche trascinare una tua scena direttamente sotto un piano.

`_Visual` e `_Floors` sono cache interne rigenerabili: modifica i nodi dati,
non queste mesh. Salvataggio e undo delle operazioni del pannello conservano
gli elementi dell'utente. **Play casa selezionata** prepara una copia temporanea
in `user://house_builder_playtest.tscn` e avvia gli stessi dati nel banco di prova.
La scena sorgente non viene modificata dal gameplay.

## Passaggio 2: planimetria iniziale

**Genera stanze (piano attivo)** usa `seed_value` e `requested_rooms` del piano.
Il metodo riserva un ingresso longitudinale, suddivide i rettangoli residui,
costruisce il grafo delle adiacenze e apre un insieme di porte che collega le stanze.
Per case a L viene aggiunta la stanza nell'ala. I piani multipli riservano una
scala con corridoio laterale e un foro nel solaio; gli accessi delle stanze evitano
l'ingombro della scala. Per questa configurazione automatica servono almeno
6 m di larghezza e circa 6 m di profondità; altrimenti il comando spiega il limite
e mantiene la planimetria precedente. Si possono comunque disegnare soluzioni manuali.

La geometria viene verificata prima di applicarla: stanze troppo strette,
sovrapposizioni e stanze scollegate impediscono la sostituzione. Seed uguale e
parametri uguali producono lo stesso risultato. Undo ripristina la proposta precedente.

## Passaggio 3: modifiche protette

Per aggiungere una stanza dentro una stanza generata: **Aggiungi stanza**, posiziona
e ridimensiona il volume, poi **Integra stanza e genera muri**. Il comando ritaglia
le stanze generate sovrapposte e crea partizioni con accesso, senza alterare stanze
modificate o bloccate. Ritagli troppo stretti o passaggi ostruiti vengono rifiutati.
È un'operazione esplicita con undo; il semplice volume azzurro non è già un muro.

Una proposta rifiutata apre una finestra **Operazione non eseguita** con il motivo,
mostra il messaggio in rosso nel pannello e lo registra fra gli avvisi dell'editor.
Non aggiunge un'azione alla cronologia undo. Un risultato valido ma identico viene
segnalato come **Nessuna modifica necessaria**.

Le stanze nell'albero si chiamano **Ingresso**, **Soggiorno**, **Cucina**, **Camera**,
**Ripostiglio**, con suffisso numerico per i duplicati. `Room Type` sceglie la funzione
e l'arredo; `Display Name` assegna un nome descrittivo. Le rinomine fatte direttamente
nell'albero vengono rispettate. Gli identificativi interni della generazione restano
stabili anche quando cambia il nome visibile.

**Rigenera muri dalle stanze** aggiorna le partizioni dopo aver modificato le stanze.
Il blocco esplicito, gli elementi aggiunti a mano e le proprietà cambiate rispetto
alla generazione precedente vengono conservati. **Blocca / sblocca elemento**
permette anche di accettare una modifica come nuova base per la rigenerazione.
Gli oggetti cancellati non ricompaiono alla rigenerazione; undo della cancellazione
li ripristina. Le scene personali sotto il piano restano intatte.

Prima della sostituzione viene controllata la percorribilità su una griglia di
18 cm, con 31 cm di margine per il giocatore: una proposta che isola una stanza
viene scartata interamente, con messaggio nel pannello. È una verifica della
planimetria con porte aperte, non una simulazione completa del movimento.

## Passaggio 4: arredo opzionale

**Arreda piano** propone tavoli, sedie, letti, cassapanche e scaffali in base a
`room_type`: `soggiorno`, `cucina`, `camera`, `ripostiglio`. `ingresso` resta libero.
**Arreda stanza selezionata** limita l'operazione alla stanza selezionata del piano
attivo. **Rimuovi arredo generato** conserva mobili modificati, bloccati o manuali.
I tre comandi supportano undo/redo.

I mobili sono nodi Oggetto normali: spostali con il gizmo, cambia `prop_type` e
`dimensions` nell'Inspector oppure assegna una tua scena salvata al campo `asset`.
Il kit iniziale usa geometria semplice e materiali ruvidi; è una base di layout,
non l'arredo artistico definitivo. La scena assegnata deve avere origine al centro
della base e collisioni proprie; `dimensions` deve descriverne l'ingombro reale.

La gerarchia è **Piano → Stanza → Mobili**. Le vecchie scene vengono raggruppate
all'apertura usando l'associazione alla stanza, senza cambiare la posizione dei
mobili. Salva la scena per conservare la nuova gerarchia. Spostare una stanza
sposta anche il suo arredo; muri condivisi e scale restano sotto il piano.
**Aggiungi dettaglio**, con una stanza o un suo mobile selezionato, crea il nuovo
oggetto sotto quella stanza. Gli oggetti senza stanza assegnata restano sul piano.

Il posizionamento prova candidati lungo le pareti, evita l'area di apertura delle
porte, gli sbarchi delle scale e gli altri mobili, poi verifica la percorribilità.
Quando manca spazio omette un mobile. Non forza il numero richiesto a costo di
bloccare il passaggio. Gli oggetti personali trascinati direttamente sotto il piano
sono conservati, ma non partecipano alla verifica degli ingombri: per includerli,
usa un nodo Oggetto con `asset` e dimensioni corrette.

## Prova rapida

Apri `scenes/dev/house_authoring_example.tscn`: è una casa con due piani già salvati,
stanze e mobili editabili. Seleziona la radice e usa **Interni: crea / mostra**,
**Piano successivo** e **Play casa selezionata**. Puoi istanziarla nel laboratorio
per avere anche terreno e illuminazione nell'editor. La tua scena di laboratorio
esistente non viene sostituita dall'esempio.

Flusso consigliato: dimensioni casa → numero di piani → genera stanze dal basso
verso l'alto → modifica e blocca stanze → rigenera muri → arreda → ritocca a mano →
salva → Play. Dopo modifiche importanti a casa e piani, rigenera esplicitamente:
il sistema non ridistribuisce automaticamente i tuoi contenuti durante un drag.

## Limiti attuali

- Fino a tre piani; stanze rettangolari allineate alla casa e un'ala laterale.
- Il generatore iniziale privilegia un corridoio longitudinale e una scala diritta.
  Non è ancora un solver per qualsiasi pianta, scala o combinazione di requisiti.
- Le stanze sono volumi di progetto: i muri si aggiornano con il comando dedicato.
  Pareti e oggetti possono essere ruotati; i volumi stanza devono restare allineati.
- Il controllo di percorribilità è conservativo e considera le porte aperte.
  Le geometrie manuali e gli asset complessi richiedono comunque una prova in gioco.
- Luci di prova, oscuramento esterno e camera sono quelli precedenti. GI e lightmap
  restano una fase separata; non è stato fatto un passaggio di ottimizzazione.

## Verifiche ripetibili

Con Godot 4.6.3 dalla radice del progetto:

```text
--headless --path . --script res://tools/check_house_plan.gd
--headless --path . --script res://tools/check_house_generation.gd
--headless --path . --editor res://scenes/dev/house_builder_playground.tscn -- --house-editor-test
--path . res://scenes/dev/house_interior_playable.tscn -- --house-authored-test
```

Coprono salvataggio/ricaricamento, seed, adiacenze, ala, protezione delle modifiche,
cancellazioni, percorribilità, arredo e undo/redo nell'editor. La prova grafica usa
il giocatore reale sulla casa di esempio salvata: porta chiusa/aperta, stanza,
salita, discesa e uscita. Le immagini sono in `captures/house_interior/authored_*.png`.

`tools/build_house_authoring_example.gd` ricrea soltanto la scena di esempio:
non eseguirlo su una copia che hai personalizzato senza prima salvarla con altro nome.

Checkpoint: `e0a6b08` stato iniziale, `6cb96c2` interni persistenti, `a0698e1`
planimetrie, `154bd81` rigenerazione protetta. L'arredo e le verifiche finali sono
nel commit successivo a questi checkpoint.
