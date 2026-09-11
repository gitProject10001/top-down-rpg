# Architettura runtime

Come gira il gioco, meccanica per meccanica, con i file in cui ogni cosa succede.
L'inventario file per file sta in [COMPONENTS.md](COMPONENTS.md).

## Avvio

`project.godot:14` apre direttamente `scenes/dev/hearth_village_playable.tscn`. Non c'è menu, né splash, né schermata di caricamento.

Prima della scena partono undici autoload, nell'ordine dichiarato in `project.godot:18-30`: `EventBus`, `Fx`, `Traits`, `Dialogue`, `Hud`, `Dbg`, `CombatFeedback`, `Notice`, `Sheet`, `Run`, `Water`. L'ordine conta: `CombatFeedback` risolve `/root/Fx` e `/root/EventBus` in `_ready` (`scripts/combat_feedback.gd:21-22`) e può farlo solo perché arrivano prima, mentre `Water` è l'ultimo e viene cercato per path a ogni chiamata.

`Traits._ready` (`scripts/traits/traits.gd:215`) legge `user://traits_save.dat`. I numeri di combattimento del giocatore dipendono quindi da un file di salvataggio esterno al repository.

Nel primo frame entrambi i combattenti indossano il manichino grigio. Un frame dopo `VillageCharacterPalette` (`scripts/village/village_character_palette.gd:28`, chiamata differita) trapianta la mesh di `hearth_warden.glb` sullo scheletro esistente, ricolora ogni superficie e costruisce a runtime il faro `VillageBeam`.

## L'albero della scena

```text
Node3D
└── Pixel (SubViewportContainer, filtro nearest)
    └── View (SubViewport)
        ├── Ground           piano 44x44 m, unico collider del terreno
        ├── Camp             833 righe di scenografia: edifici, tende, alberi, sei figure
        ├── IsoCam           camera ortografica + PostPixel (disattivato)
        ├── PixelSnap        quantizza i due combattenti sul reticolo della camera
        ├── VillageCharacterPalette
        ├── Player           istanza di scenes/player/player3.tscn
        └── Duelist          istanza di scenes/enemy_duelist.tscn
```

Tutto il mondo vive dentro un `SubViewport`. È l'aggancio per un render a bassa risoluzione con quantizzazione di palette, e in questa scena la seconda metà è spenta: il nodo `PostPixel` ha `visible = false`.

Il villaggio ha un solo collider di terreno e cinque `StaticBody3D` di edificio. Tende, barili, casse, carri e incudini sono puramente visivi: ci si cammina attraverso.

## Il corpo: una scena, due guidatori

`scenes/player/player3.tscn` è il combattente completo e non contiene nessun nodo che decida qualcosa. Porta il collider, il manichino, la spada, l'`AnimationTree`, `Health` e `HurtBox`, dieci stati, la torcia e tre figli di effetto.

`scenes/enemy_duelist.tscn` eredita quella scena e aggiunge un solo nodo, `DuelBrain`. `scripts/enemy_duelist.gd:36-52` cambia quattro cose e nient'altro: i gruppi, i due layer fisici di hurtbox e hitbox, il `target_group`, e nasconde la torcia ereditata.

Il seme è in `Player._setup_intent` (`scripts/player.gd:219-228`): il corpo cerca fra i propri figli un `FighterIntent` e lo adotta; se non ne trova uno costruisce un `PlayerIntent`. Poi `_intent_first` (`scripts/player.gd:235`) lo sposta all'indice 0, così che scriva le sue decisioni prima che la macchina a stati le legga.

Nessuno stato legge mai `Input`. Leggono l'intent. È questo che rende i due combattenti la stessa cosa.

## L'intent

`scripts/combat/fighter_intent.gd` è sei campi di livello più due latch:

| campo | significato |
|---|---|
| `move` | direzione di movimento in XZ mondo |
| `look` | dove guardare |
| `guard` | la guardia è alzata adesso |
| `guard_dir` | quale delle quattro direzioni copre |
| `attack_held` | il colpo è in carica |
| `attack_dir` | in che direzione arriverà |

I latch sono `can_start_attack()`/`consume_attack()` e `request_release()`/`consume_release()`: la pressione e il rilascio sono eventi, non livelli, e vanno consumati una volta sola.

`PlayerIntent` (`scripts/combat/player_intent.gd`) li riempie da una persona: WASD o levetta sinistra ruotati nella resa della camera, i pulsanti, e la direzione a quattro vie presa dalla levetta destra o dal movimento accumulato del mouse oltre `mouse_pixels` (26 px).

`DuelBrain` (`scripts/combat/duel_brain.gd`) riempie gli stessi campi da una macchina a cinque modi, ridecisa ogni `think_period` (0.35 s).

## Attacco direzionale

Il vocabolario è `scripts/combat/swing_dir.gd`: `NONE`, `UP`, `DOWN`, `LEFT`, `RIGHT`. Una direzione è scritta nel sistema di riferimento di chi impugna l'arma, quindi il mio fendente a sinistra arriva alla tua destra. Lo scambio deve specchiare sinistra/destra **esattamente una volta**, dalla parte del difensore, e quel punto unico è `SwingDir.mirror()` chiamato da `scripts/states/guard.gd` dentro `blocks()`.

`scripts/states/dir_attack.gd` (343 righe) è il colpo tenuto, in quattro fasi:

1. **WINDUP** — consuma il latch di attacco, spende 12 di stamina (`dir_attack.gd:72`), avvia la clip.
2. **HOLD** — al 60% del punto d'impatto, se il rilascio non è ancora arrivato, l'orologio dell'animazione si ferma. Costa 8 al secondo. Cambiare direzione qui è una finta: la carica si riavvolge per 4 di stamina.
3. **SWING** — l'orologio riparte, la `HitBox` si apre.
4. **RECOIL** — recupero, oppure il rientro punitivo di `blocked()` se il colpo è stato parato.

Congelare l'animazione congelerebbe anche le gambe, quindi allo startup lo stato `Slash` dell'`AnimationTree` viene ricostruito in un blend tree: la clip d'azione dietro un nodo `TimeScale` azzerabile, mascherata sulla parte bassa del corpo contro un'andatura che continua a camminare. Lo fa `scripts/combat/combat_animation_layers.gd`, installato da `scripts/player.gd:426` solo se la macchina ha `DirAttack`.

C'è una correzione di mira silenziosa. `dir_attack.gd:205-236` durante i primi 0.16 s di windup ruota il corpo verso il bersaglio se è entro 1.50 m, entro 5 gradi dalla direzione in cui già guardi, non ostruito da un raycast, e non ti stai muovendo.

## Guardia, parata e rottura

`scripts/states/guard.gd` tiene la clip `block`, muove `GuardPose` verso la direzione scelta, cammina al 40% della velocità e blocca la faccia sul bersaglio acquisito entro 6 m. Espone tre risposte:

- `guard_dir()` — cosa sto coprendo.
- `blocks(attack_dir)` — la direzione in arrivo è quella giusta? Rifiuta mentre la guardia sta ancora cambiando direzione e mentre il blend è sotto 0.65, così un cambio istantaneo non copre tutto.
- `is_parry_active()` — siamo dentro i primi 0.24 s (`parry_window`).

La risoluzione sta in `Player.on_incoming_hit` (`scripts/player.gd:1030-1140`), in tre cancelli:

1. Un `Projectile` non parabile salta l'intercettazione del tutto.
2. **Percorso direzionale stretto.** Se il colpo porta una direzione e lo stato corrente espone `blocks()`, la risposta è solo la lettura corretta. Sbagli e il colpo entra intero: non c'è credito parziale.
3. **Percorso omni.** Un colpo senza direzione cade nella vecchia guardia a cono frontale.

Un blocco non è solo assenza di danno. `_do_block` spende stamina, suona il contatto acciaio su acciaio, poi risale la catena dei nodi dall'hitbox fino a chi ha colpito e gli chiama `on_swing_blocked()`, che lo manda in rinculo. Una parata è la stessa lettura fatta presto: costa solo 10 di stamina, aggiunge hitstop, e cerca la punizione in tre livelli, `stagger()` poi `on_swing_parried()` poi niente.

Finire la stamina mentre si para rompe la guardia e spinge in `Hurt` (`scripts/player.gd:1103`).

## Stamina

Una sola riserva da 100, con rigenerazione a 8 al secondo che si ferma mentre lo stato è `Guard`, `Block` o `DirAttack` (`scripts/player.gd:949-953`). Costa 12 aprire un colpo direzionale, 8 al secondo tenerlo al culmine, 4 riavvolgerlo per una finta, 6 abortirlo in guardia, e ogni colpo assorbito dalla guardia spende la sua parte. Il calcolo gira da `_process`, quindi è ritmato dai frame renderizzati, non dalla fisica.

## Macchina a stati

`scripts/states/state_machine.gd` registra ogni figlio `State` con il nome del nodo in minuscolo, inietta `player` e `fsm`, e instrada `_physics_process` e `_unhandled_input`. `transition_to()` su un nome sconosciuto non fa nulla in silenzio: è questo il meccanismo degli stati opzionali.

Gli eventi di input vengono rifiutati due volte: mentre una conversazione è aperta, e per qualunque corpo il cui intent non sia un `PlayerIntent`. È l'unica cosa che tiene la tastiera fuori dal duellante.

Dieci nodi stato in `player3.tscn`. Il grafo completo:

```text
Idle  <-> Move                                   polling su move input
Idle/Move -> DirAttack                           polling su intent.can_start_attack()
Idle/Move -> Guard                               polling su intent.guard
Idle/Move -> Dash | DashAttack | Jump | Attack   solo da handle_input
DirAttack -> Guard | Dash | Idle/Move
Guard     -> DirAttack | Dash | Jump | Idle/Move
Dash      -> Attack | DashAttack | Idle/Move
DashAttack-> Attack | Idle/Move
Attack    -> Dash | Idle/Move
Jump      -> Idle/Move
Hurt      -> Idle                                forzato da Player._on_damaged
Dead                                             forzato da Player._on_died, senza uscita
```

Due nomi non hanno nodo e quindi non fanno nulla: `Shoot` (chiamato da `idle.gd:32` e `move.gd:36`) e `Block` (`idle.gd:40`, `move.gd:44`). `Attack` non è raggiungibile da Idle o Move, perché la riga `idle.gd:29` la offre solo a un corpo *senza* `DirAttack`; ci si arriva solo passando per `Dash`.

Il duellante raggiunge solo `Idle`, `Move`, `DirAttack`, `Guard`, `Hurt` e `Dead`, perché gli altri quattro passano da `handle_input`, che gli è negato.

## Danno

```text
stato chiama Sword.hit(dir)
  -> sword.gd:165  scrive i meta e apre la HitBox
  -> hitbox.gd     dedup per attivazione, poi HurtBox.apply_hit(danno, self)
  -> hurtbox.gd:59 get_parent().on_incoming_hit(...)   <- blocco e parata vivono qui
  -> health.gd     take_damage(), l'unico posto dove gli hp calano
  -> Health.damaged -> Player._on_damaged -> knockback, flash, CombatFeedback, stato Hurt
  -> hitbox emette dealt_hit(bersaglio, punto, applicato)  <- dopo, col danno già risolto
```

La firma di `take_damage` non ha spazio per il resto, quindi ogni carico specifico del colpo viaggia come metadato sul nodo `HitBox`, che è passato come `source` per tutta la catena: `swing_dir`, `knockback`, `finisher`, `contact_point`.

Ci sono **due modalità di rilevamento**, scelte dall'argomento `dir` di `Sword.hit()`. Un colpo senza direzione usa l'overlap normale dell'`Area3D` contro il grande box ancorato al giocatore. Un colpo direzionale mette `manual_contact = true`, che disattiva sia lo sweep di `activate()` sia il gestore `area_entered`, e tutto il danno passa dalla lama spazzata frame per frame. **In questa build entrambi i combattenti hanno `DirAttack`, quindi in pratica gira solo il percorso della lama spazzata.**

La portata non è una costante da nessuna parte nel codice: è il `CollisionShape3D` dentro `sword.tscn`, misurato a runtime da `Sword._measure_envelope`. Il box misurato finisce a 2.08 m in avanti e lo stacco è netto, quindi il colpo si impegna su un bersaglio invece di fidarsi della geometria: `acquire_target` ordina i candidati prima per angolo e poi per distanza.

Chi può colpire chi è deciso interamente dai layer fisici. Nessuna riga di codice fa amico-nemico.

## Camera

`scripts/village/iso_cam.gd` è l'unica camera. È ortografica e ricostruisce la propria trasformata da zero ogni frame da `pitch`, `yaw`, `distance` e un punto di fuoco smorzato sul giocatore. Non c'è rig, né orbita, né zoom, né ricentraggio: pitch e yaw sono export fissati nella scena a 48 gradi e `ortho_size` 17.5.

Il **lock-on** appartiene alla camera, non al giocatore. Polla `lock_on` e `lock_cycle` in `_physics_process` invece di gestire l'input, perché sta dentro il `SubViewport`. Il giocatore legge poi il bersaglio dalla camera in `Player.combat_lock_target` (`scripts/player.gd:765`).

Siccome la proiezione è ortografica, un pixel schermo vale sempre lo stesso numero di metri, quindi la camera arrotonda il proprio scorrimento a multipli interi di quella misura. `scripts/village/pixel_snap.gd` fa lo stesso ai due combattenti, scrivendo la loro `global_position` fuori dalla fisica: senza, la loro sagoma cade su una frazione di pixel diversa a ogni frame e il contorno frigge.

## Aspetto

Il look è montato in quattro strati:

1. **Superfici d'ambiente** — shader scritti a mano che campionano un'immagine dipinta e sovrascrivono `light()` con un lambert avvolto e posterizzato. `painted_architecture.gdshader` copre 78 materiali, `architecture_clear.gdshader` altri 17.
2. **Personaggi** — `scripts/toon_skin.gd` sostituisce ogni superficie con una copia di `assets/materials/toon_character.tres` (tre bande di luce) e attacca il contorno a scafo invertito come `next_pass`.
3. **Palette del villaggio** — `village_character_palette.gd` rimpiazza poi quei materiali con `hearth_hero_material.gdshader`, un colore piatto per superficie, caldo per l'eroe e freddo per il duellante.
4. **Risoluzione a pixel** — `pixel_post.gdshader` con `palette.gdshaderinc`: contorno da geometria, tonemap, poi aggancio alla palette più vicina in Oklab con dithering ordinato 8x8. **Questo strato è presente ma spento.**

Il flash da colpo passa dall'uniform standard `albedo_color`, non da uno custom, così funziona su qualunque shader che ne abbia uno.

## Feel e feedback

`scripts/combat_feedback.gd` è la facciata che divide gli effetti in CONTACT (gli hp sono davvero cambiati) e BEAT (è arrivata l'animazione). `Fx.hitstop` è l'unico scrittore di `Engine.time_scale` e fonde invece di annidare: una seconda richiesta durante un fermo prende la scadenza più lontana e la scala più profonda.

L'unico suono del progetto è sintetizzato campione per campione a runtime in `scripts/fx/sword_contact.gd:4-21`. Non c'è nessun file audio nel repository.

## HUD e servizi

`scripts/hud.gd` costruisce tutta l'interfaccia in codice su un `CanvasLayer` e la **polla** dal giocatore ogni frame: blocchi hp, frecce, barra stamina, quadrante di guardia, barra del boss. Non ha segnali in ingresso tranne la vignetta.

Il quadrante di guardia è quattro `ColorRect` attorno a un vuoto: oro per la direzione che stai coprendo, rosso per la carica del nemico più vicino, e il rosso vince quando coincidono.

`Dbg` (`scripts/debug_view.gd`) tiene due flag e i tasti: F3 mostra i volumi di hitbox e hurtbox, F8 nasconde tutto insieme. I volumi se li disegnano da soli.

## Mappa input

| azione | tasto | pad | letta da |
|---|---|---|---|
| `move_up/down/left/right` | WASD | levetta sx | `player_intent.gd:17` |
| `attack` | click sinistro | RS | `player_intent.gd`, `idle`, `move`, `dir_attack` |
| `block` | click destro | LS | `player_intent.gd:26`, `idle`, `move`, `dir_attack` |
| `dash` | Shift | B | `idle.gd:33`, `move.gd:37`, `guard.gd`, `dir_attack.gd` |
| `jump` | Spazio | A | `idle.gd:41`, `move.gd:45`, `guard.gd` |
| `interact` | E | Y | `dialogue.gd:149`, `notice.gd:206` |
| `aim_up/down/left/right` | — | levetta dx | `player_intent.gd:40` |
| `lock_on` | tasto centrale | L3 | `iso_cam.gd:80` |
| `lock_cycle` | tasto laterale | R3 | `iso_cam.gd:83` |
| `toggle_light` | L | — | `hero_torch.gd:38`, `village_beam.gd:19` |
| `pause` | Esc | Select | `sheet.gd:403` |
| `shoot` | Q | RT | `idle.gd:31`, `move.gd:35` — porta a uno stato inesistente |
| `tool_use` | Q | X | nessuno |
| `tool_next` | Tab | — | nessuno |

È vivo anche il flag da riga di comando `--trace-combat`: stampa le righe `GUARD_CONTACT` e `FRONTAL` da `scripts/player.gd:1050` e `:1080`.

## Macchinario dormiente

Questo esiste nel codice, viene compilato e non parte mai nella scena del villaggio. Saperlo evita di cercare bug dove non c'è comportamento.

- **Scossa di camera.** `EventBus.combat_impact` ha otto emettitori e zero ascoltatori. Ogni numero di shake calcolato in `sword.gd` viene buttato via.
- **Ciclo di run, hub e finale.** `Run.begin()` non ha nessun chiamante, quindi `in_run` è sempre falso, e questo spegne la conta delle uccisioni, la morte, l'Insight in sospeso nell'HUD e il finale. `run_manager.gd:14` punta a `res://scenes/world/room.tscn`, che non esiste: è l'unico path `res://` rotto rimasto.
- **Dialoghi, carte di check e scheda.** `Dialogue.start` è chiamato solo dal finale irraggiungibile. Niente nel villaggio avvia una conversazione, malgrado il tasto `E` sia mappato.
- **Arco, frecce, scudo e bracciale.** `player.gd:35` e `:38` cercano `Visuals/Bow` e `Visuals/ArmL/Shield`, che in `player3.tscn` non esistono. Restano tipi dichiarati: cancellarli è un errore di parsing, non un alleggerimento. Di conseguenza il lampo di parata non nasce mai, perché sta dentro `if scene and shield` (`player.gd:1125`), e l'HUD disegna sei frecce per un corpo senza arco.
- **ToolBelt.** Sedici righe di stub: `active_tool()` torna null, quindi la riga strumento dell'HUD è sempre vuota.
- **Acqua.** Nessun nodo entra nel gruppo `water_oracle`, quindi ogni query torna il valore di ripiego. `Fx.splash` e `Fx.dust` non hanno chiamanti.
- **`Projectile`.** 270 righe complete di volo balistico e contratto di colore, ma niente lo istanzia. Vive come tipo per i controlli in `player.gd:1036` e `:1134`.

## Difetti noti

- **La scena principale annulla due passate di sanificazione.** `hearth_village_playable.tscn:3326-3327` e `:3331-3332` sovrascrivono `locomotion_clips` di entrambi i combattenti con i vecchi nomi Mixamo (`run_fwd`, `atk_h`, `aim_*`), che nella libreria Quaternius non esistono, e azzerano `loop_clips`. Il risultato è che `_strip_root_drift` non gira quasi su nessuna clip e che `idle_sword` e `block` non vengono più messe in loop. I valori giusti sono quelli in `player3.tscn:120-121`.
- **La morte del duellante emette il segnale del giocatore.** `dead.gd` è condiviso dai due corpi, quindi quando il duellante muore emette `EventBus.player_died`. `EventBus.enemy_died` non è emesso da nessuna parte.
- **F3 è legato due volte.** `debug_view.gd:34` accende i volumi e `hud.gd:248` accende il contatore di frame; `Dbg` non consuma l'evento, quindi una pressione fa entrambe le cose.
- **`Q` è legato due volte**, a `shoot` e a `tool_use`. `shoot` porta a uno stato che non esiste, `tool_use` non è letto da nessuno.
- **`sheet.gd:78` e `:106` chiamano `/root/Pause`**, che non è fra gli autoload. La messa in pausa che la scheda si aspetta non avviene.

## Verifica

```powershell
& 'C:\Users\jonny\Desktop\game\godot\Godot_v4.6.3-stable_win64.exe' --headless --path . --editor --import --quit
& 'C:\Users\jonny\Desktop\game\godot\Godot_v4.6.3-stable_win64.exe' --headless --path . --quit-after 200
```

Entrambi i comandi devono chiudersi senza righe `ERROR`. Poi va eseguita la prova grafica: movimento, attacco direzionale in tutte e quattro le direzioni, parata corretta e parata sbagliata, dash e lock-on.

## Prima di potare

Una ricerca testuale non vede tutto.

- I `.res` binari compressi dichiarano dipendenze proprie: `assets/models/camp/hearth_baked/geometry_021.res` carica `assets/models/char_a_Image_0.png` e `_1.png`, che nessun file di testo nomina. La lista vera sta in `.godot/editor/filesystem_cache10`.
- `addons/GPUTrail/` usa `preload()` relativi alla cartella dello script.
- I file `.import` portano dipendenze: entrambi i GLB dei personaggi passano da `assets/models/animations/bonemap_ual.tres`.
- Metà dei nodi del giocatore sono costruiti a runtime e non compaiono in nessuna scena: i due `BoneAttachment3D` delle impugnature, `GuardPose`, `ToolBelt`, `VillageBeam`.
- Nessun `.tscn` contiene un blocco `[connection]`. Ogni collegamento di segnale è una chiamata `connect()` nel codice.
