# Scena integrata — prova degli strumenti esistenti

## Obiettivo e stato

`scenes/dev/integrated_landscape.tscn` compone i builder esistenti in un'unica
scena editabile. La reference guida la disposizione città / acqua / borgo /
boschi: non è una riproduzione della sua qualità grafica o di ogni edificio.
Nessun nuovo generatore, asset Blender, shader o sistema architettonico è stato
aggiunto per questa prova. I nuovi file sono composizione, Play e verifica.

## Aprire e provare

Aprire la scena e premere F6. Il Play usa `gameplay_preview_rig.tscn`, lo stesso
personaggio, camera, luci e viewport delle prove gameplay precedenti.

- WASD: movimento; partenza davanti al portone aperto.
- F8: alterna camera gameplay e panoramica dell'intera composizione.
- F: frecce del campo acqua.
- 1 / 2 / 3: spostamenti di debug a città, guado, lago.
- Fiume e lago avviano già la simulazione, senza dover premere F7.

La panoramica serve a leggere il level design; non cambia la scala del
personaggio o i parametri della camera durante il gioco normale.

## Passi eseguiti dall'alto verso il dettaglio

1. Area piana di 152 x 144 metri. Fondale e rive derivati dalle funzioni già
   presenti nei nodi acqua; mesh del terreno e collisione salvate nella scena.
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
7. Boschi: 91 istanze dei nuovi `study_broadleaf.tscn` e `study_pine.tscn`, con
   collisione del tronco e materiali originali. Esclusione di acqua, città e
   strada del borgo; nessun nuovo generatore di vegetazione.
8. Due guide `formation.gd` compongono gli affioramenti a nord; ogni roccia
   rimane un elemento del builder modificabile. Cinque massi separati nel fiume.
9. Play: onde e corrente attive su entrambi i corpi d'acqua; impulsi del
   personaggio. Il lago usa una zona simulata di 50 x 50 metri, il fiume la
   propria estensione. Entrambi rimangono a 64 x 64: il dettaglio ne risente.
10. Verifica del percorso portone / uscita città / guado / borgo e capture
    panoramico dalla scena realmente renderizzata.

## Come modificare

Case e torri: Inspector e gizmo dei builder. Cortine: riferimenti fra torri.
Strade e piazza: guide del Village Builder. Fiume: `Fiume/FlowGuide`, larghezze
e `Fiume/Rocks`. Lago: perimetro nel nodo `Lago`. Affioramenti: le due Path3D.
Alberi: istanze spostabili singolarmente sotto `Boschi`.

Il terreno è una fotografia delle rive alla creazione: modificare l'acqua non
ricalcola automaticamente la sua collisione. Il raccordo dinamico terreno /
acqua non è stato aggiunto di nascosto per questa scena.

`tools/build_integrated_landscape.gd` riproduce la composizione iniziale tramite
i builder. Eseguirlo nuovamente SOVRASCRIVE la scena di esempio: salvare prima
una copia se si vogliono conservare modifiche manuali. Il Play non la riscrive.
I seed qui fissano varianti locali e posizioni della prova, non rappresentano
un generatore completo della regione.

## Limiti emersi e miglioramenti futuri

| Priorità | Osservazione nella scena | Futuro lavoro, non incluso |
|---|---|---|
| Alta | Boschi radi e chiome sbiancate/sottili in panoramica | T01.2c / T01.4: palette, copertura alpha, LOD e budget foresta |
| Alta | Griglia acqua diluita su superfici estese | W04.3 / W04.5: GPU, zone locali continue e profilo completo |
| Alta | Fiume e lago separati | W02.2: raccordi e continuità del flow |
| Alta | Fondale statico dopo edit delle rive | W01.2: aggiornamento authoring del terreno e collisioni |
| Media | Attraversamento basso invece di ponte | W03: ponte, attacchi alle rive e quote; ora il fiume è guadabile |
| Media | Mura squadrate e case poco gerarchizzate | Composizione manuale più organica usando gli strumenti; ulteriore varietà architettonica |
| Media | Piazza e strade poco integrate nel suolo | Rifinire superfici e transizioni con sistemi esistenti, poi eventuali estensioni |
| Media | Acqua leggibile ma senza rifrazione del fondale | Caustiche/rifrazione e qualità delle rive già in backlog |
| Media | Mancano chiesa, porto, mulino e campi della reference | Future componenti, nessun sostituto approssimativo introdotto adesso |
| Media | Tutto il livello caricato insieme | Misurare geometria, ombre, overdraw e streaming prima di aumentare densità |

Il risultato è un'integrazione esplorabile, non una città finita. Gli spazi
rimangono prevalentemente piani come richiesto; non abbiamo introdotto colline.

## Verifiche ripetibili

- `tools/check_integrated_landscape.gd`: cortine valide, due acque simulate,
  conteggio alberi, movimento reale attraverso portone e guado verso il borgo,
  cambio panoramica/gameplay.
- Avvio scena con `--capture-integrated`: `captures/integrated_landscape.png`.
- Aggiungere `--gameplay-view`: `captures/integrated_gameplay.png`.
- Il noto messaggio PagedAllocator può comparire in chiusura headless; verificare
  separatamente gli errori durante la prova, non interpretarli come test superato.
