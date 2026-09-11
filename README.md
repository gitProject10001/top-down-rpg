# Top-Down RPG

Vertical slice minimale del villaggio giocabile, portata da `rpg-3d`. Questo repository contiene solo il runtime necessario alla scena principale; `rpg-3d` resta il laboratorio e non viene modificato.

## Documentazione

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — come gira il gioco, meccanica per meccanica, con i file in cui ogni cosa succede.
- [docs/COMPONENTS.md](docs/COMPONENTS.md) — ogni file di codice, cosa fa e come entra nel gioco.
- [docs/TERRAIN.md](docs/TERRAIN.md) — il materiale del terreno, come si estende senza ripetersi e come si aggiungono strade ed erba.

## Stato attuale

- Godot 4.6, Forward Plus, Jolt Physics.
- Scena principale: `scenes/dev/hearth_village_playable.tscn`, aperta direttamente all'avvio.
- Un villaggio esplorabile con due combattenti identici, HUD e combattimento direzionale.
- Il duellante è la stessa scena del giocatore con un cervello al posto delle mani. Non esiste una seconda implementazione della meccanica.
- Dungeon, test, nemico classico, animazione procedurale e asset non raggiungibili dalla scena non fanno parte del runtime.
- Progressione, dialoghi e ciclo di run esistono nel codice ma non partono in questa scena. La lista completa è in `ARCHITECTURE.md`, sezione *Macchinario dormiente*.

## Comandi

| | |
|---|---|
| `WASD` / levetta sinistra | movimento |
| click sinistro | tieni premuto, muovi il mouse per scegliere la direzione, rilascia per attaccare |
| click destro | guardia direzionale; nei primi 0.24 s è parata |
| `Shift` | dash |
| `Spazio` | salto |
| `L` | torcia |
| frecce sinistra e destra, levetta destra | ruota la camera, 360 gradi, quando non sei agganciato |
| tasto centrale del mouse | lock-on |
| `F3` / `F8` | volumi di debug |

## Combattimento

`PlayerIntent` raccoglie input e direzione; `FighterIntent` espone uno stato neutro; `SwingDir` definisce `UP`, `DOWN`, `LEFT`, `RIGHT`. `DirAttack` consuma direzione e rilascio, avvia l'animazione e apre la `HitBox` nella fase di impatto.

```text
input mouse/stick -> PlayerIntent -> StateMachine/DirAttack
                                  -> Sword/HitBox -> HurtBox/Health -> CombatFeedback
```

La direzione si sceglie mentre il colpo è in carica, e cambiarla è una finta. Chi difende deve leggere la direzione giusta: non c'è credito parziale. Lo specchio sinistra/destra dell'attaccante verso il difensore è applicato in un punto solo, `SwingDir.mirror()`.

## Struttura

- `scenes/`: scena principale e prefab runtime.
- `scripts/player.gd`: orchestratore del personaggio.
- `scripts/combat/`: intenti, direzioni, guardia e coordinamento.
- `scripts/states/`: macchina a stati (`Idle`, `Move`, `Attack`, `DirAttack`, `DashAttack`, `Guard`, `Dash`, `Jump`, `Hurt`, `Dead`).
- `scripts/components/`: salute, hitbox, hurtbox e trail.
- `scripts/village/`: camera, pixel snapping, palette e beam.
- `scripts/traits/`: progressione, run e finale.
- `addons/GPUTrail/`: trail runtime/editor, vendorizzato senza modifiche.

## Regola del progetto

Le nuove funzionalità vengono prima consolidate in `rpg-3d`, poi portate qui solo se necessarie al villaggio. Prima di rimuovere un file si verificano scene, script, autoload, classi globali Godot e le dipendenze binarie dei `.res`, che una ricerca testuale non vede. La lista delle trappole è in fondo a `ARCHITECTURE.md`.
