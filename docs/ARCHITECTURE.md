# Architettura del progetto

## Flusso runtime

```text
project.godot
  -> scenes/dev/hearth_village_playable.tscn
      -> mondo 3D e SubViewport pixel-art
      -> player/player3.tscn
      -> enemy_duelist.tscn
      -> autoload globali
```

## Confine tra porting e laboratorio

Il progetto contiene due tipi di codice:

1. **Runtime**: player, nemici, combattimento, HUD, dialoghi, mondo e progressione.
2. **Development**: generatori, probe, shot, lab e script di verifica sotto `scripts/dev/`.

Gli strumenti development possono produrre scene e risorse runtime, ma non devono diventare dipendenze obbligatorie del gioco finale senza una decisione esplicita.

## Villaggio

La scena attualmente avviata è `scenes/dev/hearth_village_playable.tscn`. Esiste anche `scenes/hearth_village_playable.tscn`, ma non è una copia perfetta: usa un riferimento diverso al player. Per questo le due scene non vanno unite o cancellate alla cieca.

La scena del villaggio è soprattutto un contenitore di geometria, materiali e luci. Il prossimo refactoring sicuro è dividerla in sottoscene per terreno, edifici, decorazioni, vegetazione e gameplay, mantenendo invariata la scena principale come composizione.

## Priorità tecniche

1. Eliminare la duplicazione tra scene del villaggio dopo aver scelto una sola variante del player.
2. Estrarre la geometria statica del villaggio in sottoscene.
3. Ridurre gli autoload ai servizi realmente globali.
4. Spostare gli strumenti non runtime in un’area `tools/` o mantenerli marcati chiaramente come development.
5. Aggiungere test headless per scena principale, combattimento e ciclo della run.

