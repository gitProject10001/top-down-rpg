# House Builder: interni modificabili

Checkpoint iniziale: `e0a6b08`. GI e lightmap sono rimandati.

## Passaggio 1: dati dell'editor

Seleziona una casa e premi **Interni: crea / mostra**. `InteriorPlan` contiene
piani persistenti e nodi per stanze, muri, scale e oggetti. Aggiungi elementi
dal pannello, spostali/ruotali con W/E e ridimensionali con le maniglie azzurre.
L'Inspector espone dimensioni, porta del muro, scena dell'oggetto e blocco manuale.
Puoi anche trascinare una tua scena direttamente sotto un piano.

`_Visual` e `_Floors` sono cache interne rigenerabili: modifica i nodi dati,
non queste mesh. Salvataggio e undo delle operazioni del pannello conservano
gli elementi dell'utente. **Play casa selezionata** prepara una copia temporanea
in `user://house_builder_playtest.tscn` e avvia gli stessi dati nel banco di prova.
La scena sorgente non viene modificata dal gameplay.

## Passaggi successivi

2. Generazione delle stanze e dei collegamenti con seed e controlli geometrici.
3. Rigenerazione selettiva e protezione di blocchi/modifiche dell'utente.
4. Arredamento opzionale con kit riutilizzabile e spazi di accesso liberi.
