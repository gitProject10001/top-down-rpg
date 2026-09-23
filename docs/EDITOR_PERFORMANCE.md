# Editor: selezione terreno e lavoro a scena ferma

> **Diagnosi specifica e misure storiche della selezione del terreno.** Per cache, generazione incrementale e streaming correnti vedere [PERFORMANCE](PERFORMANCE.md). Nessuna delle due note certifica il frame time su tutta la mappa.

## Misure del 15 settembre 2026

Le prove riproducono la scena integrata. I tempi editor sotto sono misurati
con Godot 4.6.3 `--headless --editor`, quindi non sono FPS della finestra utente
ne' un benchmark GPU. Servono a separare il lavoro editor dal rendering.

- Terreno isolato renderizzato a 1400x900: shader originale ~1,37 ms GPU;
  materiale semplice ~1,03 ms. Non giustifica da solo il forte rallentamento.
- Editor, selezione diretta della vecchia MeshInstance3D: ~100-135 ms/frame.
- Sostituire solo il materiale non risolve; anche una PlaneMesh mantiene il
  costo della selezione. Rimuovere il collider nella prova lo riduce ma non
  lo elimina. Deselezionare riporta circa 10 ms. Non attribuiamo il problema
  alla complessita dello shader o dichiariamo risolto il percorso interno Godot.
- Nuova selezione del gruppo terreno: ~9,5 ms/frame nel test locale.
- Audit CPU degli interni a scena ferma: plan.gd + plan_element.gd da circa
  2,69 a 0,43 ms/frame, stessa geometria e stessi materiali. Nessuna
  rigenerazione idle rilevata dai contatori delle case nella finestra campionata.

## Modifiche

`TerrenoComposto` e' ora un Node3D raggruppato con metadata editor `_edit_group_`:
il clic ordinario seleziona il gruppo, senza aprire i dati della mesh
nell'Inspector. `TerrenoComposto/Superficie` contiene mesh e materiale originali;
il collider rimane suo figlio. Per modificare il materiale selezionare
esplicitamente Superficie nell'albero. Questo percorso puo' ancora essere
lento: il raggruppamento evita il problema nell'editing ordinario, non modifica
il codice dell'Inspector Godot. Terreno, collisioni e dettaglio sono invariati.

Gli interni controllano gerarchia, nomi e diagnostica ogni 100 ms quando
invariati. Dimensioni modificate, stato dirty e trasformazioni degli elementi
saltano l'attesa; gli aggiornamenti geometrici richiesti restano immediati.
Modifiche indirette a un piano possono richiedere al massimo un intervallo
di audit. Il runtime non viene limitato da questo intervallo editor.

Il Village Builder aggiorna `builder_inverse` solo al cambio di trasformazione
o materiale. Prima lo inviava a ogni frame; il test ha mostrato che quelle
chiamate NON emettevano Resource.changed: non sono state dichiarate la causa
del problema di selezione.

## Strumenti di verifica

- `tools/profile_integrated_ground.gd`: GPU shader vs materiale semplice,
  eseguire con rendering, senza --headless.
- `tools/profile_builder_idle.gd`: campionamento per famiglia di script con
  --headless --editor; non usare come misura di costo completo del frame.
- `tools/profile_editor_ground.gd`: --headless --editor, confronto gruppo (0)
  e mesh esplicita (1). Apre la scena integrata nell'editor di prova.
- `tools/check_idle_ground_material.gd`: aggiornamento trasformazione e cambio
  materiale dopo eliminazione delle scritture ripetute.
- `tools/check_integrated_landscape.gd`: percorso, guado, porta e cutaway.

Le prove editor headless possono stampare leak alla chiusura dell'editor;
i test gameplay hanno il noto avviso PagedAllocator finale. Questi messaggi
non vanno confusi con errori durante la prova. Nessuna riduzione grafica e'
stata applicata in questo intervento. Restano profiling GPU della scena intera,
costo degli alberi/ombre e diagnosi del percorso Inspector della mesh esplicita.
