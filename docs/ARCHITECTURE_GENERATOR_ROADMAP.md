# Piano evolutivo dei generatori architettonici

Aggiornato: **2026-09-14**. Baseline iniziale: `e0c9cd5`; incrementi successivi documentati sotto.
Stato: **builder in sviluppo; priorità alla costruzione architettonica assistita**.
Questo documento è il registro da aggiornare a ogni incremento, non una lista di
funzionalità già disponibili.

## Direzione attuale — costruzione assistita prima della generazione globale

Il numero di villaggi/case/castelli è contenuto: per ora non serve moltiplicare layout completi tramite seed. Priorità alle geometrie architettoniche e agli strumenti con cui utente e assistente costruiscono una scena da disegno, cartina o screenshot. Le quantità citate (quattro villaggi, circa cento case, quattro castelli) sono una motivazione della scelta, non un budget definitivo approvato.

L'interazione desiderata è quella di un builder reattivo: l'utente modifica un volume e regole locali propongono/adattano finestre, campate e dettagli. La reference Tiny Glade descrive questo obiettivo d'interazione; non richiede di copiarne il rendering. Conservare i generatori e i seed esistenti come infrastruttura, ma rimandare varietà del planner, città automatiche e confronto dei quattro castelli generati. Il confronto potrà tornare quando utile allo strumento.

**Priorità richiesta: completare prima A07; poi B01.1, facciata assistita su una casa rettangolare.** Il ramo ambientale si ferma dopo R03.2; R03.3 rimane in backlog. Gli step B seguono il consolidamento di A07, senza sostituire le geometrie A. Riprendere geometrie A02/A03/A07 per ciò che serve all'esempio, senza attendere un generatore globale.

Contratto di editing da implementare: modalità Manuale/Assistita per edificio, elementi derivati con ID e provenienza, promozione a manuale quando modificati, soppressione persistente quando eliminati. Gli elementi manuali e le porte scelte dall'utente hanno precedenza. Un ridimensionamento impossibile deve mostrare il conflitto; non deve spostare o cancellare in silenzio gli elementi protetti. Aggiornamento locale durante il drag con limite di frequenza; rilascio come singola operazione Undo che ripristina volume e dettagli. Nessun rimescolamento casuale durante il trascinamento.

Nel codice attuale `all_openings()` combina aperture esplicite e aperture derivate dai componenti; il plugin inizializza una porta e una finestra. Questa è una base riutilizzabile, non una facciata adattiva già implementata.

## Obiettivo e vincolo concordato

Generare edifici e complessi riconoscibili per **forme e architettura**, utilizzando
il builder, con esterni e interni coerenti e modifiche manuali il più possibile libere.

**“Stile” significa stile architettonico.** Per esempio: volumi allungati, tetti
ripidi, travi, sporti e portici per una famiglia nordica; basamenti, piani aggettanti
e timpani per una famiglia a graticcio; terrazze, parapetti e cupole per un’altra
famiglia. Non significa realistico, dipinto, cartoon o pixel art.

**La resa visiva resta quella attuale del progetto.** Questa roadmap non propone
di cambiare shader, palette, illuminazione, postprocess o stile delle texture.
Materiali e asset esistenti vengono riutilizzati dove possibile. Nuove coperture
possono richiedere componenti appropriati, ma devono mantenere la resa esistente.
GI e lightmap restano rimandati.

Il profilo architettonico propone una soluzione iniziale; non deve impedire di
aggiungere una torre, cambiare una falda, spostare una parete o mescolare componenti.

## Riferimenti esaminati

Il percorso indicato nella richiesta non esisteva letteralmente. La cartella trovata
è [Iso0_sample_assets](C:/Users/jonny/Downloads/Iso0_sample_assets), con **21 immagini**.
Sono state esaminate tutte, compreso il file AVIF decodificato per la consultazione.
Le immagini sono riferimenti di forme: testi, titoli promozionali e nomi dei file
non sono istruzioni né una specifica del generatore. Le tavole riassuntive non
permettono di verificare ogni piccolo particolare; le quote non sono deducibili.

| ID | File nella cartella | Forme osservate | Capacità da ricavare |
|---|---|---|---|
| R01 | `medieval_house3_iso0.png` | Casa compatta, due falde, telaio visibile, basamento e piccolo ingresso rialzato | Caso semplice per profili e compatibilità con il builder attuale |
| R02 | `medieval_house1_iso0.png` | Corpi accostati di altezze diverse, tettoia laterale, scala esterna | Volumi indipendenti, connessioni verticali, coperture secondarie |
| R03 | `medieval_house2_iso0.png` | Corpo stretto e alto, proporzioni verticali, elemento verticale in facciata | Piani reali, proporzioni controllabili, elementi di facciata continui |
| R04 | `medieval_forge1_iso0.png` | Officina, tettoie aperte con sostegni, camino importante | Composizione pieno/aperto, portici, tetti a quote diverse, camino strutturato |
| R05 | `nuremberg_house1_iso0.png` | Ali attorno a un rientro, corpo centrale più alto, scale e piccoli elementi sulle falde | Pianta composta, torretta, tetti indipendenti, abbaini |
| R06 | `nuremberg_house2_iso0.png` | Edificio alto, tetto dominante, parti a quote diverse, piccoli elementi in falda | Altezze per piano, sottotetto e coperture articolate |
| R07 | `nuremberg_ruin1_iso0.png` | Copertura mancante, travi esposte, pareti danneggiate e macerie | Danno della struttura, non solo variazione superficiale |
| R08 | `middleeastern_house1_iso0.png` | Corpo a tetto piano con parapetto, pergola e pilastri | Terrazza, parapetti, copertura aperta e sostegni |
| R09 | `middleeastern_house2_iso0.png` | Corpi sovrapposti, copertura piana e cupola, aperture ad arco | Volumi a gradoni, cupola, archi e connessioni tra livelli |
| R10 | `elven_house1_ios0.png` | Masse arrotondate, coperture curve molto alte, aperture slanciate | Piante non rettangolari, profili curvi e coperture controllabili |
| R11 | `8c7e316457a377f6d841165ca88abecf.jpg` | Sezione di edificio nordico con struttura lignea, spazio centrale e arredo laterale | Struttura portante, sala comune, spazio sotto la copertura |
| R12 | `isometric-viking-hall-v0-tu2yfa4n6ule1.webp` | Sala lunga aperta in sezione, file di sostegni, tavoli, zona terminale rialzata | Navate funzionali, pilastri e arredo coerenti con la struttura |
| R13 | `r-rainbow-avikings04.jpg` | Corpi di altezze differenti, tetti molto caratterizzati, piattaforma su sostegni e pontile | Tetti sagomati, torri lignee, piattaforme, fondazioni e passerelle |
| R14 | `images (2).jpg` | Esterno con telaio ligneo e tetto dominante; piccola vista interna | Coerenza tra involucro e interno; dettagli fini da verificare su riferimenti migliori |
| R15 | `file (1).jpg` | Tavola con capanne, case allungate, torri circolari, recinti e coperture diverse | Vocabolario di componenti riutilizzabili e proprietà composte |
| R16 | `file.jpg` | Tavola di molte varianti a scala ridotta | Famiglie di proporzioni e composizioni; non ricavare dettagli costruttivi dai thumbnail |
| R17 | `4WqSf8.jpg` | Mastii, complessi fortificati, corti, stalle e corpi accessori | Castle Builder come compositore di edifici, mura e accessi |
| R18 | `IsPs64.jpg` | Chiese, torri, porte fortificate e segmenti murari | Navate, torri, fronti monumentali, mura concatenate; casi successivi opzionali |
| R19 | `Ox0WU5.jpg` | Complesso fortificato inserito in un tessuto di edifici | Gerarchia dei volumi, ingombri composti e relazione con il villaggio |
| R20 | `uYx3kY.jpg` | Castello con torri circolari, cortile, ingresso e scala, corpi esterni | Percorsi sulle mura, quote, porta principale e corti interne |
| R21 | `medieval-castle-modern-office-transformation-generative-ai_804788-79551.avif` | Castello a torri quadrate di diverse altezze, merli, contrafforti, ingressi e coperture interne ai coronamenti | Torri composte, coronamenti, contrafforti e collegamenti verticali; nessuna adozione della resa grafica |

Le immagini esterne non documentano automaticamente gli interni. Per quei casi
la planimetria sarà una proposta di gameplay coerente con l'involucro, non una
ricostruzione presunta del riferimento. R11 e R12 forniscono invece indicazioni
interne visibili da usare come casi di prova.

## Diagnosi: cosa manca davvero

Il divario principale è il **vocabolario delle forme**. Cambiare texture o assegnare
un'etichetta a una casa rettangolare non basta a ottenere gli edifici osservati.

Le priorità geometriche sono:

1. Più volumi, con dimensioni, quota, orientamento e connessioni propri.
2. Piani e coperture indipendenti: la casa alta non è soltanto una parete più alta.
3. Parti aperte: portici, tettoie, pergole, ballatoi e passaggi sotto un volume.
4. Facciate organizzate per campate, con supporti e aperture coerenti.
5. Interni costruiti sullo stesso involucro degli esterni.
6. Torri, mura e corti come composizioni, non come varianti di una singola casa.
7. Forme curve e danni strutturali dopo la stabilizzazione di quelle precedenti.

## Base esistente da preservare

| Area | Già presente nel codice/documentazione consultati | Limite da superare |
|---|---|---|
| House Builder | Rettangolo, una ala a L, aperture modificabili, spessore dei muri e collisioni | Un corpo principale e una sola ala; vincoli impliciti sulle coperture |
| Coperture | Tegole geometriche, danni, raccordo della casa a L | Poche famiglie di tetti e controllo legato alla casa |
| Interni | Piani, stanze, muri, scale, mobili sotto le stanze, proposta iniziale e protezione delle modifiche | Planimetrie soprattutto rettangolari; supporto parziale dell'ala; scala e corridoio con configurazione guidata |
| Contratto edificio | `building_request.gd`: tipo, ingombro rettangolare, piani, seed, lato ingresso | Tipi hardcoded; stile architettonico non distinto dalla funzione e dal benessere |
| Villaggio | Corti, lotti, strade, percorsi condivisi, densità, esclusioni, suolo e Play | Ingombri e accessi devono evolvere per complessi non rettangolari |
| Editing | Undo/redo, IDs e baseline per alcune categorie, nodi dati persistenti | La geometria esterna generata è una cache interna, non ancora un insieme di parti architettoniche liberamente editabili |

Riferimenti tecnici: [House Builder](HOUSE_BUILDER.md), [interni](HOUSE_AUTHORING.md),
[Village Builder](VILLAGE_BUILDER.md), [contratto edificio](../addons/house_builder/building_request.gd),
[generatore casa](../addons/house_builder/house.gd), [elementi interni](../addons/house_builder/plan_element.gd).
La documentazione più vecchia contiene descrizioni del prototipo: verificare sempre
il codice e il relativo Play prima di dichiarare una capacità completata.

## Architettura dei dati proposta

Nomi indicativi, da consolidare nella prima fase; **non sono API già implementate**.

### Profilo architettonico, funzione e stato sono distinti

| Dato | Esempi | Responsabilità |
|---|---|---|
| `architecture_profile` | `nordic_timber`, `central_european_half_timber`, `flat_roof_courtyard`, `elven_curvilinear` | Preferenze di forme, proporzioni, struttura, coperture e componenti |
| `archetype_id` | abitazione, fucina, sala comune, stalla, torre, porta fortificata | Organizzazione funzionale, spazi e collegamenti necessari |
| `condition` | integro, usurato, parzialmente crollato | Stato della struttura; usura e crollo non sono la stessa proprietà |
| `scale / capacity` | dimensioni, numero di piani, occupanti previsti | Entità della proposta; senza confondere una torre con una casa semplicemente scalata |
| `seed` e seed locali | edificio, tetto, arredo | Riproducibilità senza rimescolare tutto quando cambia una parte |

Le label sono nomi leggibili per risorse con ID stabili, non stringhe libere che
il generatore deve “indovinare”. Il profilo contiene componenti consentiti alla
generazione e preferenze ponderate; l'editor manuale può usare anche altri componenti.
Un profilo mancante deve avere un fallback esplicito, non cancellare la geometria.

Esempio: **Fucina + nordico ligneo** propone sala di lavoro, camino e tettoia con
proporzioni nordiche. Posso aggiungere una torre in pietra o sostituire il tetto
della sola tettoia senza cambiare profilo all'intero edificio.

### Separazione delle scale

`Regione → Insediamento → Proprietà / Complesso → Edificio → Volume / Piano → Stanza → Elemento`

- L'insediamento assegna area, accessi, programma funzionale e profilo preferito.
- Un compositore di proprietà o castello dispone edifici, corti, mura e connessioni.
- L'House Builder costruisce i singoli edifici e il loro involucro.
- Il sistema degli interni usa lo stesso involucro per stanze, scale e passaggi.
- L'arredo usa funzione, ingombri e collegamenti, senza dipendere dal Village Builder.

Il contratto verso il livello superiore deve restituire ingombri effettivi,
accessi con quota e orientamento, altezze e aree da mantenere libere. Per un castello
non basta un rettangolo o un singolo ingresso. Usare un'approssimazione semplice per
la ricerca iniziale e poligoni/componenti reali per la verifica finale.

Non creare un unico algoritmo universale per stanze, villaggi e castelli. Condividere
ID, transazioni, vincoli geometrici, profili e presentazione delle proposte; mantenere
separati gli algoritmi e le regole di ciascuna scala.

## Libertà manuale: requisiti non negoziabili

- Ogni volume, falda, apertura e componente significativo deve avere identità propria.
- Distinguere proprietà ereditate dal profilo, generate e impostate dall'utente.
  Una modifica alla finestra non deve congelare tutta la casa.
- Priorità proposta: valore manuale della proprietà → override del componente →
  valore generato → default del profilo. Cambiare profilo aggiorna solo quanto eredita.
- Rigenerare una selezione o una categoria, con confronto delle modifiche prima di applicare.
- Conservare elementi manuali, rinomine, blocchi e cancellazioni intenzionali.
- Cambiare la gerarchia non deve spostare accidentalmente oggetti nel mondo.
  Stanze possiedono mobili; muri condivisi e collegamenti hanno proprietari espliciti.
- Permettere di trascinare scene personali e scegliere agganci opzionali a muro,
  pavimento, bordo del tetto o terreno. Consentire anche il posizionamento libero.
- Prevedere **Rendi indipendente** per una parte: estrazione in nodi/mesh ordinari,
  non più sovrascritti dalla generazione. Non promettere un editor di vertici completo
  dentro Godot: per modifiche arbitrarie della mesh resta possibile un editor esterno.
- Un elemento indipendente può essere sostituito/importato; riagganciarlo richiede
  descrivere ingombro e connessioni. Non presumere che qualsiasi mesh sia di nuovo parametrica.
- Un'incompatibilità con lo stile è un avviso, non un divieto. Una stanza non
  raggiungibile può restare come bozza con errore evidente; la proposta automatica
  non deve applicare silenziosamente un layout non percorribile.
- Dati non validi per costruire la mesh bloccano quella generazione mantenendo
  l'ultimo risultato valido. Non impediscono di correggere altre parti dell'edificio.

## Modularità per aggancio: terrazze, balconi e aperture automatiche

Requisito aggiunto il 2026-09-13: **terrazze e componenti devono poter essere
attaccati all’edificio come le finestre, adattando il supporto quando necessario**.
È fattibile; la prima versione deve supportare relazioni geometriche definite,
poi ampliare gli agganci. Non serve iniziare da operazioni booleane arbitrarie
tra qualsiasi coppia di mesh.

### Un componente comprende geometria e richiesta di adattamento

Esempio **balcone**:

- Geometria: pavimento, bordo, parapetto, eventuali mensole o pilastri.
- Aggancio: facciata identificata stabilmente, posizione locale, quota e orientamento.
- Adattamento: crea una porta di accesso, oppure usa una porta esistente scelta
  dall’utente. Il foro riguarda entrambe le facce del muro e la collisione.
- Connessione: dichiara il passaggio tra piano interno e superficie del balcone.
- Vincoli: soglia alla quota corretta, vano libero, nessun sostegno davanti alla porta.

Una **terrazza** può essere addossata al fabbricato, su sostegni, sopra un volume
oppure indipendente. Non implica sempre un buco nel muro: l’utente sceglie
**Porta nuova / Apertura esistente / Nessun accesso al muro**. La proposta può
suggerire l’opzione, ma non deve cancellare automaticamente una porzione arbitraria
di facciata o trasformare una finestra scelta a mano senza anteprima.

| Componente | Supporto / aggancio | Adattamento possibile |
|---|---|---|
| Finestra / porta | Parete | Vano, imbotti e collisione |
| Balcone / terrazza addossata | Facciata e quota di piano | Porta, soglia, pavimento esterno e parapetto |
| Scala esterna | Terreno/pianerottolo e accesso superiore | Connessione fra quote e apertura nel parapetto |
| Scala interna | Due piani | Foro nel solaio, protezioni sul bordo e sbarchi liberi |
| Abbaino | Falda | Taglio della copertura, pareti laterali e raccordo del piccolo tetto |
| Camino | Volume/copertura | Attraversamento della falda e raccordo; nessun foro nel solaio senza specifica |
| Portico / pergola | Facciata oppure terreno | Sostegni e copertura; apertura nel muro solo se richiesta |
| Torre / ala | Volume o bordo di un complesso | Pareti condivise e passaggio esplicito fra i corpi |

### Come devono sopravvivere le modifiche

Memorizzare `component_id`, `host_id`, riferimento alla faccia/superficie,
trasformazione locale e richiesta di apertura. Non agganciarsi al numero di un
triangolo della mesh rigenerata. I nomi sono indicativi; l’implementazione userà
risorse/dati versionati con adattatore per le aperture attuali.

Il foro resta un dato derivato dall’aggancio. Spostando il balcone si aggiorna
l’apertura associata; rimuovendolo si chiude soltanto l’apertura creata dal componente
che non sia stata resa manuale o condivisa. Una porta preesistente o modificata
dall’utente va conservata. Più componenti che usano lo stesso accesso devono
condividerne il riferimento, non creare vani sovrapposti.

Quando cambia il supporto: ricostruire facciata, vano, collisione e raccordi
interessati, senza rigenerare l’arredo o tutto l’edificio. Se il supporto viene
eliminato, mantenere il componente come **aggancio da riparare**, con evidenziazione
e comandi **Riaggancia / Rendi indipendente / Rimuovi**.

UI: scegli il componente, punta una superficie compatibile, vedi anteprima di
volume e taglio, poi posiziona. Dopo il posizionamento, gizmo locali per larghezza,
profondità e quota; aggancio magnetico disattivabile. Fuori dai casi supportati,
consentire la composizione indipendente e dichiarare che il raccordo automatico
non è disponibile, senza vietare l’editing.

### Primo caso completo: A02a

- [x] Balcone rettangolare agganciato a una parete piana, con porta nuova o esistente.
- [x] Spostamento e ridimensionamento con aggiornamento del vano e della collisione.
- [x] Quota collegata al piano; soglia e parapetto coerenti.
- [x] Undo/redo e riapertura ripristinano componente e foro insieme.
- [x] Rimuovere il balcone conserva una porta preesistente/manuale e rimuove soltanto
  un vano derivato non più utilizzato.
- [x] Provare il passaggio interno→balcone con il giocatore.
- [ ] Poi estendere a terrazza su pilastri e scala esterna; abbaini e solai vengono
  dopo, riutilizzando lo stesso meccanismo di dipendenze.

A02a parte dopo A01, usa un edificio esistente e precede il completamento del
sistema multi-volume: rende subito verificabile la modularità senza attendere
castelli e forme curve. Piani/interazioni necessari al test riusano il prototipo
attuale e vengono consolidati in A04.

## Sequenza di implementazione

Stati: `TODO`, `IN CORSO`, `VERIFICA`, `FATTO`, `BLOCCATO`.
Ogni fase deve produrre un esempio editabile e un risultato verificabile, evitando
un lungo refactoring senza qualcosa da provare nel builder.

| ID | Stato | Incremento | Dipendenze | Esempio / criterio di uscita |
|---|---|---|---|---|
| A00 | FATTO | Analisi delle 21 immagini e roadmap | — | Inventario e vincolo: architettura, resa attuale invariata |
| A01 | FATTO | Profilo architettonico minimo e contratto versionato | A00 | Preset, editing preservato, container Components e ID persistenti |
| B01.1 | TODO | Facciata assistita: finestre su volume rettangolare | A07 prima, A01 e aperture esistenti | Allarga/restringi: numero e spaziatura si adattano; porte e finestre manuali preservate; Undo completo |
| B01.2 | TODO | Editing e diagnostica degli elementi automatici | B01.1 | Seleziona, rendi manuale, elimina senza ricomparsa; conflitti e modalità evidenti nell'UI |
| B02 | TODO | Campate e dettagli coerenti | B01.2, A03, A05 | Travi, davanzali e cornici seguono facciata e aperture senza ostruire i vani |
| B03 | TODO | Assistenza nei raccordi fra volumi e accessori | B01.2, A02, A03 | Balcone/portico/volume agganciato aggiorna aperture e struttura; override preservati |
| B04 | TODO | Esempio costruito da reference tramite builder | B01.2, geometrie A necessarie | Casa o piccolo complesso editabile, costruito con gli strumenti senza mesh ad hoc |
| A02a | IN CORSO | Componenti agganciati: balcone + porta | A01 | Vano, collisione e aggancio aggiornati senza perdere le modifiche manuali |
| A02 | IN CORSO | Composizione di più volumi rettangolari | A01 | Fucina R04 con corpo e tettoie modificabili indipendentemente |
| A03 | IN CORSO | Coperture indipendenti e parti aperte | A02 | Falde a quote diverse, portico e tetto piano; raccordi senza geometria interna superflua |
| A04 | TODO | Piani e interni coerenti con i volumi | A02, A03 | Casa R02: ingresso, scala esterna/interna, piano superiore percorribile |
| A05 | TODO | Facciate e strutture per campate | A03, A04 | Graticcio e portico: travi e aperture seguono la struttura senza invadere i vani |
| A06 | TODO | Due archetipi completi con profili architettonici | A04, A05 | Fucina e sala nordica: differenze leggibili nelle forme e negli interni |
| A07 | IN CORSO | Piante poligonali, torri e coperture curve | A03–A06 | Torre quadrata/circolare, terrazza con cupola; caso elfico separato |
| A07.4 | FATTO | Torri segmentate a 8/12/16 facce | A07.1 | Vani obliqui, collisioni, parapetti e salvataggio coerenti; campionario editabile |
| A07.5 | FATTO | Copertura conica della torre | A07.4 | Tetto indipendente e parametrico, gronda e raccordo al corpo, gestione accesso al tetto |
| A07.6 | FATTO | Cupola e profilo curvo | A07.5 | Edificio terrazzato con cupola; controlli leggibili e copertura separata |
| A07.6a | FATTO | Profilo a cupola sulle torri | A07.5 | Cupole basse/slanciate, tegole e collisioni; salvataggio e regressione cono |
| A07.6b | FATTO | Cupola su edificio terrazzato | A07.6a | Esempio con terrazza accessibile e volume coperto separato, raccordi e percorso verificati |
| A07.7 | TODO | Consolidamento A07 e percorso giocabile | A07.4–A07.6 | Aperture, interni e raccordi coerenti con la pianta; verificare limiti delle stanze e accessi |
| A08 | IN CORSO | Primo Castle Builder: cortina, torri e porta | A04, A07 | Castello piccolo con cortile e percorso giocabile ingresso→mura→torre |
| A09 | IN CORSO | Complessi articolati e castelli multilivello | A08 | Mastio, corpi accessori, più corti, raccordi e quote indipendenti |
| G01 | RIMANDATO | Composizione da metadati, separata dai builder | A01, A08, A09 | Piano riproducibile, varianti strutturali, editing protetto |
| A10 | TODO | Rovine strutturali controllabili | A03, A04, A07 | R07: togli una porzione di tetto/muro, interno e collisione coerenti |
| A11 | TODO | Integrazione insediamento e consolidamento | Incrementale; chiusura dopo A08 | Case e castello nello stesso villaggio, rigenerazione locale e budget misurati |
<!-- WORLD_PIPELINE_START -->

| ID | Stato | Incremento ambientale / integrazione | Dipendenze | Esempio / criterio di uscita |
|---|---|---|---|---|
| G01.3b.2b | FATTO | Diagnostica ingombri e verifica editor/Play | Pipeline mondo | Proposta comprensibile, Undo/Redo reali, passaggi percorribili |
| R01 | IN CORSO — prototipo disponibile | Generatore di singola roccia/affioramento | Pipeline mondo | Seed, dimensioni, piani di frattura, stratificazione, spigolosità; 6 varianti con stesso linguaggio geometrico; collisione semplice |
| R02 | IN CORSO — R02.1–R02.3 verificati | Composizione di gruppi rocciosi | Pipeline mondo | Path/area, direzione dominante degli strati, masse grandi/medie/piccole; variazione locale senza distruggere i pezzi spostati a mano |
| R03 | IN CORSO — R03.1–R03.2 verificati | Pareti e creste montuose | Pipeline mondo | Pareti fra piattaforme piane, quote discrete, rampe brevi e passaggi riservati, assenza di compenetrazioni macroscopiche; LOD e budget misurati |
| R01.1 | FATTO | Roccia parametrica | Pipeline mondo | Sei varianti, seed e collisione verificati |
| R02.1 | FATTO | Gruppi su guida | Pipeline mondo | ID e modifiche manuali preservati |
| R02.2 | FATTO | Fascia libera | Pipeline mondo | Diagnostica geometrica e gizmo contestuale |
| R02.3 | FATTO | Addensamenti e raccordi | Pipeline mondo | Picchi condivisi, basi sovrapposte e 12 seed verificati |
| R03.1 | FATTO | Terrazza piana | Pipeline mondo | Quota discreta, volume solido, salvataggio e Undo/Redo |
| R03.2 | FATTO | Accesso alla terrazza | Pipeline mondo | Rampa, varco e salita/discesa del giocatore verificati |
| R03.3 | TODO | Ciglio e sagoma della terrazza | Pipeline mondo | Raccordo terra/roccia, bordo meno rettangolare, piano e accesso preservati |
| W01 | TODO | Laghi editabili | Pipeline mondo | Perimetro e quota dell'acqua, riva e bacino, esclusione edifici; superficie d'acqua inizialmente semplice |
| W02 | TODO | Fiumi editabili | Pipeline mondo | Spline, larghezza/profondità, profilo discendente e confluenze; raccordo alle quote dei laghi; niente flussi in salita |
| W03 | TODO | Attraversamenti e rive | Pipeline mondo | Ponti, guadi, approdi, passaggi e accessi alle sponde; terreno/rocce/strade leggono gli stessi vincoli |
| C01 | TODO | Ingressi di grotta | Pipeline mondo | Apertura reale nel blocco roccioso, soglia percorribile, collisione coerente e leggibilità alla camera fissa |
| C02 | TODO | Piano di grotta | Pipeline mondo | Stanze/cunicoli con anelli e diramazioni, quote e collegamenti; editing manuale separato dall'involucro esterno |
| G01.4 | TODO | Catalogo architettonico | Pipeline mondo | Ruoli del piano associati a profili/componenti; famiglie sostituibili senza cambiare il planner |
| G01.5 | RIMANDATO | Varietà compositiva del castello | Pipeline mondo | Recinti segmentati, più torri/corpi, corti e gerarchie differenti; preservazione manuale |
| S01 | RIMANDATO | Composizione urbana organica | Pipeline mondo | Strade principali e secondarie, piazze, porte, edifici gerarchizzati, addensamenti e vuoti; insediamenti su piani/terrazze, collegamenti ai vincoli del paesaggio |
| S02 | TODO | Edifici urbani più articolati | Pipeline mondo | Volumi aggregati, tetti collegati, facciate e accessori; le città cambiano forma oltre al colore |
| V01 | RIMANDATO | Confronto dei quattro castelli | Pipeline mondo | Quattro richieste/seed tramite tool, scene editabili e stessa camera; almeno due organizzazioni strutturali distinte |
| V02 | TODO | Vertical slice città–villaggio–POI | Pipeline mondo | Tempi reali di cammino, incontri, visibilità e streaming; aggiornamento delle distanze proposte dal concept |
<!-- WORLD_PIPELINE_END -->


### A01 — Prima implementazione consigliata

- [x] Introdurre una risorsa `ArchitectureProfile` minimale con ID, nome e parametri
  geometrici già supportati; nessun framework di regole generale in questo passo.
- [x] Separare il ruolo dell'edificio dal profilo. Migrare l'enum attuale con un
  adattatore compatibile, conservando la scelta esistente.
- [x] Versionare i nuovi dati e preservare i vecchi salvataggi.
- [x] Rendere visibile nell'UI cosa eredita il profilo e cosa è manuale.
- [x] Dimostrare che cambiare profilo non cancella un'apertura modificata.
- [x] Preparare il contenitore per componenti con ID, senza riscrivere subito tutto
  `house.gd`: il vecchio generatore resta il primo backend.

**Uscita:** due preset geometrici distinguibili usando il vocabolario già disponibile,
stessa resa attuale; una vecchia casa e il villaggio di esempio funzionano ancora.
Il supporto architettonico completo dei riferimenti non viene dichiarato in A01.

**A01.1 verificato — 2026-09-13.** Due risorse di proporzioni: compatta a graticcio
e corpo nordico allungato. Esempio editabile in
`scenes/dev/architecture_profiles_example.tscn`, con terza casa allungata manualmente
a 14 m. Materiali e vocabolario costruttivo restano quelli esistenti: il secondo
preset non implementa ancora l'architettura nordica completa.
Il pannello Casa distingue adozione esplicita delle quattro proporzioni e cambio
che conserva quelle manuali. Il riconoscimento usa il confronto con i valori
precedentemente ereditati, non blocchi espliciti per proprietà. Le richieste del
villaggio conservano impronta e altezza assegnate; possono ereditare il tetto.
Verificati riapertura, aperture conservate, undo/redo editor e regressioni villaggio
con `check_architecture_profiles.gd`, `check_house_editor.gd` e
`check_village_builder.gd`. Il ruolo separato è un dato: non aggiunge ancora nuove
regole di distribuzione per sala o fucina.
**A02a.1 verificato — 2026-09-13.** `Components/Balcone` salva un ID persistente
locale alla casa e un host semantico (`main/front`, `main/back`, `main/right`,
`main/left`). La duplicazione nella stessa casa assegna un nuovo ID. Porta e vano
sono derivati dal componente; le aperture manuali restano dati indipendenti.
Il tab Componenti offre posizionamento con anteprima, tre maniglie contestuali,
rimozione e messaggi di errore. Una configurazione invalida non genera un foro;
il contorno selezionato diventa rosso. Sono controllati bordo, altezza, ala che
copre la facciata, aperture manuali e balconi sulla stessa facciata.
Esempio: `scenes/dev/balcony_attachment_example.tscn`, con due piani e scala.
Verifiche: collisione del vano/pavimento, spostamento, cancellazione, riapertura,
ID, conservazione di accesso manuale; undo/redo nell'editor; giocatore reale che
sale, esce sul balcone e rientra (`check_balcony_attachment.gd`,
`check_house_editor.gd`, `check_balcony_play.gd`).
Il test gameplay headless completa tutte le asserzioni ed esce con codice 0;
il motore segnala a chiusura `PagedAllocator: Pages in use` e GPUTrail segnala
il refresh rate non disponibile. Questi messaggi restano da investigare separatamente.
**A02a.2 verificato — 2026-09-13.** Il tab Componenti ora permette di collegare
il balcone a un piano e a una porta manuale. Gli ID sono salvati nei dati del piano
(metadata `floor_id`) e dell'apertura (`opening_id`); la posizione nell'elenco e il
nome del nodo non sono l'identità. La quota effettiva segue l'altezza dei piani;
la porta referenziata determina facciata e posizione orizzontale. Applicare un
piano a un balcone con porta manuale collega anche quella porta allo stesso piano.
Scollegare il piano conserva la quota; rimuovere il balcone conserva la porta e
il suo collegamento al piano. Riferimenti rimossi o quote incompatibili danno
un errore, senza rigenerare o cancellare l'apertura manuale.
Verificati cambio 2,8→3,2 m, rinomina, riordino aperture, rimozione/ripristino di
piano e porta, riapertura e undo/redo dei due comandi editor. Il test giocatore
passa anche con la porta manuale collegata. La cattura `floor_binding.png`
confronta 2,8 e 3,3 m. Il gizmo di altezza delle porte ora conserva la soglia elevata.
Restano: agganci sulle ali, sgancio libero, controllo degli ingombri tra facciate
 differenti/altre case, duplicazione dei piani collegati con rimappatura degli ID,
terrazze su pilastri. La scala interna esistente non si ridimensiona automaticamente
quando cambia l'altezza del piano: va regolata separatamente.
**A02a.3 verificato — 2026-09-13.** Terrazza su quattro pilastri e scala esterna
rettilinea frontale, tramite opzioni dello stesso componente. Il parapetto apre
solo il varco della rampa e si richiude quando questa viene rimossa. Piano e quota
terreno determinano altezza dei pilastri, numero di gradini e lunghezza della
scala (32 gradi, pianerottolo superiore). Collisione inclinata continua per il
personaggio; gradini separati nella geometria visibile.
UI contestuale: posizionamento con anteprima del piano e della scala, conversione
del selezionato e rimozione scala con undo/redo. Inspector per larghezza, offset
laterale e quota terreno. Esempio: `terrace_stairs_example.tscn`.
Verifiche: `check_terrace_geometry.gd` (parapetto, ripristino, serializzazione,
validazione), `check_terrace_play.gd` (giocatore sale, entra, scende; poi piano
alzato a 3,2 m), test editor conversione/rimozione/undo/redo, regressioni balcone.
Persistono i messaggi di chiusura headless già annotati in A02a.1.
Limiti: quota terreno manuale uniforme; nessuna verifica contro strade, edifici
o terreno irregolare; rampa frontale con offset, senza rotazioni laterali/L/U.
La scala resta una parte configurabile del componente, non un nodo agganciabile
indipendente. Prossimo passo: separare le rampe come componenti con agganci propri,
consentendo scelta del lato e pianerottoli; poi composizione multi-volume A02.

**A02a.4 verificato — 2026-09-13.** `ExteriorStair` è un nodo dati figlio della
terrazza con ID persistente, bordo frontale/destro/sinistro, larghezza, offset,
quota terreno ed abilitazione. Due maniglie contestuali sulla sola scala selezionata.
I parapetti usano il bordo e l'ingombro del componente; cambio lato, disabilitazione
e rimozione ripristinano il tratto precedente. Nuove terrazze usano il nodo;
le vecchie proprietà frontali restano supportate da un adattatore senza riscrivere
le scene. Conversione esplicita e reversibile tramite il pannello.
Verifiche: giocatore sale/entra/scende su entrambi i lati; test di collisione
parapetti, identità/serializzazione, conversione/cambio lato/eliminazione con
undo/redo editor; regressioni della scala frontale e dei balconi collegati.
Esempio `side_stairs_example.tscn`, cattura `side_stairs.png`.
Limiti: una scala per terrazza, terreno uniforme manuale, nessuna collisione
preventiva con altri edifici; nessuna rampa composta a L/U o libera dal proprio
host. La cancellazione di una scala selezionata riporta la selezione sulla
terrazza per evitare riferimenti editor a nodi rimossi.
Prossimo incremento: pianerottoli e rampe composte, oppure primo volume accessorio
A02 per verificare la stessa modularità su forme architettoniche più grandi.


### A02 — Volumi, non una lista di eccezioni per ogni edificio

**A02.1 verificato — 2026-09-13.** Il tab **Volumi** aggiunge corpi accessori
su una facciata della casa. Ogni nodo `Volumes/…` riusa il builder della casa e
conserva dimensioni, tetto, aperture e ID propri. Le maniglie modificano il corpo
selezionato; facciata e offset definiscono l'aggancio. Sganciandolo si possono
usare le trasformazioni native, senza perdere gli altri corpi.

Il raccordo taglia involucro e collisioni nascoste: il giocatore attraversa
casa e bottega senza incontrare una doppia parete. Sgancio, rimozione o raccordo
non valido richiudono la casa principale. Gli errori compaiono nel tab e nelle
configuration warnings. Il Village Builder include i corpi nell'ingombro del lotto.

Esempio editabile: `scenes/dev/multi_volume_example.tscn`, casa + bottega + deposito.
Verificati salvataggio, aperture indipendenti, collisioni del raccordo, sgancio,
undo/redo dell'editor e attraversamento con il giocatore reale. Test:
`check_multi_volume.gd`, `check_multi_volume_play.gd`, `check_house_editor.gd`;
regressioni Village Builder e balconi superate. Render:
`captures/balcony_attachment/multi_volume.png`.

**Limiti:** agganci ortogonali al piano terreno e tetti accessori sotto la gronda
principale. Sono esclusi volumi annidati, convivenza con l'ala legacy e intersezioni
fra corpi accessori. Non c'è ancora un piano interno unico esteso agli annessi,
né un raccordo configurabile con tramezzo/porta, né un solver per compluvi.
La duplicazione con rimappatura degli ID e la migrazione dell'ala restano da fare.
**A02.2 verificato — 2026-09-13.** Scelta contestuale del raccordo: passaggio
aperto oppure parete principale conservata con porta derivata dal volume.
Larghezza, altezza e offset sono editabili; il vano e la collisione si aggiornano
insieme. La porta usa l'interazione esistente, mantiene lo stato nel volume e
non modifica le aperture manuali. Sgancio o raccordo non valido eliminano la
porta derivata. Esempio aggiornato: bottega aperta, deposito con porta.

Verificati muro ai lati, blocco a porta chiusa, attraversamento a porta aperta,
salvataggio e undo/redo. `check_volume_junction_play.gd` usa il personaggio reale;
immagine `captures/balcony_attachment/junction_door.png`. Restano i limiti geometrici
di A02.1 e l'integrazione delle stanze su più volumi; ora il raccordo con porta
è disponibile. Prossimo passo: portici e tettoie come corpi aperti, mantenendo
il controllo indipendente di ingombro, sostegni e copertura.

- [ ] Nodi dati `Volume`: pianta rettangolare, quota, altezza, orientamento e ID.
- [ ] Duplicazione, ridimensionamento e movimento di una sola parte con gizmo locale.
- [ ] Agganci opzionali; possibilità di sganciare e spostare liberamente.
- [ ] Confini condivisi espliciti: parete comune, passaggio aperto, semplice contatto.
- [ ] Trattare la casa a L esistente come due volumi nell'adattatore, senza spostamenti.
- [ ] Conservare aperture agganciate quando si muove la relativa parte.

**Uscita:** almeno tre volumi con quote differenti, salvataggio/undo e preview di
un raccordo problematico. L'utente può scollegare un volume senza perdere gli altri.

### A03 — Tetti e parti aperte

**A03.1 verificato — 2026-09-13.** Tipo `Portico / tettoia aperta` sul Volume,
con involucro generato da sostegni e travi. Riusa copertura e materiali esistenti,
aggancio e maniglie del builder. Sezione e passo dei pali sono editabili; le
campate seguono la profondità. Il portico valido si appoggia alla casa senza
pali posteriori; sganciandolo diventa una tettoia con sostegni anche sul retro.
La parete principale non viene tagliata e gli ingressi manuali restano utilizzabili.
Le aperture proprie sono conservate nei dati ma sospese finché il corpo è aperto.

La UI sceglie il tipo prima della creazione e disabilita i comandi del raccordo
interno sui portici. Play considera le tettoie esterne, senza oscurare il mondo.
Esempio: `scenes/dev/porch_canopy_example.tscn`; render reale:
`captures/balcony_attachment/porch_canopy.png`. Verifiche:
`check_porch_canopy.gd`, `check_porch_canopy_play.gd` e suite editor.

Limiti: due falde, terreno piano, file di pali automatiche. Restano coperture a
falda singola/piane, scelta individuale dei sostegni, archi e controventi.
Prossimo incremento consigliato: falda singola per portici appoggiati alla parete,
con pendenza verso l'esterno e la stessa gestione delle tegole.

**A03.2 verificato — 2026-09-13.** Falda singola per i volumi aperti, alta sul
retro locale (parete quando agganciata) e bassa verso l'esterno. La generazione
riusa le tegole con un riferimento ruotato e una sola superficie inclinata:
nessuna scalatura della mesh per ottenere la pendenza. Pali e travi seguono
l'altezza locale. Dropdown contestuale con undo/redo e maniglie sui bordi alto/basso.
Conservate le due falde esistenti e i dati durante il cambio della copertura.

Esempio aggiornato `porch_canopy_example.tscn`, render `porch_canopy.png` nella
cartella captures/balcony_attachment. Test su pendenza dei vertici, ridimensionamento,
salvataggio, editor e attraversamento reale dell'ingresso superati. Limite:
solo volumi aperti, direzione locale retro → fronte, terreno piano. Prossimo
incremento: sostegni selezionabili e modificabili singolarmente, preservando
le modifiche manuali quando cambiano le dimensioni del portico.

**A03.3 verificato — 2026-09-13.** Conversione esplicita della disposizione dei
pali in nodi dati `Supports/Sostegno_…`. ID, posizione locale, sezione e abilitazione
persistono; il builder genera mesh e collisioni senza rigenerare i nodi manuali.
Gizmo di selezione contestuale e traslazione nativa; aggiunta, rimozione e ritorno
alla disposizione automatica con undo/redo. Il resize conserva i dati, adatta
le altezze e segnala i pali fuori copertura invece di spostarli o cancellarli.

Esempio porch_canopy aggiornato con pali anteriori spostati e ingrossati.
`check_authored_supports.gd` verifica resize, collisioni, disabilitazione,
cancellazione e salvataggio; suite editor e Play superati. Nell'apertura della
scena playground personalizzata sono comparsi anche messaggi preesistenti di
`plan.gd:58` sull'organizzazione dell'arredo fuori dall'albero: non riguardano i
sostegni e quella scena non è stata modificata da questo incremento.

Limiti: sezione quadrata, pali verticali; niente ridistribuzione automatica dopo
la conversione, né adattamento delle travi alle posizioni manuali. Prossimo passo:
controventi e travi di collegamento editabili per completare il telaio dei portici.

**A03.4 verificato — 2026-09-13.** Collegamenti `FrameLinks` fra due sostegni
manuali, con sezione, abbassamento dal tetto e due controventi regolabili.
Riferimenti tramite ID: rename e movimento dei pali preservano la connessione;
sostegni mancanti o invalidi sospendono la geometria senza eliminare i dati.
Sottotab Sostegni/Collegamenti, gizmo contestuale, creazione/rimozione con undo/redo.
Il telaio automatico può essere disabilitato esplicitamente sul volume.

Verifiche: `check_frame_links.gd` (movimento, rename, collisione, salvataggio,
sostegno mancante), suite editor e Play portico. Corretto anche il riferimento
geometrico delle travi parallele all'asse Z, che prima poteva collassare.
Esempio porch_canopy aggiornato; vista ravvicinata in
`captures/balcony_attachment/frame_links_detail.png`. Restano i messaggi editor
sull'arredo descritti in A03.3, indipendenti da questi test superati.

Limiti: estremi su due pali, controventi simmetrici, nessun aggancio libero o alla
parete; nessuna verifica strutturale. Prossimo passo: aggancio di un estremo alla
parete per costruire telai completi dei portici con soli pali esterni.

**A03.5 verificato — 2026-09-13.** Estremo del FrameLink agganciato alla facciata
ospitante del portico. Un solo sostegno necessario; offset laterale editabile,
quota derivata dal tetto e controvento solo sul palo. Validazione dell'aggancio,
della copertura e delle aperture; sgancio del portico sospende la trave e conserva
il record. Compatibile con le quattro facciate e undo/redo.

Esempio `wall_frame_example.tscn`, render `wall_frame_detail.png` nella cartella
captures/balcony_attachment. Test `check_wall_frame.gd`: facciate, movimento,
offset, sgancio, valori invalidi e salvataggio. Suite editor e Play verificano
creazione annullabile e attraversamento della porta con due soli pali anteriori.
Limiti: parete ospitante, quota derivata; nessun estremo libero o solver strutturale.

**A03.6 verificato — 2026-09-13.** Copertura piana sui volumi accessori aperti e
chiusi: soletta con parapetto opzionale, materiali esistenti, collisione dedicata.
Cambio reversibile senza perdita di aperture o sostegni; il corpo chiuso non
genera timpani sotto il tetto piano. Altezza parapetto dalla maniglia superiore.
Il taglio del raccordo mantiene la parete ospitante sopra la soletta.

Esempio `flat_roof_example.tscn`, render `captures/balcony_attachment/flat_roof.png`.
Test `check_flat_roof.gd` su collisione, parapetto, conversione, salvataggio e muro
sopra il raccordo; editor e Play degli interni superati. Restano accesso al tetto,
varco nel parapetto e integrazione del tetto praticabile con i piani. Prossimo
passo: collegare un accesso superiore alla copertura piana, senza cambiare la
planimetria manuale esistente.

**A03.7 verificato — 2026-09-13.** Accesso esterno al tetto piano mediante lo
stesso ExteriorStair usato dalle terrazze. Nodo ScalaTetto, tre bordi, offset e
larghezza; il varco del parapetto segue la scala e si richiude se viene disabilitata,
rimossa o resa invalida. Quota e rampa seguono la soletta. Nuovo sottotab Accesso
tetto e gizmo della scala nel contesto Volumi.

Play distingue quota del tetto e interno sottostante: salita, permanenza all'esterno
e discesa verificati con il giocatore reale (`check_roof_access_play.gd`). Test
`check_roof_access.gd` su varchi, bordi, disabilitazione, resize, errori e salvataggio;
suite editor su undo/redo. Esempio `roof_access_example.tscn`; immagine
`captures/balcony_attachment/roof_access_play.png`. Texture lasciate invariate
su richiesta. Restano porta verso il piano superiore, controllo degli ingombri
esterni e integrazione con il piano interno; nessuna planimetria viene riscritta.

**A03.8 / primo raccordo A04 verificato — 2026-09-13.** Porta derivata dal tetto
piano verso un livello persistente dell'InteriorPlan della casa. ID del livello,
controllo di quota (6 cm), offset lungo la facciata, stato della porta indipendente
dal raccordo inferiore. Il comando non crea o sposta stanze e solai; un piano
mancante o una quota incompatibile produce un errore. Rimozione richiude la parete.

Esempio `roof_door_example.tscn` con piano superiore vuoto. Test
`check_roof_door.gd`: ID, rename, mismatch, rimozione, sgancio e salvataggio.
`check_roof_door_play.gd`: scala → tetto → porta → solaio superiore → ritorno e
 discesa; cattura `captures/balcony_attachment/roof_door_play.png`. Comandi editor
con undo/redo verificati. Limiti: una porta di dimensioni fisse per volume;
nessun controllo automatico di tramezzi o arredi davanti all'accesso.

- [ ] Ogni copertura ha pianta, colmo, pendenza, quota, sporto e collegamento al volume.
- [ ] Prima due falde e una falda; poi tetto piano/parapetto e quattro falde.
- [ ] Raccordi: intersezioni, compluvi/displuvi, bordi e taglio delle parti nascoste.
- [ ] Portici e tettoie: sostegni e travi, senza forzare quattro pareti chiuse.
- [ ] Camini e abbaini come componenti con aperture reali e ingombro.
- [ ] Tegole/copertura seguono la superficie senza stirarsi e senza pattern periodici
  introdotti dalla suddivisione in componenti.

**Uscita:** R04 e R08 come composizioni di forme; spostare un tetto o cambiare una
pendenza aggiorna soltanto i raccordi dipendenti. Le texture attuali restano la base.

### A04 — Un solo edificio per esterno e interno

- [ ] Quote e altezze per piano; solai, fori e doppie altezze.
- [ ] Stanze confinate nell'involucro composto, includendo ali e rientri.
- [ ] Muri condivisi univoci: evitare doppie pareti e aperture sovrapposte.
- [ ] Scale e pianerottoli con connessioni tra quote; scale esterne e ballatoi.
- [ ] Porte/finestre tagliano lo stesso involucro visto dall'interno e dall'esterno.
- [ ] Adattare la vista sezionata a più volumi, senza rimuovere collisioni.
- [ ] Generazione interna facoltativa e manuale libera; non imporre una camera da
  letto e un corridoio standard a una fucina o a una sala comune.

**Uscita:** Play della casa R02, dal terreno al piano superiore e ritorno. Dopo una
modifica esterna viene mostrato quali stanze richiedono revisione; niente perdita
silenziosa di muri, porte o mobili.

### A05–A06 — Architetture riconoscibili e interni funzionali

- [ ] Campate, montanti, traversi, basamento, timpani e piani aggettanti.
- [ ] Aperture ad arco/rettangolari e varianti di scala definite geometricamente.
- [ ] Spazi di lavoro per la fucina: camino, zona di lavoro e tettoia, senza mobili
  che ostruiscano porte o area operativa.
- [ ] Sala nordica R11–R12: sala lunga, file di sostegni, tavoli laterali/centrali,
  passaggi e pedana; spazio sotto il tetto coerente con l'esterno.
- [ ] Override del profilo per una sola parte e composizione di famiglie diverse.

**Uscita:** riconoscere fucina, sala comune e abitazione dalle forme e dall'organizzazione,
anche con i materiali attuali. Cambiare un componente manualmente non disfa il resto.

### Priorità aggiornata verso il castello — 2026-09-13

Su richiesta, il percorso ora privilegia A07/A08. Le varianti mancanti di A04–A06
restano nel piano ma non bloccano il primo recinto fortificato. Stima indicativa,
non scadenza: 2–3 incrementi per una prima torre A07 poligonale con aperture e
accesso; altri 3–4 per mura, torri, portone e camminamento del primo castello.
Il castello completo A09, le cupole e i tetti curvi richiederanno altro lavoro.

**Fondazione A08 verificata:** merli parametrici del parapetto piano e preset di
torre quadrata indipendente, creato dal builder. Passo dei merli, vuoti e collisioni,
varco della scala, salvataggio e creazione con undo/redo. Esempio
`square_tower_example.tscn`; test `check_battlements.gd` e
`check_square_tower_play.gd`. Questo non completa A07: la pianta è ancora rettangolare.
Il prossimo incremento prioritario è la pianta poligonale della torre, prima di
aggiungere altro dettaglio a portici e terrazze.

### A07 — Geometrie non rettangolari

**A07.3 verificata — 2026-09-13:** scala interna al tetto come elemento
modificabile dell’ultimo piano, quota derivata dalla copertura e apertura
sincronizzata anche su spostamento, disattivazione e rimozione. Preset nel tab
Interni con Undo/Redo; niente sovrascrittura degli elementi esistenti.
Esempio `tower_roof_stair_example.tscn`; test `check_tower_roof_stair.gd`,
`check_tower_roof_stair_play.gd`, suite editor. Percorso reale completo
terra→primo piano→tetto→terra verificato, con cambio interno/esterno e discesa.
Restano parapetti del vano/botola, scale compatte e stanze poligonali.
Prossimo incremento prioritario: A08, cortina parametrica e primo portone.


**A07.2 verificata — 2026-09-13:** due piani interni con lo stesso InteriorPlan
modificabile delle case, solai ottagonali e scala rettilinea tra i piani. Il vano
segue le modifiche manuali della scala; il taglio visivo segue le facce rivolte
alla camera. Preset in Interni con protezione da sovrascrittura e Undo/Redo.
Esempio `tower_interior_example.tscn`; test `check_tower_interior.gd`,
`check_tower_interior_play.gd`, suite editor. Verificati quota, collisioni,
spostamento vano, salvataggio e percorso ingresso→primo piano→uscita.
Restano accesso interno al tetto, parapetti del vano, scale più compatte e
stanze poligonali. Prossimo passo: collegamento dal piano superiore al tetto,
poi primo recinto fortificato A08.


**A07.1 verificata — 2026-09-13:** torre ottagonale indipendente in Volumi,
con larghezza/profondità modificabili, aperture sulle otto facce (anche oblique),
pavimento e tetto poligonali, merli e scala esterna condivisi con il builder.
Gizmo del perimetro e selezione aperture aggiornati; il Play distingue i vertici
tagliati dall’interno. Esempio: `scenes/dev/polygon_tower_example.tscn`.
Verificati raycast sulle otto facce, taglio/collisione porta obliqua, assenza di
solai negli angoli esterni, salvataggio, creazione/Undo/Redo e salita/discesa reale.
Limiti: otto lati fissi, tetto piano, corpo indipendente; piani/stanze poligonali,
scale interne, coperture coniche e raccordi alle mura ancora da implementare.
Passo successivo realizzato in A07.2: piani interni coerenti con la pianta e collegamento verticale.


- [ ] Piante poligonali semplici; supporto delle curve con pochi controlli leggibili.
- [ ] Torri cilindriche/prismatiche, coperture coniche, cupole, parapetti.
- [ ] Taglio di aperture su pareti non planari o facce segmentate.
- [ ] Solai, scale e arredo rispettano la pianta reale, non il suo rettangolo limite.
- [ ] Profili curvi delle coperture come capacità separata; confronto con R10 e R13.

**Uscita:** torre e edificio terrazzato R09 giocabili. Non richiedere subito tutte
le curve elfiche per sbloccare il castello: torri quadrate/circolari bastano alla fase A08.

### A08–A09 — Castello come complesso

- [ ] Perimetro di mura tramite path, con altezza, spessore e quota modificabili.
- [ ] Torri sugli angoli o aggiunte a mano; porte, merli e contrafforti come componenti.
- [ ] Camminamenti, scale, parapetti e passaggi nelle torri realmente connessi.
- [ ] Cortile interno libero, mastio e servizi come edifici riutilizzati dall'House Builder.
- [ ] Richiesta d'ingresso dalla scala villaggio e restituzione di più accessi/ingombri.
- [ ] In A09: quote diverse, più corti, bastioni e corpi accostati, usando gli stessi dati.

**Uscita A08:** piccolo recinto fortificato con due torri e una porta; il giocatore
entra, raggiunge le mura e passa nella torre. **Uscita A09:** complesso ispirato a
R20/R21 senza trasformare tutto il castello in un unico monolite rigenerabile.

### A10 — Rovine

- [ ] Danno locale applicato a componenti selezionati, riproducibile tramite seed.
- [ ] Rottura del tetto con travi esposte; tagli di muri e solai, bordi coerenti.
- [ ] Macerie come oggetti distinti con collisioni/ingombri deliberati.
- [ ] Conservare accessi utili o marcare esplicitamente una zona inaccessibile.
- [ ] Permettere riparazione/sostituzione manuale della sola parte danneggiata.

**Uscita:** confronto integro/rovina di R07, salvato e giocabile. Nessuna necessità
di simulazione fisica del crollo per ottenere la prima versione.

### A11 — Consolidamento continuo

- [ ] Pubblicare ingombri e accessi composti al Village Builder senza esporre la
  logica interna delle stanze o le mesh delle singole tegole.
- [ ] Verificare collisioni, visibilità degli ingressi e sezioni con camera fissa.
- [ ] Misurare tempi di drag/rigenerazione, memoria e costo del Play su casa,
  villaggio e castello; registrare macchina e condizioni prima di fissare budget.
- [ ] Ricostruzione locale, cache e livelli di dettaglio dove le misure lo richiedono.
- [ ] Valutare esportazione/bake finale conservando i dati di authoring originali.
- [ ] Affrontare illuminazione avanzata soltanto come task successivo separato.

## UI e protocollo comune a ogni incremento

Mantenere pannelli per scala. Nel contesto edificio: **Volumi, Tetti, Facciate,
Interni, Arredo** come contesti/sottoschede, non tutti i controlli contemporaneamente.
Profilo architettonico e funzione sono selettori distinti, con nomi leggibili.

Solo la selezione attiva mostra i gizmo dettagliati. Evidenziare aggancio, quota,
elemento proprietario e differenza fra oggetto parametrico e indipendente.
Un comando deve dire cosa rigenera: “Tetto selezionato”, “Muri di questo piano”,
“Proposta per questa corte”, non un generico pulsante che riscrive tutto.

Ogni fase segue: **proposta → anteprima → applicazione → Play → salvataggio/riapertura**.
Undo deve ripristinare sia dati sia risultato visibile. Gli errori devono indicare
elemento e causa e permetterne la selezione nell'editor.

## Criteri trasversali di completamento

- [ ] Riferimento e proprietà geometriche obiettivo dichiarati prima del lavoro.
- [ ] Esempio costruito dal builder, salvato e modificabile; non una mesh dimostrativa isolata.
- [ ] Modifica manuale → rigenerazione locale → undo/redo → riapertura senza perdita.
- [ ] Compatibilità verificata con gli esempi precedenti o migrazione esplicita.
- [ ] Ingressi e parti importanti leggibili alla camera di gioco fissa, non solo da vicino.
- [ ] Passaggi, porte, scale e collisioni provati quando modificati dalla fase.
- [ ] Nessun cambiamento non richiesto alla resa visiva del progetto.
- [ ] Documentazione e riga del registro aggiornate con prove reali e limiti residui.

## Registro degli incrementi

| Data | Fase | Risultato | Verifica / evidenza | Commit |
|---|---|---|---|---|
| 2026-09-13 | A02a (pianificata) | Aggiunto requisito di terrazze/componenti agganciati con adattamento del muro | Specifica balcone + porta; nessuna implementazione ancora | Stesso incremento documentale |
| 2026-09-13 | A00 | Esaminate 21 immagini; distinta architettura da resa visiva; definita sequenza | Inventario R01–R21, confronto con codice e documentazione dei builder | Commit che introduce questo documento |

### Scheda da compilare per ogni prossimo incremento

```text
Fase / sottofase:
Stato precedente → nuovo stato:
Riferimenti (Rxx) e capacità geometriche obiettivo:
Componenti / dati modificati:
Esempio salvato:
Modifiche manuali che devono sopravvivere:
Compatibilità / migrazione:
Verifiche effettivamente eseguite:
Limiti o problemi rimasti:
Commit:
Prossimo passo concreto:
```

Aggiornare le checkbox solo dopo la verifica; dividere una fase in sottofasi se
necessario senza perdere gli ID. Una scena che “sembra giusta” non chiude una fase
se editing, salvataggio o Play richiesti non funzionano. Il primo recinto A08 è percorribile. A08.7 protegge i vani scala; A09.1 introduce il primo mastio. A09.2 aggiunge il corpo accessorio collegato. A09.3 introduce raccordi in pendenza. A09.4 aggiunge raccordi a gradini. A09.5 introduce la corte rialzata. A09.6 coordina la quota con gli edifici. Priorità aggiornata: **G01, scheletro del compositore e protezione delle modifiche manuali**. Bordi della corte e distribuzione degli accessi restano nel backlog A09.


### A08.1 — Cortina rettilinea e portone — 2026-09-13

Implementato un componente Cortina modificabile tramite il builder, con
camminamento e merli, spessore solido e passaggio a tutto spessore. Portone
interattivo parametrico e persistente. UI nel tab separato Fortificazioni con
Play sul componente selezionato; gizmo contestuali e creazione annullabile.
Esempio `curtain_wall_example.tscn` con scala esterna. Test
`check_curtain_wall.gd`, `check_curtain_wall_play.gd` e suite editor: passaggio,
collisioni, salita/discesa, spostamento/disattivazione portone, save e Undo/Redo.
Questo non chiude A08: manca il recinto, i raccordi alle torri e gli angoli.
Prossimo incremento: collegamento tra cortina e torre con passaggio sul
camminamento, poi composizione del piccolo recinto fortificato.


### A08.2 — Raccordo torre–cortina — 2026-09-13

Cortina agganciata a una delle otto facce della torre, con quota del camminamento
allineata al tetto e apertura dei due parapetti. Nodo figlio modificabile,
faccia e dimensioni persistenti, creazione Undo/Redo nel tab Fortificazioni.
Play include torre, interni e cortina. Esempio `tower_curtain_example.tscn`.
Test `check_tower_curtain.gd`, `check_tower_curtain_play.gd`, suite editor:
percorso reale terra→torre→cortina→terra, giunto solido, faccia obliqua,
ridimensionamento, scollegamento/rimozione e serializzazione.
Limiti: raccordo al tetto, singola estremità; nessun collegamento alla seconda
torre, angolo o recinto chiuso. Prossimo incremento: seconda estremità della
cortina e composizione del primo recinto con torri.


### A08.3 — Due torri collegate — 2026-09-13

Gruppo Fortificazione con torri indipendenti, cortina referenziata a entrambe
le estremità, lunghezza derivata e apertura del parapetto di arrivo.
Validazione allineamento, facce opposte, larghezze e quote. Comando nel tab
Fortificazioni e snapshot/Play dell’intero gruppo. Interni attivi sulla torre
principale; torre secondaria percorribile sul tetto.
Esempio `two_towers_example.tscn`; test `check_two_towers.gd`,
`check_two_towers_play.gd` e suite editor (scena base square_tower_example per
non ostruire i raycast dei test di authoring con la fortificazione estesa).
Verificati percorso completo, spostamento origine/destinazione, errori,
scollegamento, riferimenti serializzati e Undo/Redo.
Prossimo passo: quattro torri e recinto chiuso, mantenendo le cortine come
collegamenti fra nodi distinti. A08 non è ancora conclusa.


### A08.4 — Primo recinto chiuso giocabile — 2026-09-13

Raggiunto il primo esempio di piccolo castello: quattro torri, quattro cortine,
portone e cortile, accesso dalla corte alla torre principale e anello di
camminamenti percorribile. Comando dedicato nel tab Fortificazioni. Tutti i
nodi restano parametrici e i collegamenti sono gli stessi introdotti in A08.3.
Esempio `castle_enclosure_example.tscn`; test `check_enclosure.gd`,
`check_enclosure_play.gd` e suite editor. Verificati portone/collisioni perimetrali,
percorso completo ingresso→corte→torre→intero anello→uscita, ridimensionamento
di un lato, riferimenti salvati, Undo/Redo e snapshot. Nessun arredo aggiunto.
La milestone del primo castello giocabile è raggiunta; A08 resta aperta per
consolidare editing e varianti. Limiti: rettangolo, quote uniformi, interni e
cambio vista sulla torre principale soltanto. Mastio e castelli multilivello
restano A09. Prossimo passo consigliato: editing contestuale del recinto e
validazione complessiva, poi interni delle torri secondarie.


### A08.5 — Editing contestuale e diagnostica — 2026-09-13

Sottotab Crea/Recinto. Ridimensionamento assistito del rettangolo tramite distanza
fra centri delle torri; stato applicato e annullato senza rigenerare i nodi.
Elenco dinamico degli errori con selezione del nodo interessato: riferimenti,
allineamento/quote, occupazione facce, grado delle torri, componenti separate e
portone. Le piante manuali non rettangolari vengono preservate e segnalate.
Verificati preservazione di scala/portone modificati, rifiuto senza mutazioni,
resize/Undo/Redo e selezione diagnostica nella suite editor.
Test `check_enclosure_editing.gd`; esempio `castle_enclosure_resized_example.tscn`.
Limiti: niente gizmo dedicato ai lati del gruppo, resize di rettangoli soltanto,
nessun controllo esaustivo delle collisioni con arredi manuali. Prossimo passo:
interni e cambio vista nelle torri secondarie del gruppo.


### A08.6 — Interni delle torri secondarie — 2026-09-13

Preset del recinto con quattro interni distinti e ingressi rivolti alla corte.
Comando per completare soltanto le torri senza InteriorPlan, con preflight e
Undo/Redo; piani esistenti e aperture manuali preservati. Il Play attiva la torre
in base alla pianta locale e aggiorna cutaway, piani, porte e luci. Esempio
`castle_interiors_example.tscn`; `check_castle_interiors_play.gd` percorre ingresso,
primo piano, tetto e ritorno in ogni torre. Suite editor: preservazione, Undo/Redo
e no-op sugli interni esistenti; regressione torre singola.
Limiti: nessuna suddivisione in stanze o arredo, illuminazione esistente e vani
scala senza parapetti/botole. Prossimo passo consigliato: proteggere i vani scala
e rendere gli sbarchi più leggibili, poi avviare il mastio A09.


### A08.7 — Parapetti dei vani scala — 2026-09-13

Protezione automatica in legno su tre lati del vano, con sbarco aperto.
Geometria e collisioni seguono posizione, rotazione e dimensioni della scala.
Il parapetto appartiene al piano di arrivo (o al tetto), rispettando il cutaway.
Opzione per scala `guardrails_enabled`, salvata nei record e preservata dalla
rigenerazione; le scene precedenti ricevono il comportamento predefinito.
Verificati collisioni, sbarco, toggle, trasformazioni, salvataggio, percorso
completo in tutte le quattro torri e suite editor. Restano i messaggi preesistenti
di reparenting degli arredi nella suite editor, che termina HOUSE_EDITOR_ALL_OK.
Limiti: parapetto pieno in legno, altezza fissa 0.92 m, nessuna botola;
nessun controllo automatico delle interferenze con elementi manuali adiacenti.
Prossimo passo: A09, primo mastio modificabile con piani e accesso alla corte.


### A09.1 — Primo mastio indipendente — 2026-09-13

Comando contestuale Fortificazioni → Recinto → Aggiungi mastio nella corte.
Preset 6 × 6 m, tre piani da 2.8 m, scale alternate e parapetti automatici,
finestre e ingresso sul lato +Z (sud del preset). Tipo architettonico `keep`.
Usa Volume/House e InteriorPlan: piani, scale, dimensioni e aperture sono nodi
modificabili, non un interno generato soltanto nel Play. `buildings()` separa
gli edifici visitabili dal grafo delle torri/cortine; il Play include il mastio
nel cambio di edificio, luci, porte e cutaway. Materiali esistenti.
Esempio: `scenes/dev/castle_keep_example.tscn`.
Verificati ingresso, tre piani, ritorno nella corte con il giocatore;
Undo/Redo preserva l'identità del mastio, snapshot e duplicati controllati.
Diagnostica di ingombro centrale con margine 1 m, conservativa su quattro torri;
non è un controllo completo di collisioni per corti arbitrarie. Suite editor
conclusa HOUSE_EDITOR_ALL_OK, con i messaggi preesistenti di reparenting arredi.
Limiti: primo preset singolo, nessun arredo/stanze automatiche, tetto a falde
non accessibile; il resize del recinto lascia il mastio nella posizione manuale
ed evidenzia eventuali ingombri fuori limite. A09 resta IN CORSO.
Prossimo passo A09.2: corpo accessorio agganciato al mastio con passaggio interno,
poi corti e quote diverse. Riferimenti: check_keep_play.gd e check_house_editor.gd.


### A09.2 — Corpo accessorio del mastio — 2026-09-13

Volume basso chiuso (3 × 2.8 m, altezza 2.6 m), tetto piano e porta di raccordo
al piano terra. Comando in Fortificazioni/Recinto e strumenti Volumi esistenti.
Il mastio può ospitare volumi senza abilitare agganci annidati arbitrari.
Le aperture superiori non bloccano più l'aggancio se restano sopra la copertura;
quelle interferenti restano protette. Diagnostica conservativa con ingombri AABB
di torri/cortine e margine 0.5 m. Se invalido, nessun taglio della parete.
Play: porta apribile, continuità interno/cutaway e luce di prova nel corpo basso,
con lo stesso sistema di illuminazione esistente. Esempio:
`castle_keep_accessory_example.tscn`, costruito con i volumi del builder.
Verificati porta chiusa/aperta, attraversamento e ritorno, successiva salita
ai tre piani, sgancio/rimozione che ripristinano il muro, stato invalido,
salvataggio, Undo/Redo e preservazione finestre. Suite editor conclusa con
HOUSE_EDITOR_ALL_OK; restano i messaggi preesistenti del reparenting arredi.
Limiti: corpo al piano terra, nessuna pianta indipendente a più piani nell'annesso,
nessun arredo, illuminazione solo di prova. Le verifiche degli ingombri sono
conservative per rotazioni oblique e non considerano ogni oggetto manuale.
Prossimo passo: quote e raccordi verticali del complesso, mantenendo indipendenti
muri, edifici e interni. A09 resta IN CORSO.


### A09.3 — Camminamenti fra tetti a quote diverse — 2026-09-13

Opt-in per cortina `allow_sloped_walkway`; sottotab Fortificazioni/Quote con
abilitazione collettiva delle cortine senza portone e Undo/Redo. Le altezze
restano sui nodi torre/InteriorPlan. Muro, camminamento, parapetti e collisioni
si adattano alle quote terminali senza sollevare la fondazione. Aperture dei
parapetti delle torri riutilizzano il controllo di validità del raccordo.
Esempio `castle_sloped_walkways_example.tscn`: due torri posteriori più alte
(+1.2 m), con piani e scale aggiornati, mastio e corpo accessorio preservati.
Test geometrici su quote/collisioni, opt-in, portone incompatibile, limite,
ritorno a quota uniforme e salvataggio. Test Play dedicato con partenza sul tetto
per percorrere entrambi i raccordi in salita/discesa. Suite editor: Undo/Redo e
no-op, oltre alle regressioni precedenti; messaggi preesistenti degli arredi.
Limiti: basi sullo stesso piano, assi verticali e facce opposte allineate;
pendenza massima 45% (non 45 gradi); niente portone sul tratto inclinato.
Sono rampe continue, non scale. Nessun adattamento al terreno e nessuna quota
indipendente di fondazione in questa versione. A09 resta IN CORSO.
Prossimo passo: accessi e scale per dislivelli maggiori, poi corti su quote diverse.


### A09.4 — Raccordi a gradini e sbarchi — 2026-09-14

Profilo `walkway_profile` Rampa/Gradini per cortina, con conversione contestuale
nel tab Quote e Undo/Redo. Il profilo a gradini ammette dislivelli oltre il limite
delle rampe, con alzata visiva massima 18 cm, pedata minima 24 cm e pendenza
massima 75%. Due sbarchi da 50 cm restano piani; parapetti e muro seguono il
raccordo. La collisione è continua sotto le pedate, come nelle scale interne,
per evitare sobbalzi del personaggio. Non è una simulazione del contatto piede-pedata.
Esempio `castle_stepped_walkways_example.tscn`: torri posteriori +4 m, tre piani
editabili, vano scala laterale che lascia libero l'arrivo del camminamento.
Test: quote degli sbarchi, collisione separata dalle pedate, limiti, salvataggio,
ritorno a quota uniforme, UI Undo/Redo; Play dedicato salita/discesa di entrambi
i lati con partenza sui tetti. Suite editor con messaggi preesistenti arredi.
Limiti: cortine senza portone, basi complanari; nessuna scala a più rampe o
pianerottolo intermedio. A09 resta IN CORSO. Prossimo passo: corti e fondazioni
su quote diverse, con accessi coerenti alla camera fissa.


### A09.5 — Corte e fondazioni rialzate — 2026-09-14

Preset contestuale Quote/Crea corte posteriore rialzata: piattaforma modificabile,
rampa centrale, mastio e torri posteriori a +1.2 m. Portone e torri anteriori
restano al terreno iniziale. L'operazione preserva i nodi/interiori e supporta
Undo/Redo; rifiuta quote preesistenti e ingombri principali fuori dalla piattaforma.
Le cortine ammettono basi a quote diverse, mantenendo allineamento orizzontale,
limiti delle pendenze e vincolo del portone. Il piede della cortina discendente
si estende alla quota inferiore. Resize del recinto mantiene le quote dei nodi.
Diagnostica del centro di appoggio degli edifici e pendenza della rampa.
Test: collisioni piattaforma/rampa, basi/resize, mismatch manuale, salvataggio,
Undo/Redo. Play dal portone al mastio/annesso, tre piani, ritorno al terreno.
Esempio: `castle_raised_courtyard_example.tscn`. Suite editor passata con i
messaggi preesistenti degli arredi. Materiali e luci di prova esistenti.
Limiti: piattaforma rettangolare, un solo accesso centrale, nessun terreno
scolpito; controlli di appoggio al centro, non verifica completa delle fondazioni.
Modificare Elevation/Size/posizione non trascina automaticamente gli edifici:
la diagnostica evidenzia quote incoerenti; resize del recinto non allarga la corte.
A09 resta IN CORSO. Prossimo passo: editing coordinato di quota e bordi della
corte, preservando gli offset manuali degli edifici.


### A09.6 — Quota coordinata della corte — 2026-09-14

Comando Quote/Applica quota a corte ed edifici collegati, con lista persistente
`linked_buildings`. Il delta di quota viene applicato agli edifici conservando
posizioni X/Z e offset Y manuali; i nodi e gli interni non vengono rigenerati.
Undo/Redo ripristina quota, posizioni e collegamenti. Le corti precedenti, prive
di collegamenti, inizializzano la lista dagli edifici con centro sulla piattaforma.
Link mancanti e pendenza eccessiva producono errore senza applicazione parziale.
Il preset nuovo salva già i riferimenti degli edifici sollevati.
Esempio a quota 1.6 m: `castle_linked_courtyard_example.tscn`.
Verificati offset manuale, Undo/Redo e Play dal portone a mastio/annesso, tre piani
e ritorno. Suite editor con i messaggi preesistenti del reparenting degli arredi.
Limiti: il comando riguarda solo la quota; Size, accesso e traslazione della
piattaforma restano manuali. Modificare direttamente Elevation nell'Inspector
non sposta gli edifici: usare il comando coordinato. Nessun trascinamento
implicito degli edifici aggiunti dopo aver creato i collegamenti.
Prossimo passo: bordi della corte e accessi, mantenendo espliciti i collegamenti.


### A09.7 — Corte aperta e visibilità del giocatore — 2026-09-14

Nuovo esempio con torri distanti 26 m, mastio/annesso e servizi sul fondo; centro
ampio e libero. Creato con gli stessi builder, salvato come nodi editabili:
`castle_open_courtyard_example.tscn`. Il terreno verde è solo una base di prova,
non un giardino arredato o una nuova texture definitiva.
Nel Play dei gruppi fortificati un taglio locale lungo la vista della camera
libera giocatore e spazio circostante. Raggio predefinito 3.6 m; sotto piedi
+35 cm non si taglia, preservando piano dei camminamenti e riferimenti bassi.
Agisce su materiali architettonici esistenti (intonaco, legno/pietra, tetti),
senza modificare collisioni o mesh persistenti. Bordo sfumato a dithering e
transizione di attivazione; nessuna trasparenza globale di tutta la facciata.
Tab Vista e F8 per confronto. In editor il taglio è disattivato per default sui
materiali: i parametri sono applicati per mesh soltanto nel Play. Gli oggetti
aggiunti/rigenerati vengono rilevati periodicamente.
Test: immagini prima/dopo nella stessa posizione, ripristino, muro ancora solido,
camminamento con pavimento preservato, creazione UI e snapshot. Limiti: solo
shader architettonici integrati, un giocatore/camera per il gruppo, niente
vegetazione o materiali importati; la lettura del terreno resta influenzata
dalle ombre esistenti. La reference non è riprodotta integralmente nelle coperture.

Validazione A09.7 conclusa: OPEN_CASTLE_REVEAL_RESTORE_COLLISION_WALKWAY_OK e
HOUSE_EDITOR_ALL_OK (con i messaggi preesistenti del reparenting arredi).


### A09.8 — Sezioni della muratura nel reveal (2026-09-14)

Il ritaglio del castello ora ha un bordo netto, irregolare e leggermente svasato verso la camera: rende leggibile lo spessore alla camera fissa. La geometria temporanea della sezione viene ricavata dalle intersezioni con la mesh finale tramite il BVH nativo TriangleMesh, conservando le aperture già generate. Le cortine piene hanno un materiale di pietrame scuro con giunti irregolari; le sezioni delle pareti degli edifici cavi sono nere. Non viene aggiunto un disco nero sopra il giocatore o il cortile.

Implementazione: `architecture_sections.gd` viene coordinato da `architecture_visibility.gd`. Le sezioni seguono lo stesso fuoco e raggio del reveal, si disattivano con F8 e non proiettano ombre né aggiungono collisioni. Le mesh accelerate sono memorizzate e invalidate quando la mesh sorgente cambia. Il campionamento angolare è di 192 strisce: la sezione è una discretizzazione visiva, non una sottrazione booleana permanente.

Copertura attuale: mesh Walls dei generatori esistenti e copertura/camminamento delle cortine. Tegole, infissi mobili e asset esterni non ricevono nuove sezioni. La classificazione deriva dal generatore (cortina piena / edificio cavo); non è ancora un attributo liberamente assegnabile a ogni materiale. Geometrie aperte o con orientamenti incoerenti non garantiscono una sezione chiusa. Il materiale interno è una convenzione grafica scura, non una simulazione della frattura o della luce nell'intercapedine.

Validazione: `check_architecture_sections.gd` verifica spazio vuoto fra pareti, passaggio libero e spessore della sezione (`ARCHITECTURE_SECTION_ROOM_VOID_DOORWAY_THICKNESS_OK`). `check_open_castle_play.gd` verifica presenza di sezioni piene e cave, disattivazione, ingresso, collisioni e supporto dei camminamenti (`OPEN_CASTLE_REVEAL_RESTORE_COLLISION_WALKWAY_OK`). Prova grafica D3D12 completata; screenshot aggiornati in captures/balcony_attachment. Nell'ultimo campione il rebuild delle sezioni ha richiesto circa 3,9 ms: misura puntuale, non benchmark di un villaggio completo.


#### A09.8 correzione — attivazione su occlusione del personaggio

Il reveal non rimane più attivo per semplice vicinanza alle mura. Due raggi verso la camera, all'altezza del busto e della testa, verificano se la geometria visibile del builder copre il personaggio. Per la camera ortografica i raggi sono paralleli. Il controllo usa la mesh originale, indipendentemente dal ritaglio dello shader, per evitare oscillazioni. Quando entrambi i raggi sono liberi, dopo 120 ms di stabilità il taglio si richiude gradualmente. F8 abilita/disabilita questo comportamento automatico. Gli ostacoli esterni al gruppo del castello non sono inclusi.

Validazione Play: giocatore nascosto → reveal con sezioni; giocatore visibile nel cortile → raggio zero e nessuna sezione; ritorno dietro le mura → riattivazione. Screenshot: `captures/balcony_attachment/open_castle_visible_uncut.png`.


#### A09.9 — Taglio rettangolare selettivo e porte leggibili

Il reveal usa ora un volume rettangolare orientato secondo gli assi locali dell'edificio o della cortina: lati verticali e base orizzontale, senza foro circolare o svasatura. Le sezioni chiudono le quattro facce verticali e la base tramite intersezioni con la mesh finale. Questa versione sostituisce il campionamento angolare A09.8 con strisce planari (96 per faccia); edifici ruotati mantengono l'allineamento al proprio volume.

L'occlusione viene registrata per singola mesh: solo quelle attraversate dai raggi busto/testa ricevono il taglio. Le mesh vicine che non coprono il giocatore rimangono complete, anche se comprese nell'area di reveal di un altro oggetto. Le transizioni di apertura e chiusura sono indipendenti. Non si tratta ancora di selezione per singolo mattone o faccia all'interno della stessa mesh.

Le ante e i dettagli delle aperture sono esclusi dal reveal e dai suoi trigger. Le porte restano a tutta altezza anche nel cutaway interno. La porta utilizzabile più vicina riceve un contorno dorato con normale test di profondità, coerente con il prompt E: apri/chiudi; il contorno scompare allontanandosi. Non è un indicatore attraverso muri opachi.

Validazione: Play GPU con passaggio attraverso il portone, ripristino nel cortile aperto, riattivazione dietro il muro, collisioni e camminamento. Aggiunti controlli per raggio nullo sulle mesh non ostruenti, porta esclusa e a piena altezza, highlight della porta vicina. Test delle sezioni: vuoti delle stanze, porte, spessori e orientamento di un volume ruotato. Screenshot: open_castle_revealed.png e open_castle_door_highlight.png in captures/balcony_attachment.


#### A09.10 — Prima passata di rilievo della muratura

La porzione pietra del materiale painted_architecture usa un campo di altezza metrico: blocchi con larghezza variabile, file sfalsate, angoli smussati e fughe arretrate. Il gradiente del campo modifica la normale in illuminazione; AO e pigmento mantengono leggibili i giunti senza dipingere una direzione del sole. La palette deriva ancora dall'atlante esistente. Legno e tegole mantengono i loro materiali.

House espone Wall Finish: Intonaco / Pietra, disponibile anche sui volumi derivati e sulle torri. Le cortine continuano a usare la finitura in pietra. La scena separata `scenes/dev/masonry_relief_example.tscn` conserva il castello del builder, con torri in pietra e camera ortografica di dimensione 17.5. Si può modificare normalmente e confrontare con l'esempio precedente. Gli edifici già salvati non cambiano automaticamente finitura d'intonaco.

Limite: questa è una passata di bump procedurale, non displacement geometrico o parallax. Lo spessore apparente delle fughe reagisce alla luce, ma non proietta nuove ombre geometriche e non cambia la silhouette dei singoli blocchi. Angoli e merli conservano la geometria esistente; pietre d'angolo modellate e raccordi del pattern fra facce restano da sviluppare.

Verifica GPU D3D12 tramite `tools/preview_masonry_relief.gd`: confronto prima/dopo a luce invariata e seconda direzione radente, screenshot masonry_before/front/raking.png. Il test Play del castello passa ancora per reveal selettivo, porte, collisioni e camminamenti. Non è un benchmark prestazionale su scala villaggio.


#### A09.11 — Campione di muratura con pietre modellate

Scena di confronto: `scenes/dev/solid_masonry_comparison.tscn`. A sinistra il materiale attuale; a destra il campione geometrico generato da `stone_wall_sample.gd`. Width, Height e Stone Seed restano modificabili nell'Inspector. La geometria interna si rigenera senza salvare un nodo per ogni pietra.

Il campione comprende 71 blocchi, ciascuno con facce frontali leggermente irregolari, smussi, sporgenza e inclinazione variabili. La malta è arretrata. Il materiale usa una palette grigia poco satura, con variazioni calde/fredde e superficie opaca. Le ombre nelle fughe e il profilo dei blocchi derivano dalla geometria, non dal bump. Tutti i blocchi condividono una mesh e un materiale (circa 4.544 triangoli per le pietre del campione, oltre al nucleo).

Validazione grafica D3D12: camera ortografica 17.5 per confronto alla scala di gioco, camera 9 per dettaglio, seconda direzione di luce radente. `tools/preview_solid_masonry.gd` salva la scena e tre screenshot solid_masonry_comparison/detail/raking.png. Esecuzione conclusa con SOLID_MASONRY_SAMPLE_OK.

È un prototipo visivo separato: non sostituisce ancora la muratura di case e castelli, non ha collisioni né integrazione con porte/reveal. Dopo la valutazione visiva, il lavoro successivo è adattare la generazione alle superfici del builder, preservando aperture, angoli e sezioni del cutaway. Il confronto cambia anche la palette: non è una misura isolata dell'effetto della sola geometria.


#### A09.12 — Coesione della muratura e variante economica

Campione aggiornato: nucleo di malta più vicino alle facce, variazioni ridotte di sporgenza e colore, fughe variabili, smussi diversi lungo lo stesso blocco. Una variazione cromatica continua attraversa più pietre, con lieve deposito nella fascia bassa. Rimane un campione separato, non un aggiornamento dei muri di produzione.

Inspector del campione: Detail Mode = Dettaglio / Economica. La modalità economica mantiene seed, numero e disposizione delle pietre; conserva i blocchi di bordo completi e semplifica quelli interni, omettendo le superfici posteriori coperte dal nucleo e riducendo la triangolazione delle facce. Il nucleo chiude il retro; non usare questo prototipo per generare aperture o sezioni senza adattare la geometria nascosta.

Confronto misurato sulle mesh: 72 pietre, 4.608 triangoli in dettaglio e 2.802 in economica (-39,2%), più 12 triangoli del nucleo in entrambi i casi. Due mesh/materiali per pannello, non un nodo per pietra. Questa riduzione non implica lo stesso guadagno in FPS: manca ancora una misura su un castello completo e non è presente selezione LOD automatica.

Scena di confronto `solid_masonry_comparison.tscn` e variante salvata `solid_masonry_economical.tscn`. Preview GPU completata con luce frontale e radente; la prova controlla uguaglianza del numero di pietre e riduzione dei triangoli superiore al 20%. Screenshot detail/economical usano stessa camera e luce. Il materiale con normali per distanze maggiori resta un passaggio futuro.


#### A09.13 — Rivestimento del castello e pietra sotto l'intonaco

`masonry_cladding.gd` integra i blocchi della variante economica nelle mesh Walls del builder, prima delle sottrazioni per volumi e aperture. La pietra segue le facce dei volumi, incluse le torri ottagonali. Le cortine orizzontali usano il rivestimento geometrico; le torri del nuovo castello aperto nascono con Wall Finish = Pietra. L'esempio `castle_open_courtyard_example.tscn` è aggiornato. Camminamenti e merli mantengono il materiale con rilievo, ora con palette grigia coerente.

Per Wall Finish = Intonaco e Weathered attivo, viene generata muratura arretrata sotto la facciata. Il materiale dell'intonaco apre le chiazze consumate e mostra pietre e fondo di malta reali. I tagli riguardano la fascia di parete esterna: i timpani sopra Wall Height mantengono per ora la colorazione d'usura precedente. Weathered disattivato conserva l'intonaco integro. Volumi aperti e cortine inclinate mantengono il percorso precedente, senza rivestimento geometrico non adattato alla loro forma.

Collisioni separate: `_collision_shell` conserva la mesh semplice del muro e riceve le stesse sottrazioni per aperture e volumi. I blocchi decorativi non diventano ostacoli fisici. Il reveal selettivo e le sezioni operano sulla mesh visiva; il materiale della pietra supporta gli stessi parametri di taglio. Porte e cornici restano escluse come prima.

Verifica GPU: `check_masonry_integration.gd` conferma muratura sotto ogni facciata, parametri dell'intonaco e finitura delle torri. Nella casa di prova: 10.075 triangoli visivi contro 546 nella collisione del muro. `check_open_castle_play.gd` passa ingresso, cortile libero, riattivazione reveal, porte e camminamenti. Screenshot integrated_masonry_castle/plaster.png. Non c'è ancora LOD automatico: aumenta la geometria visiva e il tempo di rigenerazione nell'editor; non è una validazione prestazionale di un villaggio completo.

Validazione aggiuntiva A09.13: suite editor completata con HOUSE_EDITOR_ALL_OK (restano gli avvisi preesistenti di ownership degli arredi). Il test di integrazione controlla anche la separazione fra mesh visiva e collisione per una casa con ala laterale.


#### A09.14 — Lastre del camminamento e occlusione nei giunti

Le superfici orizzontali della pietra usano un disegno distinto dalle pareti: lastre rettangolari di dimensioni miste, suddivisioni variabili e giunti sfalsati. Smussi e fughe sono generati nello shader in scala metrica, con rilievo più contenuto rispetto alla muratura verticale. La variazione dipende dalla posizione e non ripete una singola immagine di mattoni. Nessun ornamento moderno è stato trasferito dalle referenze.

I blocchi geometrici portano valori di occlusione sui vertici: contatti e basi degli smussi più scuri, facce quasi libere dall'occlusione aggiuntiva. Il dato è conservato anche nel rivestimento del castello dopo le sottrazioni per aperture. Aumentata l'influenza dell'AO dei materiali; non sono state scurite globalmente le luci né modificata la risoluzione delle shadow map. Le ombre proiettate restano quelle della geometria esistente.

Validazione: check_masonry_integration verifica presenza dei valori AO, muratura sotto l'intonaco, collisioni semplici e produce viste frontale/radente in integrated_masonry_castle/raking.png. Numero di triangoli invariato: per la casa campione 10.075 visivi e 546 nella collisione. Il pavimento conserva il rilievo shader, non aggiunge geometria alle lastre.


#### A09.15 — Merli geometrici e conci d'angolo

Merli, parapetti e copertine del tetto piano ora usano blocchi geometrici in corsi, con il materiale solid_masonry e smussi proporzionati alle dimensioni. Non riutilizzano il vecchio motivo di mattoni proiettato sui blocchi piccoli. I tagli per accesso alle scale e i raccordi fra torri/cortine conservano gli intervalli del generatore esistente; il camminamento mantiene le lastre.

`corner_masonry.gd` individua estremità coincidenti delle facce e aggiunge conci che avvolgono lo spigolo, con bracci lunghi/corti alternati per corso. Il profilo segue l'angolo fra le facce, inclusi gli spigoli ottagonali; le sottrazioni di porte e volumi vengono applicate successivamente. I conci si aggiungono al rivestimento visivo, senza aumentare il collision shell. Nelle torri ottagonali con Wall Finish = Pietra i montanti lignei agli spigoli sono rimossi; restano sulle torri intonacate.

Verifica GPU completata: screenshot integrated_masonry_corner.png, test integrazione e test Play con porte, reveal e supporto dei camminamenti. Il test Play è passato prima dell'ultima rimozione dei montanti lignei; la vista GPU e il test d'integrazione sono stati rieseguiti dopo. Aumenta la geometria del coronamento; non è un benchmark di villaggio e non è presente LOD automatico.


#### A09.16 — Rimozione del vecchio materiale sotto i blocchi

Il corpo di torri in pietra e cortine rivestite usa ora un materiale di malta neutro, senza atlante a mattoni. Anche le fasce verticali di pietra del materiale condiviso eliminano il reticolo precedente quando è disponibile il rivestimento geometrico; le superfici orizzontali conservano le lastre del camminamento. Le cortine inclinate non rivestite mantengono il materiale precedente come fallback.

Verifica GPU ravvicinata e check_masonry_integration: materiale di fondo solid_masonry con colore uniforme sulle torri/cortine, nessun atlante sul substrato; geometria e collisioni restano invariate. Screenshot integrated_masonry_corner.png aggiornato.


#### A09.17 — Pavimenti geometrici dei camminamenti

`flagstone_floor.gd` riveste i tetti piani con lastre di larghezza variabile, smussi, colore e occlusione ai contatti della muratura geometrica. Il fondo usa malta neutra senza il precedente pattern shader. Le lastre vengono ritagliate sulle facce finali del pavimento: rispettano profili poligonali, raccordi e aperture delle scale. Una sola superficie aggiuntiva per camminamento, senza nodi per lastra; aumenta comunque il numero di triangoli e non introduce LOD automatico.

Le collisioni sono costruite prima del rivestimento e rimangono semplici. Il rilievo è inferiore a 3 cm. Le cortine inclinate/a gradini conservano per ora il profilo e il materiale dedicati precedenti.

Verifica: check_masonry_integration supera il confronto verticale fra pavimento originale e decorato su torri e cortine (bordi, vuoti delle scale e altezza); screenshot GPU integrated_masonry_castle.png aggiornato. check_open_castle_play supera porte, reveal/ripristino e supporto del giocatore sul camminamento.


### G01 — Compositore da metadati (priorità attuale)

Obiettivo: separare evoluzione del vocabolario architettonico ed evoluzione delle regole di composizione. A02–A09 restano il backlog dei componenti; non vengono dichiarati completi da questa fase. Le rifiniture dei materiali non sono il prossimo passo principale.

Pipeline: **Request → regole della famiglia → piano validato → adapter → builder esistenti → scena editabile**. Il planner non costruisce mesh e non conosce proporzioni o materiali delle case. Le regole implementano `request_errors`, `propose`, `validate`. L'adapter associa i ruoli del piano ai builder. `ArchitectureProfile` e `BuildingRequest` esistenti restano contratti dei singoli edifici; le regole di composizione non li sostituiscono.

- [x] G01.1 Scheletro: richiesta Resource con seed, intervallo dimensioni e quota minima scoperta; piano schema 1, ID semantici, seed locali; validazione e tentativi limitati.
- [x] G01.1 Prima famiglia single_court: quattro torri ottagonali, un mastio, un corpo servizi; variazioni di dimensioni, proporzioni del recinto, lato del mastio e posizione arretrata. Adapter tramite Fortification Factory, Keep Factory e BuildingRequest.
- [x] G01.1 Esempio editabile `scenes/dev/castle_generated_seed17.tscn`; test 100 seed e diagnostica del builder su seed 17.
- [x] G01.2 UI contestuale in Fortificazioni → Crea → Genera: seed, dimensioni, quota scoperta, pianta leggera, diagnostica e creazione di un nuovo gruppo tramite Undo/Redo. Confronto sequenziale con seed successivo; nessuna sostituzione implicita.
- [ ] G01.3 Persistenza delle modifiche: baseline, override e lock per ID, rigenerazione locale con Undo/Redo; test che porte spostate e torri bloccate sopravvivano. Gli ID attuali sono solo la fondazione, non implementano questa protezione.
- [ ] G01.4 Catalogo ruoli → componenti/profili architettonici. Nuove forme estendono catalogo/adapter; nuove disposizioni estendono regole. Segnalare capacità mancanti, mai sostituire silenziosamente una forma.
- [ ] G01.5 Recinti più grandi con cortine segmentate, numero variabile di torri, perimetri non rettangolari; validazione dei collegamenti e degli accessi.
- [ ] G01.6 Più corti e quote, metadati di funzione/ricchezza separati dalla famiglia architettonica, vincoli terreno; integrazione insediamento A11.
- [ ] G01.7 Validazione navigabilità/visibilità in Play per una matrice di seed, budget mesh e tempi; preservazione manuale end-to-end.

Limiti G01.1: distanza fra centri delle torri 26–27 m su ciascun asse, per rispettare le cortine attuali; altezza e topologia delle torri rimangono fisse. La percentuale scoperta usa il rettangolo interno conservativo con margine di 5 m, sottraendo gli ingombri dei due edifici. Verifica geometrica dei passaggi, non prova di navigabilità. Niente terreno o rigenerazione in-place. Il piano viene conservato nei metadata del nuovo gruppo; gli elementi restano nodi parametrici modificabili. Materializer supporta esplicitamente solo schema/famiglia iniziali, non promette un adattatore universale.

Uso: `tools/preview_generated_castle.gd` genera e salva l'esempio seed 17 e una cattura Godot; `tools/check_castle_generator.gd` verifica determinismo, 100 piante distinte, vincoli, richiesta impossibile e raccordi del gruppo realizzato. Il test non certifica 100 castelli in Play.

**Prossimo incremento: G01.3, override e lock**, prima di introdurre qualsiasi comando che rigeneri un gruppo editato.


#### G01.2 — Anteprima contestuale e confronto richiesto

Il pannello separa Preset e Genera sotto Crea, mantenendo gli strumenti Recinto/Quote/Vista. Il contenitore scrollabile esistente resta attivo. L'anteprima disegna il piano 2D senza istanziare edifici; richieste impossibili cancellano la vecchia anteprima e disabilitano la creazione. La creazione passa per `_add_authored`, con la normale azione Undo/Redo del plugin. Test automatico del pannello: cambio seed, riproducibilità, segnale con il piano esatto, errore e recupero. Controllo sintattico del plugin; Undo/Redo non ancora provato interattivamente per questo nuovo comando.

- [ ] **Confronto di quattro castelli richiesto dall'utente:** produrli esclusivamente con il generatore, salvare richiesta/seed e scene editabili; catture alla stessa camera e scala. Attivare quando la varietà supera il semplice cambio dimensioni/posizioni della corte rettangolare: almeno due organizzazioni del complesso e differenze leggibili in numero/disposizione dei corpi o torri. Non selezionare quattro seed quasi identici per dichiarare completata la varietà.

Questa consegna resta nel backlog ed è collegata a G01.4–G01.5. La prima famiglia attuale non soddisfa ancora il criterio; nessuna promessa che quattro stili architettonici siano già disponibili.


#### G01.3a — Rigenerazione conservativa della disposizione

Implementato il primo passo di G01.3. In Genera: Anteprima rigenerazione del selezionato e Blocca/sblocca elemento selezionato. Le posizioni dei corpi interni vengono confrontate con la baseline, associata agli ID; un corpo spostato manualmente resta dov'è anche dopo rigenerazioni ripetute. I lock sono metadata persistenti. La proposta mostra posizioni prima/dopo ed elementi preservati; alla conferma viene ricalcolata per rifiutare una scena modificata nel frattempo. Applicazione tramite Undo/Redo senza sostituzione dei nodi.

Questa fase muove solo i corpi interni automatici. Non cambia dimensioni, dettagli, seed locali, porte, arredi o interni. La richiesta viene ricalcolata sulle dimensioni del recinto selezionato. Recinti modificati, edifici ruotati/scalati, quote diverse, ID mancanti/duplicati e volumi aggiuntivi richiedono un'estensione della validazione e vengono segnalati. Sovrapposizioni con corpi preservati bloccano l'operazione. La baseline mantiene il riferimento precedente per gli override manuali; sbloccare un elemento non cancella una modifica manuale alla posizione.

Test check_castle_regeneration: porta modificata e nodo manuale preservati, override ripetuto, lock, conflitto senza applicazione, Undo/Redo e round-trip PackedScene con baseline/lock. Test di modello senza mesh in scena; controllo sintattico plugin. Non è ancora la verifica interattiva completa del comando nell'editor.

- [x] G01.3a Disposizione interna conservativa, baseline/lock persistenti, anteprima e Undo/Redo.
- [ ] G01.3b UI dello stato per elemento e reset esplicito degli override; validazione degli ingombri orientati/accessori e prova editor/Play.
- [ ] G01.3c Rigenerazione delle dimensioni e della struttura con protezione per proprietà, aggiunte/rimozioni e migrazioni degli ID.

Il confronto dei quattro castelli resta previsto dopo l'ampliamento della varietà architettonica/compositiva; questo passo non lo sostituisce.


#### G01.3b.1 — Stato degli elementi e ritorno al controllo automatico

Genera ora contiene due sotto-schede, Proposta ed Elementi. La lista contestuale del castello selezionato mostra posizione automatica/manuale/bloccata; cliccare una riga seleziona il nodo nell'editor. Le torri riportano che la rigenerazione del recinto non è disponibile. Lo stato riguarda la posizione, non pretende di classificare ogni dettaglio dell'edificio.

Rendi posizione automatica aggiorna la baseline alla posizione corrente e rimuove il lock: non muove il nodo e non cancella porte/dettagli. Alla prossima proposta la sua posizione torna disponibile al generatore. L'azione è annullabile; sbloccare soltanto un nodo mantiene invece l'eventuale override manuale della posizione. UI aggiornata ogni 0,4 secondi con la selezione e le modifiche dell'editor.

Verifica: check_castle_element_ui testa stato, rilascio, Undo/Redo, nessuno spostamento immediato, porte preservate, torri non supportate e assenza di selezione; cattura Godot castle_element_states.png. Rieseguiti check_castle_regeneration e check_castle_composition_ui. Plugin verificato sintatticamente. Non ancora test end-to-end della selezione e del comando Undo nell'editor interattivo.

- [x] G01.3b.1 UI stato per elemento e reset esplicito dell'override di posizione.
- [ ] G01.3b.2 Ingombri orientati/accessori e verifica editor/Play: rimane il prossimo incremento della protezione.

Il confronto dei quattro castelli rimane nel TODO G01.4–G01.5, subordinato alla varietà strutturale.


#### G01.3b.2a — Ingombri orientati e accessori dei corpi interni

`castle_generator/footprints.gd` legge l'authoring e produce poligoni XZ, senza mesh e senza modificare transform durante la proposta. Supporta rotazione sul piano Y e volumi accessori rettangolari, anche annidati; per gli agganci calcola il transform dalle stesse proprietà del builder. Le proposte traslano gli ingombri mantenendo orientamento e dimensioni correnti.

La validazione usa separazione dei poligoni e distanza fra segmenti per riservare almeno 1 m fra edifici differenti. Gli accessori dello stesso edificio possono intersecarsi con il corpo principale. Tutti i vertici devono restare nel rettangolo interno con margine dalle mura. La superficie occupata è una somma conservativa: eventuali sovrapposizioni interne possono ridurre la stima di spazio scoperto e produrre un rifiuto prudenziale. Non è un calcolo dell'unione esatta né una prova di navigabilità delle porte.

Snapshot di rigenerazione esteso agli ingombri: spostare o ridimensionare un accessorio invalida una proposta aperta prima della conferma. Restano rifiutati scala, inclinazione, ali integrate legacy e accessori delle torri; tetti sporgenti e props arbitrari non fanno parte di questi ingombri di authoring.

Test `check_castle_footprints`: corpi orientati separati con AABB sovrapposti, sovrapposizione reale, accessorio fuori recinto, passaggio ostruito, raccolta agganci senza mutazioni, modifica accessorio rilevata nello snapshot, scala non supportata. Rieseguiti test rigenerazione e UI stati, con Undo/Redo e round-trip. Verifica geometrica automatica; prova end-to-end editor/Play ancora pendente.

- [x] G01.3b.2a Validazione orientata di corpi e volumi accessori.
- [ ] G01.3b.2b Verifica editor/Play della rigenerazione con accessori e rotazioni; diagnostica visuale degli ingombri.

Prossimo incremento: G01.3b.2b, prima di ampliare il catalogo per il confronto dei quattro castelli.


### Coordinamento con il paesaggio e il concept

Il concept delle quattro fazioni guida solo la composizione. Nuovo backlog trasversale in [WORLD_GENERATION_ROADMAP.md](WORLD_GENERATION_ROADMAP.md): rocce stratificate, gruppi e montagne, laghi/fiumi, attraversamenti e grotte, composizione urbana e dipendenze fra generatori. Il flusso corrente resta G01.3b.2b; R01 è il successivo prototipo ambientale circoscritto. Il confronto dei quattro castelli rimane previsto quando il catalogo e le regole forniranno sufficiente varietà.


Vincolo confermato per il paesaggio: superfici prevalentemente piane, terrazze a quote discrete, rampe brevi e rare; niente città distribuite su pendenze continue. I profili rocciosi delimitano le aree o separano i piani. Dettagli in WORLD_GENERATION_ROADMAP.md.


### G01.3b.2b — Diagnostica e verifica editor/Play completate

La proposta di rigenerazione include un diagramma dei contorni reali dei corpi e degli accessori, con margine interno del recinto. In caso di conflitto viene mostrata una diagnostica grafica senza applicare la proposta. Il diagramma è contestuale alla conferma, non aggiunge gizmo persistenti alla scena.

Verifiche: `check_castle_composer_editor.gd`, avviato tramite --castle-composer-editor-test nel vero EditorPlugin, supera selezione, lock, rilascio della posizione, conferma rigenerazione e Undo/Redo con un corpo ruotato e accessorio. `check_composed_castle_play.gd` supera ingresso dal portone, persistenza dell'accessorio e collisione del muro ruotato dopo generazione/salvataggio/Play. Screenshot composed_castle_footprints_play.png. Restano nei log i warning preesistenti di organizzazione arredi in plan.gd, estranei a questi assert.

- [x] G01.3b.2b Diagnostica visuale, percorso reale editor e prova mirata Play.

Prossimo prototipo ambientale: R01 (roccia parametrica); sviluppo compositivo successivo G01.4–G01.5. Il terreno resta prevalentemente piano con quote discrete, secondo WORLD_GENERATION_ROADMAP.md.


### A07.4 — Ripresa prioritaria: torri segmentate

Su richiesta dell'utente A07 viene prima della modalità assistita B01. Disponibili nel tab Volumi: torre ottagonale, torre a 12 facce e torre a 16 facce. Le nuove torri più arrotondate hanno diametro iniziale 8 m, modificabile come larghezza/profondità; conservano il linguaggio materiale esistente. Non sono cilindri matematici: pareti planari segmentate consentono di usare i vani e le collisioni del builder.

Il numero di facce si sceglie alla creazione. Nell'editor, cambiarlo su una torre con aperture, interni o figli è rifiutato con avviso per evitare di riassegnare i riferimenti numerici delle pareti; usare una nuova torre. Ridimensionare larghezza e profondità resta disponibile. Questo limite è intenzionale e non costituisce ancora un remapping generale della topologia.

Corretta la risoluzione delle aperture condivisa, che limitava gli indici a 7: usa ora wall_count(). I test controllano tutte le facce nelle tre varianti, porta aperta sull'ultima faccia, collisione del tetto e round-trip PackedScene. Superata anche la regressione della torre ottagonale con porta obliqua e scala. Parser del plugin verificato; prova interattiva delle nuove varianti e interni a 12/16 facce ancora da eseguire, prima di chiudere A07.

Esempio: scenes/dev/segmented_towers_example.tscn. Screenshot reale: captures/balcony_attachment/segmented_towers.png. Script: tools/preview_segmented_towers.gd, tools/check_segmented_towers.gd. Prossimo A07.5: copertura conica, poi cupola; A07 complessivo resta IN CORSO.


### A07.5 — Copertura conica parametrica

Sulla torre poligonale, Inspector → Tower Roof: Terrazza / Conico. Roof Height controlla l'altezza del cono; larghezza/profondità e numero di facce restano quelli del corpo. La copertura ha gronda di 0.3 m, sottofondo scuro e tegole geometriche rastremate disposte per faccia, con il materiale roof_clay esistente. Una superficie mesh; non un nodo per tegola. Il backend conical_roof.gd è separato dalla torre. I merli/parapetti della terrazza rimangono nei parametri e tornano visibili passando alla terrazza.

Il tetto conico ha collisione ma non è un piano di accesso. Il passaggio al cono viene rifiutato quando è presente una scala esterna abilitata o un'uscita interna sul tetto. Disattivare la scala esterna oppure togliere roof_exit alla scala interna prima del cambio. Il preset UI per aggiungere una scala interna al tetto rifiuta il cono. Modifiche manuali successive incompatibili producono un avviso di configurazione: non viene eliminato il contenuto della torre.

Test check_conical_towers.gd: tre topologie, triangoli finiti e non degeneri, determinismo, una superficie e meno di 30000 triangoli per ciascun esempio provato, collisione inclinata, salvataggio, ritorno a terrazza e protezione scala. Regressione torre ottagonale superata; parser plugin verificato. Nessun benchmark su molti edifici, nessun nuovo Play degli interni in questo incremento. Copertura ancora segmentata; colmi speciali, danni delle tegole e aperture/abbaini sul cono non implementati.

Esempio editabile scenes/dev/conical_towers_example.tscn; render GPU captures/balcony_attachment/conical_towers.png. Prossimo A07.6: cupola e profilo curvo, poi consolidamento A07.7. B01 resta successivo ad A07.


### A07.6a — Profilo a cupola disponibile

Inspector della torre → Tower Roof → Cupola. Roof Height regola la rise; il profilo verticale è un quarto d'ellisse, campionato in fasce e raccordato alle 8/12/16 facce del corpo. Non è una curva libera né un profilo a cipolla. Il backend delle coperture ha una funzione di profilo condivisa: cono lineare e cupola curva usano lo stesso emettitore di tegole. Il sottofondo segue la curvatura, le tegole sono sollevate lungo la normale locale. Restano una mesh/superficie e il materiale roof_clay esistente.

Cupola e cono condividono protezione degli accessi, collisione e ritorno alla terrazza. Non vengono cambiati numero di facce, aperture o dettagli manuali. Esempio scenes/dev/domed_towers_example.tscn con altezze 1.8, 3.5 e 5 m; capture captures/balcony_attachment/domed_towers.png. Test check_domed_towers.gd: tre topologie, geometria finita/non degenere, determinismo, budget del campione, collisione, salvataggio e scala protetta. Regressione check_conical_towers.gd superata. Render GPU ispezionato; nessun nuovo test di cammino in questo incremento.

A07.6 resta IN CORSO: la sua uscita include un edificio terrazzato con volume a cupola, non solo tre torri. Prossimo A07.6b prima di A07.7. Il passo rifinisce forme e strumenti, non riapre la generazione globale da seed.


### A07.6b — Edificio terrazzato con padiglione a cupola

Nel tab Volumi: **Crea edificio terrazzato con cupola**. La factory compone un volume rettangolare a tetto piano (14 × 12 m, quota tetto 3.18 m), scala esterna centrale con varco nel parapetto e padiglione a 12 facce sulla terrazza. Cupola, pareti, porta e finestra usano i builder esistenti. Il comando crea nodi editabili con l'azione Undo/Redo di authoring condivisa; non produce una mesh monolitica né richiede un seed di composizione.

La scala è agganciata alla terrazza; il padiglione è un volume indipendente posizionato sulla sua quota iniziale. Se si cambia altezza del basamento, occorre aggiornare manualmente la quota del padiglione: questo esempio non implementa ancora un vincolo verticale fra corpi. Il basamento non ha ingresso o interni arredati. La porta del padiglione parte aperta; il Play consente di azionarla con E vicino alla soglia.

Esempio salvato: scenes/dev/domed_terrace_example.tscn. Prova F6: scenes/dev/domed_terrace_playable.tscn (WASD / E), che carica la scena salvata e usa player3. Il test check_domed_terrace_play.gd guida il vero controller terreno→scala→terrazza→padiglione→terreno e verifica le quote, il passaggio della soglia e il ripristino della cupola all'uscita. Il taglio visivo è attivato solo entrando nel padiglione; collisioni restano fisiche. Render esterno domed_terrace.png e interno domed_terrace_inside.png ispezionati. Parser plugin verificato; il click del nuovo comando/Undo in editor non è stato provato interattivamente in questo incremento.

A07.6 è concluso secondo il suo esempio di uscita; A07 generale resta IN CORSO. Prossimo A07.7: consolidamento degli interni sulle topologie 12/16, raccordi e diagnostica delle combinazioni non supportate, prima della modalità B01.
