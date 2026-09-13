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

## Componenti agganciati: balcone

Apri `scenes/dev/balcony_attachment_example.tscn`. La casa ha due piani, una scala
interna e un balcone a 2,8 m. Seleziona la casa e usa **Play casa selezionata**:
entra, sali la scala, raggiungi la porta del balcone; E apre/chiude le porte.

Nel tab **Componenti**, premi **Posiziona balcone + porta** e clicca sulla facciata
alla quota del pavimento desiderata. Il rettangolo azzurro anticipa l'ingombro.
Occorrono 2,12 m liberi sopra la quota per la porta. Un posizionamento invalido
mostra il motivo e non crea il componente.

Il nodo `Components/Balcone` resta editabile e salvato nella scena. Selezionalo
per mostrare le maniglie: posizione sulla facciata, larghezza, profondità.
Nell'Inspector puoi cambiare facciata, quota e dimensioni. Usa queste proprietà
anziché il gizmo di trasformazione nativo, perché il transform deriva dall'aggancio.
Se una modifica rende il balcone invalido, il pannello mostra l'errore e il contorno
è rosso; geometria e porta derivata restano sospese fino alla correzione.

La porta generata taglia realmente muro e collisione, alla quota del balcone.
Rimuovere il balcone richiude quel vano. Le porte manuali non vengono cancellate:
per utilizzarne una, sceglila nel menu degli accessi e premi **Applica accesso**.
Il balcone segue posizione e facciata della porta; non ne assume la proprietà.
Seleziona un piano e premi **Applica collegamento al piano**: sia il balcone sia
la porta collegata seguono `InteriorPlan.floor_height`. **Quota manuale** rimuove
il legame al piano mantenendo la quota corrente. La porta manuale conserva il
proprio collegamento al piano anche se il balcone viene rimosso.

Con una porta manuale collegata, sposta l'accesso dal tab Aperture: la maniglia
centrale del balcone non sposta più l'insieme. Larghezza e profondità restano libere.
Con un piano collegato la maniglia non cambia la quota: modifica il piano oppure
passa a Quota manuale. **Porta generata dal balcone** scollega l'accesso manuale,
che viene conservato; sposta quindi il balcone per evitare una sovrapposizione.
Rinominare un piano o riordinare le aperture conserva i legami; eliminare un
riferimento mostra un errore esplicito e sospende il balcone.

Gli agganci supportano
le quattro facciate del corpo principale; ali e terrazze sono incrementi successivi.
Aggiunta, maniglie, rimozione e modifiche Inspector supportano undo/redo.

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

## Terrazza su pilastri e scala esterna

Nel tab **Componenti**, **Posiziona terrazza + scala** crea il piano con quattro
pilastri e una rampa frontale. Il clic indica la quota del piano; l'anteprima mostra
anche l'ingombro della scala. Per convertire un balcone già selezionato usa
**Aggiungi pilastri e scala al selezionato**. **Rimuovi scala esterna** conserva
terrazza e pilastri e richiude automaticamente il parapetto. Undo/redo ripristina
la configurazione precedente.

Nell'Inspector, **Terrazza e scala esterna** offre pilastri e scala indipendenti,
larghezza e spostamento laterale della rampa lungo il bordo frontale, e **Ground
Level** (quota del terreno nelle coordinate della casa, inizialmente 0). La scala
mantiene 32 gradi di pendenza e comprende un pianerottolo di raccordo; lunghezza,
gradini, pilastri e collisioni seguono automaticamente il piano collegato.

Esempio editabile: `scenes/dev/terrace_stairs_example.tscn`. Seleziona la casa e
premi **Play casa selezionata**: gira davanti alla rampa, sali ed entra dalla porta
superiore. Verificati salita, ingresso, discesa e ripetizione dopo aver alzato il
piano da 2,8 a 3,2 m, con il giocatore del gioco.

Per ora la scala è rettilinea e frontale: non gira ad angolo e non si aggancia ai
lati della terrazza. La quota terreno è manuale e uniforme; non vengono ancora
rilevati terreno irregolare, strade o edifici nell'ingombro della rampa. L'errore
per una quota terreno incompatibile compare nel pannello Componenti.

## Scala come componente e scelta del bordo

Una nuova terrazza crea ora il nodo `Terrazza/ScalaEsterna`. Nel tab Componenti,
**Scala indipendente · frontale / destra / sinistra** crea il nodo su una terrazza
esistente oppure cambia il bordo di quello già presente. Le vecchie scene con
scala frontale incorporata continuano a funzionare; il comando le converte
conservando larghezza, offset e quota terreno. Undo ripristina anche il formato
precedente.

Seleziona **ScalaEsterna**: compaiono solo le sue maniglie di larghezza e posizione
lungo il bordo. L'Inspector espone lato, larghezza, offset, quota terreno ed
abilitazione. Il nodo conserva un ID nel salvataggio ed eredita la quota di partenza
dalla terrazza; la sua quota di arrivo può differire da quella dei pilastri.
**Elimina scala indipendente** rimuove il nodo e richiude il parapetto. La terrazza
e la porta rimangono; **Rimuovi scala esterna** la disabilita senza eliminarla.

Esempio: `scenes/dev/side_stairs_example.tscn`, con accesso da destra e Play casa.
Verificati accessi da destra e sinistra con il giocatore, apertura/chiusura dei
parapetti, salvataggio e undo/redo. Una sola scala per terrazza in questo incremento;
rampe a L/U, pianerottoli intermedi e posizionamento libero senza terrazza restano
successivi. Il nodo è indipendente nei parametri ma rimane agganciato alla terrazza:
usa le sue maniglie e proprietà invece della trasformazione nativa Godot.

## Corpi accessori: tab Volumi

Apri `scenes/dev/multi_volume_example.tscn`: **CasaComposta** contiene
`Volumes/Bottega` e `Volumes/Deposito`, modificabili separatamente.
Seleziona **CasaComposta** e premi **Play casa selezionata** per provare l'intero
edificio; l'ingresso frontale porta anche ai due corpi laterali.

Nel tab **Volumi**, scegli **Aggiungi corpo** sulla facciata desiderata. Seleziona
il nuovo nodo per usare le maniglie di larghezza, profondità, altezza e tetto.
Nell'Inspector, **Host Wall** e **Host Offset** controllano facciata e posizione
lungo la parete. Il tab **Aperture** modifica le finestre e porte di quel corpo.
Il tetto e le aperture mantengono parametri indipendenti dalla casa principale.

**Sgancia volume** conserva la trasformazione corrente e permette spostamento
e rotazione con gli strumenti Godot; **Riaggancia volume** ripristina l'aggancio
alla facciata configurata. **Rimuovi volume selezionato** conserva gli altri corpi.
Queste operazioni supportano undo/redo. L'aggancio aggiorna automaticamente il
taglio della parete e le collisioni. Il tipo di raccordo si sceglie nel tab Volumi.

Il pannello indica **VOLUME NON RACCORDATO** se dimensioni, tetto o posizione
impediscono il raccordo. Il tetto accessorio deve rimanere almeno 15 cm sotto
l'altezza della parete principale: il corpo predefinito richiede circa 4 m di
parete. Riduci le altezze del corpo o aumenta quella della casa. La larghezza deve
entrare nella facciata, senza sovrapporsi ad aperture manuali o ad altri annessi.
Non inserire aperture sul retro del corpo, che è il lato condiviso.

Questo incremento supporta corpi al piano terreno, senza ali legacy o volumi
annidati. Un raccordo non valido lascia chiusa la parete principale. Interni
su più volumi e intersezioni complesse dei tetti sono successivi.


## Raccordo aperto oppure parete con porta

Seleziona il corpo accessorio e, nel tab **Volumi**, scegli **Raccordo · passaggio
aperto** oppure **Raccordo · parete con porta**. La seconda modalità conserva la
parete principale e genera un'apertura con porta interattiva. Non aggiunge una
seconda parete sovrapposta. I comandi supportano undo/redo.

Nell'Inspector, **Raccordo interno** espone larghezza, altezza e offset della porta.
L'offset sposta il vano lungo il raccordo mantenendo almeno 25 cm dai bordi.
Una porta troppo grande produce un errore esplicito e non taglia il muro.
La porta è derivata dal volume, non compare nell'elenco delle aperture manuali:
passare alla modalità aperta o sganciare il corpo la rimuove senza toccare quelle.
Dimensioni e stato aperto/chiuso si salvano con il volume.

Nell'esempio `multi_volume_example.tscn`, la bottega ha un raccordo aperto e il
deposito una porta. Seleziona CasaComposta e usa Play; **E** aziona la porta vicina.
`tools/check_volume_junction_play.gd` verifica che la porta chiusa blocchi il
personaggio, poi la apre e attraversa il raccordo in entrambe le direzioni.


## Portici e tettoie aperte

Nel tab **Volumi**, scegli **Nuovo: portico / tettoia aperta**, poi la facciata con
**Aggiungi corpo**. Il tipo nuovo vale solo per le creazioni successive. Per
convertire un volume esistente usa **Struttura → Structure Kind** nell'Inspector.
Le aperture manuali del corpo vengono conservate ma non generate nel tipo aperto;
tornano visibili riconvertendolo in corpo chiuso. I pulsanti del raccordo interno
sono disabilitati quando si seleziona un portico.

Le maniglie controllano larghezza, profondità, altezza di gronda (**Wall Height**,
qui altezza dei sostegni) e rialzo del colmo (**Roof Height**). **Post Size** regola
la sezione dei pali, **Post Spacing** la distanza massima lungo i lati. Il numero
di campate segue la profondità: allungare una tettoia aggiunge sostegni.

Il portico agganciato conserva la parete della casa e può coprire una porta
esistente se l'altezza lascia spazio al suo vano. Non genera un ingresso nuovo.
**Sgancia volume** permette di spostarlo liberamente come tettoia: ricompaiono i
sostegni posteriori. Terreno e pavimentazione restano quelli della scena.

Apri `scenes/dev/porch_canopy_example.tscn`: portico davanti all'ingresso e tettoia
indipendente accanto alla casa. Seleziona **CasaComposta → Play casa selezionata**.
Sotto le coperture si resta all'esterno; l'oscuramento si attiva entrando in casa.
Verificati collisione dei pali, lati aperti, ingresso/uscita del giocatore,
salvataggio e creazione con undo/redo.

Prima versione: tetto a due falde, pali rettilinei in due file, base orizzontale.
Non include ancora falda singola, archi, controventi, terreno irregolare o
modifica individuale dei pali. Per un portico agganciato la copertura deve restare
sotto la gronda principale, come per i corpi chiusi.


## Falda singola per portici e tettoie

Seleziona il portico nel tab **Volumi** e scegli **Copertura selezionata: falda
singola**. Il controllo è attivo solo sui corpi aperti e supporta undo/redo.
La stessa proprietà è nell'Inspector, **Struttura → Canopy Roof**.

**Wall Height** è la quota del bordo basso esterno; **Roof Height** è il dislivello
verso la parete. La profondità determina la pendenza insieme al dislivello.
Le maniglie di altezza si trovano sui due bordi corrispondenti. Pali e travi
seguono la falda; le tegole conservano rilievo, materiali e variazioni esistenti.
L'aggancio taglia la porzione nascosta nella parete senza chiudere l'ingresso.
Sganciando la tettoia rimane la stessa direzione locale di pendenza; si può ruotare
l'intero volume con Godot.

L'esempio `porch_canopy_example.tscn` ora confronta il portico a falda singola con
la tettoia a due falde. Verificati adattamento al ridimensionamento, salvataggio,
undo/redo e ingresso/uscita col giocatore. Questa copertura è per i corpi aperti:
i corpi chiusi conservano il tetto a due falde. Restano da implementare coperture
piane e sostegni modificabili individualmente.


## Sostegni modificabili singolarmente

Nel tab **Volumi**, seleziona un portico e premi **Sostegni: rendi editabili**.
La disposizione corrente diventa una lista di nodi `Supports/Sostegno_…`, ciascuno
con ID persistente. Seleziona un nodo nell'albero o tramite il suo gizmo: compare
solo il suo contorno. Usa la traslazione Godot per spostarlo e **Section**
nell'Inspector per la sezione quadrata; **Enabled** lo sospende senza cancellarlo.
L'altezza segue la copertura dalla quota base del nodo.

**Aggiungi sostegno** inserisce un palo al centro del bordo anteriore;
**Rimuovi sostegno selezionato** lo cancella. Queste operazioni, la conversione e
**Ripristina sostegni automatici** supportano undo/redo. Il ripristino rimuove
l'intera disposizione manuale; Undo la recupera. Prima della conversione continua
a funzionare il passo automatico. Dopo, anche una lista vuota rimane manuale:
i pali cancellati non ricompaiono e cambiare Post Spacing non li ridistribuisce.

Ridimensionare o sganciare il portico conserva numero, posizioni locali e sezioni
manuali. I pali fuori dalla copertura vengono segnalati nell'Inspector e nel
pannello quando selezionati, conservati nei dati e sospesi nella geometria.
Non vengono spostati automaticamente per adattarli: correggili a mano.

Prima versione: pali verticali, sezione quadrata; usa posizione e Section, non
rotazione o scala (se impostate, compare una segnalazione). Le travi restano
quelle del telaio automatico: non è un controllo di stabilità strutturale.
L'esempio porch_canopy ora ha due pali anteriori più spessi e spostati verso
l'interno. Verificati persistenza dopo ridimensionamento, collisioni, cancellazione,
salvataggio, undo/redo e Play.


## Travi collegate e controventi

Il tab **Volumi** ora separa **Sostegni** e **Collegamenti**. Rendi i sostegni
editabili, selezionane due dello stesso portico nell'albero con Ctrl + clic,
poi premi **Collegamenti → Collega con trave e controventi**. Il nodo risultante
è sotto `FrameLinks`; selezionandolo compare solo il suo gizmo.

Gli estremi seguono gli ID dei pali: spostamenti, rinomine e variazioni del tetto
aggiornano trave e collisione. Nell'Inspector: **Section** regola la sezione,
**Roof Offset** la distanza verticale sotto la sommità dei pali, **Braces** abilita
i due controventi, **Brace Drop** la discesa sul palo e **Brace Fraction** la
lunghezza relativa lungo la trave. **Enabled** sospende l'intero collegamento.
Sposta i pali per cambiare gli estremi; la trasformazione del nodo collegamento
non posiziona la geometria.

**Rimuovi collegamento selezionato** conserva i pali. Creazione e rimozione
supportano undo/redo. Un palo mancante, disabilitato o fuori copertura sospende
la geometria del collegamento e mostra un errore, senza cancellare i riferimenti.
Annullando la rimozione del palo il collegamento torna valido. Ripristinare tutti
i sostegni automatici sospende i collegamenti manuali finché non si recuperano
i pali originali tramite Undo o si ricreano i collegamenti.

Il telaio automatico della copertura resta attivo per compatibilità; puoi
disabilitare **Automatic Frame** sul volume e costruire i collegamenti manuali.
Questo non rimuove né tetto né pali. Per ora si collegano due sostegni: non ci
sono estremi liberi o agganci diretti alla parete e non viene verificata la
stabilità strutturale. L'esempio include tre travi con controventi, frontale e
laterali. La cattura `frame_links_detail.png` mostra il telaio da vicino.


## Collegamento di un sostegno alla parete

Seleziona un solo palo e usa **Volumi → Collegamenti → Collega un sostegno alla
parete**. La trave parte dal palo e raggiunge la facciata a cui è agganciato il
portico. Il controvento è presente solo sul palo. **Wall Offset** sposta l'estremo
lungo la parete rispetto al palo; la quota segue il tetto e **Roof Offset**.
Il punto rimane sulla facciata anche cambiando lato di aggancio del portico.

Se sganci il portico, il collegamento viene sospeso con un messaggio; riagganciandolo
ritorna valido. Sono segnalati estremi fuori copertura e sovrapposizioni del punto
di aggancio con aperture. Dati e modifiche si conservano; creazione e rimozione
supportano undo/redo. Il collegamento resta alla facciata ospitante: non permette
ancora di scegliere una parete diversa o un punto libero in altezza.

Esempio `scenes/dev/wall_frame_example.tscn`: due pali anteriori, una trave frontale
e due travi verso la parete. Seleziona **CasaComposta → Play** per attraversare
l'ingresso. `wall_frame_detail.png` mostra il telaio da vicino.


## Copertura piana e parapetto

Seleziona un volume accessorio e scegli **Volumi → Copertura selezionata: piana /
parapetto**. Funziona sia sul corpo chiuso sia sul portico; la casa principale
conserva la copertura esistente. **Parapet Enabled** nell'Inspector abilita il
parapetto perimetrale, **Roof Height** ne regola l'altezza. La soletta è spessa
18 cm sopra Wall Height. Porte, finestre, pali e collegamenti vengono conservati.
La maniglia superiore modifica il parapetto; con il parapetto disabilitato la
sua altezza rimane memorizzata ma non influisce sulla copertura.

Il tetto piano usa i materiali già presenti per intonaco e pietra. Soletta e
parapetto hanno collisione; la vista interna nasconde la copertura senza rimuovere
le collisioni. Il raccordo non taglia la parete della casa sopra la soletta.

Esempio `scenes/dev/flat_roof_example.tscn`: bottega con parapetto e deposito senza.
Seleziona CasaComposta e premi Play per verificare gli interni. Non viene ancora
creato un accesso al tetto: scala, porta superiore e varco nel parapetto restano
un incremento successivo. Non è ancora un piano aggiunto alla planimetria interna.


## Scala esterna verso il tetto piano

Seleziona il volume e usa **Volumi → Accesso tetto → Aggiungi scala al tetto piano**.
Il nodo `ScalaTetto` riusa la scala delle terrazze: **Side** sceglie fronte/destra/
sinistra, **Width** la larghezza, **Offset** la posizione lungo il bordo e
**Ground Level** la quota inferiore. Le maniglie della scala modificano larghezza
e posizione. Il pianerottolo segue la sommità della soletta (Wall Height + 18 cm).

Il parapetto apre un varco corrispondente. Rimozione, disabilitazione o parametri
invalidi richiudono il varco; cambio di copertura sospende la scala conservandola.
Aggiunta e rimozione supportano undo/redo. La scala può stare su uno dei tre bordi
esterni: non sul retro verso la casa. Una sola scala per volume in questa versione.
La disposizione rispetto ad altre case, strade o ostacoli rimane manuale.

Esempio: `scenes/dev/roof_access_example.tscn`, seleziona CasaComposta e premi Play.
Raggiungi la scala esterna della bottega, sali sul tetto e ridiscendi. Il tetto resta
illuminato come esterno e visibile quando il giocatore vi cammina. Non è ancora
collegato con una porta al piano superiore della casa; la planimetria interna
non viene modificata. Le texture sono rimaste quelle della versione precedente.


## Porta dal tetto al piano superiore

Seleziona il volume con tetto piano e usa **Volumi → Accesso tetto → Collega porta
al piano interno**. Il comando cerca un livello dell'InteriorPlan della casa alla
quota del tetto, con tolleranza di 6 cm. Collega il suo ID persistente senza
modificare stanze, muri o quote. Se manca il livello, compare un errore esplicito:
allinea prima le quote nella tua planimetria. Non viene creato un piano nascosto.

La porta è derivata dal volume, larga 1,2 m e alta 2 m. **Roof Door Offset** la
sposta lungo il raccordo; **Rimuovi porta dal tetto** richiude il muro conservando
le aperture manuali. Aggiunta e rimozione supportano undo/redo. La rinomina del
piano non rompe il collegamento; cancellazione, quota incompatibile o sgancio
del volume sospendono la porta e mostrano l'errore. Lo stato aperto si salva con
il volume separatamente dalla porta del raccordo al piano terra.

`scenes/dev/roof_door_example.tscn` contiene un piano superiore vuoto persistente,
una porta e la scala esterna. Con CasaComposta → Play: sali, premi E alla porta,
entra, ritorna sul tetto e scendi. Non viene verificata la presenza di arredi o
tramezzi davanti alla porta: libera manualmente il passaggio nel piano collegato.
Il formato attuale ha un collegamento superiore per ciascun volume.


## Torre quadrata e merli

**Volumi → Crea torre quadrata merlata** aggiunge un volume indipendente costruito
con lo stesso builder: pianta e altezza modificabili, porta e finestra, tetto piano.
**Battlements Enabled** alterna parapetto continuo e merli; **Battlement Spacing**
regola il passo. Il ritmo si adatta alla lunghezza dei lati e rispetta il varco
per la scala. I vuoti fra i merli e i blocchi pieni hanno collisioni distinte.
Materiali e resa sono quelli attuali; il preset definisce la forma, non un nuovo
stile grafico. Le torri sono ancora quadrate/rettangolari.

Esempio `scenes/dev/square_tower_example.tscn`: seleziona **TorreQuadrata → Play**.
Una scala esterna laterale porta al tetto; scala e merli restano modificabili.
Non ci sono ancora scale interne o piani arredati nel preset. La torre è
indipendente: gli agganci dei corpi accessori alla torre e le torri poligonali
sono incrementi successivi.


### Torre ottagonale (A07.1)

In **Volumi → Crea torre ottagonale**, poi modifica larghezza, profondità,
altezza pareti e parapetto con i gizmo o Inspector. Le otto facce sono fisse;
larghezza e profondità diverse producono una pianta allungata.
Porte e finestre si inseriscono con gli strumenti Aperture sulle facce del
modello: i tagli e le cornici seguono anche le pareti oblique. Gli ID delle
facce sono 0–7, partendo dalla facciata anteriore e procedendo verso destra.
Merli, spaziatura e scala esterna sono gli stessi componenti della torre quadrata.
La scala a sinistra usa la faccia 6; a destra la 2; davanti la 0.

Apri `scenes/dev/polygon_tower_example.tscn`, seleziona TorreOttagonale e usa
Play per provare la scala e il tetto. L'esempio è salvato con parametri del
builder, non come mesh scollegata. Non sono ancora supportati ala legacy,
aggancio ad altri corpi e coperture diverse da quella piana. Per i piani interni
usa il supporto InteriorPlan descritto in A07.2; la generazione delle stanze
poligonali resta da implementare.

Verifiche: `check_polygon_tower.gd`, `check_polygon_tower_play.gd` e suite
editor. Rimane il messaggio noto PagedAllocator alla chiusura del test Play,
dopo il completamento delle asserzioni.


### Interni torre ottagonale (A07.2)

Seleziona una torre di almeno 6 × 6 metri, quindi **Interni → Torre: due piani e scala**.
Il comando crea un `InteriorPlan` ordinario con `PianoTerra`, `PrimoPiano` e
`PianoTerra/ScalaPrimoPiano`. Non sostituisce un piano già presente; è annullabile.
La quota iniziale è 2.8 m per piano e le pareti si adeguano ai due piani.

Sposta o ridimensiona ScalaPrimoPiano con gli strumenti esistenti: il vano nel
solaio superiore segue posizione, rotazione e dimensioni. I pavimenti seguono
la pianta ottagonale anche dopo il ridimensionamento della torre. Per cambiare
l’altezza dei piani modifica Floor Height e adegua Dimensions Y della scala.
Un avviso sul nodo Scala segnala quota errata o sbarco fuori dalla pianta.

Usa Piano successivo per la vista editor; Play seleziona il piano in base alla
quota del giocatore. Esempio salvato: `scenes/dev/tower_interior_example.tscn`.
Verificati ingresso, salita, discesa e uscita con il giocatore reale; taglio del
solaio dopo spostamento manuale della scala; salvataggio e Undo/Redo.

Limiti di A07.2: scala rettilinea tra i due piani; accesso al tetto aggiunto in A07.3;
nessuna generazione automatica di stanze poligonali (il comando espone un errore
esplicito). Il vano scala non ha ancora parapetti automatici. Muri e dettagli
manuali restano disponibili; non vengono adattati automaticamente alle facce oblique.


### Accesso interno al tetto (A07.3)

Su una torre ottagonale con InteriorPlan e almeno due piani, usa
**Interni → Torre: scala interna al tetto**. La disposizione iniziale richiede
almeno 7 × 7 metri; aggiunge `ScalaTetto` al piano superiore senza sostituire le
scale esistenti. Il preset va controllato se hai già modificato il layout.

`Roof Exit` distingue la scala verso il tetto. La sua altezza segue automaticamente
la quota della copertura; posizione, rotazione e larghezza/lunghezza rimangono
modificabili. Il vano nel tetto segue questi dati e si richiude disattivando
Roof Exit o eliminando la scala. Deve appartenere all’ultimo piano; un avviso
segnala l’uso su un piano inferiore o uno sbarco esterno alla pianta.

Esempio: `scenes/dev/tower_roof_stair_example.tscn`. Seleziona TorreOttagonale e
Play: entra, sali la prima scala, gira sul pianerottolo e percorri la seconda.
Il tetto torna visibile all’uscita e la scala resta visibile per ridiscendere.
Il cambio vista e illuminazione usa il comportamento già presente nel gioco.

Verificati percorso completo in entrambe le direzioni, collisioni, spostamento,
disattivazione/eliminazione del foro, salvataggio e Undo/Redo. Restano botola e
parapetti automatici del vano; la prima disposizione non risolve automaticamente
interferenze con muri o arredi aggiunti manualmente.


### Fortificazioni: cortina e portone (A08.1)

Nuovo tab **Fortificazioni → Crea mura con portone**. Il nodo Cortina usa i gizmo
per lunghezza (Width), spessore (Depth), altezza e merli. In Inspector → Portone
si regolano Gate Enabled, Gate Width, Gate Height, Gate Offset e Gate Open.
Il passaggio attraversa tutto lo spessore; disattivandolo il muro torna pieno.
Il portone riutilizza la porta interattiva e conserva lo stato aperto/chiuso.
I materiali sono quelli esistenti del builder.

**Play fortificazione** prova il nodo selezionato. Esempio:
`scenes/dev/curtain_wall_example.tscn`, con ScalaCamminamento modificabile
come scala esterna del builder. Il passaggio e il camminamento sono esterni:
non attivano il taglio o l’oscuramento dell’interno di una casa.

Verifiche: portone chiuso blocca il giocatore, aperto permette l’attraversamento;
salita/discesa dal camminamento; collisione dell’architrave e passaggio a tutto
spessore; spostamento/disattivazione, salvataggio, tab contestuale e Undo/Redo.
Limiti: segmento diritto indipendente, portone a una sola anta, lunghezza fino
al limite di 20 m del builder; nessun raccordo automatico a torri, angoli o altri
segmenti. Gli strumenti generici di aperture/interiori delle case non sono il
flusso di authoring della cortina: usa i parametri Portone. Scala nell’esempio;
il comando di creazione produce soltanto il muro. Per aggiungerla usa Volumi →
Accesso tetto sul muro selezionato.


### Raccordo torre–cortina (A08.2)

Seleziona la torre ottagonale e usa **Fortificazioni → Collega nuova cortina alla torre**.
Il comando sceglie una faccia libera e crea Cortina come figlio della torre.
In Inspector → Raccordo torre, `Tower Face` seleziona la faccia 0–7. Il muro si
allinea alla normale della faccia; posizione e altezza sono vincolate alla torre,
mentre lunghezza, spessore, merli e portone restano parametrici.

Il camminamento arriva al tetto della torre: entrambi i parapetti si aprono nel
punto di raccordo, con collisioni e quote coerenti. Non è una porta verso un
piano interno a quota diversa. Sono supportate anche le facce oblique.
Un avviso segnala una cortina troppo larga o due cortine sulla stessa faccia.
Disattivando Connect To Tower si libera il muro e si richiudono le estremità;
eliminando il muro si richiude il parapetto della torre.

Play fortificazione su una cortina collegata include anche la torre e gli
interni. Esempio: `scenes/dev/tower_curtain_example.tscn`. Il giocatore può salire
dall’ingresso al tetto, passare sul muro e tornare giù; anche il portone della
cortina è incluso nella ricerca delle porte interattive.

Verificati percorso completo, collisione continua al raccordo, faccia obliqua,
ridimensionamento, scollegamento/rimozione, salvataggio e Undo/Redo.
Limiti: una torre all’origine di ogni cortina, estremità opposta ancora chiusa;
nessun raccordo a una seconda torre, angolo tra muri o recinto automatico.
Le aperture manuali sottostanti non vengono controllate per interferenze con
il volume pieno della cortina: scegli una faccia libera.


### Due estremità e gruppo fortificazione (A08.3)

**Fortificazioni → Crea due torri collegate** crea un gruppo Fortificazione con
TorreOvest e TorreEst distinte. La cortina è sotto la torre di partenza e usa
`Target Tower` (riferimento relativo) e `Target Face` per l’arrivo. I nodi delle
torri restano modificabili; il gruppo serve a salvare e provare l’insieme.

Muovi la torre di arrivo lungo l’asse del collegamento: lunghezza e posizione
della cortina si aggiornano. Le facce devono essere opposte e allineate, i tetti
alla stessa quota; la distanza libera ammessa è 1.8–19.8 m. Una configurazione
invalida produce un avviso e non apre i parapetti. Svuotando Target Tower si
torna alla cortina collegata soltanto all’origine e il parapetto d’arrivo si richiude.
Non usare il gizmo Width per cambiare la lunghezza di una cortina vincolata a
due torri: è derivata dalla loro posizione.

Play fortificazione su gruppo, torre o cortina include l’intero gruppo.
Esempio `scenes/dev/two_towers_example.tscn`: entra in TorreOvest, sali al tetto,
attraversa la cortina e raggiungi TorreEst. Interni e ingresso sono predisposti
solo nella torre principale; per ora Play gestisce il cambio interno/esterno
su quella torre, mentre la seconda è percorribile sul tetto.

Verificati andata/ritorno con giocatore, apertura del secondo parapetto,
spostamento di entrambe le torri, errore di disallineamento, scollegamento,
riferimenti dopo salvataggio, creazione/Undo/Redo e snapshot del gruppo.
Limiti: nessun recinto automatico o risolutore per facce disallineate; nessuna
migrazione automatica degli interni su tutte le torri del gruppo.


### Primo recinto chiuso (A08.4)

**Fortificazioni → Crea recinto con quattro torri** crea Castello: quattro torri
ottagonali e quattro cortine collegate, un solo portone anteriore e cortile vuoto.
Sono tutti gli stessi nodi modificabili del builder. Nessun muro o torre è una
mesh scollegata dai parametri. L’esempio è in
`scenes/dev/castle_enclosure_example.tscn`.

Play fortificazione parte fuori dal portone. Aprilo, entra nel cortile e raggiungi
la porta obliqua della torre principale, rivolta verso il cortile. Le due scale
portano ai merli; il camminamento forma un anello percorribile fino al ritorno
alla torre di partenza. Le altre tre torri hanno il tetto percorribile ma non
ancora interni configurati per Play.

Per allargare il rettangolo, seleziona insieme le due torri dello stesso lato e
traslale lungo l’asse del collegamento: le cortine adiacenti cambiano lunghezza.
Spostare un solo angolo fuori allineamento produce l’avviso già previsto per i
raccordi. I parametri del portone restano su TorreOvest/Cortina.
`Courtyard Entry` ed `Entry Position` sul gruppo controllano lo spawn di prova.

Verificati portone chiuso/aperto, cortile confinato sugli altri lati, percorso
reale completo di tutti i camminamenti e uscita, ridimensionamento di un lato,
salvataggio dei quattro collegamenti, Undo/Redo e snapshot per Play.
Limiti: recinto iniziale rettangolare e quote uniformi; niente mastio, arredi,
terreno adattivo o interni delle torri secondarie. Questo è il primo castello
percorribile, non la chiusura di tutte le varianti del Castle Builder.


### Editing e diagnostica del recinto (A08.5)

Il tab Fortificazioni contiene ora **Crea** e **Recinto**. Seleziona il gruppo o
un suo elemento e apri Recinto: i due campi indicano la distanza fra i centri
delle torri sugli assi X/Z, non la dimensione esterna comprendente le torri.
**Applica dimensioni al recinto** sposta le torri del rettangolo e aggiorna le
cortine; non rigenera aperture, scale, dettagli o parametri del portone.
L’operazione è annullabile. Il bordo anteriore e quello sinistro restano fissi;
lo spawn di prova viene riposizionato proporzionalmente lungo X.

L’elenco diagnostico segnala collegamenti mancanti/disallineati, quote errate,
facce occupate più volte, torri non collegate correttamente, parti separate e
assenza di portone. **Clicca una voce per selezionare il nodo**; il tooltip
mostra il messaggio completo. Si aggiorna durante le modifiche manuali.

Il ridimensionamento assistito riguarda rettangoli di quattro torri senza
rotazioni locali. Una pianta modificata liberamente o dimensioni incompatibili
producono un errore prima di cambiare la scena; l’editing manuale rimane disponibile.
Esempio ridimensionato: `scenes/dev/castle_enclosure_resized_example.tscn`.
Verifiche: `check_enclosure_editing.gd` e suite editor, con preservazione delle
modifiche, Undo/Redo e selezione tramite diagnostica. La diagnostica non è ancora
una verifica di tutte le collisioni con dettagli o arredi personalizzati.


### Interni delle torri secondarie (A08.6)

I nuovi recinti vengono creati con interni in tutte e quattro le torri. Per un
recinto esistente, seleziona il gruppo e usa **Fortificazioni → Recinto →
Completa interni delle torri mancanti**. Il comando salta ogni torre che ha già
InteriorPlan, conserva le aperture manuali e aggiunge una porta verso il cortile
solo dove manca una porta. Se il nuovo ingresso interferisce con un’apertura,
segnala il problema prima di modificare la scena.

Il preset richiede almeno 7 × 7 m e pareti alte 4.8–7 m: due piani, scala
rettilinea e accesso al tetto. Mantiene l’altezza della torre dividendo la quota
fra i due piani. Nessun arredo aggiunto. Creazione e completamento sono annullabili.

Nel Play il riconoscimento dell’interno usa la pianta e la posizione di ciascuna
torre. Cambiano insieme piano visibile, nome nell’HUD, porte interattive e posizione
delle luci interne; le altre torri restano esterne. Salendo al tetto si ripristina
la vista esterna, ridiscendendo viene mostrato l’interno della torre corretta.

Esempio: `scenes/dev/castle_interiors_example.tscn`. Dal cortile sono raggiungibili
i quattro ingressi. Le ante aperte occupano spazio reale: avvicinati alla base
della scala passando intorno all’anta, senza tagliarne la rotazione.
Test: `check_castle_interiors_play.gd`, suite editor e regressione della torre
singola. Limiti: piani aperti senza stanze/arredo; nessuna GI/lightmap nuova,
nessun rifacimento delle texture e nessun parapetto automatico del vano scala.


### Parapetti dei vani scala

Le scale generano un parapetto sui tre bordi chiusi del vano al piano superiore;
lo sbarco resta aperto. Le scale `Roof Exit` lo generano sul tetto della torre.
Spostamento, rotazione e dimensioni della scala aggiornano anche i parapetti.
Per una soluzione manuale, seleziona la scala e disattiva **Guardrails Enabled**
nell'Inspector. I parapetti generati hanno collisioni e seguono la visibilità
del piano di arrivo; non modificare le mesh interne generate.
Prova `castle_interiors_example.tscn` con Play dal builder.
Test: `tools/check_stair_guards.gd`; immagini riproducibili tramite
`tools/preview_stair_guards.gd`.


### Mastio nella corte (A09.1)

Seleziona Castello o un suo elemento, apri **Fortificazioni → Recinto** e premi
**Aggiungi mastio nella corte**. Richiede un recinto rettangolare con quattro
torri e spazio centrale sufficiente; un secondo clic segnala l'edificio già
presente senza duplicarlo. L'operazione supporta Undo/Redo.
Il nodo `Mastio` è un Volume indipendente: usa i normali strumenti della casa
per dimensioni, aperture e componenti. In `InteriorPlan` trovi PianoTerra,
PrimoPiano e SecondoPiano con scale editabili. Le altezze seguono Floor Height
e il numero di piani; le scale manuali vanno mantenute coerenti con tali quote.
Il resize del recinto non sposta il mastio; la diagnostica segnala gli ingombri
fuori dalla zona centrale prevista. Il controllo è conservativo, non copre
ogni interferenza fra aggiunte manuali.
Apri `scenes/dev/castle_keep_example.tscn`, seleziona Castello/Mastio e usa il
Play del builder per entrare e salire ai tre piani. La copertura a falde non
è accessibile. Nessun arredo aggiunto in questa versione.


### Corpo accessorio del mastio (A09.2)

In **Fortificazioni → Recinto**, usa **Aggiungi corpo accessorio al mastio**:
il preset si aggancia al lato sinistro e compare sotto `Mastio/Volumes`.
Puoi rinominare il mastio. Per scegliere un altro lato usa il tab **Volumi**,
oppure Host Wall e Host Offset nell'Inspector. La copertura bassa lascia libere
le finestre del mastio. Ridimensionando, controlla le segnalazioni del raccordo.
**Raccordo interno** permette porta oppure passaggio aperto. La porta si apre
con E nel Play. Sganciando o eliminando il volume si ripristina il muro del mastio.
Le geometrie interne generate non vanno modificate direttamente.
La luce dell'annesso nel Play è una luce di prova, non un impianto salvato o GI.
Esempio: `scenes/dev/castle_keep_accessory_example.tscn`.
Verifiche: `check_keep_accessory.gd`, `check_keep_accessory_play.gd` e suite editor.


### Quote dei camminamenti (A09.3)

Seleziona il castello e apri **Fortificazioni → Quote → Abilita raccordi in
pendenza**. Il comando abilita le cortine senza portone e supporta Undo/Redo.
Modifica **Floor Height** dell'InteriorPlan della torre e l'altezza delle sue
scale ordinarie; la scala Roof Exit aggiorna automaticamente la propria altezza.
Per una torre priva di interni usa **Wall Height**. Non spostare la base in Y:
questa versione raccorda altezze dei tetti con fondazioni sullo stesso piano.
Per agire su una singola cortina usa **Allow Sloped Walkway** nell'Inspector.
Gli errori compaiono in Recinto: disallineamento, pendenza oltre 45%, oppure
portone su un dislivello. I parapetti terminali si aprono solo con raccordo valido.
Esempio pronto: `scenes/dev/castle_sloped_walkways_example.tscn`.
Le rampe sono continue e seguono le quote; materiali e illuminazione restano quelli
esistenti. Test: check_sloped_walkways.gd e check_sloped_walkways_play.gd.


### Camminamenti a gradini (A09.4)

Seleziona la cortina nell'albero e usa **Fortificazioni → Quote → Converti cortina
selezionata in gradini**. Deve collegare due torri e non avere portone. Il comando
abilita anche il raccordo delle quote; puoi tornare alla rampa dallo stesso tab.
Nell'Inspector trovi **Walkway Profile**. Dimensioni e numero di gradini seguono
le altezze delle torri e la loro distanza, con 50 cm di sbarco a ogni estremità.
Limiti: alzata massima 18 cm, pedata minima 24 cm, pendenza massima 75% nel tratto
centrale; gli errori restano visibili nella diagnostica del recinto. La collisione
è una rampa continua sotto i gradini. Le basi restano alla stessa quota.
Esempio pronto: `scenes/dev/castle_stepped_walkways_example.tscn`.


### Corte rialzata (A09.5)

Seleziona il castello e usa **Fortificazioni → Quote → Crea corte posteriore
rialzata**. Il preset richiede il recinto rettangolare (almeno 16 m fra centri),
con edifici alla quota iniziale zero. Aggiunge `CorteRialzata`, alza mastio e torri
posteriori di 1.2 m e raccorda le cortine. Undo annulla tutto insieme.
Il nodo espone Size, Elevation, Access Width e Access Run. La geometria e le
collisioni si aggiornano; gli edifici restano indipendenti. Dopo modifiche manuali
allinea le basi alla nuova quota, aiutandoti con la diagnostica Recinto. Il resize
del recinto non modifica automaticamente la piattaforma. I controlli di appoggio
usano il centro degli edifici: controlla anche i loro bordi e le aggiunte manuali.
Il portone rimane al terreno iniziale; la rampa conduce alla corte superiore.
Esempio: `scenes/dev/castle_raised_courtyard_example.tscn`.
Test: check_raised_courtyard.gd e check_raised_courtyard_play.gd.


### Cambiare quota insieme agli edifici (A09.6)

In **Fortificazioni → Quote**, imposta **Nuova quota della corte** e premi
**Applica quota a corte ed edifici collegati**. L'operazione sposta verticalmente
la corte e gli edifici elencati in **Linked Buildings**, preservando i loro offset
manuali, con Undo/Redo. Per corti precedenti la lista viene inizializzata dagli
edifici con centro sulla piattaforma. Verifica la lista se hai aggiunto edifici.
Un riferimento mancante o una rampa troppo ripida blocca l'operazione senza
spostamenti parziali. Modificando direttamente Elevation rimane disponibile il
comportamento manuale; Size e posizione non trascinano gli edifici.
Esempio: `scenes/dev/castle_linked_courtyard_example.tscn`.


### Castello aperto e visuale libera (A09.7)

**Fortificazioni → Crea → Crea castello con corte aperta** genera il layout più
spazioso. Apri `scenes/dev/castle_open_courtyard_example.tscn` e usa il Play del
builder. **F8** confronta visuale completa e taglio locale; il sottotab **Vista**
permette di salvare la preferenza. Sul gruppo, **Visibility Radius** regola quanto
spazio attorno al giocatore liberare; **Courtyard Visibility** abilita il sistema.
Il muro diventa invisibile solo nella zona fra camera e giocatore; rimane solido.
Pavimento sotto il giocatore e parti basse restano visibili. Il comportamento
si somma al cutaway degli interni e funziona con i materiali architettonici del
builder, non automaticamente con shader esterni o vegetazione.


#### Sezioni nel Play del castello (A09.8)

Con la visibilità attiva (F8), il bordo del taglio mostra ora lo spessore: pietrame scuro nelle cortine piene, sezione nera nelle pareti degli edifici cavi. La svasatura rende il bordo visibile dalla camera fissa. Il sistema segue le aperture della mesh finale e lascia liberi cortile e passaggi; resta un effetto temporaneo di visualizzazione. Non modifica i nodi salvati, le collisioni o gli strumenti del builder. Per ora le sezioni riguardano la muratura generata, non ogni oggetto o tegola.
