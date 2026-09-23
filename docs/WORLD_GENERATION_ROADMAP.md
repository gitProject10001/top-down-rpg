# Pipeline dei generatori del mondo

Il concept delle quattro fazioni è un riferimento **di composizione**, non un risultato finale da copiare. Guida densità, masse, percorsi, spazi liberi e rapporti dimensionali. Non impone texture, colori, città identiche al disegno o un terreno scolpito a mano per imitarlo.

## Priorità attuale — 2026-09-23

Indice trasversale: [PROJECT_STATUS](PROJECT_STATUS.md). Prossimo incremento di gioco: V02 sul circuito esistente, prima di espandere il territorio. Il ramo editor conserva la dipendenza A07 → B01.1. Le prove ambientali sotto sono capacità disponibili e lavoro residuo, non un ordine per avviare tutti i TODO.


Incremento corrente: paesaggio integrato 304 × 288 m e ciclo giorno–notte. Si riusano World (piano, modifiche, streaming e Undo), Rock Builder (pareti/piattaforme), Water Builder (fondali/limiti) e House Builder (finestre). La scena conserva le composizioni; i dati centrali non vengono rigenerati. Implementazione, misure e limiti in [EXPANDED_LANDSCAPE.md](EXPANDED_LANDSCAPE.md).

È un campione artistico e funzionale: non chiude R03, W01.2, W01.3, T01.4 o il budget dell'intero mondo. Restano il confronto con il concept, la rifinitura dei cigli e i picchi di generazione. G01.4/S02 e B01–B03 conservano i criteri architettonici; A07 conserva il confronto R10/R13 aperto. Generazione globale da seed e confronto V01 restano rimandati.

Il primo circuito giocabile riusa borgo e guado e aggiunge una torre con incontro e ritorno nel bosco: [BORGO_EXPLORATION_CIRCUIT.md](BORGO_EXPLORATION_CIRCUIT.md). Checkpoint temporanei e misura del percorso sono disponibili; quest persistenti e scorciatoie condizionate restano future. Nessun cambiamento allo stato delle macrofasi.

## Punto di ripartenza

Campione chiesa aggiornato: navata 8,8 × 14,2 m, frontone collegato al tetto,
campanile 13,8 m e finitura in pietra riutilizzabile. La composizione locale
arretra il corpo di 1,8 m nel lotto per preservare l'imbocco stradale: non è
ancora una regola generica edificio–terreno. Il confronto visivo usa un profilo
di luce con occlusione e riempimento modificabili. G01.4/S02 e B01–B03 mantengono
i criteri aperti sopra indicati.

G01.3b.2b: diagnostica degli ingombri e verifica della rigenerazione nell'editor/Play. Sono disponibili edifici parametrici, torri/cortine, corte singola generata, editing protetto delle posizioni e validazione degli accessori. Non sono ancora disponibili la varietà delle città del concept o una generazione completa di paesaggio roccioso/idrologia/grotte.

La scena precedente conserva il rilievo procedurale e le piccole SphereMesh del WorldStream. La scena integrata usa invece un piano World a quote discrete, pareti continue del Rock Builder e alberi originali istanziati dal WorldStream. Il catalogo generale delle montagne resta da consolidare.


## Vincolo di terreno e leggibilità — aggiornamento utente

**Terreno prevalentemente piatto, altezze discrete.** Niente colline continue o città interamente in pendenza. Gli insediamenti occupano un piano principale o poche terrazze orizzontali. I cambi di quota usano rampe brevi, chiaramente leggibili, con raccordi localizzati. Il contrasto fra piani si legge tramite bordo/scarpata/parete, non con una pendenza lieve estesa.

Le montagne del concept si traducono soprattutto in masse e pareti rocciose ai bordi dello spazio giocabile, o separazioni fra piattaforme; non in un heightfield collinare percorribile ovunque. Una città può sorgere **accanto** a una parete rocciosa, con strade e case in piano. Aree di combattimento, piazze e accessi principali restano orizzontali. Verificare ogni salto di quota con la camera fissa prima di aumentarne il numero.

Il modello futuro del terreno deve esporre piattaforme con ID, quota e perimetro e collegamenti tramite rampa/scala; i generatori leggono questi dati. Non introdurre rumore altimetrico continuo nel layout giocabile come impostazione predefinita. Anche laghi e fiumi vanno progettati su questi piani: bacini a quota definita, tratti fluviali leggibili e raccordi fra quote localizzati. Dettaglio irregolare consentito sulle superfici rocciose, non come ondulazione generalizzata dei percorsi.

## Separazione dei sistemi

### Spunti dal video Bergfried — piano futuro

Il video locale analizzato il 20 settembre mostra tracciati murari lungo creste
irregolari (1:30–1:38), complessi con forti differenze fra masse principali e
accessorie (1:46–2:14) e anteprime che rendono visibili occupazione e conflitti
prima della posa (3:58–4:38). Fonte, tempi e limiti dell'osservazione sono nella
[roadmap architettonica](ARCHITECTURE_GENERATOR_ROADMAP.md#riferimento-aggiuntivo-bergfried-devlog-00--20-settembre-2026).

Per il nostro piano: mostrare insieme piattaforma disponibile, corpo proposto,
accessi e vicini interessati; far leggere il conflitto prima della conferma.
Le ricette G01.4/S02 devono differire anche in silhouette, aggregazione, parti
aperte e corti funzionali. Il tracciato delle mura riusa cortine e torri, e
strade/terreno restano nei loro builder: nessun secondo modello di authoring.
Non deduciamo dal filmato un solver generale delle intersezioni o un sistema
di rigenerazione protetta. Rimangono aperti i relativi criteri e resta valido
il vincolo del nostro mondo a quote discrete; questa analisi non introduce
nuova geometria, nuovi comandi o cambi di stato delle card.

### Contratto comune

Richiesta e seed → piano modificabile → validazione → realizzazione geometrica → scena editabile. Riutilizzare questo contratto, non un unico algoritmo universale.

- Terreno espone quota, pendenza, superfici e zone riservate.
- Rocce espongono ingombri solidi, pareti e varchi; nessuna conoscenza delle stanze.
- Acqua espone rive, profondità, direzione e attraversamenti.
- Insediamento legge queste informazioni e produce strade, piazze e richieste di edifici.
- Edifici producono volumi, aperture, interni e punti di accesso.
- Grotte collegano un ingresso nel rilievo a un proprio piano interno.

Ogni elemento generato necessita ID stabile, seed locale, override e lock. Gizmo solo dello strumento/elemento attivo. Rigenerare una roccia non deve ricalcolare le case; migliorare le stanze non deve riscrivere l'insediamento.

## Incrementi e criteri di uscita

| ID | Stato | Passo | Risultato verificabile |
|---|---|---|---|
| I01 | FATTO | Scena integrata con strumenti esistenti | Città murata, borgo, fiume/lago simulati, nuovi alberi e affioramenti; Play, panoramica, terreno della main e 12 case con InteriorPlan; acqua su patch locali. Passi e limiti in INTEGRATED_LANDSCAPE.md |
| I01.1 | FATTO | Primo intervento performance editor | Selezione terreno raggruppata e audit idle interni ridotto; misure e limiti in EDITOR_PERFORMANCE.md, Inspector mesh esplicita ancora da indagare |
| T01.1 | FATTO | Studio alberi Blender → Godot | Latifoglia e pino originali, alpha spray, normali chioma, palette e vento runtime; scena F6, sorgente e test in TREE_WORKFLOW.md |
| T01.1a | FATTO | Prova alberi con presentazione gameplay | Rig estratto dalla scena principale: stesso player, camera follow, viewport, luci e palette; movimento e collisioni verificati |
| T01.2 | TODO | Rifinitura visiva alberi | Confronto reference alla camera di gioco, tronco, ciuffi e ombre; approvazione prima di sostituire gli alberi esistenti |
| T01.2a | FATTO | Tronco e radici continui | Sezioni senza ribaltamenti, curva progressiva, colletto e radici nella stessa mesh; verificato in Blender e nella scena gameplay |
| T01.2b | TODO | Corteccia e raccordo al terreno | Venature leggere alla scala di gioco, variazione lungo il tronco, terra/muschio al piede; evitare texture rumorose e radici a stella troppo regolari |
| T01.2c | TODO | Palette e silhouette chioma | Ridurre zone grigie/sbiancate con le luci gameplay, ciuffi meno uniformi e pino più arioso; conservare la leggibilità dei volumi |
| T01.2d | TODO | Vento gerarchico | Rami e ciuffi con movimento coerente, tronco stabile, niente foglie che slittano sugli attacchi; valutazione dalla camera gameplay |
| T01.3 | TODO | Authoring alberi | Percorsi e guide editabili con rigenerazione locale e preservazione delle modifiche manuali |
| T01.4 | TODO | Foresta e budget | LOD, istanze, overdraw e ombre misurati; visibilità giocatore e integrazione catalogo world editor |
| G01.3b.2b | FATTO | Diagnostica ingombri e verifica editor/Play | Proposta comprensibile, Undo/Redo reali, passaggi percorribili |
| R01 | IN CORSO — prototipo disponibile | Generatore di singola roccia/affioramento | Seed, dimensioni, piani di frattura, stratificazione, spigolosità; 6 varianti con stesso linguaggio geometrico; collisione semplice |
| R02 | IN CORSO — R02.1–R02.3 verificati | Composizione di gruppi rocciosi | Path/area, direzione dominante degli strati, masse grandi/medie/piccole; variazione locale senza distruggere i pezzi spostati a mano |
| R03 | IN CORSO — R03.1–R03.2 verificati | Pareti e creste montuose | Pareti fra piattaforme piane, quote discrete, rampe brevi e passaggi riservati, assenza di compenetrazioni macroscopiche; LOD e budget misurati |
| R01.1 | FATTO | Roccia parametrica | Sei varianti, seed e collisione verificati |
| R02.1 | FATTO | Gruppi su guida | ID e modifiche manuali preservati |
| R02.2 | FATTO | Fascia libera | Diagnostica geometrica e gizmo contestuale |
| R02.3 | FATTO | Addensamenti e raccordi | Picchi condivisi, basi sovrapposte e 12 seed verificati |
| R03.1 | FATTO | Terrazza piana | Quota discreta, volume solido, salvataggio e Undo/Redo |
| R03.2 | FATTO | Accesso alla terrazza | Rampa, varco e salita/discesa del giocatore verificati |
| R03.3 | TODO | Ciglio e sagoma della terrazza | Raccordo terra/roccia, bordo meno rettangolare, piano e accesso preservati |
| W01 | IN CORSO — esempio W01.1 | Laghi editabili | Perimetro e quota dell'acqua, riva e bacino, esclusione edifici; superficie d'acqua inizialmente semplice |
| W01.1 | FATTO | Lago ed emissario di prova | Nodo tool con perimetro, flusso prescritto, vortice opzionale, fondale percorribile e onde locali; camera gameplay e test ingresso/uscita |
| W01.2 | TODO | Authoring lago e rive | Gizmo contestuali, Undo/Redo, diagnostica perimetro; preview fondale in editor e protezione terreno manuale |
| W01.3 | IN CORSO — campione con fondale | Qualità visiva acqua | Rive naturali, fondale, riflessi e caustiche meno ripetitive; riferimento alla camera gameplay |
| W01.3a | FATTO | Caustiche senza griglia regolare | Celle deformate e linee discontinue con intensità variabile; rendering gameplay verificato |
| W01.4 | FATTO | Lago mosso: prima versione visiva | Preset calmo/brezza/mosso, vento, superficie deformata e schiuma pulsante al passaggio delle creste verso riva |
| W01.4b | TODO | Risacca e impatti sulla costa | Fascia di terreno bagnata con avanzamento/ritiro, spruzzi delle onde sulle rocce e transizione visiva onde/fondale più accurata |
| W04 | IN CORSO — W04.1 disponibile | Interazioni acqua locali | Scie, spruzzi, ostacoli e oggetti galleggianti; simulazione limitata solo a comportamenti necessari |
| W04.1 | FATTO | Scia del personaggio e spruzzi | Scia orientata dalla velocità, schiuma, normali disturbate e 48 gocce riutilizzate; niente emissioni da fermo o sulla terra |
| W04.2 | FATTO | Prototipo A/B onde locali | Lago Play, F7 analitico/simulato, griglia CPU 64x64 a 30 Hz, impulsi, maschere, smorzamento e test di stabilita; costo solver misurato; contrasto creste/avvallamenti corretto per visibilita dopo F7, resa da affinare |
| W04.3 | TODO | Onde locali: GPU e qualita visiva | Profilare costo completo, backend GPU, lettura dalla camera isometrica, confronto riflessioni e caustiche derivate dal campo sul fondale |
| W04.4 | FATTO | Trasporto onde nel campo artistico | Campo precalcolato condiviso solver/shader, guida e influenza rocce, rebake su edit, test deriva firmata e stabilita; nessuna conservazione di portata |
| W04.5 | TODO | Controllo artistico e continuita del flow | Perturbazioni locali con media controllata, bake persistente, maschere raffinate, continuita tra patch e riduzione dissipazione |
| W02 | IN CORSO — W02.1 disponibile | Fiumi editabili | Spline, larghezza/profondità, profilo discendente e confluenze; raccordo alle quote dei laghi; niente flussi in salita |
| W02.1 | FATTO | Fiume curvo con rocce | Path3D e larghezze, corrente indipendente dall'asse X, rocce del builder che deviano il campo e producono schiuma; scena gameplay e frecce debug |
| W02.2 | TODO | Robustezza rive e raccordi | Diagnostica curve strette/incroci, vincolo di non attraversare le sponde, quote discrete e confluenze; fondale aggiornato in editor |
| W03 | TODO | Attraversamenti e rive | Ponti, guadi, approdi, passaggi e accessi alle sponde; terreno/rocce/strade leggono gli stessi vincoli |
| C01 | TODO | Ingressi di grotta | Apertura reale nel blocco roccioso, soglia percorribile, collisione coerente e leggibilità alla camera fissa |
| C02 | TODO | Piano di grotta | Stanze/cunicoli con anelli e diramazioni, quote e collegamenti; editing manuale separato dall'involucro esterno |
| G01.4 | IN CORSO — ricette locali verificate | Catalogo architettonico | Sei ruoli, BuildingRequest opzionale, persistenza/edit/UndoRedo e dodici case di prova verificati; integrazione planner e famiglie sostituibili ancora aperte; BUILDING_RECIPES.md |
| G01.5 | RIMANDATO | Varietà compositiva del castello | Recinti segmentati, più torri/corpi, corti e gerarchie differenti; preservazione manuale |
| S01 | RIMANDATO | Composizione urbana organica | Strade principali e secondarie, piazze, porte, edifici gerarchizzati, addensamenti e vuoti; insediamenti su piani/terrazze, collegamenti ai vincoli del paesaggio |
| S02 | TODO | Edifici urbani più articolati | Estendere le ricette oltre le dodici case di prova: volumi aggregati, tetti collegati, facciate/accessori e interni coerenti; varietà strutturale verificata, non solo ruoli o colori |
| V01 | RIMANDATO | Confronto dei quattro castelli | Quattro richieste/seed tramite tool, scene editabili e stessa camera; almeno due organizzazioni strutturali distinte |
| V02 | TODO | Vertical slice città–villaggio–POI | Sul circuito esistente: assegnazione e conclusione deterministiche, incontro, conseguenza/ricompensa e scorciatoia leggibile; salvataggio/riapertura senza duplicazioni, morte e checkpoint; playtest di orientamento e misure CPU/GPU durante il percorso. Prova temporanea disponibile, ciclo completo non implementato |

## Come ottenere le rocce del concept

La qualità nasce dalle forme: volumi principali spigolosi, tagli orientati, strati con una direzione comune, sporgenze e fessure fra masse. Un seed può variare fratture, proporzioni e inclinazioni entro una famiglia; rumore uniforme su una sfera produce soprattutto un masso irregolare. R01 costruirà una grammatica geometrica piccola e controllabile; R02 la userà per comporre affioramenti senza ripetizioni evidenti. Il materiale attuale resta il riferimento del gioco: niente rincorsa al rendering del concept.

## Cosa manca alla città

La città illustrata mescola una fortezza dominante, edifici subordinati, corti, vie irregolari ma connesse e una relazione con il pendio. Il compositore del castello ha soprattutto una corte singola e due corpi interni. La scena integrata aggiunge edifici collocati e variati localmente; il catalogo di ricette introduce i ruoli, ma non risolve aggregazione urbana, sagome/recinti differenti e collocazione automatica su piani e terrazze. Per questo non dichiariamo pronta la varietà delle quattro città.

## Ordine pratico

Completare e verificare l'incremento locale delle ricette nella scena integrata. La sequenza generale resta: confronto A07 con R10/R13, ultimo criterio aperto dell'audit, prima di B01.1; raccordi e urbanistica nei rispettivi step, senza fondere i generatori. R03.3 resta il prossimo incremento del ramo terrazze quando verrà ripreso; le zone sopraelevate del concept non ne sostituiscono tutti i criteri. L'idrologia stabile precede i ponti e il posizionamento definitivo delle città; C01 precede gli interni delle grotte. V01 rimane una consegna futura esplicita, attualmente rimandata.


## R01.1 — Roccia parametrica disponibile

Comando **Progetto → Strumenti → Crea roccia parametrica**, oppure nodo personalizzato ProceduralRock. Nell'Inspector: Rock Seed, Dimensions, Fracture, Strata, Strata Dip, Lean, Stone Color e collisione opzionale. La posizione del nodo resta manuale; cambiare seed rigenera soltanto la sua geometria. La creazione usa Undo/Redo dell'editor.

Mesh unica chiusa: contorno angolare irregolare, rastremazione, cima inclinata e piccoli arretramenti degli strati, interrotti su alcune facce. Il materiale deriva dalla pietra attuale del gioco. Un corpo StaticBody con forma convessa raccoglie l'ingombro, senza riprodurre ogni fessura. Il generatore non sposta il terreno e non crea colline. Una roccia è il primo componente per le future composizioni R02, non ancora una parete rocciosa completa.

Campionario: `scenes/dev/rock_generator_examples.tscn`, sei nodi editabili con proporzioni/seed diversi. Screenshot reale Godot `captures/balcony_attachment/rock_generator_examples.png`. Script di rigenerazione del campionario: tools/preview_rock_generator.gd.

Test tools/check_rock_generator.gd: 12 seed, determinismo dei vertici, triangoli non degeneri, una superficie e massimo 400 triangoli nei parametri provati, raycast fisico con collisione attiva/disattivata, round-trip PackedScene. Nessun benchmark su intere montagne; LOD e gruppi MultiMesh restano R02/R03. La resa è ancora un prototipo di forme: non dichiara raggiunta la varietà del concept.

Prossimo incremento R02.1: comporre poche masse grandi/medie/piccole lungo una guida, con orientamento degli strati comune e seed locali, lasciando i pezzi editabili. Conservare una fascia piana libera davanti alla parete.


## R02.1 — Gruppi rocciosi lungo una guida

Comandi **Progetto → Strumenti → Crea gruppo roccioso su guida** e **Rigenera gruppo roccioso selezionato**. Il gruppo è un Path3D: selezionalo e modifica la Curve3D con gli strumenti di percorso di Godot. Regola Formation Seed, Spacing, Wall Height, Strata e Strata Dip nell'Inspector, poi rigenera. Le modifiche alla guida non ricostruiscono il gruppo automaticamente.

Per ogni stazione della guida vengono proposte masse grandi, medie e piccole, con seed locali e orientamento geologico coerente. Le nuove rocce si dispongono a sinistra rispetto al verso del percorso; invertire il percorso inverte il lato. La distanza dal fronte è prudenziale, ma non è ancora una prova globale di assenza di ingombri su curve strette o autointersecanti. Il terreno non viene modificato; la guida deve restare a quota locale zero.

Ogni roccia è un nodo figlio con ID e baseline. Trasformazioni, dimensioni o parametri modificati a mano e nodi con figli manuali vengono preservati. Le rocce eliminate manualmente non vengono ricreate a parità di stazioni. Gli ID sono indice di stazione e taglia: grandi cambiamenti alla topologia/lunghezza della guida non costituiscono ancora un sistema di identità spaziale generale. Gli elementi manuali oltre una guida accorciata restano presenti. I campi generation_ids/formation_* sono dati di authoring, non controlli da modificare durante l'uso normale.

Creazione e rigenerazione hanno azioni Undo/Redo distinte. La rigenerazione conserva i nodi presenti e aggiorna quelli automatici; quelli rimossi perché fuori dalla guida vengono ricreati se si annulla. Non elimina figli manuali delle rocce preservate. Non introduce ancora batching/LOD; limite 80 stazioni, cioè al massimo 240 rocce nuove per gruppo.

Esempio editabile: scenes/dev/rock_formation_example.tscn. Cattura Godot: captures/balcony_attachment/rock_formation_example.png. Test check_rock_formation: determinismo, riconoscimento automatico iniziale, spostamento e figlio manuali, cancellazioni rispettate, Undo/Redo, PackedScene e rifiuto delle guide non piane. La creazione nel menu è verificata sintatticamente; non è un benchmark né la prova interattiva completa del gizmo Path3D.

Prossimo R02.2: ridurre l'effetto di fila regolare, raccordare meglio le masse ed evidenziare il lato libero/diagnosticare le curve problematiche prima delle pareti R03.


## R02.2 — Fascia libera verificata e variazione delle masse

Le stazioni hanno ora uno scostamento deterministico lungo la guida; le masse medie/piccole variano anche nelle proporzioni. Gli estremi restano ancorati. ID, baseline, modifiche manuali e cancellazioni mantengono il comportamento R02.1. La disposizione resta una composizione a tre taglie: non è ancora una parete continua, né un algoritmo geologico completo.

Prima di applicare la proposta si proietta l'inviluppo convesso della geometria di ciascuna roccia sul piano locale XZ. L'ingombro viene confrontato con una fascia di 2 metri sul lato libero di ogni segmento della guida campionata. Questo sostituisce la sola distanza prudenziale R02.1. Se una roccia, anche manuale, invade la fascia, il comando mostra il suo ID e non applica nessuna modifica. La verifica è conservativa: non sfrutta cavità sotto le rocce; non verifica navigabilità del mondo o oggetti estranei al gruppo. Le intersezioni fra rocce sono permesse per comporre masse.

Selezionando il Path3D, il gizmo verde indica la fascia libera. Non compare sugli altri gruppi né in gioco. La verifica geometrica avviene al comando Rigenera, non durante il trascinamento. La fascia è espressa in unità locali: mantenere scala del gruppo a 1 per avere 2 metri nel mondo.

Verifiche: 12 seed sulla guida dolce; guida incrociata rilevata; intrusione manuale segnalata senza spostamento; regressioni determinismo, cancellazioni, Undo/Redo e salvataggio superate. Parser Godot di gizmo/plugin superato; screenshot GPU dell'esempio rigenerato ispezionato. L'interazione del nuovo gizmo nell'editor non è stata verificata manualmente.

Prossimo R02.3: raccordi fra masse e alternanza di gruppi/addensamenti per superare ulteriormente l'effetto fila, poi R03 con pareti e terrazze discrete. La varietà architetturale G01.4 e il confronto di quattro castelli V01 restano nella pipeline.


## R02.3 — Addensamenti e raccordi bassi

Le stazioni sono suddivise dal seed in gruppi di 2–4 elementi. Ogni gruppo comprime le distanze e condivide un profilo di altezza con picco e spalle più basse. Gli estremi della guida restano ancorati. Le masse principali sono più larghe; la taglia media diventa una base larga e bassa, parzialmente sovrapposta ai piedi delle rocce. Il distacco dalla guida dipende dalla profondità, poi viene verificato sulla geometria completa come in R02.2.

La composizione cambia con il seed nelle posizioni e nelle dimensioni, oltre che nella geometria dei singoli pezzi. Non aggiunge nodi o nuove collisioni rispetto alle tre taglie esistenti. Mantiene ID e baseline: le rocce già modificate a mano non adottano automaticamente le nuove proporzioni. I raccordi sono sovrapposizioni di mesh, non una fusione booleana o una parete impermeabile garantita; restano possibili discontinuità sulle guide difficili.

Verificati 12 seed con fascia libera, variazione della composizione fra seed, ordine delle stazioni e ancoraggio degli estremi per 2/3/4/7/80 stazioni. Superate anche le regressioni di modifica manuale, cancellazione, Undo/Redo e salvataggio. Esempio e screenshot GPU rigenerati con tools/preview_rock_formation.gd; risultato ispezionato.

Prossimo R03.1: introdurre una parete di contenimento per una terrazza a quota discreta, con superficie superiore piana. Prima una piccola scena di prova; rampe e collegamenti controllati in un incremento successivo. G01.4 e V01 rimangono aperti.


## R03.1 — Terrazza rettangolare a quota discreta

Comandi Progetto → Strumenti → **Crea terrazza rocciosa** e **Rigenera terrazza selezionata**. Selezionare il nodo Terrazza, impostare Footprint (6–60 m per lato), Elevation (quota intera 1–6 m) e Terrace Seed nell'Inspector, poi rigenerare. I parametri descrivono la prossima generazione: la piattaforma attiva conserva separatamente lo stato applicato, anche dopo salvataggio. Mantenere scala unitaria e rotazione attorno al solo asse Y per quote piane in metri.

La piattaforma ha nucleo rettangolare pieno con collisione BoxShape3D e piano superiore orizzontale; non deforma il terreno esistente. Il bordo usa il generatore di rocce esistente e il suo sistema di ID/baseline, con rocce figlie sotto BordoRoccioso, modificabili singolarmente. Spostamenti, parametri, figli manuali e cancellazioni sono rispettati. Il comando di rigenerazione dei gruppi rocciosi riconosce questo bordo e rimanda alla terrazza. Modifiche importanti alle dimensioni possono lasciare pezzi manuali distanti dal nuovo bordo: non vengono riposizionati automaticamente.

Creazione e rigenerazione usano azioni Undo/Redo distinte. Il nucleo interno si ricostruisce dallo stato salvato; le rocce sono nodi posseduti dalla scena. La superficie ha per ora colore uniforme e bordo superiore geometrico regolare: raccordo estetico terra/roccia, sagome libere, navigazione e collegamento con il sistema di terreno restano da fare. Non ci sono ancora rampe o accessi: il piano superiore è solido, ma non raggiungibile dal basso senza un collegamento.

Esempio: scenes/dev/rock_terrace_example.tscn. Render Godot: captures/balcony_attachment/rock_terrace_example.png, rigenerabile con tools/preview_rock_terrace.gd. Test tools/check_rock_terrace.gd: determinismo, raycast sul piano a +3 m e sul fianco, modifiche e figli manuali, cancellazione, Undo/Redo della quota, PackedScene e rigetto dei parametri invalidi. Parser del plugin verificato. Non è stata eseguita una prova interattiva del menu né una passeggiata con il personaggio.

Prossimo R03.2: un accesso tramite rampa corta con pendenza controllata e varco nel bordo, verificato col giocatore. Poi raccordo visivo del ciglio e maggiore libertà della sagoma; evitare che il prototipo rettangolare diventi il vincolo del generatore.


## R03.2 — Rampa con varco e prova giocabile

La terrazza offre Ramp Enabled, Ramp Width e Ramp Length. In questa versione l'accesso è centrato sul lato locale +Z; ruotare l'intera terrazza per orientarlo. La lunghezza deve essere almeno due volte la quota (massimo 26.6°), larghezza minima 2 m. Rigenerare dopo aver modificato i parametri. I salvataggi precedenti restano senza rampa fino alla rigenerazione.

La rampa è un cuneo solido con superficie inclinata e collisione convessa, collegato alla piattaforma. La proposta esclude le rocce automatiche che invadono il corridoio di accesso; disabilitando la rampa le ripristina. Una roccia manuale nel varco produce un errore senza alterare la scena. La verifica riguarda il bordo della terrazza, non eventuali oggetti estranei aggiunti alla scena. Niente parapetti, navigazione AI o accessi multipli in questo incremento.

Aprire scenes/dev/rock_terrace_playable.tscn e usare F6/WASD per provare l'esempio salvato. Usa player3 e il controller reale con camera isometrica fissa, senza teletrasporto sulla rampa. Test check_rock_terrace_play: arresto a metà rampa, salita sul piano e ritorno al terreno; quote misurate rispetto alla posizione del corpo a riposo. Test check_rock_terrace: varco/ripristino, rampa troppo ripida, ostruzione manuale, collisioni, salvataggio e Undo/Redo. Screenshot reale rock_terrace_ramp_play.png. Il movimento è stato verificato tramite input automatici; non è una sessione manuale estesa né un benchmark.

Prossimo R03.3: raccordare il ciglio e la sagoma mantenendo piano e accesso percorribili. R03 complessivo resta IN CORSO: mancano ancora integrazione terreno, LOD e misure di budget.

## Gestione del lavoro

La board docs/GENERATOR_KANBAN.md è generata dalle tabelle delle due roadmap. Aggiornare prima la tabella pertinente e le note, quindi eseguire `python tools/update_generator_board.py`: aggiorna anche le righe ambientali nella Sequenza di implementazione della roadmap architettonica. Non segnare FATTO una macrofase perché è concluso un suo prototipo.
