# W01.1 — Acqua prescritta, primo esempio

Aprire `scenes/dev/water_study.tscn`, F6. WASD per camminare dalla riva nel
lago e nell'emissario. F visualizza il campo (rosso: componente X, blu: Z);
V attiva/disattiva un vortice locale. Camera, player, viewport e luci provengono
dal rig gameplay condiviso. La reference guida acqua bassa, trasparenza e
increspature; gli effetti magici luminosi non fanno parte di questo incremento.

## Separazione dei sistemi

`addons/water_builder/water_body.gd` è un nodo tool. In Inspector espone
Boundary (XZ locale, 3–32 vertici), Flow Path (massimo 16 punti), Flow Speed,
Basin Depth e vortice. La posizione Y del nodo determina la quota della superficie.
La preview dell'acqua compare nell'editor; il fondale della scena esempio viene
costruito entrando in Play, usando gli stessi dati del perimetro.

La scena usa un unico perimetro che include lago ed emissario. Il percorso guida
un campo vettoriale; la corrente cresce avvicinandosi all'uscita, lungo X locale
in questo esempio. Non è ancora un generatore autonomo di fiumi da spline.

Il fondale dell'esempio è una griglia triangolata con collisione, raccordata alla
riva e profonda circa 40 cm. La superficie non è un pavimento: il giocatore
cammina sul fondale. Mancano ancora nuoto, variazione di velocità e zone proibite.

Il materiale ha colore dipendente dalla distanza dalla riva, trasparenza,
normali animate, linee luminose procedurali e schiuma di bordo. Le linee sono
un'approssimazione artistica delle caustiche sulla superficie, non luce simulata
sul fondale. La profondità è derivata dal perimetro, non dal depth buffer.

## Perché non importare tutta la shallow-water simulation

Esaminato `rpg-3d/addons/sim_water/shaders/swe_sim.gdshader`: evolve altezza,
velocità e schiuma, con accoppiamento, vincoli di passo e correzioni specifiche.
Non viene copiato né eseguito quel solver. Qui il livello resta costante:
nessun trasporto di massa, riempimento, allagamento o instabilità di integrazione.

W01.3a: caustiche cellulari deformate, linee curve interrotte da variazioni locali
di intensità. Sostituito il prodotto periodico di sinusoidi che produceva una
scacchiera. Rimangono un effetto artistico di superficie, da rifinire sul fondale.

Il campo guida due fasi di scorrimento interpolate, evitando deformazioni visive
che crescono senza limite. Il vortice è un campo tangenziale con attenuazione
locale; non risucchia acqua. Le interazioni usano otto onde analitiche a durata
massima di due secondi, ora irregolari e attenuate. W04.1 aggiunge 16 campioni
di scia orientati dalla velocità, schiuma discontinua e perturbazione delle normali.
Gli spruzzi sono 48 piccole mesh in un MultiMesh, riutilizzate; emissione ai lati
del personaggio, traiettoria balistica e durata massima di 0,6 secondi.
Da fermo e sulla terra non vengono emesse scie. Non ci sono ancora riflessioni
contro ostacoli, spostamento di massa o collegamento alle animazioni dei singoli piedi.

## W02.1 — Fiume e rocce

Aprire `scenes/dev/river_study.tscn`, F6. Stessa camera e interazione del lago.
F mostra frecce e componenti del campo; V abilita il vortice opzionale.
La scena è prodotta da `tools/build_river_study.gd` usando il nodo
`addons/water_builder/river.gd` e quattro rocce di `rock_builder`.

In editor selezionare `River/FlowGuide` e modificare la Curve3D con i controlli
nativi di Path3D. `River.widths` contiene larghezze interpolate lungo il percorso.
Il prototipo campiona 16 sezioni e ricava 32 vertici di sponda. La superficie
rimane alla quota del nodo River; mantenere il percorso sul piano XZ e il nodo
FlowGuide senza trasformazioni aggiuntive. La quota Y della curva non genera
cascate o pendenze. Il fondale si ricostruisce all'avvio della prova.

Le rocce sotto `River/Rocks` restano nodi editabili del builder con collisioni.
Posizione e dimensioni aggiornano il campo: ogni ostacolo è approssimato da un
cerchio; la corrente viene deviata analiticamente e limitata in velocità.
Schiuma locale al contatto e scia discontinua a valle indicano l'ostacolo.
Massimo 12 rocce influenti nel prototipo; nessun solver, erosione, accumulo
o simulazione di pressione. Le collisioni usano invece la geometria del rock builder.

`flow_at()` espone un campionamento CPU del flusso base e delle deviazioni,
utile per test e futura interazione con oggetti; non include ancora il vortice
visivo opzionale. `tools/check_river_study.gd` verifica geometria del percorso,
larghezze, velocità limitata, aggiornamento dopo spostamento roccia e collisioni.
`--capture-water` sulla scena fluviale salva `captures/river_study.png`.

Restano da risolvere curve troppo strette e autointersezioni delle rive, vincoli
precisi sulle sponde e confluenze. La deviazione circolare non ricostruisce la
forma esatta di ogni roccia e non garantisce conservazione della portata.

## Verifiche e prossimi passi

W01.4: in Play, 1 = calmo, 2 = brezza, 3 = mosso. Inspector: Wind Angle,
Wave Height e Breaking Foam. Due onde analitiche deformano la superficie;
la fase viene compressa vicino al bordo e l'ampiezza si annulla sulla linea
di riva. La schiuma segue cresta e coda, con intensità maggiore sulle coste
raggiunte dal vento; non è un bordo bianco sempre acceso.
La mesh usa quattro suddivisioni uniformi per triangolo iniziale, evitando
fessure tra bordi con tessellazione differente. Nessuna modifica al fondale
fisico, nessuna simulazione di pressione o allagamento.
La risacca è per ora rappresentata dentro la superficie: avanzamento sul terreno,
terreno bagnato e spruzzi da impatto delle onde sulle rocce sono W01.4b.
`--rough-water` insieme a `--capture-water` cattura il preset mosso.

`tools/check_water_study.gd`: ingresso e uscita reali, collisione fondale,
onde nel lago ma non sulla terra, comandi campo/vortice.
`--capture-water` salva `captures/water_study.png` con il player nel lago.

- W01.2: disegno perimetro e gizmo contestuali, Undo/Redo, errori su incroci;
  fondale e riva aggiornabili anche in editor, senza riscrivere il terreno manuale.
- W01.3: profilo di riva più naturale, fondale visibile con dettaglio, riflessi
  e caustiche meno ripetitive; confronto reference con le luci del gioco.
- W02: spline indipendente, larghezza e quota per tratto, campo continuo nelle
  curve/confluenze, nessuna dipendenza dall'asse X dell'esempio.
- W03: guadi, ponti e raccordi; maschere di ostacolo e riserve per altri builder.
- W04: interazioni locali più ricche, scie e spruzzi, oggetti galleggianti guidati
  dal campo; aggiungere simulazione solo quando un comportamento la richiede.

W01 e W02 restano aperti. Questo esempio dimostra il flusso di rendering e Play,
non completa ancora il builder di laghi e fiumi.


## W04.2 — Confronto A/B con simulazione locale

Aprire `scenes/dev/water_study.tscn` e premere F6: stessa camera e personaggio
 del gioco. F7 alterna A (scie analitiche) e B (onde simulate); O aggiunge un
impulso in acqua, WASD produce impulsi camminando. Ogni attivazione di B azzera
il campo. Premere 1 per isolare le interazioni dal vento.

`local_wave_field.gd` implementa un'equazione delle onde smorzata su griglia
CPU 64x64, 30 Hz, in una zona fissa di 20x20 metri nelle coordinate locali
 del lago. La maschera delle rive e degli ostacoli circolari viene acquisita
all'attivazione: riattivare B dopo modifiche. Le celle asciutte riflettono
le onde; il bordo esterno della zona le assorbe gradualmente. Gli impulsi
bilanciano spostamenti positivi e negativi. Passo fisso, coefficiente CFL
controllato e massimo tre passi per frame evitano accumuli di lavoro dopo pause.
Le onde aggiornano normali e altezza visiva; non modificano collisioni o livello
medio, non trasportano acqua orizzontalmente. Il flusso prescritto resta separato.
Dentro la zona le scie analitiche vengono sfumate via per evitare duplicazioni;
fuori continuano a funzionare. Gli spruzzi rimangono attivi in entrambi i modi.

Prima misura locale: circa 0,57 ms medi per passo del solver nel test headless;
circa 0,40 ms nel breve capture con rendering. Misure indicative, escluse copia
texture e costo GPU; non sono un benchmark del mondo completo. Entrambe le
catture raggiungono il limite di 60 FPS, insufficiente per stimare il costo GPU.

Verifiche: `tools/check_local_wave_field.gd` controlla propagazione (797 celle
inizialmente ferme raggiunte), decadimento, celle asciutte, impulsi ripetuti,
valori finiti e recupero dopo un frame lungo. `tools/check_water_study.gd`
verifica anche F7, O, binding shader e assenza di impulsi sulla terra.
Il test di integrazione conserva il noto messaggio PagedAllocator in chiusura
headless; i capture renderizzati terminano senza errori.

Capture: `--capture-water --compare-water` produce `captures/water_analytic.png`;
aggiungere `--simulate-water` produce `captures/water_simulated.png`.
La simulazione e' visivamente piu' discreta delle scie precedenti: il confronto
non dimostra ancora una qualita' finale superiore. Caustiche e rifrazione sono
invariate. Restano GPU, miglioramento della lettura con la camera di gioco,
caustiche sul fondale derivate dal campo e test dedicato delle riflessioni.

Riferimento studiato: [WebGL Water](https://madebyevan.com/webgl-water/) e
[solver originale](https://github.com/evanw/webgl-water/blob/master/water.js).
Questo e' un prototipo originale CPU, non una conversione completa della demo GPU.


### Correzione leggibilita dopo F7

Le normali da sole rendevano praticamente invisibili le onde millimetriche con
la camera e la luce del gioco. Lo shader ora evidenzia creste e avvallamenti
usando l'altezza simulata, aumenta il contributo delle pendenze alle normali e
lega la schiuma alla pendenza delle creste. Il contrasto e' una scelta visiva,
non una modifica alla fisica o nuovi cerchi analitici. Campo nullo significa
nessun contributo: F7 attiva il solver, camminare in acqua oppure O lo eccitano.
Verificato con capture reale durante movimento, preset brezza, senza impulso
aggiuntivo O; compilazione shader e cattura senza errori. La risoluzione locale
resta 64x64: affinare forma e riflessi rimane W04.3.
