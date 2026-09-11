# Top-Down RPG

Porting parziale del progetto `rpg-3d` verso un gioco d'azione 3D con visuale dall'alto.

## Avvio

- Engine: Godot 4.6
- Renderer: Forward Plus
- Fisica: Jolt Physics
- Scena di gioco: `scenes/dev/hearth_village_playable.tscn`
- Comandi: WASD / levetta sinistra per muoversi, mouse sinistro per attaccare, mouse destro per parare, Shift per il dash, E per interagire.

## Struttura essenziale

- `scenes/`: scene e prefab Godot
- `scripts/`: gameplay, combattimento, mondo e UI
- `scripts/dev/`: strumenti di sviluppo, prove visive e generatori
- `shaders/`: materiali e post-processing
- `assets/`: modelli, texture e materiali
- `addons/`: plugin locali, inclusi acqua simulata e animazione procedurale

## Singleton principali

Gli autoload sono dichiarati in `project.godot`. I più importanti sono `EventBus`, `Traits`, `Run`, `Hud`, `Dialogue` e `CombatDirector`.

## Regola per il refactoring

Il codice in `scripts/dev/` non deve essere considerato automaticamente gameplay definitivo. Prima di rimuovere o spostare un file, verificare i riferimenti in scene, script e `project.godot`.

