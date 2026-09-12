# Generazione per zone

World include Place tree, Paint forest, Erase trees, Raise terrain, Lower terrain,
Flatten terrain e Reserve POI zone. Per il terreno il raggio minimo effettivo
è 12 m; Height m è l'incremento assoluto per alza/abbassa e la quota di
destinazione per appiattisci. Rilasciare il mouse applica la pennellata.
Ctrl+Z annulla la pennellata o la rigenerazione, Ctrl+S salva la scena.

## Proprietà dei dati

- Ground.world_plan: Resource generata, seed e regioni salvati; il pulsante
  Regenerate procedural regions sostituisce SOLO questa risorsa, con Undo.
- Ground.reserved_zones: cerchi manuali protetti, mostrati in oro nella mappa.
- Ground.height_edits: modifiche manuali sovrapposte al terreno di base.
- WorldStream.world_edits: alberi e cancellature manuali, mai svuotati dal generatore.
- Villaggio ed ExplorationRoute: nodi autoriali, non rigenerati.

Stesso seed e stessa versione producono lo stesso piano. Nuovo seed sostituisce
le regioni precedenti, non accumula mondi e non cancella nodi o file manuali.
La versione iniziale produce sei regioni forestali e quattro rilievi, NON
villaggi, fiumi o un grafo stradale automatico. Le strade esistenti restano.

Riservare una zona NON congela il terreno generato precedente: esclude il
contributo procedurale e lascia base autoriale e sculpt. Quindi marcare prima
di costruire. Una fascia di 32 m attenua il rilievo intorno alla zona.
La riserva iniziale di 140 m protegge villaggio, primo rilievo e percorso.
I dettagli procedurali dentro una riserva sono esclusi; gli alberi manuali restano.

## Limiti attuali

Il piano è persistente, ma le mesh sono ricostruite al caricamento. Il terreno
ampio usa campioni ogni 8 m, il primo rilievo conserva 1 m: non è ancora un
sistema di sculpt fine o di streaming delle mesh del terreno. LOD nativi
ridimensionano il dettaglio visivo, non il costo di ricostruzione.
I pennelli non hanno ancora un cursore 3D e la rigenerazione ricostruisce
l'intera mesh. Le riserve sono cerchi, non poligoni. La UI mouse/Undo non è
stata collaudata manualmente; API dati, persistenza e collisioni sono testate.

Test: determinismo, cambio seed, preservazione layer manuali, protezione centro,
sculpt e raycast collisione, serializzazione/ricaricamento del piano.
