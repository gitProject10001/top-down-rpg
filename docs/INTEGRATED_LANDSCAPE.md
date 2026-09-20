# Scena integrata — paesaggio, architettura e prova giocabile

## Obiettivo e stato

`scenes/dev/integrated_landscape.tscn` compone i builder in un'unica scena
editabile. Alla composizione iniziale si sono aggiunti lo studio dipinto,
erba geometrica, chiome rielaborate, pareti continue e zone sopraelevate, oltre
alla prova di combattimento. La reference guida composizione e direzione
artistica: non dichiariamo raggiunta la sua qualità grafica.

Aggiornamento del 19–20 settembre: le ricette architettoniche introducono sei
ruoli nel borgo e sei varianti cittadine, conservando posizioni dei corpi
principali, strade e dati degli interni. Locanda e cappella adottano ingombri
maggiori (77,4 e 124,96 m²); i rispettivi accessi si aggiornano mantenendo il
collegamento alla strada. Le case ordinarie restano di circa 30–42 m².
La revisione corrente distingue anche galleria e registri superiori della
locanda, facciata e campanile gotici, tenda della bottega, muratura della fucina
e spazio aperto della stalla. Composizione e verifiche sono descritte in
`BUILDING_RECIPES.md`; i registri esterni non aggiungono nuovi piani abitabili.
La locanda include inoltre un corpo alto trasversale con colmo a 8 m,
raccordato al tetto principale da 9 m. Quota e inserimento sono parametri
del Volume nell'addon; il passaggio sotto lo sbalzo rimane libero.
La chiesa usa un frontone più stretto, collegato alla navata da una copertura
trasversale a 8,80 m, e un campanile inserito maggiormente nel corpo principale.
Cornici e pilastri in pietra sostituiscono la griglia lignea; la porta e i dati
interni sono conservati. La lunghezza aggiuntiva cresce verso il retro: il
corpo arretra di 1,80 m nel lotto per liberare l'imbocco del percorso.
Anche questi controlli appartengono all'House Builder.
Luce dipinta ribilanciata: meno ambiente uniforme, SSAO con raggio 65 cm,
occlusione SDFGI riattivata e penombra del sole a 0,5° (la prova a 2,2° perdeva
le ombre portate su tetto e terreno). Parametri salvati nel
profilo artistico, condiviso tra anteprima editor e Play e reversibile con F7.
La scena è il **prototipo visivo**; ricette e componenti negli addon sono la
**base riutilizzabile**. L'editor adattivo tipo Tiny Glade, i collegamenti
automatici fra sistemi e la generazione urbana completa restano sviluppi futuri.
Contratto e stato delle verifiche: [BUILDING_RECIPES.md](BUILDING_RECIPES.md).

## Aprire e provare

Aprire la scena e premere F6. Il Play usa `gameplay_preview_rig.tscn`, lo stesso
personaggio, camera, luci e viewport delle prove gameplay precedenti.

- WASD: movimento; partenza davanti al portone aperto.
- O: alterna camera gameplay e panoramica dell'intera composizione.
- F7: confronto con la resa originale; ripristina anche le altezze degli alberi
  e gestisce il giocatore quando si nascondono le zone sopraelevate.
- F: frecce del campo acqua.
- 1 / 2 / 3: spostamenti di debug a città, guado, lago.
- 4: raggiungi il gruppo di predoni; R: ricomincia l'incontro.
- 5: raggiungi il borgo con le sei ricette architettoniche.
- E: apre/chiude la porta vicina; click sinistro: combo, tenuto: carica;
  destro: guardia; Shift: schivata.
- Fiume e lago avviano già la simulazione, senza dover premere F7.

La panoramica serve a leggere il level design; non cambia la scala del
personaggio o i parametri della camera durante il gioco normale.
F8 resta un alias solo senza debugger: nell'editor è il comando **Ferma** di
Godot. La vista pulita usa Shift+F3. La camera di gioco usa FOV 13°; lo slider
del rig accetta 0° per l'ortografica mantenendo la scala sul piano di fuoco.

## Passi eseguiti dall'alto verso il dettaglio

1. Base di 152 x 144 metri prevalentemente piana. Fondale e rive derivati dalle
   funzioni dei nodi acqua; mesh del terreno e collisione salvate nella scena.
   Due zone sopraelevate aggiungono prati superiori e rampe presso gli affioramenti.
2. Fiume centrale: `river.gd`, guida Path3D con cinque punti e larghezze
   variabili; cinque rocce del Rock Builder influenzano la corrente.
3. Lago orientale: `water_body.gd`, perimetro editabile, fondale basso. Lago e
   fiume restano separati, evitando di simulare un raccordo non supportato.
4. Città occidentale: `open_castle_factory`, torri poligonali, cortine, mastio
   e corpo servizi esistenti. La cinta di 40 metri per lato richiede torri
   intermedie: la cortina ammette al massimo 19,8 metri fra facce. Otto torri
   e otto collegamenti rispettano questo limite senza cambiare il builder.
5. Sei case interne costruite con House Builder, con dimensioni, aperture e
   seed locali. Piazza e strada sono guide del Village Builder.
6. Borgo orientale: perimetro e strada editabili, proposta/applicazione del
   Village Builder, sei case prodotte e salvate nei rispettivi lotti.
7. Boschi: 91 istanze `study_broadleaf.tscn` e `study_pine.tscn`, con collisione
   del tronco. Lo studio artistico ricostruisce le chiome entro i volumi originali;
   F7 ripristina le mesh iniziali. Erba geometrica in dodici varianti di quattro
   famiglie, distribuita con maschere e seme riproducibile.
8. Due guide `formation.gd` conservano gli affioramenti originali e ospitano
   `ContinuousCliff`: pareti fratturate, superficie superiore con collisione e
   rampa. Cinque massi separati rimangono nel fiume. Le modifiche locali ai
   materiali e allo scatter sono risorse persistenti, non una mesh esportata.
9. Play: onde e corrente attive su entrambi i corpi d'acqua; impulsi del
   personaggio. Entrambi usano zone locali di 24 x 24 metri a 64 x 64 celle
   vicino al personaggio; il ricentramento azzera le onde precedenti.
10. Verifica del percorso portone / uscita città / guado / borgo e capture
    panoramico dalla scena realmente renderizzata.

## Come modificare

Case e torri: Inspector e gizmo dei builder. Cortine: riferimenti fra torri.
Strade e piazza: guide del Village Builder. Fiume: `Fiume/FlowGuide`, larghezze
e `Fiume/Rocks`. Lago: perimetro nel nodo `Lago`. Affioramenti: le due Path3D.
Alberi: istanze spostabili singolarmente sotto `Boschi`. Selezionare
`Affioramento_0/ContinuousCliff` o `Affioramento_1/ContinuousCliff` per quote,
profondità e rampe delle zone rialzate. La guida resta il bordo anteriore.

Selezionare `ArtStudyLayers`, aprire `Profile` e usare **Regenerate art preview**
per densità, famiglie, palette, muschio, umidità e danno. Editor e Play leggono gli
stessi dati. Le modifiche locali hanno ID, superficie, coordinate locali, seme,
blocco e cancellazione persistenti; i pennelli nella viewport sono ancora da
realizzare. Dettagli in [ART_STUDY_DATA.md](ART_STUDY_DATA.md).

Il terreno è una fotografia delle rive alla creazione: modificare l'acqua non
ricalcola automaticamente la sua collisione. Il raccordo dinamico terreno /
acqua non è stato aggiunto di nascosto per questa scena.
Le zone sopraelevate aggiornano la propria superficie, erba e quote degli
alberi collegati; questa integrazione locale non rende adattivo tutto il terreno.

`tools/build_integrated_landscape.gd` riproduce la composizione iniziale tramite
i builder: non è un comando universale per riapplicare tutte le revisioni
successive. Eseguirlo nuovamente SOVRASCRIVE la scena di esempio: salvare prima
una copia se si vogliono conservare modifiche manuali. Il Play non la riscrive.
I seed qui fissano varianti locali e posizioni della prova, non rappresentano
un generatore completo della regione.

## Limiti emersi e miglioramenti futuri

| Priorità | Osservazione nella scena | Futuro lavoro, non incluso |
|---|---|---|
| Alta | Chiome e prato migliorati nello studio, qualità ancora da confrontare alle varie distanze | T01.2c / T01.4: rifinitura, LOD e budget foresta; la prova locale non chiude la macrofase |
| Alta | Griglia acqua diluita su superfici estese | W04.3 / W04.5: GPU, zone locali continue e profilo completo |
| Alta | Fiume e lago separati | W02.2: raccordi e continuità del flow |
| Alta | Fondale statico dopo edit delle rive | W01.2: aggiornamento authoring del terreno e collisioni |
| Media | Attraversamento basso invece di ponte | W03: ponte, attacchi alle rive e quote; ora il fiume è guadabile |
| Media | Ricette distinguono gli edifici nel prototipo, ma il planner non compone una città organica | G01.4 / S02: catalogo, composizione, tetti e interni coerenti; B01–B03: editing adattivo |
| Media | Transizioni dipinte e ciottoli danno volume, ma guida strada e suolo richiedono applicazione esplicita | Preview e aggiornamenti locali con dati condivisi, senza una seconda pipeline |
| Media | Acqua leggibile ma senza rifrazione del fondale | Caustiche/rifrazione e qualità delle rive già in backlog |
| Media | Cappella di prova; porto, mulino e campi della reference assenti | Il ruolo locale non equivale a un generatore di chiese o a un insediamento completo |
| Media | Tutto il livello caricato insieme | Misurare geometria, ombre, overdraw e streaming prima di aumentare densità |

Il risultato è un'integrazione esplorabile, non una città finita. Gli spazi
rimangono prevalentemente piani; i cambi di quota sono localizzati in piattaforme
e rampe, non in colline continue su tutta l'area giocabile.

## Verifiche ripetibili

- `tools/check_integrated_landscape.gd`: cortine valide, due acque simulate,
  conteggio alberi, movimento reale attraverso portone e guado verso il borgo,
  cambio panoramica/gameplay. Passato dopo aver spostato lateralmente l'annesso
  di `CasaCitta_03` che invadeva l'accesso a `CasaCitta_00`.
- Avvio scena con `--capture-integrated`: `captures/integrated_landscape.png`.
- Aggiungere `--gameplay-view`: `captures/integrated_gameplay.png`.
- Il noto messaggio PagedAllocator può comparire in chiusura headless; verificare
  separatamente gli errori durante la prova, non interpretarli come test superato.
- Prove correnti di resa, editor/Play, altezze e F7:
  [ART_STUDY_DATA.md](ART_STUDY_DATA.md), [ANIME_ART_DIRECTION.md](ANIME_ART_DIRECTION.md).
- Camera e panoramica: `tools/check_camera_fov.gd`, `tools/check_overview_camera.gd`.
- Gruppo e ripartenza: [MEADOW_COMBAT.md](MEADOW_COMBAT.md). Per confrontare
  l'arte senza nemici usare `-- --no-enemies` o disattivare `Combat Encounter Enabled`.
- Ricette: [BUILDING_RECIPES.md](BUILDING_RECIPES.md); separare preservazione dei
  dati e verifiche fisiche dal giudizio visivo sugli edifici. Applicazione sulle
  dodici case e record interni invariati verificati anche nella nuova composizione;
  `check_borgo_recipes.tscn` passa sulla composizione finale: dodici porte/cutaway,
  sei percorsi e scansione della capsula, F7, panoramica e due acque.
  Log `captures/borgo_final_render.log`, zero errori e avvisi dal renderer reale.
  Galleria, elementi gotici, tenda e sagome dei ruoli sono stati ispezionati;
  la qualità artistica resta oggetto di confronto con le reference.
  I test di servizio, locanda, 14 tipi di
  dettaglio, Undo/Redo dell'editor e aggiornamento mirato dei materiali passano.
  Le misure della scena sono registrate con il relativo perimetro nel documento.


## Revisione precedente: terreno, acqua e case abitabili

Il terreno ora usa `ground_clear.gdshader` e le stesse texture dipinte della
main (`ground_painting.png`, `terrain_layers.png`). Il Surface Builder produce
una maschera unica delle strade applicata alla mesh del terreno: nessun piano
rettangolare sovrapposto che copra il fiume. Le guide di composizione sono
nascoste visivamente; si possono selezionare nell'albero e riattivare per editarle.
Questa è la base della composizione originale: lo studio artistico attuale
applica sopra questi dati il profilo dipinto descritto in `ANIME_ART_DIRECTION.md`.

La precedente griglia estesa a tutto il fiume dava celle di circa 2 metri e
impulsi enormi. Ora ciascuna acqua usa 64x64 celle su 24x24 metri vicino al
personaggio (37,5 cm/cella). La zona si ricentra quando ci si allontana oltre
7 metri dal centro, azzerando le onde: questa discontinuita resta da migliorare
con trasferimento del campo tra patch. Il fiume usa il preset calmo, lasciando
corrente e interazioni senza sovrapporre onde da vento del lago.

Le 12 case aggiunte hanno ora un `InteriorPlan` con un piano, stanze, muri e
arredi proposti dagli strumenti esistenti, tutti salvati e modificabili.
E apre/chiude la porta vicina, evidenziata. Entrando si attivano cutaway della
casa e visibilita del piano tramite le API esistenti. Non include ancora il
buio esterno coordinato della scena dedicata agli interni. Il castello conserva
i propri piani della factory; non sono stati inventati interni per gli edifici
che la factory lascia privi di un piano completo.

Corretto anche il record della finestra nelle case cittadine: usava `offset`
invece del campo `u` del builder, finendo sovrapposta alla porta centrale.

Verifica della revisione: INTERIOR_PASS conferma ingresso reale attraverso la
porta aperta con E e attivazione cutaway; INTEGRATED_PASS conferma il percorso
precedente. Capture panoramico senza errori runtime. Il test headless conserva
il noto messaggio PagedAllocator alla chiusura.

## Editing e performance

Il terreno e' ora raggruppato: selezionare `TerrenoComposto` per spostarlo;
mesh e materiale sono in `TerrenoComposto/Superficie`. Vedi
[EDITOR_PERFORMANCE.md](EDITOR_PERFORMANCE.md) per misure, interventi e limiti.
