# Primo percorso di esplorazione

Nella scena hearth_village_playable, `Pixel/View/ExplorationRoute` definisce
un anello di circa 213 metri a nord-ovest del villaggio. Dal sentiero nord,
vicino a X=-12 Z=-30, la pavimentazione spezzata conduce alla Radura delle
pietre antiche (X=-56 Z=-95). Il ramo occidentale riconduce al bivio.
La camera del giocatore non cambia.

## Dati e responsabilità

- `exploration_route.gd`: punti XZ, radura, indizi, pietre e scoperta locale.
- Shader del terreno: riceve la polilinea e disegna il sentiero sulla superficie.
- `world_stream.gd`: esclude decorazione procedurale da strada e radura;
  aumenta la densità ai margini. Le modifiche manuali mantengono la precedenza.

I punti e il raggio sono salvati nella scena e modificabili nell'Inspector.
Limite attuale: massimo 32 punti per il materiale. I dettagli sono deterministici
ma ricostruiti, non ancora baked. Le tre pietre alte hanno collisione;
pavimentazione e frammenti piccoli sono decorativi. La scoperta mostra il nome
una volta per esecuzione, non è un salvataggio del progresso del giocatore.

Questo è un esperimento locale di level design, NON il generatore completo
di regioni discusso nel PDF. Nessuna dipendenza aggiunta dal progetto laboratorio.
Non sono presenti quest, premi, indizi sonori o camera libera.

## Verifica

Test automatico `.godot/check_route.gd`: percorrenza dell'intero anello con
CharacterBody3D, trigger di scoperta con Player, serializzazione e ricaricamento
dei punti. Render del punto d'interesse con camera di gioco ispezionato.
Il test non valuta se un giocatore nuovo nota spontaneamente il bivio:
questa è la prossima verifica di playtesting, senza marker direzionali.
