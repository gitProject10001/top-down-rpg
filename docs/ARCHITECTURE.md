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

Nota attuale: la scena del villaggio usa ancora tre script sotto `scripts/dev/test_pixelart/` per camera pixel, pixel snapping e palette dei personaggi. Sono dipendenze runtime da spostare in una cartella di gameplay del villaggio nel prossimo passaggio; non vanno cancellati durante la pulizia.

## Villaggio

La scena runtime unica è `scenes/dev/hearth_village_playable.tscn`, configurata come `run/main_scene` in `project.godot`. La copia duplicata nella cartella `scenes/` è stata rimossa perché non era referenziata e puntava a una variante diversa del player.

La scena del villaggio è soprattutto un contenitore di geometria, materiali e luci. Il prossimo refactoring sicuro è dividerla in sottoscene per terreno, edifici, decorazioni, vegetazione e gameplay, mantenendo invariata la scena principale come composizione.

## Priorità tecniche

1. Eliminare la duplicazione tra scene del villaggio dopo aver scelto una sola variante del player.
2. Estrarre la geometria statica del villaggio in sottoscene.
3. Ridurre gli autoload ai servizi realmente globali.
4. Spostare gli strumenti non runtime in un’area `tools/` o mantenerli marcati chiaramente come development.
5. Aggiungere test headless per scena principale, combattimento e ciclo della run.
