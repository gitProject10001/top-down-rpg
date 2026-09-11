# Architettura runtime

## Ingresso

`project.godot` avvia `scenes/dev/hearth_village_playable.tscn`, che compone ambiente, luci, camera, player, duellante e servizi globali. Esiste una sola scena runtime del villaggio.

## Autoload

`EventBus` gestisce segnali; `Fx` effetti; `Traits`, `Run`, `Notice` e `Sheet` progressione e stato; `Dialogue` dialoghi; `Hud` interfaccia; `Dbg` debug; `CombatFeedback` feedback d'impatto; `Water` API leggera di compatibilità.

## Player

`Player` coordina visuali, risorse, macchina a stati e componenti opzionali. `Sword` gestisce il melee, `Bow` le frecce, `Shield` la visuale difensiva, `ArmGuard` il braccio procedurale e `ToolBelt` una API minima compatibile con l'HUD. Sul corpo del villaggio arco e scudo non sono montati: restano contratti di tipo che `player.gd` dichiara, e l'assenza di un'arma opzionale non deve impedire l'avvio.

## Input e attacco direzionale

`PlayerIntent` legge WASD, stick, mouse e pulsanti. `FighterIntent` mantiene `move`, `guard`, `attack_held`, `attack_dir` e l'evento di rilascio. La direzione si sceglie durante la pressione: stick o mouse relativo risolvono in una delle quattro direzioni di `SwingDir`.

`DirAttack` consuma quei dati, avvia l'animazione e abilita la `HitBox` solo durante l'impatto. Il difensore confronta lo stesso vocabolario; il mirror sinistra/destra viene applicato una sola volta.

## Danno e feedback

```text
HitBox.dealt_hit -> HurtBox/Health -> CombatFeedback -> FX, parata, knockback
```

Il feedback di contatto esiste solo quando il danno è applicato; i beat dell'animazione sono separati.

## Avversario

`EnemyDuelist` è una scena ereditata da `player3.tscn`: stesso rig, stessa spada, stessa macchina a stati, stesso inviluppo d'attacco misurato. Cambiano solo i gruppi, i layer fisici e il bersaglio. `DuelBrain` prende il posto di `PlayerIntent` e riempie le stesse decisioni. Non esiste una seconda implementazione della meccanica.

## Esclusioni intenzionali

Sono esclusi simulazione acqua avanzata, laboratori, suite di test, generatori dungeon, il nemico classico con il suo direttore di combattimento, l'addon di animazione procedurale e gli asset non raggiungibili dalla scena. Il progetto deve rimanere piccolo: nuove funzionalità arrivano da `rpg-3d` solo dopo essere state rifinite e verificate.

## Verifica

```powershell
& 'C:\Users\jonny\Desktop\game\godot\Godot_v4.6.3-stable_win64.exe' --headless --path . --editor --import --quit
& 'C:\Users\jonny\Desktop\game\godot\Godot_v4.6.3-stable_win64.exe' --headless --path . --quit-after 200
```

Entrambi i comandi devono chiudersi senza righe `ERROR`. Poi va eseguita la prova grafica: movimento, attacco direzionale, parata, dash e interazione.

## Prima di potare

Una ricerca testuale non vede tutto. I `.res` binari compressi (`assets/models/camp/hearth_baked/`) dichiarano dipendenze proprie: `geometry_021.res` carica `assets/models/char_a_Image_0.png` e `_1.png`, che nessun file di testo nomina. La lista vera delle dipendenze sta in `.godot/editor/filesystem_cache10`. Vanno considerati anche i `preload()` relativi alla cartella dello script, usati dentro `addons/GPUTrail/`.
