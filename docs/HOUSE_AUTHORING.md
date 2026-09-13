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
