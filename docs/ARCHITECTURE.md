# Architettura runtime

## Ingresso

`project.godot` avvia `scenes/dev/hearth_village_playable.tscn`, che compone ambiente, luci, camera, player, duellante e servizi globali. Esiste una sola scena runtime del villaggio.

## Autoload

`EventBus` gestisce segnali; `Fx` effetti; `Traits`, `Run`, `Notice` e `Sheet` progressione e stato; `Dialogue` dialoghi; `Hud` interfaccia; `Dbg` debug; `CombatFeedback` feedback d’impatto; `Water` API leggera; `CombatDirector` turni degli attaccanti.

## Player

`Player` coordina visuali, risorse, macchina a stati e componenti opzionali. `Sword` gestisce il melee, `Bow` le frecce, `Shield` la visuale difensiva, `ArmGuard` il braccio procedurale e `ToolBelt` una API minima compatibile con l’HUD. L’assenza di un’arma opzionale non deve impedire l’avvio.

## Input e attacco direzionale

`PlayerIntent` legge WASD, stick, mouse e pulsanti. `FighterIntent` mantiene `move`, `guard`, `attack_held`, `attack_dir` e l’evento di rilascio. La direzione si sceglie durante la pressione: stick o mouse relativo risolvono in una delle quattro direzioni di `SwingDir`.

`DirAttack` consuma quei dati, avvia l’animazione e abilita la `HitBox` solo durante l’impatto. Il difensore confronta lo stesso vocabolario; il mirror sinistra/destra viene applicato una sola volta.

## Danno e feedback

```text
HitBox.dealt_hit -> HurtBox/Health -> CombatFeedback -> FX, parata, knockback
```

Il feedback di contatto esiste solo quando il danno è applicato; i beat dell’animazione sono separati.

## Nemici

`Enemy` gestisce movimento, distanza, attacchi melee/ranged e recupero. `CombatDirector` coordina i turni per evitare attacchi simultanei. I prefab area attack, freccia, roccia e marker sono dipendenze runtime conservate perché referenziate dal nemico.

## Esclusioni intenzionali

Sono esclusi simulazione acqua avanzata, laboratori, suite di test, generatori dungeon, materiali cyberpunk e asset non raggiungibili dalla scena. Il progetto deve rimanere piccolo: nuove funzionalità arrivano da `rpg-3d` solo dopo essere state rifinite e verificate.

## Verifica

```powershell
& 'C:\Users\jonny\Desktop\game\godot\Godot_v4.6.3-stable_win64.exe' --headless --path . --editor --import --quit
& 'C:\Users\jonny\Desktop\game\godot\Godot_v4.6.3-stable_win64.exe' --headless --path . --quit-after 8
```

Poi va eseguita la prova grafica: movimento, attacco direzionale, parata, dash e interazione.
