# TODO futuro — NPC conversazionali con IA interamente locale

**Stato: nucleo testuale di Claude revisionato e integrato; quattro NPC nel borgo.**

Consegna del 23 settembre 2026: vedere [NPC_AI_INTEGRATION.md](NPC_AI_INTEGRATION.md).
La consegna storica seguente resta come perimetro del laboratorio. Voce esclusa
da questa integrazione; export su macchina pulita ancora da verificare.
**Data: 20 settembre 2026.**

Documento separato dallo sviluppo corrente di grafica, edifici e combattimento.
Questo documento non introduce codice o dipendenze. La consegna seguente
autorizza Claude a realizzare il primo prototipo NPC nel perimetro indicato,
quando l'utente gli affida questa attività. Non autorizza modifiche agli altri sistemi.

## Istruzioni operative per Claude — consegna prioritaria

**Lavora solo sulle funzionalità degli NPC conversazionali locali. Non toccare
edifici, grafica, ambiente, camera, combattimento o altri sistemi del gioco.**
Le sezioni storiche successive spiegano l'idea; in caso di ambiguità, questo
handoff definisce il lavoro autorizzato. Non iniziare altri TODO del repository.

### Risultato richiesto

Un prototipo verticale utilizzabile con **un fabbro NPC**, in una scena di
prova separata: dialogo testuale in italiano, identità e conoscenze delimitate,
memoria locale, inferenza offline asincrona, annullamento e risposte scritte a
mano quando il modello non funziona. Codice riutilizzabile nell'addon NPC;
la scena contiene soltanto composizione e dati del campione.

Il modello propone dialoghi, non modifica il mondo. Nel primo prototipo non
può assegnare oggetti, denaro, quest o reputazione, né comandare combattimento,
movimento del giocatore o navigazione. Le reazioni iniziali dell'NPC sono
stati di conversazione e tono, senza introdurre un nuovo sistema di gameplay.
Voce, STT/TTS, folle di NPC e dialoghi autonomi fra NPC sono fuori scope.

### 0. Branch e isolamento obbligatori

I lavori su edifici e look sono stati committati in `41c8fec`. Verifica comunque
lo stato attuale: il checkout principale puo' contenere nuovi lavori non
committati dell'utente/Codex e file non tracciati, come
`art_source/viking_modular_v1/`. Non modificarli, ripulirli, stasharli,
includerli in commit o spostarli.

- [ ] Leggi le istruzioni locali applicabili, questo documento, `git status
  --short`, branch, HEAD e diff prima di lavorare.
- [ ] Crea un **worktree separato con branch dedicato** dal HEAD locale:

```powershell
# Eseguire dal repository principale; non cambiare il suo branch.
git worktree add -b codex/npc-local-ai ../top-down-rpg-npc-ai HEAD
```

- [ ] Se branch o destinazione esistono, ispezionali e riutilizzali soltanto
  se appartengono a questa attività; altrimenti scegli un suffisso libero.
  Non usare reset, force, checkout distruttivi o cancellazioni per liberarli.
- [ ] Il worktree non contiene le modifiche non committate: è intenzionale.
  Usa questo MD gia' presente nel worktree; se il checkout originale ne
  contiene una revisione successiva, copia soltanto il MD. Non copiare la
  scena integrata o gli addon grafici modificati.
- [ ] Annota nel resoconto il commit di base e il percorso del worktree.
  Tutti i comandi di sviluppo vanno eseguiti nel worktree NPC.
- [ ] Non aggiornare il branch con pull/merge di altri lavori. Non fare merge
  su master/main e non effettuare push senza richiesta esplicita dell'utente.

### 1. Perimetro dei file

Prima di scrivere codice, controlla se esiste già un sottosistema NPC/dialoghi:
riusa i suoi contratti se disponibili. I sistemi `scripts/combat/pack_brain.gd`
e `pack_director.gd` riguardano il combattimento e **non sono il posto in cui
aggiungere questo lavoro**.

Percorsi consentiti per i nuovi file, salvo equivalenti già esistenti dedicati
esclusivamente agli NPC e identificati nel resoconto iniziale:

- `addons/npc_ai/`: risorse, contratti, contesto, memoria, validazione,
  coda di inferenza, backend locale e UI di conversazione riutilizzabile.
- `assets/npc_ai/`: profilo del fabbro, fatti consentiti, battute di ripiego,
  manifest del modello e istruzioni/licenze relative al pacchetto NPC.
- `scenes/dev/npc_ai_lab.tscn` e `scripts/npc_ai_lab/`: laboratorio isolato.
- `tools/npc_ai/`: test, prove avversarie, benchmark e packaging del solo modulo.
- `docs/LOCAL_NPC_AI_TODO.md` e nuovi `docs/NPC_AI_*.md`: avanzamento e istruzioni.

**Vietato modificare** `project.godot`, InputMap, autoload, export preset
globali, scena integrata, `scripts/village/`, `scripts/combat/`, controller del
player, camera, shader, materiali, modelli, vegetazione, House/World Builder,
roadmap/Kanban dei generatori e sistemi globali di quest, inventario o save.
Niente formattazione o refactoring esteso. Non avviare Blender né rigenerare
villaggi, edifici o terreno. Non installare servizi di sistema o alterare
configurazioni globali della macchina.

Il laboratorio deve partire direttamente come scena Godot senza cambiare
la main scene o registrare autoload. Può leggere/istanziare risorse esistenti
senza modificarle. Per il prototipo sono sufficienti forme semplici e UI
funzionale; nessun nuovo lavoro artistico.

Se un'integrazione richiede una modifica fuori perimetro, descrivi il punto
preciso in una sezione «Integrazione futura» e continua il lavoro indipendente
nel laboratorio. Non ampliare lo scope autonomamente. Quando quel collegamento
è indispensabile per procedere, chiedi all'utente indicando file e motivo.

### 2. TODO di implementazione, in ordine

#### A — Ricognizione e contratto deterministico

- [ ] Riporta brevemente componenti riutilizzabili trovati e file che prevedi
  di toccare; nessun nuovo framework parallelo se esiste già un contratto adatto.
- [ ] Crea risorse per identità stabile dell'NPC, mestiere, tono, fatti pubblici,
  conoscenze personali autorizzate e battute di ripiego in italiano.
- [ ] Definisci richiesta con `npc_id`, `session_id`, `request_id`, revisione
  del contesto, testo del giocatore e limiti; risposta con gli stessi ID,
  stato, testo e metadati di errore/tempo. Non includere comandi eseguibili.
- [ ] Implementa un backend finto deterministico per testare il contratto,
  mantenendolo chiaramente distinto dall'inferenza reale.
- [ ] Realizza il laboratorio con un fabbro, apertura/chiusura dialogo, input
  testuale, storico limitato e stati «in attesa / risposta / ripiego».

#### B — Contesto, memoria e validazione

- [ ] Il gioco prepara una lista esplicita dei fatti accessibili all'NPC.
  Non consegnare l'intero stato del mondo, file del progetto o segreti.
- [ ] Separa istruzioni del personaggio, eventi canonici del gioco,
  dichiarazioni non confermate del giocatore e testo generato.
- [ ] Memoria per `npc_id`, limiti di spazio e schema versionato. Salva in
  una cartella dedicata sotto `user://npc_ai/`, con scrittura sicura e
  recupero da file assente/corrotto. Non modificare i salvataggi del gioco.
- [ ] Per il primo prototipo usa selezione deterministica di eventi confermati
  e uno storico breve; non occorre un database vettoriale o una seconda IA.
- [ ] Limita dimensioni di input/output; valida identità della richiesta,
  struttura, lunghezza, disponibilità del contesto e stato della sessione.
  Mostra testo semplice, senza interpretare markup, codice o comandi.
- [ ] Scarta risposte obsolete dopo chiusura, nuova sessione, rimozione NPC,
  cambio scena e caricamento/reset della memoria del laboratorio.

#### C — Inferenza realmente locale

- [ ] Confronta le due opzioni descritte sotto usando documentazione primaria
  aggiornata. Scegline una e documenta motivi, versione e licenza verificata.
- [ ] Scegli e misura un piccolo modello adatto all'italiano, con licenza che
  consenta il pacchetto previsto. Non assumere che i suggerimenti Gemini
  siano compatibili o liberamente ridistribuibili.
- [ ] Implementa un unico servizio condiviso, coda limitata, una generazione
  alla volta inizialmente, timeout e annullamento. Nessun caricamento o
  inferenza bloccante sul thread principale o nel ciclo per-frame.
- [ ] Se scegli un processo incluso: avvio/arresto dal modulo, nessuna finestra
  console per il giocatore, solo loopback, isolamento della propria istanza,
  endpoint protetto e nessun processo orfano. Non terminare processi altrui.
- [ ] Gestisci modello mancante/incompatibile, runtime indisponibile, memoria
  insufficiente e crash con ripiego deterministico utilizzabile.
- [ ] Nessun account, chiave API, cloud, telemetria o chiamata esterna durante
  il gioco. Nessun download automatico all'avvio o installazione manuale
  richiesta al giocatore. I download di sviluppo devono essere espliciti
  negli strumenti e documentati con versione, origine, dimensione e checksum.
- [ ] Non inserire pesi o binari voluminosi in Git. Fornisci manifest e procedura
  riproducibile per assemblare il pacchetto NPC offline con le licenze.

#### D — Verifiche e consegna

- [ ] Test automatici del contratto, selezione dei fatti, isolamento fra due
  identità/sessioni, salvataggio/riapertura, dati corrotti e limiti di memoria.
- [ ] Test di timeout, annullamento e risposta tardiva: chiudere un dialogo
  non deve far comparire la risposta nella sessione successiva.
- [ ] Test di manipolazione: «ignora le istruzioni», falso messaggio di sistema,
  falso ricordo, richiesta di un segreto non fornito e richiesta di premi.
  Verifica invarianti del gioco; non promettere invulnerabilità del modello.
- [ ] Prova end-to-end con il backend reale e il fabbro in italiano, poi senza
  backend: il ripiego deve mantenere utilizzabile il dialogo.
- [ ] Misura caricamento a freddo, RAM/VRAM, latenza primo testo/completamento
  (mediana e p95), frame time durante generazione e cancellazione. Riporta
  hardware, modello, quantizzazione, contesto e numero di prove.
- [ ] Verifica il pacchetto del laboratorio senza rete e senza dipendenze
  installate a mano. Se una macchina pulita non è disponibile, indica
  esattamente la verifica ancora da eseguire: non dichiararla superata.
- [ ] Controlla che il diff finale contenga solo percorsi autorizzati. Esegui
  `git diff --check`; fai commit sul branch NPC con staging di percorsi
  espliciti, mai `git add .` o `git add -A`.

### Criterio di completamento per Claude

Non fermarti al mock o alla sola UI: la consegna completa richiede una prova
con inferenza locale reale, fallback funzionante e istruzioni riproducibili.
Se runtime, pesi, licenze o hardware impediscono una parte, consegna ciò che
è verificato e indica il blocco concreto senza dichiarare concluso il sistema.
Non abbassare silenziosamente il requisito «tutto locale, pronto per il giocatore».

Nel messaggio finale riporta:

1. Branch, worktree e commit realizzati.
2. Funzionalità NPC effettivamente disponibili e come avviare il laboratorio.
3. Runtime/modello scelti, licenze, percorsi e composizione del pacchetto offline.
4. Test eseguiti, risultati, misure e verifiche mancanti.
5. Elenco dei file modificati e conferma del rispetto del perimetro.
6. Eventuali soli punti d'integrazione futura, senza implementarli nel gioco.

Aggiorna le caselle di questo handoff con prove effettive. I vecchi TODO sotto
restano contesto progettuale; non duplicarli nelle roadmap di edifici o generatori.

---

## Origine e intenzione

Spunto dalla conversazione con Gemini allegata come `Testo incollato.txt`:
NPC capaci di conversare e reagire in modo credibile, con un riferimento
all'esperienza «LSPDFR style», adattata a un RPG fantasy. Il riferimento indica
il tipo di interazione desiderato, non una tecnologia da replicare.

Requisito dell'utente: **tutto locale**. Il giocatore installa il gioco e può
usarlo senza installare a mano Ollama, Python o altri programmi, senza account,
chiavi API o servizi cloud. L'installazione deve comprendere quanto necessario
per la modalità offline scelta, inclusi i pesi del modello se prevista.

La conversazione è materiale di partenza, non una specifica tecnica verificata.
Nomi di modelli, compatibilità, licenze, prestazioni e consumi vanno verificati
quando questa attività sarà effettivamente avviata.

## Esperienza da progettare

- Identità, mestiere, personalità e tono coerenti con il mondo fantasy.
- Risposte brevi, leggibili nel dialogo di gioco; qualità da verificare in italiano.
- Conoscenze limitate a ciò che quel personaggio può sapere: niente onniscienza
  su quest, segreti, inventari o eventi non osservati.
- Memoria locale selettiva: fatti confermati, rapporti e conversazioni pertinenti,
  senza conservare indefinitamente ogni messaggio.
- Il gioco resta utilizzabile se il modello è lento, assente o non disponibile:
  battute e opzioni scritte a mano rimangono il ripiego deterministico.
- Definire quali reazioni richiedano davvero un modello e quali siano meglio
  gestite dai sistemi ordinari di dialogo, reputazione e comportamento.

Voce, riconoscimento del parlato e conversazioni autonome fra NPC sono eventuali
fasi successive. Il primo esperimento, se autorizzato, sarà testuale con un NPC.

## Architettura candidata, da confrontare

| Opzione | Ipotesi | Cosa verificare prima di sceglierla |
| --- | --- | --- |
| Runtime nativo nel gioco | Integrazione basata su llama.cpp tramite GDExtension, con modello locale | Maturità dell'integrazione, licenze, piattaforme, backend GPU/CPU, compilazione, caricamento asincrono e isolamento degli errori |
| Processo locale incluso nel pacchetto | Eseguibile di inferenza distribuito con il gioco, controllato dal gioco tramite IPC o HTTP su loopback | Distribuibilità reale, avvio non bloccante, arresto, autenticazione locale, conflitti di porte, aggiornamenti e recupero dopo un crash |

Ollama è uno dei nomi proposti da Gemini: **non è una dipendenza scelta**.
Non assumere che una versione «portable» sia automaticamente adatta a essere
ridistribuita nel gioco. Valutare anche un runtime più piccolo dedicato.

HTTP non è un requisito dell'IA: è una possibile comunicazione con un processo
locale. Un'integrazione nativa può esporre chiamate dirette. Nella soluzione a
processo separato, l'endpoint deve restare locale e non esporre un servizio in LAN.
Nessuna telemetria o trasmissione esterna del testo delle conversazioni.

Schema logico proposto:

```text
Dialogo del giocatore
  → contesto consentito per quel NPC, preparato dal gioco
  → servizio locale di inferenza, con coda e limiti
  → risposta candidata
  → validazione del gioco
  → testo a schermo / eventuale richiesta di azione autorizzata
```

Valutare un modello condiviso fra NPC con contesti separati, evitando di caricare
una copia dei pesi per ogni personaggio. Nessuna inferenza nel ciclo per-frame
del combattimento. Richieste asincrone, annullabili e associate a NPC, sessione
e stato del mondo; scartare risposte obsolete dopo chiusura dialogo, cambio
scena, morte dell'NPC o caricamento di un salvataggio.

## Coerenza del ruolo e prompt injection

La conversazione suggerisce prompt rigidi e delimitatori. Possono aiutare a
organizzare l'input, ma **non costituiscono una garanzia** contro uscite dal ruolo
o manipolazioni. Anche un sistema interamente locale deve distinguere istruzioni
di gioco da testo non affidabile del giocatore e da ricordi generati.

Confine da mantenere nel progetto:

- Il gioco decide stato, regole, fatti canonici e azioni consentite.
- Il modello propone testo e, solo se necessario, intenzioni da validare.
- Nessun accesso libero a file, shell, rete o comandi del motore.
- Un'affermazione del modello non concede oggetti, denaro, reputazione o quest.
- Eventuali azioni usano identificatori ammessi e parametri strutturati;
  il gioco verifica disponibilità, costi, distanza e prerequisiti prima di agire.
- Un formato JSON valido non dimostra che un'azione sia lecita o corretta.
- Il testo generato non viene interpretato come script, markup arbitrario o
  istruzione privilegiata da reinserire nella memoria.
- Risposte fuori contesto, invalide o scadute portano a una battuta di ripiego
  coerente con il personaggio, senza interrompere il gioco.

La memoria canonica dovrebbe derivare dagli eventi confermati dal gioco.
Riassunti e ricordi prodotti dal modello restano dati da filtrare, non nuove
istruzioni di sistema o prove che un evento sia realmente avvenuto.

## Risorse, distribuzione e prestazioni

Le stime di VRAM e le promesse di fallback automatico riportate da Gemini non
sono budget di progetto. Misurare pesi, contesto/KV cache, buffer del runtime e
memoria già occupata dal rendering; il solo numero di parametri non basta.

Da rilevare sulla scena reale, non su una chat isolata:

- Picco RAM/VRAM con gioco e modello attivi, caricamento a freddo e rilascio.
- Tempo al primo testo e alla risposta completa, mediana e p95.
- Frame time del gioco durante caricamento, generazione e annullamento.
- Qualità e velocità con GPU, CPU e configurazioni miste effettivamente supportate.
- Dimensione del pacchetto, tempi di avvio e condizioni di licenza del runtime
  e dei pesi per distribuzione commerciale e offline.

Non promettere compatibilità con GPU specifiche o risposta istantanea prima
dei test. Stabilire limiti di contesto, risposta e concorrenza; prevedere una
modalità senza modello quando il budget disponibile non è sufficiente.

## Backlog originario — riferimento per il handoff

- [ ] Definire l'interazione desiderata: testo libero, opzioni guidate, reazioni
  contestuali e grado di memoria; scegliere un caso concreto, per esempio un fabbro.
- [ ] Esaminare il sistema di dialogo esistente e i suoi punti di estensione,
  senza creare una seconda pipeline di quest o comportamento.
- [ ] Confrontare runtime nativo e processo incluso nel pacchetto; verificare
  documentazione ufficiale, manutenzione e licenze al momento della scelta.
- [ ] Confrontare modelli locali piccoli e quantizzati su italiano, ruolo,
  conoscenze limitate e rispetto del formato; nessun modello è già approvato.
- [ ] Definire il contratto fra gioco e modello: contesto, risposta, intenzioni,
  validazioni, errori, timeout, annullamento e battute di ripiego.
- [ ] Progettare memoria e salvataggi per NPC, separando eventi canonici,
  dichiarazioni del giocatore e riassunti non affidabili.
- [ ] Preparare prove di manipolazione: cambio identità, falsi messaggi di sistema,
  delimitatori chiusi dal giocatore, falsi ricordi, richieste di segreti e premi.
- [ ] Misurare il budget insieme al rendering e fissare criteri quantitativi
  di accettazione prima di estendere il sistema.
- [ ] Prototipo isolato con un NPC, entro il handoff sopra, e nessuna modifica
  diretta del mondo da parte del modello.
- [ ] Verificare il pacchetto su una macchina pulita e senza rete: niente installazioni
  manuali aggiuntive, servizi orfani o dipendenze nascoste.
- [ ] Decidere se promuovere il prototipo a capacità riutilizzabile del progetto
  oppure conservare il dialogo deterministico.

## Criteri di uscita del futuro prototipo

Un NPC utilizzabile offline, con risposte brevi e coerenti, conoscenze delimitate,
stato di gioco protetto, memoria verificabile e ripiego funzionante. Avvio,
arresto, salvataggio e annullamento devono essere affidabili; il costo su memoria
e fluidità deve rientrare nel budget che sarà concordato. Un prompt convincente
o una singola conversazione riuscita non bastano a considerare conclusa la prova.
