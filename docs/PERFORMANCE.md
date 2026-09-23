# Editor, caricamento e streaming — 23 settembre 2026

> **Ambito:** editor, generazione e streaming. Le misure dei campioni restano legate alla revisione provata; carica/ragdoll e DOF recenti richiedono un nuovo percorso di benchmark. Vedere [PROJECT_STATUS](PROJECT_STATUS.md) e V02 nella roadmap mondo.

## Utilizzo

- In `ArtStudyLayers`, **Preview Quality → Lavoro** è il valore predefinito:
  erba su 3×3 chunk al 25% della densità, centrata su `art_preview_center`.
  **Completa** ripristina la densità normale. Il cambio non ricrea materiali,
  alberi o geometria della scena. In Play la qualità è sempre completa.
- I gizmo delle case e dei volumi mostrano una sagoma durante il trascinamento.
  Al rilascio il tetto dettagliato e i tagli fra volumi vengono elaborati a
  piccoli passi. Una modifica successiva invalida il risultato precedente.
  Undo/redo e annullamento continuano a modificare i dati originali.
- Le modifiche dall'Inspector vengono accorpate per 200 ms dall'ultima richiesta.
  Le anteprime e i risultati intermedi sono nodi interni senza owner e non
  vengono salvati nella scena.

## Implementazione

Lo streaming usa un budget CPU di 2.000 µs, speso in un aggiornamento fisico al
massimo per fotogramma anche quando la fisica recupera tick arretrati. Il singolo
chunk può sospendersi fra campionamenti e piccoli gruppi di trasformazioni,
conservando stato del generatore casuale e ordine dei campioni. I raycast
rimangono sul thread fisico principale. Anche gli upload e la rimozione dei
nodi sono distribuiti; una singola chiamata del motore non è interrompibile.

In Play sono visibili i consueti 5×5 chunk; un anello aggiuntivo viene preparato
ma resta nascosto. La cache conserva al massimo 81 chunk completati e riusa
quelli vicini. I chunk obsoleti vengono smontati un nodo per aggiornamento.
Ricostruzioni, nuovi collider statici, modifiche delle forme e spostamenti dei
collider invalidano la cache; l'audit delle trasformazioni avviene ogni 250 ms.
La chiusura della scena annulla esplicitamente il lavoro sospeso.

Tetti e maschera di copertura sono memorizzati sotto
`user://generation_cache_v1/`, in uno spazio distinto per progetto. Parametri,
dipendenze e hash delle sorgenti identificano i risultati. La maschera include
percorsi, pennellate, trasformazioni e geometria delle superfici sopraelevate;
le sole impostazioni di illuminazione non ne cambiano la chiave. Una cache
mancante o incompatibile viene ricostruita. I tetti restituiti ai builder sono
copie: tagli e materiali locali non possono modificare il risultato condiviso.

## Misure del primo intervento

Godot 4.6.3, Windows, stessa macchina; rendering D3D12 Forward+ su RTX 3070.
Le misure CPU di avvio terminano al ritorno dell'inizializzazione della scena,
prima della presentazione del primo fotogramma GPU.

| Misura CPU headless | Prima | Dopo |
| --- | ---: | ---: |
| Preparazione scena (`ready`) | 19.563 ms | 16.641 ms, cache fredda |
| Preparazione scena (`ready`) | 19.563 ms | 13.725 ms, cache calda |
| Lettura risorsa scena | 862 ms | 787–790 ms |
| Streaming erba, p95 | 33,54 ms | circa 2,02 ms |
| Streaming erba, massimo nel primo confronto | 51,16 ms | 2,24 ms |

Il test dell'editor con la scena integrata ha misurato 38,65 ms al p95 e
39,60 ms al massimo durante 60 aggiornamenti di trascinamento, senza alcun
rebuild dettagliato durante il gesto. Sono tempi di fotogramma dell'editor
headless, non una misura della GPU della viewport.

La prova renderizzata distingue i picchi GPU dai tempi del generatore: sono
stati osservati picchi GPU nei primissimi fotogrammi dopo l'avvio, quindi il
budget CPU dell'erba non è una garanzia sul tempo totale di ogni fotogramma.
Nella prova finale: CPU erba p95 2,02 ms, massimo 5,01 ms all'avvio; GPU mediana
9,78 ms, p95 17,62 ms, massimo 184,45 ms al secondo fotogramma campionato.
I superamenti GPU di 33 ms rilevati sono tutti nella prima posizione, nei
fotogrammi iniziali; non sono comparsi nelle successive posizioni del percorso.
Il log `PERF_SPIKE` identifica posizione e fotogramma per distinguere avvio e
attraversamento. I teletrasporti di debug fanno comparire l'erba progressivamente.

## Verifiche ripetibili

Eseguire con l'eseguibile Godot del progetto, `--headless --path . --script`:

- `res://tools/check_incremental_generation.gd`: trascinamento senza rebuild,
  annullamento, invalidazione di lavori precedenti, undo/redo, volumi collegati,
  esclusione delle anteprime dal salvataggio e cache dei tetti.
- `res://tools/check_grass_streaming.gd`: riuso, limite cache, anello nascosto,
  modalità Lavoro, cancellazione, invalidazione del terreno e determinismo.
- `res://tools/check_house_builder.gd`, `check_house_plan.gd`,
  `check_house_generation.gd` e `check_integrated_landscape.gd`: geometria,
  aperture, roundtrip, interni, porte, acqua e percorsi della scena integrata.

Il confronto esatto con gli algoritmi precedenti è stato eseguito estraendo
le versioni Git iniziali in `.godot/reference_roof.gd` e
`.godot/reference_grass.gd`. I due nuovi test le confrontano quando presenti:
array dei tetti e trasformazioni/colori dell'erba coincidono.

`check_editor_performance.gd` richiede anche `--editor`: apre la scena e prova
il trascinamento senza salvarla. L'uscita forzata del test editor può stampare
avvisi di risorse del motore non rilasciate; verificare separatamente gli errori
degli script e il contatore `failures`.

`profile_scene_streaming.gd` registra avvio, streaming e rebuild. Aggiungere
`-- --render-profile` senza `--headless` per i tempi GPU. Per misurare avvio
freddo/caldo usare due esecuzioni consecutive con
`-- --startup-only --generation-cache-test=<identificatore-nuovo>`:
lo stesso identificatore riusa la cache senza toccare quella normale.

## Secondo intervento: costo della finalizzazione

La prima misura dell'editor copriva il trascinamento, non il tempo dal rilascio
alla geometria definitiva. Il nuovo benchmark isola la **cappella realmente
salvata nella scena integrata**, conservandone volumi e dettagli; confronta anche
una casa semplice, un'ala legacy e una casa con volume agganciato.

Le modifiche di questa fase:

- `MeshJoin` conserva gli array indicizzati esterni ai tagli. Usa limiti
  conservativi dei gruppi e dei triangoli prima della sottrazione; mantiene
  ordine dei tagli, interpolazione degli attributi e filtro dei triangoli
  degeneri nelle zone elaborate.
- Il generatore del tetto conserva limiti e intervalli degli indici di ogni
  tegola. I tagli propagano questi gruppi; tangenti e indici vengono ricalcolati
  nei gruppi interessati. Le tegole intatte conservano i propri buffer.
  Per mesh generiche e superfici trasformate resta un fallback conservativo:
  sulle facce con UV degeneri trasformare semplicemente le tangenti produce
  un normal mapping diverso. Nessuna tegola o pietra è stata semplificata.
- Cache separate per singola parete di pietre (massimo 64), geometria originale,
  raccordi e tetto rifinito. Dimensioni, seme, distribuzione e piani di taglio
  determinano il riuso. I volumi con dipendenze invariate conservano i nodi
  generati; i tipi specializzati conservano fallback più prudenti.
- Colore e usura della muratura aggiornano le uniformi, senza rebuild. Le
  aperture conservano il tetto originale e il suo risultato già tagliato quando
  le dipendenze del tetto sono invariate.
- Il budget cooperativo dell'editor passa a **8 ms**, condiviso con i volumi.
  Un lavoro breve termina nella stessa chiamata. Restano operazioni native
  indivisibili, quindi questo budget **non è un tetto rigido** alla durata del
  fotogramma. L'erba mantiene il proprio budget di 2 ms.
- Scritture dei tetti accodate durante i tempi inattivi e sospese mentre una
  finalizzazione è attiva. I risultati superati, anche di un volume cancellato
  tramite il suo host, non entrano nelle cache delle fasi.

### Misure sulla stessa macchina

Godot 4.6.3 headless, limite 60 fps, processi di benchmark eseguiti da soli.
Prima: 3 campioni per fixture. Dopo: 20 dimensioni mai usate in un namespace
cache nuovo, poi gli stessi campioni in un secondo processo con cache su disco
calda. Incrementi piccoli mantengono validi i volumi della cappella; il benchmark
segnala un errore se un edit invalida un volume inizialmente valido.
I dati grezzi sono in `performance/edit-benchmark-2026-09-23.json`.

| Finalizzazione, ms | Prima, mediana | Dopo freddo mediana / p95 | Dopo caldo mediana / p95 |
| --- | ---: | ---: | ---: |
| Casa semplice | 617 | 100 / 100 | 17 / 20 |
| Ala legacy | 3.793 | 250 / 253 | 184 / 199 |
| Casa con volume | non misurata | 298 / 314 | 129 / 134 |
| Cappella integrata | 19.453 | 840 / 871 | 483 / 500 |

Per la cappella fredda: CPU mediana **539 ms**, attesa fra fotogrammi mediana
**302 ms**. Con cache del tetto calda: **296 ms CPU**, **189 ms di attesa**.
Le mediane delle componenti sono calcolate separatamente. Il calo della latenza
combina una riduzione del lavoro con l'aumento del budget; non va interpretato
come una riduzione CPU di 23 volte. Le aperture della cappella, con tetto e
distribuzione invariati: mediana **99 ms**, p95 **106 ms**, CPU mediana **63 ms**.
Le variazioni di colore/usura non incrementano il contatore dei rebuild.

**Il criterio 100 ms di mediana / 200 ms al p95 non è raggiunto per il
ridimensionamento completo della cappella.** Nei campioni freddi rimangono circa
250–270 ms di preparazione del tetto, circa 150–160 ms di tagli e circa 35 ms di
rivestimenti, oltre a collisioni e volume accessorio. La modalità progressiva
non viene usata come prova del raggiungimento del criterio. Queste misure non
includono GPU, composizione della viewport o i 200 ms di debounce dell'Inspector.

**Editor con l'intera scena attiva:** tre nuove dimensioni della cappella,
`check_editor_performance.gd --editor --max-fps 60`: finalizzazione mediana
**1.660 ms**, massimo **1.683 ms**. La misura comprende due fotogrammi dopo il
completamento del builder per gli aggiornamenti di presentazione e interni.
La CPU del builder resta circa 570 ms; l'attesa cresce con il lavoro complessivo
dell'editor. Trascinamento: p95 **43,46 ms**, massimo **46,19 ms**, nessun rebuild
dettagliato durante il gesto. Anche questa prova usa il renderer headless:
non è una misura GPU. Il test isolato della tabella non rappresenta quindi il
tempo totale percepito nell'editor.

Avvio CPU della scena integrata dopo questo intervento, una prova fredda/calda:
lettura risorsa **853 / 832 ms**, istanziazione **4,5 / 4,8 ms**, inizializzazione
`ready` **7.412 / 4.676 ms**. Sono tempi CPU prima del primo fotogramma presentato,
non una nuova misura del primo input o della GPU. Il flush dei file avviene dopo
il campionamento, per rendere ripetibile la prova calda.

### Verifiche e riproduzione

- `check_mesh_join_equivalence.gd` confronta il nuovo algoritmo con una copia
  congelata del precedente algoritmo di **questo progetto** in
  `tools/fixtures/mesh_join_reference.gd`. Confronta triangoli, normali, UV,
  UV2, colori e tangenti dei materiali che usano normal mapping, compresi tagli
  sovrapposti, rimozione completa e trasformazioni non uniformi.
- Confrontati anche i mesh di casa, ala e cappella salvati prima dell'intervento:
  nessun triangolo non degenere mancante o aggiunto; attributi entro tolleranza.
  Le tangenti della cappella differiscono meno di 0,00043 in norma. Non è stato
  rifatto in questa fase un confronto di screenshot o una misura GPU.
- `check_edit_dependencies.gd`: materiali senza rebuild, apertura senza
  rigenerare il tetto, volume invariato, invalidazione della distribuzione,
  salvataggio/riapertura e sospensione delle scritture durante gli edit.
- Passano i test di generazione incrementale, builder, generazione casa,
  pianta, volumi e loro passaggi, muratura, tetti curvi, ricette e relativi
  dettagli, tetti piani, porte sul tetto, torri poligonali, cortine e interni.
  Passano anche scena integrata, streaming dell'erba e i test del vero plugin
  editor per modifica/undo/redo e applicazione delle ricette.
- `check_roof_access.gd` fallisce su «Disabled access restores parapet
  collision». Riproduce lo stesso fallimento con house/volume/MeshJoin
  precedenti a questo intervento, caricati separatamente: è un problema
  preesistente, non risolto qui. Alcuni test headless/editor stampano avvisi
  del motore sulle risorse in uso all'uscita, dopo il proprio indicatore PASS.

Benchmark CPU (eseguire due volte, stesso identificatore nuovo):

```powershell
& $godot --headless --path . --max-fps 60 --script res://tools/bench_house_edits.gd -- --reps=20 --flush-cache --generation-cache-test=edit-nuovo-id
```

Aggiungere `--chapel`, `--edit=opening`, `--edit=roof` o `--counters` per isolare
un caso o stampare triangoli esaminati/tagliati e contatori per fase. `--step`
controlla l'incremento delle dimensioni. `--golden` salva riferimenti locali;
`--verify` richiede i riferimenti catturati prima della modifica e confronta le
mesh con nomi stabili (i mobili con nomi generati dal motore sono esclusi).
Per l'avvio usare `profile_scene_streaming.gd` con
`--startup-only --flush-cache --generation-cache-test=avvio-nuovo-id`.

`rpg-3d` non è stato modificato. Glade Kit è stato soltanto un riferimento
concettuale: nessun suo codice è stato copiato.
