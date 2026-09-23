# Inventario dei componenti

> **Inventario storico del runtime hearth.** Non è più un elenco completo del progetto. Per sistemi attuali e punti di ingresso usare [ARCHITECTURE](ARCHITECTURE.md) e [PROJECT_STATUS](PROJECT_STATUS.md). Riferimenti numerici e comandi sotto possono essere superati; non usarli per decidere rimozioni di file.

Ogni file di codice del progetto, cosa fa e come entra nel gioco che gira.
Come le parti si mettono insieme sta in [ARCHITECTURE.md](ARCHITECTURE.md).

La colonna **agganciato da** è la sola che conta quando si cerca qualcosa: metà dei nodi del giocatore sono costruiti a runtime e non compaiono in nessuna scena.

## Autoload

Undici, nell'ordine di `project.godot:18-30`. L'ordine è una dipendenza reale: chi risolve un altro autoload in `_ready` deve venire dopo.

| # | nome | file | ruolo |
|---|---|---|---|
| 1 | `EventBus` | `scripts/event_bus.gd` | Solo dichiarazioni: quattro segnali, zero funzioni. |
| 2 | `Fx` | `scripts/fx.gd` | Unico scrittore di `Engine.time_scale`; tiene i preload dei tre effetti one-shot. |
| 3 | `Traits` | `scripts/traits/traits.gd` | Quattro caratteristiche, i numeri derivati di combattimento, il tiro 2d6, le Convinzioni. Legge il salvataggio all'avvio. |
| 4 | `Dialogue` | `scripts/dialogue.gd` | Conversazioni con macchina da scrivere e risposte a scelta; si costruisce la UI in codice. |
| 5 | `Hud` | `scripts/hud.gd` | Tutta l'interfaccia, costruita in codice e pollata dal giocatore ogni frame. |
| 6 | `Dbg` | `scripts/debug_view.gd` | Due flag di debug e i tasti F3/F8. Non disegna niente. |
| 7 | `CombatFeedback` | `scripts/combat_feedback.gd` | Facciata CONTACT/BEAT: l'unico posto dove hitstop, scossa e vibrazione sono messi insieme. |
| 8 | `Notice` | `scripts/traits/notice.gd` | La carta del check: rallenta il tempo a 0.25 e scrive l'esito. |
| 9 | `Sheet` | `scripts/traits/sheet.gd` | Il menu a schermo pieno: boon, Convinzioni, caratteristiche, finale. |
| 10 | `Run` | `scripts/traits/run_manager.gd` | Ciclo di vita della discesa: inizio, uccisioni, morte, Insight. |
| 11 | `Water` | `scripts/water.gd` | Query di superficie dell'acqua su un oracolo duck-typed. |

## Scene

| file | cosa è | agganciato da |
|---|---|---|
| `scenes/dev/hearth_village_playable.tscn` | Il villaggio: 204 nodi, 178 sub-resource, 3333 righe. | `project.godot:14`, scena principale. |
| `scenes/player/player3.tscn` | Il combattente completo, senza nessun nodo che decida. | Istanziata come `Player` nella scena principale. |
| `scenes/enemy_duelist.tscn` | Scena ereditata da `player3.tscn`, più il solo nodo `DuelBrain`. | Istanziata come `Duelist`. |
| `scenes/components/sword.tscn` | Lama, elsa, nastro e `HitBox`. La hitbox è figlia della radice, non della lama. | `Visuals/Sword` in `player3.tscn`. |
| `scenes/fx/blob_shadow.tscn` | Decal di ombra di contatto, senza contenuto autorato. | Figlia di `player3.tscn`. |
| `scenes/fx/toon_skin.tscn` | Nodo scriptato senza contenuto: applica il cel-shading al genitore. | Figlia di `player3.tscn`. |
| `scenes/fx/hit_spark.tscn` | Scintille arancioni, 16 particelle one-shot. | `HitBox.hit_vfx` in `sword.tscn`. |
| `scenes/fx/slash.tscn` | Mesh vuota; lo script costruisce la mezzaluna. | `load()` da `scripts/sword.gd:385`. |
| `scenes/fx/parry_flash.tscn` | Luce blu e 22 particelle. | `load()` da `scripts/player.gd:1124`, **dietro `if shield`: non nasce mai**. |
| `scenes/fx/foot_dust.tscn` | Sbuffo di terra largo e lento. | `preload` in `fx.gd:14`; `Fx.dust` **non ha chiamanti**. |
| `scenes/fx/water_splash.tscn` | 18 goccioline verso l'alto. | `preload` in `fx.gd:12`; **percorso morto**. |
| `scenes/fx/water_ring.tscn` | L'anello di schiuma dello splash. | `preload` in `fx.gd:13`; **percorso morto**. |

## Il combattente

| file | ruolo | agganciato da |
|---|---|---|
| `scripts/player.gd` (1160 righe) | Il corpo: velocità, `AnimationTree`, impugnature, stamina, intercettazione del danno. Non decide niente per frame, lo fa lo stato attivo. | Script sulla radice di `player3.tscn`. |
| `scripts/enemy_duelist.gd` | Solo identità: gruppi, due layer fisici, `target_group`, nasconde la torcia. | Script sulla radice di `enemy_duelist.tscn`. |
| `scripts/components/health.gd` | hp, i-frame e chiusura della morte. L'unico posto dove il danno viene sottratto. | Nodo `Health` in `player3.tscn`. |
| `scripts/components/hurtbox.gd` | Il volume ricevibile. Dà al proprietario il diritto di prima risposta prima di `Health`. | Nodo `HurtBox` in `player3.tscn`, layer 2 (4 sul duellante). |
| `scripts/components/hitbox.gd` | Il volume che infligge. Porta il carico del colpo come metadato sul nodo. | Nodo `HitBox` in `sword.tscn`, maschera 4 (2 sul duellante). |
| `scripts/sword.gd` (391 righe) | Misura da sé la propria portata, timbra i meta, spazza la lama, cavalca l'impugnatura. | Radice di `sword.tscn`. |
| `scripts/components/blade_trail.gd` | Nastro `GPUTrail3D` acceso a raffiche; corregge la lunghezza dipendente dal frame rate dell'addon. | Due nodi vivi: `Sword/Blade/Trail` e `DashTrail` su `player3.tscn`. |
| `scripts/hero_torch.gd` | Omni che sfarfalla con rumore Perlin e vaga in una piccola ellisse, così le ombre si muovono. | Nodo `HeroLight` in `player3.tscn`. **Spenta all'avvio dalla palette del villaggio.** |
| `scripts/toon_skin.gd` | Sostituisce ogni superficie con una copia del materiale toon e attacca il contorno come `next_pass`. | `toon_skin.tscn`, figlia di `player3.tscn`. |
| `scripts/blob_shadow.gd` | Decal proiettato, texture radiale generata in codice, raycast al pavimento ogni frame fisico. | `blob_shadow.tscn`, figlia di `player3.tscn`. |

## Intento e direzione

| file | ruolo | agganciato da |
|---|---|---|
| `scripts/combat/fighter_intent.gd` | La superficie dati che ogni stato legge al posto di `Input`. Sei livelli più due latch. | Adottato o costruito da `player.gd:219-228`, spostato all'indice 0. |
| `scripts/combat/player_intent.gd` | Riempie l'intent da una persona. | Costruito da `player.gd:225` quando la scena non porta un intent. |
| `scripts/combat/duel_brain.gd` (281 righe) | Riempie gli stessi campi da una IA a cinque modi, ridecisa ogni 0.35 s. | Nodo `DuelBrain` in `enemy_duelist.tscn`. L'unica differenza fra i due combattenti. |
| `scripts/combat/swing_dir.gd` | Il vocabolario a quattro vie e l'unico punto in cui esiste lo specchio sinistra/destra. | Classe statica, usata per nome da dieci file. |
| `scripts/combat/guard_pose.gd` | Solo la classe base ormai: dichiara `amount` e `dir`. Il suo `_process_modification` è interamente sovrascritto. | Mai istanziata da sola. |
| `scripts/combat/guard_ik.gd` | Il modificatore che gira davvero: IK a due ossa sul braccio della spada, più contrappeso del braccio sinistro. | `load().new()` da `player.gd:358`, figlio di `GeneralSkeleton`. |
| `scripts/combat/combat_animation_layers.gd` | Ricostruisce lo stato `Slash` in un blend tree con orologio azzerabile e maschera sulle gambe. | Chiamato una volta da `player.gd:426`, solo se esiste `DirAttack`. |

## Macchina a stati

`scripts/states/state_machine.gd` e `state.gd` sono l'impianto; gli altri dieci sono nodi sotto `StateMachine` in `player3.tscn`.

| file | stato | come ci si arriva |
|---|---|---|
| `idle.gd` | Neutro in piedi. | Stato iniziale. |
| `move.gd` | Corsa. | Da Idle con input di movimento. |
| `dir_attack.gd` (343 righe) | Il colpo direzionale tenuto: windup, hold, swing, recoil. | Polling da Idle, Move e Guard. |
| `guard.gd` | La guardia direzionale; possiede `blocks()`. | Polling da Idle, Move e DirAttack. |
| `dash.gd` | Scatto a durata fissa con i-frame. | Solo da `handle_input`. |
| `dash_attack.gd` | Affondo: i-frame nella prima parte, hitbox a metà corsa. | Dash con attacco premuto. |
| `attack.gd` (193 righe) | Combo a click in tre colpi, senza direzione. | **Solo da Dash.** Idle e Move la offrono a un corpo senza `DirAttack`. |
| `jump.gd` | Salto con controllo aereo pieno. | Solo da `handle_input`. |
| `hurt.gd` | Stordimento: mangia l'input, cancella il colpo in corso. | Forzato da `player.gd:1021` e `:1103`. |
| `dead.gd` | Congelamento terminale; annuncia `EventBus.player_died`. | Forzato da `player.gd:1024`. Senza uscita. |

## Villaggio e camera

| file | ruolo | agganciato da |
|---|---|---|
| `scripts/village/terrain.gd` | Una sola manopola per quanto è grande il mondo: ridimensiona insieme il quad del terreno e il suo collisore. | Nodo `Pixel/View/Ground`. Vedi [TERRAIN.md](TERRAIN.md). |
| `scripts/village/iso_cam.gd` | L'unica camera: ortografica, ricostruisce la trasformata ogni frame, possiede il lock-on e la rotazione libera a 360 gradi. | Nodo `IsoCam`, gruppo `camera_rig`. |
| `scripts/village/pixel_snap.gd` | Quantizza i due combattenti sullo stesso reticolo della camera. Scrive `global_position` fuori dalla fisica. | Nodo `PixelSnap`, `process_priority = 100`. |
| `scripts/village/village_character_palette.gd` | All'avvio trapianta la mesh del warden su entrambi i corpi e ricolora ogni superficie. | Nodo fratello di Player e Duelist; `apply` differita. |
| `scripts/village/village_beam.gd` | Il faro dell'eroe: si configura interamente in `_ready`. Vero proprietario del tasto `L`. | **Non esiste in nessuna scena**: creato da `village_character_palette.gd:72-75`. |

## Effetti

| file | ruolo | agganciato da |
|---|---|---|
| `scripts/fx_oneshot.gd` | Due righe: accende un `GPUParticles3D` one-shot e lo libera alla fine. | Radice di `hit_spark`, `water_splash`, `foot_dust`. |
| `scripts/slash.gd` | Costruisce con `SurfaceTool` una mezzaluna affusolata, la dissolve in 0.16 s e si libera. | `slash.tscn`. |
| `scripts/fx/sword_contact.gd` | Acciaio su acciaio: sintetizza il suono campione per campione, più scintille. **Unico audio del progetto.** | `load()` statico da `player.gd:1152`. |
| `scripts/parry_flash.gd` | Luce blu che si spegne in 0.3 s. | `parry_flash.tscn`. **Mai istanziata.** |
| `scripts/water_ring.gd` | L'anello di schiuma che si allarga guidando il proprio uniform `progress`. | `water_ring.tscn`. **Percorso morto.** |

## Progressione

| file | ruolo | stato nel villaggio |
|---|---|---|
| `scripts/traits/traits.gd` (646 righe) | Caratteristiche, check 2d6, Convinzioni, boon, persistenza JSON. | Solo il lato lettura: l'HUD polla le lettere, quattro punti di combattimento leggono i getter derivati. |
| `scripts/traits/sheet.gd` (476 righe) | Il pannello a schermo pieno in quattro modi. | Niente lo apre. |
| `scripts/traits/notice.gd` (299 righe) | La carta del check con rallentamento del tempo. | Niente la chiama. |
| `scripts/traits/run_manager.gd` | Inizio run, uccisioni, morte, Insight, viaggio all'hub. | `Run.begin()` non ha chiamanti: tutto dormiente. |
| `scripts/traits/finale.gd` | Costruttore statico del finale: dialogo a quattro voci e scheda statistiche. | Raggiungibile solo dal ciclo di run. |

## Armi opzionali, presenti come tipo

Nessuna di queste ha un nodo su `player3.tscn`. `player.gd` le dichiara come tipi, quindi cancellarle è un errore di parsing e non un alleggerimento.

| file | cosa sarebbe | perché resta |
|---|---|---|
| `scripts/bow.gd` | Lanciatore di frecce. | `@onready var bow: Bow` in `player.gd:35`. |
| `scripts/projectile.gd` (270 righe) | Volo balistico, homing, contratto di colore parabile/non parabile. | `source is Projectile` in `player.gd:1036` e `:1134`. |
| `scripts/shield.gd` | Stub: solo `follow_grip()` fa qualcosa. | `@onready var shield: Shield` in `player.gd:38`. Il suo essere nullo apre e chiude tre rami. |
| `scripts/arm_guard.gd` | Modificatore di scheletro senza `_process_modification`. | Costruito solo dentro `if shield`. |
| `scripts/tools/tool_belt.gd` | Stub da 16 righe. | **Costruito davvero** a ogni avvio da `player.gd:196` e pollato dall'HUD. |

## Shader

| file | cosa fa | quanti materiali |
|---|---|---|
| `shaders/pixelart/painted_architecture.gdshader` | Superfici dipinte a mano, un quadrante di un atlante 2x2, proiettato per asse dominante. | 78 |
| `shaders/pixelart/architecture_clear.gdshader` | Lo stesso look ma guidato dalle UV della mesh, con override `solid`. | 17 |
| `shaders/pixelart/painted_foliage.gdshader` | Ciuffi di foglie da un mip forzato, così leggono come masse dipinte. | 10 |
| `shaders/pixelart/pixel_surface.gdshader` (366 righe) | Lo shader d'ambiente generale: triplanare o UV, parallasse, displacement, AO, de-tiling, bagnato. | 2 |
| `shaders/pixelart/painted_canopy.gdshader` | Chiome ad albero su griglia dura 256x256, ricolorabili. | 2 |
| `shaders/pixelart/ground_clear.gdshader` | Il terreno: la pittura del villaggio stampata al centro, e fuori un atlante dipinto steso all'infinito con tiling stocastico a varianza conservata, più strade e prati da una mappa di controllo. | 1 |
| `shaders/pixelart/painted_npc.gdshader` | Figure di folla colorate per altezza: stivali, stoffa, maglia, elmo. | 1 |
| `shaders/pixelart/hearth_flame.gdshader` | Fiamma procedurale su un quad. L'unica geometria animata del villaggio. | 1 |
| `shaders/pixelart/ivy_leaf_geometry.gdshader` | Edera vera in un verde oliva fisso, variata dal colore dei vertici. Nessun uniform. | 1 |
| `shaders/pixelart/hearth_hero_material.gdshader` | I corpi dei due combattenti: un colore piatto per superficie, con scacchiera opzionale per la maglia. | Applicato solo in codice. |
| `shaders/pixelart/pixel_post.gdshader` (223 righe) | Risoluzione a pixel: contorno, tonemap, aggancio alla palette in Oklab, dithering 8x8. | 1, **spento** |
| `shaders/pixelart/palette.gdshaderinc` | sRGB verso Oklab, matrice di Bayer, ricerca della voce di palette più vicina. | incluso solo da `pixel_post` |
| `shaders/toon_lit.gdshader` | Cel shading dei personaggi: lambert quantizzato in bande con terminatore regolabile. | via `toon_character.tres` |
| `shaders/toon_outline.gdshader` | Contorno a scafo invertito, solo facce posteriori. | `next_pass` dei materiali toon |
| `shaders/water_ring.gdshader` | L'anello di schiuma che si allarga e assottiglia. | `water_ring.tscn`, percorso morto |

## Risorse

| file | cosa è |
|---|---|
| `assets/models/animations/player3_anims.tres` | La libreria di 85 clip Quaternius. Circa 18 sono nominate da qualche parte; ogni combattente la duplica in profondità all'avvio per non condividere le clip ritemporizzate. |
| `assets/models/animations/bonemap_ual.tres` | Mappa il rig Quaternius sul profilo umanoide di Godot. È il motivo per cui lo scheletro si chiama `GeneralSkeleton` e le ossa `RightHand`, `Hips` e così via. Referenziato dai `.import` dei due GLB, non da una scena. |
| `assets/materials/toon_character.tres` | L'unica istanza autorata del materiale toon: tre bande, terminatore 0.08, ombra fredda. Duplicata per ogni superficie. |
| `assets/models/ual2_mannequin.glb` | Il rig su cui è costruito ogni combattente. |
| `assets/models/camp/hearth_warden.glb` | Il corpo vestito che entrambi indossano in gioco. Caricato per stringa, mai da una scena. |
| `assets/models/camp/hearth_baked/*.res` | Nove mesh del campo troppo grandi o troppo riusate per stare inline nella scena. `geometry_021.res` porta con sé due PNG che nessuna ricerca testuale trova. |
| `assets/models/char_a_Image_0.png`, `_1.png` | Le due texture di cui sopra. Cancellarle rompe il caricamento della scena. |

| `assets/textures/hearth_painted/terrain_layers.png` | L'atlante dipinto del terreno: tre colonne, erba, terra e pietrisco. Ogni colonna è alta tre volte la sua larghezza. |
| `assets/textures/hearth_painted/terrain_roads.svg` | La mappa di controllo di strade ed erba: R terra battuta, G pietrisco, B erba rigogliosa. Dato lineare, mai albedo. Importata senza perdita. |

## Terze parti

`addons/GPUTrail/` è codice di celyk, MIT, tenuto come vendor drop intatto. `scripts/components/blade_trail.gd` lo estende invece di modificarlo, così l'addon resta aggiornabile.

`GPUTrail3D.gd` usa `preload()` **relativi alla propria cartella** per `shaders/trail.gdshader`, `shaders/trail_draw_pass.gdshader`, `defaults/texture.tres` e `defaults/curve.tres`; `plugin.gd` fa lo stesso per `gizmos/gizmo.gd` e `bounce.svg`. Nessuno di questi path compare in una ricerca di `res://`.
