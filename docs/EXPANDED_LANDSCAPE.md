# Paesaggio esteso e ciclo giorno–notte

## Stato della revisione — 23 settembre 2026

Campione funzionale nella scena integrata: inviluppo del terreno **304 × 288 m**, senza scalare edifici o personaggi. La resa non è ancora equivalente al concept: cigli, coste, grandi masse rocciose e densità dei boschi richiedono un ulteriore confronto artistico. Nessuna nuova generazione degli insediamenti; lavoro NPC sospeso.

## Responsabilità e dati

| Sistema | Dati e capacità riutilizzabili | Composizione locale |
|---|---|---|
| World | `world_plan`, `height_edits`, `reserved_zones`, `world_edits`, World dock/Undo, streaming e mappa con limiti espliciti | `integrated_world_plan.tres`, nucleo protetto 152 × 144 m |
| World terrain adapter | `addons/world_editor/integrated_ground.gd` estende il Terrain esistente; conserva la mesh centrale come sorgente, ricostruisce terreno e collisioni dai dati | Terreno 304 × 288, quote piane fuori dal nucleo |
| Rock Builder | ContinuousCliff con variazioni correlate, normali sfaccettate opzionali, superficie superiore e rampa dal medesimo campionatore | Quattro guide nord/ovest e due promontori costieri; vecchie guide conservate |
| Water Builder | Profilo di profondità salvabile; campo condiviso fra fondale, shader e barriera alle acque profonde; ritaglio fra corpi collegati | Lago ampliato verso est, mare a sud, fiume prolungato alla foce |
| Environment Builder | Controller e profilo giorno–notte | Durata 30 minuti, avvio 10:00, colori e intensità |
| House Builder | Identificazione delle superfici finestra per emissione serale | Edifici, interni e accessi conservati |
| Vegetazione e percorsi | WorldStream riusa alberi originali tramite MultiMesh; anime_grass e ExplorationRoute leggono lo stesso terreno | Foreste esterne, radure e raccordo periferico |

Non esiste un secondo generatore del paesaggio nel controller della scena. Il controller collega i sistemi; World mantiene i propri comandi di modifica e Undo. Il piano World supporta piattaforme discrete senza attivare il rumore altimetrico precedente. Le piattaforme di questo campione sono ancora le guide del Rock Builder: non è implementato un nuovo catalogo unificato delle piattaforme.

Il terreno generato e i chunk non sono dati autoriali. Il salvataggio editor conserva la mesh sorgente e i dati di World; la preview viene ricostruita. Non rilanciare `build_integrated_landscape.gd`. Sette alberi preesistenti raggiunti dal nuovo lago sono stati spostati alla riva; la posizione precedente resta nella metadata `pre_expansion_position`. Edifici e NPC non sono stati spostati.

## Uso

- **F6**: pannello ora, pausa orologio, −60×/−10×/1×/10×/60×, alba/mezzogiorno/tramonto/mezzanotte.
- **F7**: cambia stile conservando l'ora; il controller riapplica l'illuminazione all'ambiente attivo.
- **O**: panoramica aggiornata. **3**: riva accessibile del lago ampliato.
- `DayCycle/profile` nell'Inspector: durata reale, orario iniziale, alba/tramonto, colori ed energie.
- World dock: selezione/preview, distribuzione e modifiche locali sul terreno della scena integrata; nessun reset globale necessario.
- `Lago` e `Mare/depth_profile`: profondità massima, fascia bassa, tasche locali, limite guado. I profili assenti mantengono il comportamento precedente.

24 ore trascorrono in 1800 secondi; 05–21 corrisponde a circa 20 minuti di giorno. Il clock eredita la pausa del mondo, compresi i dialoghi. Il riavvolgimento cambia soltanto luce e orario, senza annullare eventi. Il ciclo non rigenera geometria. Le luci decorative sono attenuate di giorno e non aggiungono ombre locali multiple.

## Acqua e attraversamenti

Il fondale geometrico usa lo stesso profilo analitico campionato nella texture di profondità. La soglia guado genera una parete di collisione verticale, senza pavimento invisibile. Fondale basso, assorbimento, caustiche limitate alla riva, rifrazione leggera e riflessi variano con profondità e illuminazione. Il lago viene ritagliato al raccordo con il fiume; la foce incontra il mare. Il mare visivo prosegue oltre il terreno per evitare un taglio nell'inquadratura.

La simulazione resta locale al giocatore. Non sono inclusi nuoto, cascate complesse, solver idrologico, risacca completa o collegamenti automatici fra quote d'acqua diverse. La griglia del fondale è di 2 m: i margini possono ancora mostrare segmenti triangolari; è un limite visivo del campione da risolvere con raffinamento locale.

## Verifiche

`tools/check_expanded_world.tscn`: ultima esecuzione `captures/expanded_acceptance.log`, `EXPANDED_WORLD_RESULT []`, uscita pulita. Copre orario positivo/negativo e mezzanotte, durata, pausa reale nei dialoghi, F6/F7, inviluppo, campo di profondità, barriera profonda, raggi di supporto sulle sei rampe, salita/discesa del player sulla rampa nord, salvataggio/riapertura dei dati World e profilo, Undo/Redo programmatico tramite API World. Catture alla stessa camera per alba, mezzogiorno, tramonto e notte e campioni costa/parete/lago.

`tools/check_borgo_recipes.tscn`: dodici ingressi/uscite/cutaway e sei percorsi strada–porta passati, F7 e panoramica passati. Il test rispetta la precedenza del suggerimento NPC su E. `check_continuous_cliff.gd`: determinismo, geometria/collisione, corridoio e conservazione dati passati. `check_river_study.gd`: curve, larghezze, flusso e movimento passati; permane un messaggio dell'allocatore alla chiusura della relativa prova, non un criterio dichiarato risolto.

Misure D3D12, RTX 3070, 1152 × 648: campione borgo mediana 16,675 ms, p95 16,833 ms; GPU mediana 11,203 ms. Ultima prova costa stabilizzata: mediana 16,673 ms, p95 17,112 ms; render GPU mediana 6,470 ms/p95 9,706 ms, render CPU mediana 0,424 ms/p95 0,530 ms (non l’intero costo CPU del gioco). Salita/discesa nord: intervallo fra tick fisici mediano 16,679 ms, p95 16,899 ms, massimo 33,201 ms; non è una misura GPU del movimento. Avvio con generazione completa: 16,462 s dopo la rimozione delle ricostruzioni ridondanti (18–33 s nelle prove precedenti). Queste misure non certificano 60 fps ovunque: panoramica e caricamento dei chunk presentano picchi visibili. La metrica GPU riguarda il viewport 3D, non tutta la UI/composizione.

`tools/npc_ai/check_integrated_npcs.tscn` in fallback: quattro NPC, collocazione, dialoghi, pausa, separazione e cancellazione passati (`failures=[]`); il processo segnala ancora il PagedAllocator alla chiusura, come la prova fluviale.

La verifica di Undo è programmatica: non equivale a un audit completo dei gesti del dock. Restano da misurare sistematicamente movimento sull'intera mappa e picchi CPU/GPU; usare LOD, culling e generazione incrementale prima di diminuire la copertura vicina.

## Prosecuzione nelle roadmap esistenti

- R03/R03.3: sagome e cigli meno regolari, continuità visiva fra grandi masse, budget distante.
- W01.2/W01.3/W01.4b: authoring protetto completo delle rive, raffinamento locale del fondale, raccordi più naturali, risacca.
- T01.4: culling, LOD e picchi durante l'esplorazione.
- Conservare A07 e gli automatismi architettonici futuri aperti. La prova non li completa.

Le roadmap sorgenti e il Kanban generato restano l'elenco dei lavori; questo documento descrive l'incremento, senza creare una seconda lista di card.
