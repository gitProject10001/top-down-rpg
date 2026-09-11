# Top-Down RPG

Vertical slice minimale del villaggio giocabile, portata da `rpg-3d`. Questo repository contiene solo il runtime necessario alla scena principale; `rpg-3d` resta il laboratorio e non viene modificato.

## Stato attuale

- Godot 4.6, Forward Plus, Jolt Physics.
- Scena principale: `scenes/dev/hearth_village_playable.tscn`.
- Villaggio 3D esplorabile con player, duellante, HUD, dialoghi e combattimento direzionale.
- L'acqua simulata avanzata è esclusa; `Water` è solo un servizio leggero di compatibilità.
- Dungeon, test, nemico classico, animazione procedurale e asset non raggiungibili dalla scena non fanno parte del runtime.

## Comandi

- `WASD` / levetta sinistra: movimento.
- Click sinistro: tieni premuto, muovi il mouse per scegliere la direzione, rilascia per attaccare.
- Click destro: guardia/parata. `Shift`: dash. `E`: interazione. `L`: torcia.

## Combattimento

`PlayerIntent` raccoglie input e direzione; `FighterIntent` espone uno stato neutro; `SwingDir` definisce `UP`, `DOWN`, `LEFT`, `RIGHT`. `DirAttack` consuma direzione e rilascio, avvia l'animazione e abilita la `HitBox` nei frame di impatto.

```text
input mouse/stick -> PlayerIntent -> StateMachine/DirAttack
                                  -> Sword/HitBox -> Health/HurtBox/CombatFeedback
```

`EnemyDuelist` eredita la scena del player e ne riusa l'intero contratto: stesso rig, stessi stati, stessa `HitBox`. L'unica differenza è `DuelBrain`, che sostituisce `PlayerIntent` nel decidere le mosse.

## Struttura

- `scenes/`: scena principale e prefab runtime.
- `scripts/player.gd`: orchestratore del personaggio.
- `scripts/combat/`: intenti, direzioni, guardia e coordinamento.
- `scripts/states/`: macchina a stati (`Idle`, `Move`, `Attack`, `DirAttack`, `DashAttack`, `Guard`, `Dash`, `Jump`, `Hurt`, `Dead`).
- `scripts/components/`: salute, hitbox, hurtbox e trail.
- `scripts/village/`: camera, pixel snapping, palette e beam.
- `scripts/traits/`: HUD/progressione, run e finale.
- `addons/GPUTrail/`: trail runtime/editor, vendorizzato senza modifiche.

## Regola del progetto

Le nuove funzionalità vengono prima consolidate in `rpg-3d`, poi portate qui solo se necessarie al villaggio. Prima di rimuovere un file si verificano scene, script, autoload, classi globali Godot e le dipendenze binarie dei `.res` (che una ricerca testuale non vede).
