# Scena integrata — paesaggio, architettura e prova giocabile

## Stato corrente — 23 settembre 2026

Indice e priorità: [PROJECT_STATUS](PROJECT_STATUS.md). Il resto del documento conserva il diario degli incrementi; i risultati datati si riferiscono a quelle revisioni.

- Player action: click combo, tenere/rilasciare per caricato con scatto, guardia frontale, Shift schivata. Ctrl passo/corsa; negli interni cammina. B reinfodera sul fianco sinistro; attacco/parata estraggono.
- Camera con prospettiva stretta e zoom interno. O panoramica; F6 **nel gioco** apre il ciclo; F7 confronta lo stile; P apre i cursori del post e del DOF, con pausa. Le regolazioni P non persistono fra sessioni.
- Quattro NPC locali, circuito borgo–torre temporaneo. Missioni persistenti e ripartenza completa non sono ancora integrate.
- La prova outline resta sospesa. Capacità generiche e criteri aperti rimangono nelle roadmap.

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
La chiesa condivide inoltre `chapel_stone.tres` fra navata, frontone e
campanile: palette, scala dei corsi e usura si modificano nell'House Builder.
La navata mantiene blocchi geometrici; i corsi sui pannelli gotici sono
dettaglio di materiale. Cornici e archi conservano il proprio rilievo reale.
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


Il portale della chiesa usa il parametro riutilizzabile
`RecipeDetails/FacciataGotica.portal_recess_depth` (0,76 m): tre ordini di
pietra, conci separati e soglia a filo. Porta e accesso sono conservati.
Questa prova visiva usa l'House Builder; gli automatismi futuri di raccordo
facciata/terreno restano da implementare.

Il rosone della stessa facciata usa `rose_recess_depth = 0.10`: foro
circolare nella mesh, bordo svasato e cornice a conci. La vetrata arretrata
rimane davanti al frontone retrostante e conserva il disegno esistente.


Campione strada/vegetazione della chiesa: due componenti `wall_ivy` e una
`stone_apron` appartengono alla ricetta dell'House Builder. Il lotto usa
`chapel_path_surface.tres` del Village Builder per fondere l'accesso con
terreno ed erba attraverso la copertura condivisa. Seed e controlli sono
salvati; usare ArtStudyLayers per rigenerare dopo una modifica al percorso.
La scena resta il campione, le capacita' riutilizzabili sono negli addon.

### Campione pigmento prato — 2026-09-22

Il profilo artistico salva un campione locale centrato sulla chiesa (`grass_study_surface`,
raggio 16 m). Terreno e ciuffi leggono `meadow_field.gdshaderinc`: palette comune,
macchie grandi/intermedie e pennellate minute in coordinate mondo. Il contributo
del terreno pesa soprattutto sulle radici. Densità, dodici forme e seed non cambiano.
Normale iniziale 75% dipinta / 25% geometrica ammorbidita; raffiche noise guidano
punte e una variazione luminosa lieve. Rimangono AO, ombre ricevute e radici scure;
nessuna ombra dei singoli fili. Il campione sfuma verso lo shading precedente.

Inspector di ArtStudyProfile: scala macchie, influenza terreno, miscela normali,
forza vento (0 per fermarlo nel campione), superficie e raggio. Usare la rigenerazione
di ArtStudyLayers già esistente dopo le modifiche. F7 confronta gli stili completi;
`check_borgo_recipes.tscn -- --no-enemies --meadow-comparison` produce anche il
confronto locale before / still / wind senza cambiare camera o luce.
Le modifiche locali e le cancellazioni continuano a usare gli stessi dati di authoring.

Verifica completa a 1152×648 (`captures/meadow_final.log`): 12 ingressi/uscite,
sei percorsi, cutaway, F7 e acqua senza errori; frame mediano **16,678 ms**, p95
**16,796 ms**, GPU mediana **10,59 ms**. Sono misure della scena integrata, non
un benchmark isolato del solo shader. Confronti in `captures/meadow_before.png`,
`meadow_still.png` e `meadow_wind.png`. Geometria e densità conservate; nessuna
estensione della taratura fuori dal campione.

### Esperimento solo post-processing

`PainterlyPost` istanzia `scenes/effects/painterly_post.tscn` dentro il viewport
3D. Nella revisione iniziale **P** attivava/disattivava il pass; ora P apre il pannello con toggle del filtro e cursori. Il toggle abilita/disabilita il pass senza cambiare F7, materiali, modelli,
illuminazione o tone mapping. La UI esterna al viewport rimane nitida.
Il vecchio PostPixel resta nella sua configurazione precedente.

Nel nodo Filter, ShaderMaterial nell'Inspector: `palette_strength` (0,72),
`soften_strength` (0,6), `radius` (1,25 pixel), `edge_preservation` (80),
`warmth` (0,15). Filtro bilaterale piccolo, palette di 32 colori di base con
transizioni morbide, nessun dithering o contorno nero aggiunto. La palette è
una base cromatica, non un limite rigoroso a 32 colori sul framebuffer.
Il filtro non genera pennellate geometriche; un raggio alto può impastare
tegole e personaggi. Disabilitare il nodo per bypass completo.

Confronto ripetibile: `res://tools/check_painterly_post.tscn`, immagini
`captures/painterly_off.png` e `captures/painterly_on.png`, stessa camera e luce.

Prova a 1152×648: off 16,692 ms / on 16,679 ms mediani; p95 on 16,796 ms.
Entrambi circa 60 fps, con VSync: non si deduce un costo GPU preciso dalla
differenza fra queste due misure. Shader compilato e bypass P verificato.

### Idea sospesa — Contorno tramite envelope della mesh

Solo ricerca/progettazione futura: nessuna implementazione in questa revisione.
Riferimento: schizzo dell'utente con mesh nera, involucro blu e raggi dalla camera.

- [ ] Valutare un involucro espanso: colorare il margine visibile dell'envelope
  dove la mesh originale non lo copre, rispettando la profondità degli altri oggetti.
- [ ] Provare prima l'approccio **inverted hull** (guscio espanso, facce anteriori
  scartate e depth test). Per una silhouette esterna il raymarching potrebbe non
  servire: verificare se rasterizzazione e profondità risolvono già il caso.
- [ ] Distinguere silhouette esterna da spigoli interni, pieghe e contatti:
  l'envelope da solo non garantisce tutte le linee disegnate nello schizzo.
  Confrontare con il contorno depth/normal già presente in `pixel_post.gdshader`.
- [ ] Studiare spessore stabile in pixel alla camera di gioco (ortografica e FOV 13),
  normali smussate per l'espansione, crepe sugli spigoli, concavità, intersezioni,
  cutaway, personaggi animati e fogliame con trasparenza ritagliata.
- [ ] Solo se necessario valutare raymarching/SDF: definire prima la rappresentazione
  della superficie, aggiornamento delle mesh dinamiche e costo. Una normale mesh
  triangolare non fornisce automaticamente un campo di distanza da percorrere.
- [ ] Confrontare nero, colore scuro locale e linea interrotta pittorica; verificare
  stabilità in movimento e costo a 1152×648. Nessuna modifica automatica agli asset.

Questa eventuale strada geometrica è distinta dal preset attuale, che rimane
esclusivamente post-processing. Decisione e integrazione negli addon da progettare.


## Estensione e ciclo — 23 settembre 2026

La scena usa ora World per il piano 304 × 288 m e la distribuzione fuori dal nucleo protetto. F6 apre i controlli dell’orario; il ciclo completo dura 30 minuti e si ferma nei dialoghi. Dettagli, verifiche e limiti in [EXPANDED_LANDSCAPE.md](EXPANDED_LANDSCAPE.md). Non usare il generatore iniziale per aggiornare questa scena: le composizioni e le modifiche locali sono dati autoriali.


## Primo circuito del borgo

Borgo e guado esistenti collegati a una torre di prova tramite un sentiero stretto, percorso anche al ritorno; rimossi cartelli e bivio ridondante. Due predoni usano il combattimento già presente. Dati, comandi e limiti in [BORGO_EXPLORATION_CIRCUIT.md](BORGO_EXPLORATION_CIRCUIT.md). È una prova di percorrenza e progressione temporanea; non un nuovo sistema completo di quest.

## Combattimento action — revisione del 23 settembre 2026

La scena usa ora la combo `Attack` per il giocatore: click successivi concatenano tre colpi (due laterali e finale pesante), nella prima revisione tenere premuto non caricava; ora la carica è disponibile (sezioni successive). Shift schiva; un comando appena prima del contatto viene ricordato per 0,18 s. Destro para frontalmente, senza selezione della direzione. Rimossi gli indicatori direzionali dal HUD di questo personaggio. La mira e il movimento restano disponibili, con impegno breve durante il colpo.

Slash e scia rendono visibile il contatto; gli attacchi normali non consumano stamina. Riserva del giocatore 180, recupero 30/s fuori dalla guardia; i nemici conservano 100 e 8/s. Il knockback ordinario è contenuto per permettere di collegare la combo, maggiore sul finale. I predoni riusano PackDirector e il driver di animazione windup/release preesistente (internamente chiamato DirAttack); questo non richiede più letture direzionali al giocatore.

Il ragdoll riutilizza i vincoli articolari del progetto gemello `rpg-3d`, salvati nel prefab `scenes/components/humanoid_ragdoll.tscn`: 18 corpi, collisione con il terreno, attivazione soltanto alla morte, animazione e IK disattivati, armi agganciate alle mani. Il corpo non blocca i combattenti e viene rimosso dopo sei secondi. Non è un cambio dei modelli.

Verifica: `tools/check_pack_combat.tscn` controlla tre contatti reali, click prolungato, schivata anticipata, parata indipendente dalla direzione, riserva/recupero, ragdoll stabile a terra e attacchi coordinati di quattro nemici. `tools/check_action_combat_visual.tscn` verifica combo e morte nella scena integrata e salva `captures/action_slash.png` e `captures/action_ragdoll.png`. Il vecchio test `check_directional_combo.gd` riguarda la modalità duello precedente e non è l'accettazione di questo personaggio. Le prove headless segnalano ancora il warning di cleanup ObjectDB/PagedAllocator, non risolto da questa revisione. Il feeling e il bilanciamento restano da provare manualmente; le catture non costituiscono una misura prestazionale.

### Cedimento fisico progressivo

Il prefab ragdoll ora usa due componenti piccoli: `scripts/components/ragdoll_reaction.gd` campiona il movimento delle ossa vive e gestisce il passaggio alla fisica; `ragdoll_muscle.gd` applica una breve resistenza angolare nel callback fisico. Durata di cedimento (0,42 s), intensità, inerzia e moltiplicatore del finale sono nell'Inspector del nodo Ragdoll. Gambe e parte colpita rilasciano prima, poi braccia e busto; anche le molle di ginocchia/gomiti si rilasciano. Gravità, collisioni e limiti anatomici restano attivi. Il controllo non ancora l'anca a una posizione nel mondo e non tenta di mantenere l'equilibrio.

La velocità viene registrata prima che Hurt/Dead la sostituiscano. Movimento delle ossa e del personaggio sono miscelati senza sommarli due volte; i teletrasporti non generano inerzia. Un solo impulso raggiunge l'osso più vicino al contatto, con leva limitata e intensità maggiore sul finale. La spinta verticale fissa è rimossa. Masse distribuite maggiormente su bacino, busto e cosce, rimbalzo nullo. Il contatto dei colpi action è una stima dalla lama visibile per ogni bersaglio, non un'intersezione esatta dei triangoli né un nuovo sistema di danni per zona.

L'addon `procedural_anim` di rpg-3d è stato consultato (molle e inerzia), non importato: gait, IK e solver dell'orco restano fuori. La libreria gemella prevede `hurt_chest`, `hurt_head` e `hurt_knockback`; la revisione successiva descritta sotto le collega ai personaggi vivi. Passi di recupero dell’equilibrio e mani protettive non sono implementati. La rialzata animata è aggiunta dalla revisione successiva. Questa revisione è una breve transizione fisica alla morte, non una replica di Euphoria.

Test aggiuntivo `tools/check_ragdoll_reactions.tscn`: spalla sinistra/destra, ginocchio, movimento verso gradino; selezione della parte colpita, inerzia, callback attivo, pausa, rilascio completo e stabilità dei 18 corpi. Risultato: zero fallimenti. Verifica visiva integrata riuscita, con catture `action_ragdoll_early.png`, `action_ragdoll_collapse.png`, `action_ragdoll.png`. Il warning di shutdown PagedAllocator preesistente resta. Nessuna nuova misura comparativa delle prestazioni.

API fisiche verificate sulla [documentazione Godot PhysicalBone3D](https://docs.godotengine.org/en/stable/classes/class_physicalbone3d.html): impulsi singoli all'impatto, controllo continuo nel callback di integrazione.

### Reazioni dei nemici vivi e rialzata

`StateMachine/Hurt` seleziona `hurt_head` per un contatto stimato vicino alla testa e `hurt_chest` negli altri casi. Un finale della combo non letale usa `hurt_knockback` seguito da `getup`; entrambe erano già nella libreria retargettata locale. Nessun asset copiato e nessuna dipendenza aggiunta dall'addon dell'orco. Durate iniziali: caduta 0,55 s, rialzata 0,65 s; attivazione e durate sono esportate nell'Inspector di Hurt.

I contatti ordinari riavviano il breve flinch quando applicano danno. Durante caduta/rialzata il nemico non attacca; altri colpi possono danneggiarlo ma non riavviano la sequenza all'infinito. La morte interrompe la reazione e attiva il ragdoll dalla posa corrente. Alla fine della rialzata il clock dell'animazione torna a 1 e PackBrain può riprendere i turni. Il giocatore conserva il breve stun precedente. Nessun danno maggiorato alla testa e nessun controllo fisico dell'equilibrio: sono reazioni animate contestuali. La capsula di movimento rimane quella del personaggio, non un corpo fisico disteso per i nemici vivi.

Verifiche: `check_pack_combat.tscn` e `check_living_reactions.tscn` passano (testa/busto, finale, nessun riavvio durante caduta, pausa nella rialzata, ritorno a Idle, morte durante caduta). Le catture integrate sono `action_knockdown.png` e `action_getup.png`; restano i warning di cleanup già documentati. La difficoltà del knockdown e la durata dell'apertura vanno tarate giocando.

### Camminata, lock e passo di recupero

- All'aperto: corsa predefinita (6 m/s), Ctrl premuto per camminare (2,2 m/s). Dentro gli edifici: camminata predefinita, Ctrl per correre volontariamente. Lo stesso modificatore è associato alla pressione dello stick sinistro; l'inclinazione dello stick dosa direttamente la velocità. Shift resta schivata.
- Il contesto interno riusa il controllo della pianta/quote che guida già il cutaway: nessuna seconda rete di aree. Uscendo torna il comportamento esterno.
- Durante lock, il corpo guarda il bersaglio mentre un blend a quattro direzioni gestisce camminata/corsa avanti, indietro e laterale. Sei clip retargettate sono riusate da rpg-3d; il filtro delle gambe conserva la postura UAL della spada. Il ritmo dei passi segue la velocità effettiva. Sbloccando torna il movimento orientato verso la marcia.
- Il secondo colpo della combo può causare un breve passo di recupero del predone: circa 35 cm in 0,30 s dopo il flinch, direzione della spinta, animazione coerente e controllo delle collisioni. Il PackDirector esistente controlla anche terreno e acqua. Se manca spazio il passo si ferma. Il finale conserva caduta/rialzata.

`check_locomotion.tscn` verifica velocità per contesto, modificatore, input analogico, direzioni sotto lock e recupero libero/contro muro. `check_locomotion_visual.tscn` controlla ingresso/uscita reali dal contesto interno e cattura otto combinazioni di andatura/direzione nella scena. Questo rimane un recupero animato con collisioni, non un solver fisico dell'equilibrio.

### Carica e ultimo passo (prova di combattimento)
- Click breve: combo esistente. Tenere il primo colpo trattiene la preparazione; rilascio dopo 0,65 s: danno doppio, reazione pesante e costo di 30 stamina. Rilascio automatico a 1,30 s; sotto soglia o senza stamina resta un colpo normale. La schivata annulla la preparazione. I colpi concatenati restano rapidi.
- Morte ordinaria da posizione stabile: possibile ultimo passo di 28 cm in 0,30 s, poi ragdoll; nemico già morto, senza attacchi. Muri, assenza di appoggio, caduta in corso e finisher saltano il passo. La pausa arresta la transizione. Campionamento della posa aggiornato al passaggio alla fisica.
- È una transizione animata con controllo dello spazio e successiva fisica, non un sistema di equilibrio Euphoria. Non introduce animazioni di appoggio delle mani o un solver di foot placement.
- Verifica: `check_charge_death.tscn`, regressione `check_pack_combat.tscn`, confronto nella scena con `check_charge_visual.tscn` (runtime NPC disabilitato).

#### Correzione della carica e leggibilità del cedimento
- La carica prepara lentamente `atk_dash` (Sword_Dash) e il rilascio completo usa quel fendente orizzontale. Scatto con velocità iniziale 20 m/s rispetto ai 15 del normale DashAttack, stessa decelerazione e collisioni del CharacterBody; nessuna invulnerabilità aggiunta alla carica.
- Il mixer del player continua a valutare la posa a ogni frame fisico: si ferma soltanto ActionClock, evitando rest pose/T-pose nei modificatori dello scheletro.
- Ultimo passo portato a 38 cm / 0,42 s; un semplice stagger non lo esclude più. Restano esclusi finisher, knockdown e spazio insufficiente.

#### Rifinitura del cedimento fisico
- Risposta articolata breve: busto ruota leggermente rispetto al contatto, testa e braccia rispondono con ritardo, il lato colpito perde sostegno prima dell'altro. Profilo esposto tramite `body_response` e `collapse_duration` (0,68 s di base).
- Obiettivi angolari limitati, con rilascio progressivo; nessun vincolo di posizione o sostegno artificiale verso l'alto. Gravità, collisioni e limiti articolari restano attivi. Finisher abbreviano la risposta.
- Test: spalle destra/sinistra, ginocchio, movimento presso un gradino, pausa, rilascio completo delle resistenze e stabilità del corpo. Fixture della carica separata dai critici casuali.

### Zoom interno e spada al fianco
- Entrando in un interno già riconosciuto dal sistema cutaway, la camera riduce gradualmente lo span al 72%; uscita ripristina l'inquadratura. `interior_zoom_ratio` e `interior_zoom_speed` sono esposti sulla camera, senza alterare FOV o scala del mondo. Lock mantiene spazio sufficiente per entrambi i combattenti.
- B estrae/reinfodera da fermo o in movimento. Spada agganciata al bacino sul fianco sinistro, fodero semplice marrone e lama nascosta; nessuna hitbox attiva. Attacco/parata estraggono automaticamente. Cambio di aggancio immediato: animazione dedicata di estrazione/reinserimento ancora futura.
- Verificati ingresso/uscita, zoom, aggancio sinistro e ritorno all'attacco in `tools/check_interior_sheath.tscn`, con catture nella scena integrata. La fixture usa il fallback NPC.

### P — regolazione post-processing
P apre/chiude il pannello nella Window, fuori dal viewport filtrato: palette, ammorbidimento, raggio, conservazione dei bordi e calore. Il toggle interno abilita/bypassa il filtro. Tutte le modifiche sono temporanee per la sessione.
Profondità di campo opzionale tramite CameraAttributesPractical: fuoco segue il piano della camera sul personaggio, distanze nitide anteriore/posteriore indipendenti, transizione e intensità regolabili. Non è una sfocatura per fasce dello schermo; usa la profondità 3D. HUD e pannello restano nitidi. Nessuna modifica ai materiali o alle mesh.
Il pannello sospende il gameplay e ripristina lo stato di pausa precedente con P, Esc o Chiudi; evita colpi accidentali mentre si regolano i cursori. Test `check_post_controls.tscn`: nove slider, shader aggiornato, DOF, pausa/ripristino e cattura a 1152×648. Costo GPU del DOF da profilare prima di renderlo predefinito.
