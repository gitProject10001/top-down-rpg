# NPC locali nella scena integrata

## Consegna e revisione — 23 settembre 2026

Importazione selettiva dal worktree `top-down-rpg-npc-ai`, branch
`codex/npc-local-ai`, snapshot **b26755e**. Sono inclusi il nucleo testuale,
il laboratorio, i test, il manifest e le licenze. Nessun modulo TTS, modello
vocale o collegamento all'inverted hull è attivo nella scena.

Revisione: identità/sessioni e risposte obsolete, memoria per NPC con limiti e
recupero, servizio condiviso, cancellazione SSE, avvio e arresto del processo
posseduto, endpoint loopback con chiave casuale e packaging a lista consentita.
Corretto il ripristino di una variabile `LLAMA_API_KEY` eventualmente già presente
nell'ambiente: il backend ora la conserva dopo l'avvio del proprio processo.
La chiusura del runtime può attendere fino a 2 secondi; non è lavoro per frame.
Il pacchetto esportato su macchina pulita rimane da verificare, come nel laboratorio.

## Uso

Avviare `scenes/dev/integrated_landscape.tscn`, premere **5** per raggiungere il
borgo, avvicinarsi a una capsula fino a circa 2 metri e usare **E** quando appare
il nome. E ha un solo destinatario: l'NPC segnalato, altrimenti la porta.

- **Bruno**: capsula ruggine, accanto al banco della fucina.
- **Mira**: capsula verde, nel giardino laterale della chiesa; giovane adulta.
- **Ada**: capsula rosata, al lato del portico della locanda.
- **Tullio**: capsula azzurra, vicino alla stalla.

Il pannello consente input libero in italiano (240 caratteri), tre argomenti
iniziali, Invio, Interrompi ed Esc. Pausa il gameplay; UI e inferenza continuano.
La camera viene temporaneamente ricentrata per lasciare visibili gli interlocutori,
e poi ripristinata. HUD e istruzioni di gioco vengono temporaneamente nascosti.
Il vecchio autoload Dialogue rimane per le conversazioni a scelte predefinite:
non viene sostituito e non si può aprire questa UI mentre è già attivo.
Si riusa `Hud.suppress`; nessuna modifica a InputMap o autoload.

## Dati e authoring

`scenes/npc_ai/integrated_npcs.tscn` contiene i quattro nodi; i figli dell'istanza
ConversationalNPCs sono modificabili nella scena integrata. Nell'Inspector:
`profile`, `anchor_path`, `local_offset`, `body_color`, `topics`.
Spostare tramite **local_offset** rispetto all'edificio: è la posizione autorevole;
il gizmo della trasformazione non sostituisce quell'offset. Il terreno viene
verificato al runtime. Le capsule non sono modelli finali e non hanno routine.

Profili in `assets/npc_ai/integrated_*.tres`; lore condivisa della scena in
`integrated_lore.json`. La lore del laboratorio resta intatta, separata dal sottoinsieme
usato nel borgo: Ada e Tullio non vengono confusi con Marta e Gunnar del laboratorio.
Identificatori stabili, memorie in `user://npc_ai/memory/<npc_id>.json`.
Bruno mantiene `fabbro_bruno`, condiviso con il laboratorio.
Nessun canale per assegnare oggetti, denaro o missioni.

## Runtime

Una sola istanza scene-owned di NpcInferenceService, avviata alla prima conversazione
con Qwen3-4B-Instruct-2507 Q4_K_M, llama.cpp b10964 Vulkan. Runtime e modello sono
stati copiati dai file già presenti nel worktree: verificati SHA256 dell'archivio,
corrispondenza dei file runtime e SHA256 completo del modello. File voluminosi
ignorati da Git; nessun download, account o servizio di sistema.

Per altri checkout seguire `NPC_AI_RUNTIME.md`: i binari e i pesi non arrivano con
Git. Senza runtime il dialogo usa battute scritte, mai il mock come finta IA.
`--npc-fallback` forza questa modalità. Il laboratorio conserva il mock per i test.

## Verifiche

- Contratto: 114; contesto: 58; memoria: 52; servizio: 113; lore: 165;
  manipolazione con mock: 749; laboratorio smoke: 34. Tutti superati.
- Backend reale: 39 controlli, inclusi loopback, endpoint protetto, crash/riavvio,
  arresto e riconciliazione senza terminare istanze estranee.
- Test integrato: quattro capsule senza sovrapposizioni, terreno, prossimità e
  linea di vista, E, pausa/chiusura/riapertura, fallback distinto, risposte reali,
  cancellazione e risposta tardiva scartata.
- `tools/npc_ai/check_integrated_npcs.tscn` con
  `--npc-fallback --real-npcs --npc-memory-root=user://npc_ai/test/integrated`
  usa memorie separate da quelle del giocatore e salva immagini in captures.

Misura locale RTX 3070, 1152×648, quattro turni reali: caricamento/prontezza
3,480 s; primo token 0,335–0,478 s; completamento 0,720–0,879 s.
Frame mediano per dialogo 16,64–16,67 ms, p95 16,95–17,19 ms.
Campione piccolo, con VSync: circa 60 fps mediani, non garanzia di 60 fps costanti.

Ultima esecuzione: `captures/npc_verified.log`, tutti i controlli integrati superati.
Gli eventi E/Esc vengono iniettati nel normale percorso input e consegnati prima delle
asserzioni, senza invocare direttamente l'handler. Le sei fasce di accesso sono
state ricontrollate dopo aver spostato Tullio; il controllo borgo precedente
aveva già verificato ingresso/uscita e cutaway dei dodici edifici, F7 e acqua.
All'uscita del test con inferenza reale Godot segnala occasionalmente
`Pages in use exist at exit in PagedAllocator (Variant BucketMedium)`: nessun
errore di script o processo llama-server rimasto, ma il warning di teardown
resta da isolare; non viene dichiarata una chiusura completamente priva di warning.

Per l'audit prima del commit su master:
`powershell -ExecutionPolicy Bypass -File tools/npc_ai/check_perimeter.ps1 -Staged -Integration`.
Questo controlla esplicitamente solo l'indice; i lavori estranei non staged sono
preservati, non certificati dal controllo. Il runner completo accetta
`-StagedIntegration` per la stessa modalità. Senza lo switch rimane il controllo
originario del worktree NPC rispetto al suo commit base.
