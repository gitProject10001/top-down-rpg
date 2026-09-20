# Ricette architettoniche

Incremento del 19–20 settembre 2026. Le ricette descrivono combinazioni dei normali
nodi House Builder; la scena integrata ne prova la leggibilità nel paesaggio
dipinto. L'editor adattivo tipo Tiny Glade resta uno sviluppo successivo.

## Tre livelli distinti

| Livello | Contenuto | Limite |
| --- | --- | --- |
| Scena di prova | Sei ruoli nel borgo e sei varianti cittadine | Non dimostra ancora la varietà di un intero generatore urbano |
| Addon riutilizzabile | Ricetta Resource, applicazione proposta/conferma, volumi e dettagli editabili | Le regole locali non risolvono ogni intersezione con terreno, strade o edifici vicini |
| Interazione futura | Drag con anteprima dei dipendenti, diagnostica comune e adattamento locale | B01–B03 restano TODO; nessuna nuova pipeline di authoring parallela |

## Dati e applicazione

`addons/house_builder/building_recipe.gd` contiene `schema_version`, `recipe_id`,
`display_name`, `role`, `description`, `main_properties`, `components`, `details`
e `variants`. Le varianti sono override leggibili dei parametri e dei componenti,
non scene opache che sostituiscono l'edificio. Seme strutturale e seme del
dettaglio sono distinti; una variante può essere scelta esplicitamente per ID.

`recipe_apply.gd` espone:

```gdscript
propose(house, recipe, structural_seed = -1, detail_seed = -1,
        variant_id = "", preserve_footprint = true, minimum_wall_height = -1.0)
apply(house, state)
```

La proposta restituisce `ok`, `errors` e `before`; quando valida include `after`.
Il chiamante applica lo stato e gestisce una transazione UndoRedo usando
`before`/`after`. La proposta usa le verifiche del Volume Builder per gli agganci
e non sostituisce il nodo casa o il suo `InteriorPlan`.

`preserve_footprint=true` conserva larghezza e profondità; `false` consente di
adottare quelle dichiarate dalla ricetta. Le ricette possono alzare
le pareti esterne e la gronda; `InteriorPlan` conserva `floor_height`, piani,
stanze, arredi e relativi record. Restano i record delle aperture e le
trasformazioni dei corpi principali; la posizione derivata delle porte segue
il perimetro e può quindi cambiare quando si amplia l'edificio.
Il minimo delle pareti si ricava anche dal numero di piani per la loro altezza:
una ricetta non può abbassare l'involucro sotto i piani già presenti.

`minimum_wall_height` aggiunge un minimo esplicito per edifici senza
`InteriorPlan`: `BuildingRequest` passa `storeys * 2.6`, anche per due o tre
piani. `-1` conserva il minimo esplicito registrato nella provenienza; `0` lo
azzera. Il minimo imposto dagli interni viene invece ricalcolato sui piani
correnti. Le tettoie e i dettagli nuovi devono lasciare liberi tutti i percorsi,
non soltanto il centro porta.

House conserva il riferimento `building_recipe` e `recipe_provenance` con
ricetta/variante, semi, baseline, ID generati e cancellazioni. I componenti
modificati o bloccati si conservano; i record eliminati non devono riapparire
alla successiva applicazione. I nodi manuali estranei alla ricetta restano di
proprietà dell'autore. Riapplicare una ricetta è un'operazione esplicita: cambiare
un dato della Resource non avvia un solver adattivo durante ogni trascinamento.
`House.rebuilt` segnala ogni ricostruzione della casa, comprese quelle differite
innescate dai volumi. Nella scena integrata `refresh_architecture(house)`
riapplica il profilo solo al sottoalbero interessato, mantenendo confronto F7,
cutaway e modifiche locali ai materiali; non rigenera erba, alberi o luci.
`House.recipe_applied` resta la notifica specifica dell'applicazione della ricetta.

Nel dock **Casa**, scegliere ricetta, variante e semi, quindi **Applica ricetta ·
conserva interventi**. I semi a `-1` conservano quelli precedenti; la variante
può seguire il seme oppure essere scelta per nome. La casella **Conserva larghezza
e profondità attuali** parte disattivata: il comando adotta le dimensioni
dichiarate dalla ricetta. Attivarla conserva l'ingombro corrente. Questo default
dell'interfaccia è distinto dal parametro API `preserve_footprint=true`.
Il comando usa l'UndoRedo dell'editor, senza rigenerare il villaggio.

`BuildingRequest` può riferirsi facoltativamente a una ricetta con variante e
semi locali; le richieste precedenti continuano a costruire le case con il
contratto esistente. Questo è il raccordo da estendere nel catalogo G01.4.

## Volumi e dettagli

Le ricette usano i volumi esistenti sotto `Volumes` per le parti architettoniche.
Un record `components` con `kind="balcony"` crea invece un normale Balcony
sotto `Components`: usa le sue proprietà, `width_ratio` opzionale e lo stesso
sistema di ID, baseline, blocchi, cancellazioni e UndoRedo della ricetta.
Gli oggetti sotto `RecipeDetails` usano `recipe_detail.gd`: nodo `@tool` con tipo,
dimensioni, seme, palette, usura, ID, blocco e collisione opzionale. Il campo
`motif` dell'insegna consente scelta automatica, grano, boccale, incudine o cavallo.
Trasformazione e parametri persistono; `_GeneratedRecipeDetail` è una cache.

Il vocabolario iniziale comprende camino, campanile a vela, banco con merci,
banco da fucina, catasta di legna, abbeveratoio, recinto, insegna e abbaino.
Sono geometrie visibili da più direzioni. Gli ornamenti sul tetto seguono il
cutaway; gli oggetti a terra restano visibili. I dettagli non aprono da soli un
vano nel muro: gli ingressi restano responsabilità del builder e della ricetta.
Un abbaino decorativo non implica automaticamente un sottotetto percorribile.

Il vocabolario corrente aggiunge `market_awning` e quattro tipi gotici:

- `market_awning` usa `recipe_fabric.gd`: drappo geometrico piegato, bordo
  pendente e due pali frontali con collisione. Il centro resta una campata aperta.
- `gothic_facade`: portale ogivale aperto nella mesh e nella collisione del
  dettaglio, disposto attorno alla porta già esistente della casa.
- `gothic_bell_tower`: corpo verticale continuo, bifore aperte sui quattro lati
  e cuspide; la torre della composizione è alta 13,8 m.
- `gothic_buttress`: contrafforte con collisione aderente alla forma.
- `gothic_window`: cornice e pannello vetrato decorativi, senza collisione;
  non ritaglia da solo una nuova finestra nella parete della casa.

Le parti murarie gotiche seguono il cutaway con taglio e tappi visibili sui
monconi; il pannello finestra si nasconde entrando. Parametri e trasformazioni
restano quelli di `RecipeDetail`, con base locale a Y=0 e fronte a +Z per la
facciata. I nuovi tipi non costituiscono un generatore completo di chiese.

### Ritmo superiore della facciata

`House.facade_storey_height` (default 0) abilita una fascia orizzontale e i
controventi; `facade_upper_windows` (default false) aggiunge un ritmo semplice
di finestre attraverso `facade_openings()`. I record manuali `house.openings`
restano invariati e hanno precedenza nei conflitti. Le finestre derivate hanno
ID `upper_<parete>_<indice>`, ma non ancora modifica individuale o cancellazione
persistente nell'interfaccia. È un'opzione del prototipo, **non B01 completato**.

## Applicazione nella scena integrata

### Finitura condivisa della pietra della chiesa

`MasonryFinish` (`addons/house_builder/masonry_finish.gd`) è una Resource
opzionale di House, Volume e RecipeDetail: colore della pietra, dimensioni
nominali dei blocchi e quantità di usura. `recipes/chapel_stone.tres` è la
taratura del concept (0,72 × 0,37 m). Modificare la risorsa nell'Inspector
rigenera i nodi che la usano; una copia locale permette un override manuale.
Le ricette ereditano la finitura dal corpo principale, salvo override del
componente. Ricette e scene senza finitura conservano i materiali precedenti.

La navata mantiene i blocchi geometrici e gli spigoli in rilievo. I grandi
pannelli gotici ricevono corsi nello shader con rilievo delle normali e
occlusione delle fughe: questi giunti **non** aggiungono collisioni o nuove
ombre geometriche. Cornici, archi e pilastri restano forme reali, con pietra
leggermente più chiara e senza stampare corsi rettangolari sull'arco.
Palette e pennellate seguono la stessa funzione nei due materiali.

Muschio e umidità si concentrano alla base, nei giunti e sui ripiani; le
colature partono dalle quote delle cornici del campanile e dei contrafforti.
I corpi sopraelevati tengono conto della quota per evitare una falsa fascia
di muschio a metà parete. Le crepe sono segni superficiali radi e interrotti.
Non sono state aggiunte brecce o scheggiature geometriche nuove.

Gli strati artistici esistenti modulano muschio, umidità e danno anche sui
dettagli con questa finitura. Il segnale `RecipeDetail.rebuilt` riusa il
normale aggiornamento locale dei materiali e del cutaway: un ritocco al
campanile non rigenera prato e terreno. I pennelli interattivi restano futuri.
La taratura del sole a 0,5° resta quella approvata nel confronto F7.

Controlli: modifica live della Resource, identità condivisa dopo riapertura,
Undo/Redo e aperture originali in `check_chapel_composition`; rigenerazione
dei dettagli e ripristino F7 in `check_building_material_refresh`.
La prima prova completa della scena passa le 12 porte e i sei percorsi
(`captures/church_stone_render.log`). Il successivo controllo visivo usa
`--capture-only`, dopo l'aggiunta delle colature sotto i ripiani.
Risultato finale: `captures/church_stone_final.log`, nessun errore; mediana
frame 16,674 ms, p95 16,793 ms a 1152×648. Immagine effettiva della scena:
`captures/church_stone_final.png`. Passano i controlli di composizione,
ricette e aggiornamento dei materiali (`rebuild_notifications=7`).

### Locanda: corpo alto e raccordo dei tetti — 20 settembre 2026

La locanda ora aggiunge `Volumes/CorpoCamere`, un normale Volume largo circa
3,70 m e profondo 4,80 m, a quota 3,20 m. Il colmo secondario arriva a 8 m,
contro i 9 m del corpo principale. La parte posteriore entra nella copertura;
quella esterna sporge di circa 1,08 m, con fondo e mensole in legno. Non vengono
creati camere, scale o piani nel `InteriorPlan` conservato.

Nel Volume, l'Inspector espone `attachment_elevation`, `attachment_inset` e
`roof_junction`. I valori predefiniti mantengono i raccordi precedenti.
Il raccordo alto è esplicito: corpo chiuso a due falde, su un fianco del tetto,
quota almeno 3 m, colmo sotto quello principale e timpano posteriore interamente
nascosto nella copertura ospite. Le geometrie interne all'incrocio sono tagliate
con i piani dei volumi già usati dal builder, comprese le tegole in rilievo.
Non è un risolutore generale di tetti o il completamento di B03.

Le finestre automatiche coperte dal nuovo corpo vengono escluse: sulla locanda
restano 14 finestre superiori derivate e due aperture del corpo trasversale.
Le aperture manuali rimangono invariate. Gli abbaini occupano falde opposte.
Il cutaway converte le quote nel riferimento del volume; passare al piano terra
sotto lo sbalzo non equivale a entrare nell'edificio.

Verifiche specifiche: `check_inn_composition` passa collisione sotto lo sbalzo,
assenza del tetto principale sepolto nell'incrocio, rifiuto del timpano posteriore
esposto, cutaway e riapertura dei parametri. Passano anche ricette, Undo/Redo
del plugin reale in modalità headless, `check_multi_volume` e `check_flat_roof`.
La scena completa passa nuovamente tutte le 12 porte e i 6 percorsi; rendering
ispezionato dalla stessa camera (`captures/inn_roof_render.log`). Mediana frame
16,673 ms, p95 16,853 ms; GPU 11,661/11,734 ms, viewport 1152×648, 120 frame.
Il benchmark del combattimento riportato più sotto precede questo raccordo.

Il controllo storico `check_roof_access` fallisce su «Disabled access restores
parapet collision». La stessa asserzione fallisce anche caricando il Volume
precedente da HEAD in un processo isolato (`captures/legacy_roof_probe.log`);
non viene registrata come prova superata di questo incremento. Le verifiche
specifiche dei volumi e del tetto piano sopra elencate passano.

Questa fase rifinisce le forme della locanda. Materiali e spazio d'uso esterno
restano ulteriori passaggi del confronto artistico.

### Chiesa: frontone e copertura collegati — 20 settembre 2026

La navata cresce da 6,4 × 10,6 a 8,8 × 14,2 m: 124,96 m². Il frontone misura 5,68 m di larghezza e arriva a 8,95 m. Dietro
si innesta `Volumes/CoperturaPortale`: un corpo trasversale largo 5,68 m,
profondo 4,70 m, a quota 3 m, con gronda a 6 m e colmo a 8,80 m.
L'inserimento di 4 m raccorda le falde alla navata, il cui colmo resta a
9,20 m. Il taglio rimuove le tegole nascoste del tetto principale. Non crea
un nuovo piano interno. La porta manuale sul fianco rimane nella posizione
locale originaria: questa composizione ha ingresso laterale, non ruota la navata.
La maggiore lunghezza si sviluppa verso il retro: il centro del solo edificio
arretra di 1,80 m nel lotto, mantenendo il fronte precedente e il collegamento
stradale a z=6,40. Il lotto resta fermo; gli interni conservano i dati locali.
La migrazione registra la posa applicata e preserva eventuali spostamenti
manuali successivi. Crescere dal centro aveva ostruito l'accesso: il controllo
con capsula e camminata reale ha individuato il conflitto.

Il campanile entra per 55 cm in più nel corpo della chiesa. Il portale mantiene
una luce minima di 1,80 m anche sul frontone stretto; rosone e cornici seguono
le nuove proporzioni, senza comprimere due finestre accanto alla porta.
Una vetrata laterale riprende il ritmo dei contrafforti.

**Funzione nell'addon:** `House.masonry_trim`, disponibile anche su Volume,
sostituisce la griglia lignea con cornici e pilastri d'angolo in pietra.
È disattivata per default, salvata dalle ricette e ripristinata da Undo/Redo.
Il raccordo riusa il Volume ordinario introdotto per la locanda; non introduce
un generatore nel controller. Il campanile resta un componente ornamentale
con collisioni, senza scala o interno abitabile proprio.

**Prova visiva:** composizione e proporzioni della ricetta `chapel.tres`.
Materiali e integrazione di dettaglio restano da confrontare con la reference;
questa revisione non dichiara raggiunta la qualità finale né completa B03.

`check_chapel_composition.gd` verifica il taglio delle falde con raggi sui
triangoli, il passaggio sotto il portale con la capsula del personaggio,
cutaway, Undo/Redo, conservazione della facciata modificata e riapertura.

### Luce e occlusione del concept

L'ambiente della scena aveva già SSAO e SDFGI abilitati, ma il profilo dipinto
riduceva il raggio SSAO a 0,18 m, disattivava l'occlusione SDFGI e aggiungeva
ambiente 0,70 più luce di riempimento 0,30. Ora il profilo salvato espone
questi controlli: ambiente 0,42, riempimento 0,12, SSAO raggio 0,65 m,
intensità 1,35 e potenza 1,45; occlusione SDFGI attiva. Il sole usa una
dimensione angolare di 0,5° per la penombra. La prova a 2,2° è stata corretta:
nel confronto F7 cancellava gran parte delle ombre portate su tetto e terreno.

Audit a geometria, camera e materiali fissi: `--shadow-comparison` in
`check_borgo_recipes.tscn` varia soltanto l'angolo del sole fra 0°, 0,5° e 1°.
A 0,5° rimangono leggibili ombra della falda trasversale, rosone, portale e
sagoma proiettata a terra; a 1° queste ombre perdono già troppo contrasto.
La correzione modifica il profilo condiviso, senza dipingere ombre sulle tegole
o alterare mesh, AO e GI. Immagini di audit `captures/church_shadow_*.png`.
Riapertura del profilo corretto e confronto F7: `church_shadow_fixed.log`,
`failures=[]`; controlli delle capsule sui percorsi conservati. Immagine finale
`captures/church_shadows_fixed.png`. Questa verifica usa `--capture-only`:
la camminata completa è quella dell'incremento geometrico precedente.
La funzione dell'angolo del sole è descritta in
[Light3D](https://docs.godotengine.org/en/4.6/classes/class_light3d.html#class-light3d-property-light-angular-distance).

Inspector: `ArtStudyLayers > Profile > Painted lighting`, poi
`Regenerate art preview`. Editor e runtime leggono la stessa risorsa; F7
ripristina l'ambiente e le luci precedenti. SSAO tratta i contatti visibili;
SDFGI fornisce luce indiretta. Non è stata aggiunta una nuova soluzione GI.
Limiti della tecnica: [SDFGI Godot 4.6](https://docs.godotengine.org/en/4.6/tutorials/3d/global_illumination/using_sdfgi.html).
Le modifiche alle mesh statiche richiedono il ricalcolo della GI: il confronto
di questa revisione avviene dopo caricamento e assestamento della scena.

Verifica finale: `captures/church_final_render.log`, 12 ingressi/uscite e sei
percorsi a piedi superati, acqua e confronto F7/panoramica conservati.
1152×648, RTX 3070, 120 frame: mediana/p95 16,676/16,821 ms;
GPU 12,125/12,222 ms. Il controllo specifico della chiesa e quello generale
delle ricette passano; viene verificato anche il rifiuto della chiesa su un
lotto piccolo protetto. Immagini reali: `captures/church_composition_final.png`
e `captures/church_lighting_before_final.png` (stessa geometria/camera,
precedenti soli parametri di illuminazione).

Le sei ricette sono sotto `addons/house_builder/recipes/`:
`dwelling.tres`, `shop.tres`, `inn.tres`, `forge.tres`, `stable.tres`, `chapel.tres`.
L'ordine dei lotti del borgo è mantenuto: **casa, bottega, locanda, fucina,
stalla, cappella**. La città usa sei varianti della ricetta abitazione.
In Play, **5** raggiunge il borgo. `tools/apply_borgo_recipes.gd` applica soltanto
queste dodici ricette e controlla la conservazione degli interni; `-- --save`
salva la scena dopo la verifica. Non rigenera l'insediamento o il paesaggio.

Restano le dodici case, i rispettivi dati interni e le strade principali.
La revisione richiesta distingue anche le dimensioni funzionali dei ruoli:

| Corpo principale | Prima | Dimensioni adottate | Superficie in pianta |
| --- | --- | --- | ---: |
| Locanda | 6 × 6,4 m | 9 × 8,6 m | 77,4 m² |
| Cappella | 5,7 × 5,8 m | 8,8 × 14,2 m | 124,96 m² |
| Case ordinarie | Ingombri esistenti | Conservati | Circa 30–42 m² |

L'applicazione mirata usa `preserve_footprint=false` soltanto per locanda e
cappella, le cui ricette dichiarano larghezza e profondità. Per gli altri dieci
edifici conserva gli ingombri principali. I dodici `InteriorPlan` mantengono i
record di piani, stanze e arredi; la geometria dei solai si estende con l'involucro.
I due accessi vengono ricalcolati nelle svolte e nel punto di arrivo, mantenendo
il collegamento iniziale alla strada. Non si conserva quindi ogni coordinata
dei precedenti percorsi. Per la cappella il percorso laterale passa a 1,35 m
dal muro, invece di 0,85 m, per aggirare le basi dei contrafforti.

### Composizione corrente

| Ruolo | Caratteri architettonici della nuova revisione |
| --- | --- |
| Locanda | Corpo 9 × 8,6 m; gronda a 5,9 m e tetto alto 3,1 m; fascia a 3,2 m, 14 finestre superiori derivate e corpo trasversale sopraelevato con due finestre. Galleria `Components/GalleriaSuperiore` larga 7,83 m, aggetto 1,45 m, quota 3,45 m; portico, annesso posteriore e due abbaini su falde opposte |
| Cappella | Corpo 8,8 × 14,2 m; frontone con tetto trasversale, quattro contrafforti, tre vetrate e campanile alto 13,8 m con cuspide, base 2,9 × 2,6 m |
| Bottega | Tenda in tessuto geometrico con due pali e banco merci; sostituisce il precedente portico di tegole |
| Fucina | Muratura in pietra, pareti a 3,65 m, tetto alto 1,2 m; camino e banco con palette scura |
| Stalla | Tettoia profonda 2,0 m, ridotta da 2,4 m per esporre abbeveratoio e recinto mantenendo il passaggio attorno al palo |

La galleria della locanda usa il Balcony esistente, senza creare una nuova porta,
scala o piano interno: i due registri della facciata non aggiungono camere
giocabili al `InteriorPlan` a un piano già presente. Interni funzionali ai ruoli
rimangono un incremento distinto.

Gli arredi interni conservati non diventano per questo
un piano funzionale specifico per fucina, stalla o cappella: quello resta un
incremento distinto. Il giudizio sul ruolo riguarda per ora forme e dettagli
esterni. Le immagini finali alla camera di gioco e dall'alto mostrano proporzioni
e sagome più distinguibili fra i ruoli. Resta un laboratorio artistico: dettagli,
calore dei materiali e ricchezza della reference richiedono ulteriore confronto.

## Verifiche dell'incremento — 20 settembre 2026

### Dati e componenti della composizione corrente

I controlli seguenti sono stati ripetuti sulla nuova composizione, inclusa
l'applicazione alla scena salvata. Le prove della scena completa sono riportate
separatamente sotto; il loro esito non chiude il confronto artistico.

- `tools/check_building_recipes.gd`: **`BUILDING_RECIPE_CHECK failures=0`**.
  Contratto legacy identico senza ricetta; sei ruoli e sei varianti, semi
  distinti, idempotenza, salvataggio/riapertura, UndoRedo e figli manuali.
  Coperti anche cancellazione dopo cambio ricetta, sblocco nell'Inspector,
  parametri manuali dei volumi e migrazione delle baseline precedenti.
  `InteriorPlan` reale conserva quote e record; richieste a due/tre piani e
  riapplicazione mantengono il minimo dell'involucro e gli ornamenti sul tetto.
  Il servizio rifiuta prima di modificare la scena un tipo di dettaglio non
  registrato o dimensioni non finite/inferiori a 0,05 m.
  Esito registrato in `captures/building_recipe_check.log`.
- `tools/check_recipe_editor.gd`, attraverso il plugin con
  `-- --recipe-editor-test`: **`BUILDING_RECIPE_REAL_EDITOR_APPLY_UNDO_REDO_IDEMPOTENT_OK`**.
  Applicazione dal selettore reale, Undo/Redo del vero editor, identità dei nodi,
  ownership della scena e riapplicazione senza duplicati.
  Passa anche `BUILDING_RECIPE_REAL_EDITOR_ROLE_DIMENSIONS_KEEP_FOOTPRINT_OK`:
  scelta delle dimensioni, applicazione della tenda e locanda aggiornata.
  Questa esecuzione usa il plugin dell'editor in modalità headless; il log è
  `captures/recipe_editor_check.log`.
- `tools/check_inn_composition.gd`: **`INN_COMPOSITION_CHECK failures=0`**,
  registrato in `captures/inn_composition_check.log`.
- `tools/check_building_material_refresh.gd`:
  **`BUILDING_MATERIAL_REFRESH_CHECK failures=0`**; sei notifiche di rebuild,
  materiali aggiornati dopo la modifica differita di un Volume, mantenendo
  F7, timbri locali e geometria dell'erba. Log:
  `captures/building_material_refresh_check.log`.
- `tools/check_recipe_details.gd`: **14 tipi**, determinismo e variazione del
  seme, persistenza, figli/trasformazioni/blocchi manuali, cutaway e raggi di
  collisione. Inclusi tenda e quattro tipi gotici: portale attraversabile,
  bifore vuote controllate anche sui triangoli effettivi, monconi visibili
  durante il cutaway. Il nuovo insieme gotico della cappella contiene circa
  10.830 triangoli; la composizione è stata poi ispezionata con il renderer reale.
- `tools/apply_borgo_recipes.gd --save`: dodici edifici applicati, zero errori.
  Confronto dei dati dei dodici `InteriorPlan` invariato; invariati anche i nodi
  estranei all'intervento, inclusi terreno, boschi e acqua.

### Scena completa: composizione corrente

- `tools/check_borgo_recipes.tscn`: verifica riuscita su ingresso,
  cutaway e uscita dalle dodici porte; cammino sui sei accessi e scansione
  dell'intero percorso con il volume della capsula, senza ostacoli. La scansione
  ha guidato le correzioni agli ingombri della fucina, alla tettoia della stalla
  e al percorso esterno ai contrafforti della cappella.
  F7 andata/ritorno conserva le dimensioni; la panoramica ripristina la camera
  a 13°; presenti entrambe le acque. Log finale:
  `captures/borgo_final_render.log`, **`BORGO_CHECK_RESULT buildings=12 failures=[]`**.
  Il renderer reale termina con uscita 0, senza errori o avvisi. Panoramica,
  locanda, cappella, bottega e varianti cittadine ispezionate nella composizione
  salvata, inclusi galleria, elementi gotici e nuova tenda.
- `tools/check_meadow_encounter.tscn --full`: scena completa, quattro nemici in
  movimento, tre colpi reali, quattro morti nemiche e una del giocatore;
  ripartenza riuscita, `failures=[]` ed uscita 0 sulla composizione finale.
  Il coordinatore registra dodici turni concessi e undici attacchi iniziati;
  tutti e quattro i nemici ricevono tre turni. Log finale:
  `captures/meadow_final_render.log`.

Le esecuzioni con renderer reale sono terminate senza errori o avvisi. Nella
chiusura headless resta il precedente avviso `PagedAllocator`, distinto dai
risultati delle verifiche. Anche `check_integrated_landscape.gd` è passato:
la diagnosi ha trovato l'annesso posteriore di `CasaCitta_03` nell'avvicinamento
a `CasaCitta_00`; spostato l'annesso lateralmente, il percorso è tornato libero.
La verifica è passata correggendo l'ingombro, senza allentare l'asserzione.

### Misure locali

Forward+ / D3D12, RTX 3070, viewport reale **1152×648**, 120 frame campionati.
Il borgo usa la scena completa con incontro disattivato e 100 frame di
assestamento nell'inquadratura; il combattimento usa `--full` e 120 frame di
assestamento prima del campionamento.

| Scena | Intervallo frame mediana / p95 | GPU viewport mediana / p95 |
| --- | ---: | ---: |
| Borgo, camera di gioco, composizione finale | 16,677 / 16,859 ms | 5,965 / 6,258 ms |
| Radura, combattimento completo, composizione finale | 16,678 / 16,859 ms | 6,182 / 6,251 ms |

La misura del borgo include tutta la geometria finale e gli accessi corretti.
Anche il combattimento usa la scena completa con la stessa composizione finale.
Gli intervalli includono l'attesa di presentazione e non garantiscono lo stesso
budget in ogni punto della mappa o su altri computer.

Immagini reali in `captures/borgo_gameplay.png`, `borgo_overview.png`,
`borgo_dwelling.png`, `borgo_shop.png`, `borgo_inn.png`, `borgo_forge.png`,
`borgo_stable.png`, `borgo_chapel.png` e `borgo_city_variants.png`.
La prova della scena non chiude le macrofasi G01.4/S02 o i criteri di editing
adattivo.

## Sviluppi successivi

- **B01:** facciata adattiva su rettangolo, anteprima durante il drag, elementi
  manuali protetti, conflitti visibili e un Undo per gesto.
- **B02:** campate, travi e cornici che seguono davvero aperture e dimensioni.
- **B03:** raccordi e dipendenze fra volumi/accessori, mantenendo override e ID.
- **G01.4:** catalogo collegato al planner e famiglie sostituibili.
- **S02:** aggregazioni e tetti più articolati con interni coerenti, oltre al
  prototipo locale. L'audit A07 mantiene aperto il confronto R10/R13.

Fonti di stato: [roadmap architettonica](ARCHITECTURE_GENERATOR_ROADMAP.md),
[roadmap del mondo](WORLD_GENERATION_ROADMAP.md),
[scena integrata](INTEGRATED_LANDSCAPE.md).


### Campione: portale incassato della chiesa

Il componente `gothic_facade` espone `portal_recess_depth` nell'Inspector
(metri; zero conserva il portale precedente). La ricetta `chapel` usa 0,76 m
entro una facciata profonda 1,60 m. Tre ordini arretrati di stipiti e conci
separati da giunti reali restringono l'imbocco da 2,24 a 1,56 m; la porta
esistente da 1,40 m resta nella sua posizione. Il sopraluce arretrato e la
soglia a filo terreno completano il campione. Spessore e ombre sono geometrici.

Il servizio ricette salva il parametro, conserva gli override manuali e lo
ripristina con Undo/Redo. Le collisioni laterali lasciano libero il corridoio;
il cutaway usa la stessa pipeline della facciata. Nessun generatore parallelo.

`tools/check_chapel_composition.gd` verifica geometria profonda, determinismo,
corridoio, override e riapertura. La verifica del borgo accetta
`--portal-closeups` per aggiungere `captures/church_portal_close.png`.
Il rosone incassato è descritto sotto; i raccordi dei contrafforti restano un campione successivo.

Validazione del campione (1152x648, RTX 3070): composizione della chiesa,
ricette e dettagli passano; nella scena completa passano 12 ingressi/uscite,
sei percorsi a piedi, F7 e panoramica. Frame mediano 16,679 ms, p95 16,825 ms;
GPU mediana 5,866 ms. Sono misure della macchina attuale, non un budget
universale. Log: `captures/portal_render.log`. Il dettaglio obliquo viene
salvato in `captures/church_portal_oblique.png`.


### Rosone incassato

`gothic_facade.rose_recess_depth` controlla l'arretramento della vetrata
(zero mantiene il rilievo precedente). La ricetta della chiesa usa 0,10 m,
circa 0,22 m dal bordo esterno della cornice al fondo. Questo tiene conto
anche del rivestimento sporgente del frontone retrostante: il vetro rimane davanti alla sua
muratura. La facciata ha un'apertura circolare reale, una strombatura in
pietra e una cornice di 24 conci con giunti geometrici. I dodici settori
colorati e i raggi seguono la vetrata arretrata.

Il parametro usa Inspector, servizio ricette, override manuali e
salvataggio esistenti. La profondita' viene limitata dallo spessore della
facciata; in altre composizioni va verificato anche il corpo retrostante.
Il rosone resta una vetrata opaca decorativa, non una nuova apertura
trasparente verso l'interno dell'edificio.

Il test di composizione verifica con un raggio che davanti al vetro non
restino triangoli della parete e che la parte bassa del vetro superi il
rivestimento del corpo retrostante, oltre a determinismo, override e riapertura.
`--rose-closeup` nella verifica del borgo produce `captures/church_rose_close.png`.


### Raccordo tegole e cornice del frontone

La cornice inclinata di `gothic_facade` fornisce regioni di esclusione alla
pipeline `MeshJoin` dei tetti della casa e dei volumi collegati. Le regioni
usano gli stessi segmenti della pietra visibile, con 15 mm di margine:
le tegole vengono tagliate localmente senza modificare muri o collisioni.
Con `masonry_trim` anche le cornici dei frontoni del corpo edilizio e
il colmo in pietra escludono le tegole dal loro volume. Sui frontoni in
pietra, le file terminali finiscono sulla faccia interna della cornice:
non mantengono lo sbalzo di 30 cm previsto per il tetto senza cornice.
Trasformazione, dimensioni, cambio di tipo e rimozione della facciata
invalidano il raccordo tramite la rigenerazione esistente.

Il controllo della chiesa campiona entrambi i lati della cornice: rileva
le intersezioni nella copertura originale e verifica che non rimangano
in quella raccordata. Verifica anche l'aggiornamento dopo lo spostamento
della facciata nell'editor.
