# Piano evolutivo dei generatori architettonici

Aggiornato: **2026-09-13**. Baseline del codice esaminato: `e0c9cd5`.
Stato: **analisi dei riferimenti completata; implementazione delle nuove fasi da iniziare**.
Questo documento è il registro da aggiornare a ogni incremento, non una lista di
funzionalità già disponibili.

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
| A02a | IN CORSO | Componenti agganciati: balcone + porta | A01 | Vano, collisione e aggancio aggiornati senza perdere le modifiche manuali |
| A02 | TODO | Composizione di più volumi rettangolari | A01 | Fucina R04 con corpo e tettoie modificabili indipendentemente |
| A03 | TODO | Coperture indipendenti e parti aperte | A02 | Falde a quote diverse, portico e tetto piano; raccordi senza geometria interna superflua |
| A04 | TODO | Piani e interni coerenti con i volumi | A02, A03 | Casa R02: ingresso, scala esterna/interna, piano superiore percorribile |
| A05 | TODO | Facciate e strutture per campate | A03, A04 | Graticcio e portico: travi e aperture seguono la struttura senza invadere i vani |
| A06 | TODO | Due archetipi completi con profili architettonici | A04, A05 | Fucina e sala nordica: differenze leggibili nelle forme e negli interni |
| A07 | TODO | Piante poligonali, torri e coperture curve | A03–A06 | Torre quadrata/circolare, terrazza con cupola; caso elfico separato |
| A08 | TODO | Primo Castle Builder: cortina, torri e porta | A04, A07 | Castello piccolo con cortile e percorso giocabile ingresso→mura→torre |
| A09 | TODO | Complessi articolati e castelli multilivello | A08 | Mastio, corpi accessori, più corti, raccordi e quote indipendenti |
| A10 | TODO | Rovine strutturali controllabili | A03, A04, A07 | R07: togli una porzione di tetto/muro, interno e collisione coerenti |
| A11 | TODO | Integrazione insediamento e consolidamento | Incrementale; chiusura dopo A08 | Case e castello nello stesso villaggio, rigenerazione locale e budget misurati |

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

- [ ] Nodi dati `Volume`: pianta rettangolare, quota, altezza, orientamento e ID.
- [ ] Duplicazione, ridimensionamento e movimento di una sola parte con gizmo locale.
- [ ] Agganci opzionali; possibilità di sganciare e spostare liberamente.
- [ ] Confini condivisi espliciti: parete comune, passaggio aperto, semplice contatto.
- [ ] Trattare la casa a L esistente come due volumi nell'adattatore, senza spostamenti.
- [ ] Conservare aperture agganciate quando si muove la relativa parte.

**Uscita:** almeno tre volumi con quote differenti, salvataggio/undo e preview di
un raccordo problematico. L'utente può scollegare un volume senza perdere gli altri.

### A03 — Tetti e parti aperte

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

### A07 — Geometrie non rettangolari

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
se editing, salvataggio o Play richiesti non funzionano. Tenere il primo prossimo
passo su **A01**, poi **A02a: balcone agganciato + porta**, quindi la fucina multi-volume
di **A02**.
