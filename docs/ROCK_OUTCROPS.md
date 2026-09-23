# Affioramenti modificabili in Godot

Prima versione: area concava con buchi, percorso a punti e volume rettangolare. Plugin **Rock Outcrop Editor**, già abilitato. Le formazioni e le terrazze precedenti restano disponibili e non sono migrate.

## Prova

Apri `scenes/dev/rock_outcrop_playground.tscn`: contiene un’area con foro, un percorso e un volume. Seleziona un nodo Affioramento; nell’Inspector regola Height, Walkable, Rock Seed, Rock Spacing e colori.

Per crearne uno: **Progetto → Strumenti → Crea affioramento · area / percorso / volume**, oppure aggiungi il tipo `RockOutcrop`.

- **Disegna contorno** nella barra 3D: clicca per aggiungere vertici oppure trascina sul terreno. **Invio** o **Applica disegno** conferma; **Backspace** elimina l’ultimo punto; **Esc / Annulla** abbandona il tratto. Ridisegnare il contorno elimina i suoi vecchi buchi, con undo unico.
- **Disegna buco** aggiunge un contorno interno. Più buchi sono consentiti; contorni che si incrociano, si toccano o escono dall’area sono rifiutati, conservando il risultato precedente.
- Le maniglie arancioni modificano i punti e l’altezza; sul percorso c’è anche la larghezza. Sul volume ci sono larghezza e profondità. Trasformazione e rotazione del nodo usano il gizmo standard di Godot.
- **Edit Rocks** mostra le maniglie per spostare singole rocce orizzontalmente. Le correzioni sono salvate per ID spaziale e conservate quando la roccia torna nell’area. Un cambio di seed cambia la forma, mantenendo tali correzioni.
- **Walkable** crea una sommità piana con collisione e dettagli sul bordo. Disattivandolo, la superficie viene riempita di rocce e le pareti di esclusione arrivano 8 metri sopra Height, per impedire al personaggio di attraversare l’area saltando. I fori restano aperti. Nessuna navigazione AI viene precalcolata.

## Geometria e prestazioni

La superficie usa una decomposizione in trapezi che conserva il contorno e i fori, senza griglia voxel. Le rocce usano un generatore dedicato che interseca piani di frattura: grandi facce coerenti, spigoli poco smussati, un blocco dominante e una spalla a quota inferiore. La composizione dispone poche masse principali in file di quota diversa, oppure lungo il percorso; ciottoli piccoli e radi completano solo il piede. Sui rilievi percorribili i massi seguono i bordi e la terra lascia un ciglio di pietra; sui gruppi interdetti il nucleo non è visibile. La sagoma esterna ammette una fascia rocciosa sporgente, mentre i buchi restano protetti. Non vengono importati asset né eseguiti nodi dal file Blender di riferimento.

Durante il trascinamento si aggiornano superficie e collisione, conservando il dettaglio precedente fino al rilascio. Le rocce hanno seed per cella e cache delle mesh: modificare l’altezza riutilizza le mesh esistenti. Il nucleo viene ancora ricostruito; questa non è una soluzione universale per affioramenti arbitrariamente grandi. Limiti: 256 punti per contorno e 16384 celle candidate per nodo. Dividere le aree grandi.

Geometria generata e cache sono interne, non salvate nella scena; si salvano parametri, contorni e correzioni. Niente cache su disco o dipendenza da Blender. Collisioni statiche triangolari per nucleo e buchi; inviluppi convessi separati per blocco e gradone delle nuove rocce, anche sul bordo percorribile. I piccoli detriti sono decorativi.

## Limiti della prima versione

Il disegno si proietta sul terreno disponibile; il primo punto definisce la quota di base del nuovo contorno. La sommità resta piana: non è uno sculpt del terreno sottostante, non segue automaticamente successivi cambi del terreno e non aggiunge rampe. La base penetra solo 0,5 metri sotto la quota del nodo: su pendii forti occorre regolare il posizionamento o dividere l’area. Le aree sovrapposte non vengono fuse. Il percorso è una polilinea arrotondata in larghezza, senza tangenti Bézier. Il volume è un ingombro rettangolare parametrico. Le correzioni manuali delle rocce possono modificare l’ingombro visivo previsto dal contorno.

Non è una riproduzione del remesh di Blender né del sistema di Tiny Glade. Il riferimento visivo va ulteriormente raffinato; questa versione rende già provabile il flusso di authoring in Godot.

## Verifiche

- `--headless --path . --script tools/check_rock_outcrop.gd`: area esatta con foro, normali, raggi sulle collisioni esterne/interne, ID delle mesh, annullamento, undo/redo, serializzazione e riapertura, area concava, input non valido, percorso, volume e barriera interdetta. Stampa mediana/p95 di 20 modifiche ad altezze nuove sul volume 7×9 m.
- `--headless --path . --editor scenes/dev/rock_outcrop_playground.tscn -- --outcrop-editor-test`: azioni del plugin con EditorUndoRedoManager reale, disegno e buchi, rigetto del buco esterno, annullamento.
- `tools/preview_rock_outcrop.gd` ricrea la scena dimostrativa e, con renderer grafico, salva `.godot/rock_outcrop_preview.png`.

## Altezza e scala

La scala verticale del nodo e dei genitori cambia la composizione: all’aumentare dell’altezza vengono usate masse continue più larghe e profonde, in numero minore. Non vengono impilati corsi regolari di blocchi. Ogni massa conserva una frattura inclinata dominante e una spalla asimmetrica. Un’impronta stretta molto alta rimane necessariamente un rilievo stretto: per cambiare la sagoma globale vanno modificati anche contorno o larghezza.

La trasformazione standard di Godot rimane intatta; undo/redo, scala uniforme e ripristino della scala precedente sono conservati. I test verificano la ricomposizione con scala verticale locale e del genitore e il riutilizzo delle mesh. `tools/preview_rock_outcrop.gd -- --scale-study` confronta altezza 3, scala Y×4 e altezza 12.

## Direzione conservata: ponti rocciosi

Richiesta dell’utente: conservare l’esperimento a lastre continue lungo una curva come possibile base per **ponti rocciosi**. Riferimento: screenshot `codex-clipboard-26ddfa5e-ecc8-4af5-9a55-de1f5462bb36.png` del 23 settembre 2026. Il modulo `fracture_field.gd` è il prototipo relativo: non sostituirlo o cancellarlo nel lavoro sugli affioramenti. Non è ancora un ponte: mancano intradosso sospeso, spessore indipendente dalla quota, appoggi, passaggio sottostante e verifica del piano percorribile.

Per gli affioramenti seguire lo studio in `ROCK_GEOMETRY_NODES_STUDY.md`; il prototipo a lastre non risolve la forma delle rocce di riferimento.

## Modalità separate: Costruita e Naturale

`Formation Style` distingue **Costruita** (predefinita, conserva i nodi esistenti) e **Naturale**. Le nuove voci Progetto → Strumenti → Crea roccia naturale creano nodi Naturale con sommità non percorribile. Area, percorso e volume restano disponibili in entrambe le modalità.

La modalità naturale costruisce poche masse radicate alla base, con grandi facce e rotture asimmetriche. Nei rilievi non percorribili, i centri sono distribuiti senza griglia nell’impronta, con distanza minima; altezza e inclinazione seguono una cresta comune. Sulle aree percorribili le masse seguono il perimetro, con spalle subordinate a quote diverse. Non viene più applicato un rivestimento uniforme di piccoli blocchi su tutte le superfici. Il nucleo dei rilievi non percorribili rimane ribassato sotto le masse, con collisione corrispondente.

È una composizione di solidi sovrapposti, non una replica dei Geometry Nodes o del Voxel Remesh di Blender. La resa è ancora da validare artisticamente. Il campionamento a superficie dello studio precedente è stato sostituito per correggere la gerarchia delle forme. Gli ID dipendono dall’ordine deterministico delle masse: modificare la sagoma può riassegnare le correzioni manuali. Le 12 varianti sorgente restano condivise nella cache del nodo.

`tools/check_natural_formation.gd` verifica determinismo, masse radicate e ampie, ricomposizione all’allargamento, riuso delle mesh, foro fisico, sommità calpestabile e serializzazione. `tools/preview_rock_outcrop.gd -- --natural-study` produce una prova senza riscrivere la scena delle costruzioni.

### Sommità naturale calpestabile

Con `formation_style = Naturale` e `walkable = true`, la sommità resta alla quota `height`, con copertura di terreno e aperture conservate. Il dettaglio viene distribuito sui fianchi ed è contenuto sotto la quota del piano superiore, anche dopo gli offset manuali. La preview `--natural-study` conserva il buco e la calpestabilità dell’area a sinistra. Il test naturale verifica tramite raycast la quota del piano e l’apertura anche con il dettaglio attivo.

### Shape e livelli di dettaglio

Ingombro e altezza definiscono la forma di base. Nella sezione **Distribuzione naturale**, `Natural Rock Size` controlla la taglia orizzontale in metri, `Natural Min Spacing` la distanza fra i centri (0: proporzionale alla taglia), `Natural Density` la frazione di candidati mantenuti e `Natural Max Rocks` il limite delle masse principali (0: automatico). Il limite non è un conteggio esatto garantito: spazio e fori possono ridurre il risultato. Allungare il nodo crea spazio per altre masse, senza ingrandire automaticamente le rocce.

**Rocce medie** e **Rocce piccole** hanno taglia e densità indipendenti. Densità 0 spegne il livello. `Small Surface Ratio` distribuisce una parte dei piccoli dettagli sulle superfici delle masse principali; il resto forma gruppi al piede. Le sommità percorribili rimangono libere. Cambiare il dettaglio non ricampiona le masse principali. Le rocce al piede usano la quota locale di base, senza proiezione automatica su terreno irregolare. Non c’è fusione delle mesh sovrapposte.

Nel test 7×13 → 7×26 le masse principali passano da 8 a 16, anche usando la scala Z, mantenendo la taglia orizzontale. Densità 50% conserva 7 dei 16 candidati dello stesso seed senza spostarli. Nessuna modalità di compatibilità con le prove precedenti.

### Scena giocabile di prova

Aprire `scenes/dev/rock_parameter_study.tscn` e premere F6. Riutilizza `gameplay_preview_rig.tscn`: personaggio, camera e comandi del gioco, non una camera libera. Il terreno ha collisione. Nove esempi modificabili nell’Inspector: montagna, catena allungata, parete alta, campo di piccole rocce, affioramento medio, parete bassa, pianoro con foro, dettagli sulle superfici, sole masse principali.

`tools/check_rock_parameter_study.gd` verifica che il personaggio poggi sul terreno, si muova e abbia la camera del gioco. Il generatore `tools/build_rock_parameter_study.gd` ricrea la scena: non eseguirlo dopo avervi fatto modifiche da conservare.

La variante molto schiacciata resta un riferimento per un futuro terreno roccioso; non è ancora un preset distinto.
