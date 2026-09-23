> Integrazione nel borgo: [NPC_AI_INTEGRATION.md](NPC_AI_INTEGRATION.md).

> **Manuale del laboratorio NPC.** Per quattro personaggi, prossimità, host condiviso e pausa nella scena integrata vedere [NPC_AI_INTEGRATION](NPC_AI_INTEGRATION.md). I punti finali di «integrazione futura» registrano lo stato precedente all’importazione.
> Le sezioni sul laboratorio qui sotto documentano il nucleo importato.

# NPC conversazionali con IA locale — runtime, modello e prototipo

Prototipo verticale del handoff in `LOCAL_NPC_AI_TODO.md`: un fabbro (Bruno) in una scena di prova
separata, dialogo testuale in italiano con un modello che gira in locale, memoria per NPC, inferenza
asincrona annullabile e battute scritte a mano quando il modello manca o sbaglia. Il modello propone solo
testo: non esiste alcun canale con cui possa toccare oggetti, denaro, quest o reputazione. Tutto vive in
`addons/npc_ai/`, `assets/npc_ai/`, `scenes/dev/npc_ai_lab.tscn`, `scripts/npc_ai_lab/` e `tools/npc_ai/`;
la scena integrata, gli autoload e i sistemi del gioco non sono stati toccati. **Non e' ancora verificato
il pacchetto esportato su una macchina pulita senza rete** (vedi «Verifiche mancanti»).

| Componente | File | Ruolo |
| --- | --- | --- |
| Profilo NPC | `addons/npc_ai/npc_profile.gd`, `assets/npc_ai/blacksmith_profile.tres` | identita', tono, regole, fatti pubblici, conoscenze autorizzate, battute di ripiego |
| Contratto | `npc_chat_request.gd`, `npc_chat_response.gd` | `npc_id`, `session_id`, `request_id`, revisione del contesto, testo, limiti; stato, testo, errore, tempi. Nessun campo per comandi |
| Contesto | `npc_context_builder.gd`, `assets/npc_ai/blacksmith_facts.json` | lista esplicita di fatti dal gioco; eventi canonici scelti in modo deterministico; dichiarazioni del giocatore separate (ruolo `user`, mai `system`) |
| Lore condivisa | `npc_world_lore.gd`, `assets/npc_ai/world_lore.json` | un solo file per tutti gli NPC; voci con etichette, `known_by`, priorita', `always`, `secret`; selezione deterministica entro 12 voci e 1400 caratteri (vedi «Lore condivisa») |
| Memoria | `npc_memory.gd` | `user://npc_ai/memory/<npc_id>.json`, schema v1, limiti 32/16/24 voci e 64 KB, scrittura `.tmp` -> `.bak` -> file, recupero da file corrotto |
| Validazione | `npc_validator.gd` | identita', struttura, lunghezze, sessione; in uscita rimozione di `<think>`, marcatori di ruolo, tag, codice, controlli; taglio su frase |
| Servizio | `npc_inference_service.gd` (Node, non autoload) | un backend, coda di 4, una generazione alla volta, timeout primo token/totale, annullamento, scarto delle risposte obsolete |
| Backend finto | `npc_backend_mock.gd` | deterministico, con modalita' di guasto (timeout, errore, spazzatura, iniezione, fuori ruolo, lento, ignora cancel) |
| Backend locale | `npc_backend_llama_server.gd` | processo `llama-server` incluso, loopback, chiave in ambiente, streaming SSE, cancel = chiusura connessione, kill e riconciliazione orfani |
| Conversazione | `npc_conversation.gd` | stati chiuso/libero/in attesa/risposta/ripiego, storico breve, `confirm_event` = unico ingresso in canon |
| Interfaccia | `addons/npc_ai/ui/npc_chat_panel.gd` | pannello riutilizzabile, solo testo semplice (`add_text`, mai BBCode), badge FINTO/LOCALE, stato |
| Laboratorio | `scenes/dev/npc_ai_lab.tscn`, `scripts/npc_ai_lab/npc_ai_lab.gd` | fabbro a forme semplici, selettore backend/modello, avvio/arresto runtime, eventi confermabili, reset memoria, fixture di stato di gioco |
| Pacchetto | `assets/npc_ai/npc_package_manifest.json`, `README.md`, `licenses/` | versioni, origini, dimensioni, sha256, licenze; `runtime/` e `models/` fuori da Git e da Godot |
| Strumenti | `tools/npc_ai/` | download esplicito, check headless, bench in finestra, perimetro, runner, packaging |

## Confronto delle opzioni

| Opzione | Stato verificato (20-21 settembre 2026) | Esito |
| --- | --- | --- |
| Runtime nativo (GDExtension su llama.cpp) | NobodyWho: attivo (v11.0.0, 10 settembre 2026) ma **EUPL-1.2**, copyleft. godot-llm e godot-llama-cpp: MIT ma fermi da meta' 2024. Nessun compilatore C/C++ su questa macchina. | scartata per licenza e manutenzione |
| Processo incluso (`llama-server` di llama.cpp via HTTP su loopback) | binari Windows prebuilt ad ogni build, MIT, digest sha256 nell'API GitHub; `--host` gia' `127.0.0.1`; chiudere la connessione annulla la generazione (verificato nel sorgente del server) | **scelta** |

## Runtime scelto: llama.cpp `b10964`

- Tag `b10964` (14 settembre 2026, puntato dalla release stabile `v0.4.1`), zip `llama-b10964-bin-win-vulkan-x64.zip`,
  31 674 542 byte, sha256 `1ee3ad952f4ba71f438bd6d7bebef19e1c7af04adcaa35d08b4ddabb27d4c642`. Licenza MIT.
  Lo zip contiene la build CPU completa piu' `ggml-vulkan.dll`; i backend si caricano dinamicamente, quindi se
  Vulkan non e' disponibile si degrada a CPU. Linka BoringSSL e include `libomp.dll` (licenze in `assets/npc_ai/licenses/`).
  **Non include** il runtime Visual C++ (`vcruntime140.dll`, `msvcp140.dll`, `vcomp140.dll`).
- Argomenti: `-np 1 --host 127.0.0.1 --no-webui --no-slots --reasoning-budget 0 --reasoning-format auto -m <gguf>
  --port <casuale 49152-65535> -c 3072 -ngl all --log-file user://npc_ai/logs/...`. La chiave API viaggia nella
  variabile d'ambiente `LLAMA_API_KEY` (mai in argv). `chat_template_kwargs {"enable_thinking": false}` va nel body
  della richiesta: passato da riga di comando Godot su Windows non escapa le virgolette e il JSON arriva corrotto.
- `-ngl auto` in questa build carica solo una parte dei layer: 48 ms/token in prompt e 56 token/s contro 0,24 ms/token
  e 160-200 token/s con `all` (tempi `print_timing` del log di llama-server, non del bench end-to-end). Il default del
  modulo e' `all`; se il processo muore al caricamento si riprova una volta con `-ngl 0` per quell'avvio soltanto: il
  valore configurato non viene toccato. I log del server in `user://npc_ai/logs/` sono ruotati (ultimi 5).
- Ciclo di vita: controllo preventivo di runtime e modello (esistenza e dimensione, mai sha256 all'avvio) ->
  riconciliazione dei file di stato di istanze precedenti -> avvio senza console (`CREATE_NO_WINDOW`) -> `/health`
  ogni 200 ms -> `/props` con la chiave (il `model_path` deve essere il nostro) -> generazione di riscaldamento da un
  token -> READY. Arresto: chiusura delle connessioni, `OS.kill` del solo pid avviato qui, attesa dell'uscita, rimozione
  del file di stato. Kill anche su chiusura finestra, crash gestito e uscita dall'albero.
- Orfani: Godot non usa job object, quindi un crash del gioco o lo Stop dell'editor lasciano vivo `llama-server`.
  Ogni avvio scrive `user://npc_ai/state/llama_server_<pid Godot>_<porta>.json`; all'avvio successivo, per ogni file il
  cui proprietario non esiste piu', si interroga `/props` con la chiave salvata e si termina il processo **solo** se
  risponde con il nostro modello. Processi estranei e istanze sorelle vive non vengono toccati (test `check_npc_local_backend.gd`).

## Modello scelto: Qwen3-4B-Instruct-2507 (Q4_K_M)

Nessun benchmark italiano pubblicato copre la classe 1-4B, quindi la scelta viene da prove A/B nostre:
dieci battute fisse (`tools/npc_ai/bench_npc_local.gd`), seed fisso, rubrica 0-2 per italiano corretto, nel
personaggio, brevita' e confine (niente invenzioni, rifiuto senza uscire dal ruolo). Punteggi assegnati da una
sola lettura, quindi soggettivi; le trascrizioni stanno in `user://npc_ai/bench/transcript_*.txt`.

Primo giro (21 settembre, mattina): SmolLM3-3B batte Qwen3.5-2B e viene scelto. L'utente giudica pero' l'italiano
«cosi' cosi'» («persone straniere da lontano», «parliamo piu' spesso»). Secondo giro, stesso giorno, GPU libera dal
gioco ma editor Godot aperto (3,3 GB di VRAM occupati): tre leve provate separatamente, campionamento piu' morbido
(`temperature` 0,6, `top_p` 0,9, `min_p` 0,05, `repeat_penalty` 1,05 al posto di 1,1, che penalizzava articoli e
preposizioni), cinque battute d'esempio in italiano corretto nel prompt, e due modelli in piu'.

| Configurazione | Licenza | Italiano | Personaggio | Brevita' | Confine | Note |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| **Qwen3-4B-Instruct-2507**, senza esempi (`unsloth/…-GGUF`, 2,33 GiB) | Apache-2.0 | 1,9 | 1,9 | 1,9 | 2,0 | italiano corretto, prezzi e fatti giusti, rifiuti nel personaggio, nessun premio inventato; **scelto** |
| Qwen3-4B-Instruct-2507, con esempi | Apache-2.0 | 1,9 | 1,8 | 1,9 | 2,0 | uguale, ma ripete «Parole al vento non ne voglio» tre volte su dieci |
| SmolLM3-3B Q4_K_M, senza esempi (`ggml-org/SmolLM3-3B-GGUF`, 1,78 GiB) | Apache-2.0 | 1,3 | 1,6 | 1,7 | 1,4 | «Riparano spade», «pago come ordinamento»; inventa un incarico contro i lupi pagato in ferro |
| SmolLM3-3B Q4_K_M, con esempi | Apache-2.0 | 1,6 | 1,4 | 1,8 | 1,2 | copia tre esempi alla lettera; promette «una spada nuova e un po' di oro» |
| SmolLM3-3B Q8_0 (3,05 GiB) | Apache-2.0 | 1,5 | 1,4 | 1,7 | 1,3 | nessun guadagno visibile; con l'editor aperto scende a 5,8 token/s su 8 GB: fuori budget |
| Qwen3.5-2B (`unsloth/Qwen3.5-2B-GGUF`, 1,19 GiB), primo giro | Apache-2.0 | 1,0 | 1,4 | 1,8 | 1,3 | italiano approssimativo, confabula; resta l'alternativa piu' leggera |

Le battute d'esempio nel prompt migliorano la grammatica dei modelli piccoli ma vengono copiate alla lettera:
il profilo non le usa (il campo `example_lines` resta disponibile). Il campionamento morbido resta nel manifest
per tutti i modelli.

Esclusi con motivo documentato: Qwen2.5-3B (Qwen Research License, non commerciale), Gemma 3 (Gemma Terms: accordo e
NOTICE da consegnare a ogni giocatore, diritto di restrizione remota), Llama 3.2 («Built with Llama» e copia dell'accordo),
Velvet-2B (PR llama.cpp #11716 non unita: non carica su build standard), Minerva-7B (4,2 GiB), Phi-4-mini (MIT, ma 3,8B
e registro da assistente). Qwen3-4B-Instruct-2507 non ha modalita' di ragionamento; SmolLM3 (alternativa) la ha attiva di
default: `/no_think` in testa al system prompt, piu' `--reasoning-budget 0` e `enable_thinking=false`.

## Prompt e invarianti

Messaggi per `/v1/chat/completions`: `system` = persona, regole, «Cose che sai» (fatti pubblici, conoscenze
autorizzate, lista esplicita del gioco), «Il mondo in cui vivi» (lore condivisa scelta per il turno, vedi sotto),
«Fatti accaduti davvero, confermati dal gioco» (eventi canonici, al massimo 8, ordinati per parole in comune, giorno
e id), chiusura fissa; il prefisso fino ai fatti e' identico fra i turni e `cache_prompt` riusa la KV cache; lore ed
eventi stanno dopo perche' possono cambiare. Le dichiarazioni del giocatore arrivano come messaggio `user` con la nota «non verificate»; poi gli
ultimi 6 turni e il testo del giocatore. `max_tokens` 120, `temperature` 0,7, 320 caratteri massimi a schermo.

Invarianti verificate da `check_npc_manipulation.gd` (backend finto in tre modalita' e modello reale): la risposta ha
solo le chiavi del contratto; lo stato di gioco-fixture non cambia; gli eventi canonici non cambiano; una dichiarazione
del giocatore diventa una `player_claim`, mai un evento; il testo del giocatore non entra mai nel ruolo `system`; i
segreti-fixture non compaiono in nessun messaggio; a schermo arriva solo testo semplice. Il modello puo' comunque
dire cose sbagliate: la difesa e' che dire non equivale a fare.

## Lore condivisa

Prima della lore il modello inventava i dettagli che non trovava nel profilo (numero di case, nomi, storia): non
«sa» nulla del gioco, riempie i vuoti con luoghi comuni. `assets/npc_ai/world_lore.json` e' l'unico posto in cui
vive il mondo per tutti gli NPC; e' **provvisorio** (nomi delle citta', calendario, moneta e persone vengono da
`docs/concepts/four_factions_world_concept.md` e dal borgo della scena integrata) e si modifica a mano.

Ogni voce: `id` (`^[a-z0-9_]{1,48}$`, unico), `text` (una frase, con nomi e numeri espliciti, al massimo 320
caratteri: il modello ripete, non deduce), `tags` (parole chiave per la selezione), `known_by` (`all`, `npc:<id>`,
`trade:<mestiere>`), `priority` 0-9, `always` (entra in ogni turno: poche e corte) e `secret` (non viene MAI
inviata al modello: serve al gioco e alle prove). Le voci non conformi vengono scartate, mai «aggiustate».

Selezione (`npc_world_lore.gd`, deterministica, nessun modello): sono ammesse solo le voci non segrete che l'NPC
conosce; le voci `always` vanno in testa per priorita' e id, senza pesare le parole, cosi' l'inizio della sezione
non cambia fra i turni; le altre per punteggio = priorita' + 10 per ogni parola (di almeno 4 lettere) della battuta
del giocatore trovata nelle etichette o nel testo + 3 per le parole delle ultime quattro battute, poi id; al massimo 12 voci e 1400 caratteri (una voce che non entra viene saltata, si prova con la successiva).
Le voci finiscono nel `system` sotto «Il mondo in cui vivi», dopo i fatti e prima degli eventi canonici. Il
contesto del server e' passato da 2048 a 3072 token per far posto alla lore. `check_npc_lore.gd` verifica
caricamento, filtro `known_by`, scelta per parole chiave, budget, determinismo, segreti assenti da ogni messaggio e
prefisso stabile fino alla sezione della lore; `check_npc_manipulation.gd` ripete le manipolazioni con la lore nel
contesto. Il pannello del lab mostra «lore condivisa: N voci».

Per aggiungere un NPC basta un profilo nuovo e, se serve, voci con `known_by: ["npc:<id>"]` o
`["trade:<mestiere>"]`: la lore comune non si duplica. Limite dichiarato: il modello puo' ancora sbagliare o
confondere due voci; la lore riduce le invenzioni, non le azzera.

Misurato il 21 settembre 2026 con `ask_npc_local.gd` (seme 7, sei domande in sequenza, editor aperto): senza lore Bruno
inventava il prezzo del pasto («cinque monete di rame»), non sapeva l'anno e metteva «nebbia e boschi» oltre le montagne;
con la lore risponde «due monete di rame», «l'anno centotredici del Patto», «nessuno e' andato oltre» e nomina il
sindaco Aldo, con qualche abbellimento residuo («i vecchi lo contano con le pietre»). Costo: il `system` passa da 2,8 a
4,1-4,2 mila caratteri (9-10 voci) e, poiche' la parte dopo i fatti cambia col tema, il primo token sale da 49 a 116 ms
di mediana (p95 488 ms); completamento (693 / 936 ms), token/s (60) e VRAM (2,9 GB) restano nell'ordine di prima
(riga «+ lore condivisa» nella tabella delle misure).

## Laboratorio

```powershell
$g = 'C:/Users/jonny/Desktop/game/godot/Godot_v4.6.3-stable_win64_console.exe'
& $g --path . res://scenes/dev/npc_ai_lab.tscn              # backend locale se runtime e modello sono presenti
& $g --path . res://scenes/dev/npc_ai_lab.tscn -- --mock    # solo backend finto
```

Con `-- --self-test` il lab esegue da solo, in finestra e col backend attivo, il percorso pulsante -> casella di testo ->
anteprima -> Annulla -> Chiudi -> Arresta runtime e scrive l'esito in `user://npc_ai/logs/`.
`E` (azione `interact` gia' esistente) o il pulsante aprono e chiudono il dialogo; Invio manda il testo; Annulla
interrompe la generazione; il selettore cambia backend e modello; «Avvia/Arresta runtime» controlla il processo;
i pulsanti «Conferma: …» sono l'unico modo per aggiungere un evento canonico; «Reset memoria» azzera il file dell'NPC.
Il pannello mostra servizio, porta, pid, caricamento e la fixture di stato di gioco, che deve restare «INVARIATO».
Se `assets/npc_ai/runtime/` o il modello mancano, il lab parte col backend finto e il dialogo resta usabile in ripiego.

Da riga di comando, senza aprire il lab: `& $g --headless --path . --script res://tools/npc_ai/ask_npc_local.gd -- --text "Quante
case ha il borgo?" --text "Hai mai visto la Regina?"` manda le battute in sequenza al modello reale con la stessa richiesta
del lab (profilo, fatti, lore, storico) e stampa risposte, tempi e voci di lore scelte; `--no-lore` per il confronto,
`--model <id>`, `--seed N`. Non scrive la memoria dell'NPC.

## Pacchetto offline

```powershell
python tools/npc_ai/fetch_npc_package.py --runtime            # 31,7 MB, sha256 verificato, estratto in assets/npc_ai/runtime
python tools/npc_ai/fetch_npc_package.py --model smollm3-3b   # 1,9 GB, sha256 verificato
python tools/npc_ai/fetch_npc_package.py --verify-only
python tools/npc_ai/package_npc_lab.py --exe-dir "C:/percorso/dell/export"   # npc_ai/ accanto all'eseguibile
```

In editor il modulo legge `res://assets/npc_ai/{runtime,models}`; in un progetto esportato `<cartella exe>/npc_ai/`.
`package_npc_lab.py` copia una lista esplicita: `llama-server.exe`, le DLL del manifest, le varianti `ggml-cpu-*.dll`,
`ggml-vulkan.dll` e le licenze (anche quella del modello, che deve esistere): nessun altro eseguibile di llama.cpp.
Nessun peso o binario e' in Git (`runtime/.gitignore`, `models/.gitignore`), nessuno e' importato o esportato da Godot (`.gdignore`).

## Verifiche

| Controllo | Cosa copre | Runtime |
| --- | --- | --- |
| `tools/npc_ai/check_npc_contract.gd` | contratto, profilo, validatore, backend finto | no |
| `check_npc_context.gd` | selezione dei fatti, ruoli, segreti, prefisso stabile | no |
| `check_npc_lore.gd` | lore condivisa: caricamento, `known_by`, parole chiave, budget, determinismo, segreti mai inviati | no |
| `check_npc_memory.gd` | due identita', salvataggio/riapertura, corrotto, `.tmp`/`.bak`, limiti | no |
| `check_npc_service.gd` | coda, timeout, annullamento, risposta tardiva dopo chiusura/nuova sessione/reset/rimozione/cambio scena, conversazione | no |
| `check_npc_lab_smoke.gd` | la scena del lab headless col backend finto | no |
| `check_npc_manipulation.gd` [`-- --real`] | le cinque manipolazioni e le invarianti | opz. |
| `check_npc_streaming.gd` | avvio, streaming a piu' chunk, annullamento, arresto | si' (skip 3) |
| `check_npc_local_backend.gd` | loopback, 401, identita', crash, riavvio, orfani, guasti | si' (skip 3) |
| `bench_npc_local.gd` | misure in finestra | si' |
| `ask_npc_local.gd` | battute a scelta col modello reale, con o senza lore (strumento di prova, non un controllo) | si' |
| `check_perimeter.ps1` | percorsi, binari, URL, `git diff --check` | no |

```powershell
powershell -ExecutionPolicy Bypass -File tools/npc_ai/run_checks.ps1 -Real
& $g --path . --script res://tools/npc_ai/bench_npc_local.gd -- --model smollm3-3b --runs 12 --restarts 2
```

### Risultato verificato — 21 settembre 2026

Hardware: Intel i7-12700F (12 core, 20 thread), 32 GB RAM, NVIDIA GeForce RTX 3070 8 GB (driver 32.0.16.1656 / 616.56),
Windows 11 Home 26200, Godot 4.6.3 stable, llama.cpp b10964 Vulkan, contesto 2048 (3072 nella riga con la lore), `-np 1`, finestra Godot vuota senza
vsync (la scena del villaggio non e' stata caricata: il carico GPU del gioco vero resta da misurare). Il secondo giro e'
stato misurato con l'editor Godot aperto: caricamenti piu' lunghi e 3,3 GB di VRAM gia' occupati. Un bench eseguito mentre
un altro `llama-server` girava sulla stessa GPU e' sceso a 5,5 token/s: due modelli sulla stessa scheda da 8 GB non stanno.

| Configurazione | Caricamento (health) | Riscaldamento | Primo token med. / p95 | Completa med. / p95 | Token/s | RAM processo | VRAM in piu' |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| **Qwen3-4B-Instruct-2507**, `-ngl all`, 10 prove, editor Godot aperto | 4,4 s | 72 ms | 49 / 363 ms | 740 / 901 ms | 67 | 2,7 GB | 2,8 GB |
| **Qwen3-4B-Instruct-2507** + lore condivisa, `-c 3072`, `-ngl all`, 10 prove, editor aperto | 2,5 s | 50 ms | 116 / 488 ms | 693 / 936 ms | 60 | 2,6–2,8 GB | 2,9 GB |
| SmolLM3-3B Q4_K_M, `-ngl all` (primo giro, finestra vuota) | 2,04–2,08 s | 63–68 ms | 35 / 256 ms | 722 / 976 ms | 87 | 2,0–2,1 GB | 2,1 GB |
| SmolLM3-3B Q8_0, `-ngl all`, editor aperto | 4,8 s | 2,2 s | 200 / 3796 ms | 5678 / 15231 ms | 5,8 | 4,5 GB | 2,6 GB |
| Qwen3.5-2B, `-ngl all` | 2,01–2,03 s | 88–92 ms | 69 / 292 ms | 846 / 1286 ms | 82 | 1,5–1,6 GB | 1,3 GB |
| Qwen3.5-2B, CPU (`-ngl 0`, 6 thread), 6 prove | 1,8 s | — | 330 / 869 ms | 3355 / 4860 ms | 22 | 1,5 GB | 0,1 GB |

Frame time (intervallo fra frame, finestra vuota): mediana 0,2–1,2 ms in ogni fase, p95 sotto 1,4 ms; 2–3 frame sopra 33 ms
per fase, presenti anche nella fase di riposo senza alcuna richiesta in corso (massimo ~150 ms), quindi attribuibili
all'ambiente (finestra senza vsync, compositore) e non al modulo. L'annullamento e' consegnato al chiamante entro 1 ms;
che il server smetta davvero di generare lo verifica `check_npc_local_backend.gd`: la richiesta successiva riceve il
primo token entro 1,2 s, impossibile se i 160 token annullati (~1,8 s) proseguissero. Senza riscaldamento la prima richiesta di SmolLM3 dopo un
caricamento era costata 4,9 s: con il riscaldamento il p95 del primo token e' 256 ms.

Test eseguiti (tutti verdi): contratto 114 controlli, contesto 58, lore 165, memoria 52, servizio 113, lab 34, manipolazione 749
(finto) e 996 (finto + reale, sui messaggi davvero inviati dal backend, con la lore nel contesto), streaming 15, end-to-end locale 39, perimetro 0
errori; i log dei check restano in `user://npc_ai/logs/checks/`. Prova in finestra col backend reale attraverso la UI
(`-- --self-test`: pulsante, casella di testo, anteprima in streaming, Annulla, Chiudi, Arresta runtime), esito in
`user://npc_ai/logs/lab_selftest_*.txt`. Una revisione indipendente del diff
ha portato sei irrobustimenti, tutti coperti da test: il dialogo non resta «in attesa» se il runtime viene fermato o
cambiato durante una richiesta; l'anteprima in streaming non mostra testo fuori ruolo; i caratteri invisibili e i
separatori di riga esotici vengono rimossi prima del taglio dei marcatori di ruolo; i token speciali dei template
(`<|im_start|>`, `[INST]`, `<<SYS>>`...) vengono neutralizzati nel testo del giocatore; i tag annidati vengono
rimossi fino a testo semplice; la memoria appiattisce i testi, valida gli id degli eventi e rifiuta file oltre il
doppio del limite. Il lab in finestra parte e si chiude
senza errori, senza processi `llama-server` residui e senza file di stato.

## Verifiche mancanti e limiti

- **Pacchetto su macchina pulita senza rete: non eseguito.** Su questa macchina non ci sono export template di Godot
  4.6.3 e `export_presets.cfg` e' fuori dal perimetro. Passi residui: installare i template, esportare, eseguire
  `package_npc_lab.py --exe-dir`, avviare offline su una macchina senza sviluppo, controllare l'eventuale richiesta del
  Visual C++ Redistributable (da includere se serve), verificare che nessun `llama-server.exe` resti attivo alla chiusura.
- Misure solo su RTX 3070 con Vulkan e finestra vuota: nessuna promessa su altre GPU e nessuna misura ancora con il villaggio
  integrato in scena (il gioco rende con D3D12 e il server usa Vulkan sulla stessa GPU).
- Percorsi di installazione non ASCII: llama-server riceve gli argomenti in codifica ANSI; non provato.
- Lo Stop dall'editor termina Godot senza avvisi: il server resta vivo fino al riavvio successivo, che lo riconosce e lo chiude
  (il proprietario conta come vivo solo se il pid appartiene ancora all'eseguibile registrato nel file di stato).
- L'arresto del runtime (Arresta runtime, cambio backend o modello, chiusura) attende l'uscita del processo sul thread
  principale: di norma sotto 20 ms, al massimo 2 s.
- Il modello puo' dire cose false o fuori tono: la sanificazione e le invarianti proteggono il gioco, non garantiscono il testo.
- `Performance.TIME_PROCESS` si aggiorna a intervalli: il frame time nel bench e' l'intervallo fra frame.
- Godot riscrive `project.godot` e i file `.import` con fine riga LF dopo un `--import` o un avvio in finestra: il
  contenuto non cambia, ma `git status` li mostra modificati e `check_perimeter.ps1` li segnala. Riportarli a CRLF
  (per esempio `perl -pi -e 's/\r?\n/\r\n/' <file>`) e non metterli mai in un commit del branch NPC.

## Integrazione prevista nel laboratorio — registro storico

- Ponte verso l'autoload `Dialogue` (`scripts/dialogue.gd:55`, `start(convo)`): una battuta generata puo' diventare un
  nodo `{speaker, text}`; `Dialogue.active` e' letto da `scripts/states/state_machine.gd:44-46`, `scripts/hud.gd:54`,
  `scripts/village/iso_cam.gd:105-109`, `scripts/combat/pack_brain.gd:53-55`; `scripts/combat/player_intent.gd:24-37` non e'
  gated, quindi il movimento va bloccato altrove.
- Eventi canonici dal gioco: `EventBus` (`scripts/event_bus.gd:14-17`) come sorgente per `NpcConversation.confirm_event`.
- Prossimita' e prompt di interazione: non esiste un sistema; l'unico precedente e' `scripts/village/house_interior_play.gd:186`.
- Host persistente del servizio (oggi vive nella scena del lab) e `--sleep-idle-seconds` per liberare RAM fuori dai dialoghi.
