# Stato del progetto per macrosistemi

Aggiornato: 23 settembre 2026. Questa pagina è l'indice operativo, non una seconda lista dei TODO dei generatori. Le prove documentate riguardano campioni specifici; non certificano l'intero gioco.

## Scena e priorità

Il laboratorio corrente è `scenes/dev/integrated_landscape.tscn`: aprirlo e avviare la scena corrente. F5 continua ad aprire `hearth_village_playable.tscn`, come configurato in `project.godot`. Non è stato cambiato l'avvio del progetto.

Prima consolidare documentazione e una piccola esperienza completa sul circuito già presente; poi riprendere l'editor assistito. Nessuna nuova espansione della mappa necessaria per questo incremento. NPC conversazionali restano sospesi; la missione può usare dialoghi deterministici.

## Macrosistemi e fonti autorevoli

| Sistema | Disponibile | Lavoro aperto / fonte |
|---|---|---|
| Mondo ed esplorazione | World, quote discrete, streaming, circuito borgo–guado–torre | V02: esperienza completa; R03.3: cigli; W01.2/W01.3: rive e acqua; T01.4: budget. [Roadmap mondo](WORLD_GENERATION_ROADMAP.md) |
| Edifici e authoring | Ricette, volumi, aperture, interni, gizmo, override e cutaway | A07: confronto ancora aperto, poi B01.1/B01.2, B02/B03. [Roadmap architettura](ARCHITECTURE_GENERATOR_ROADMAP.md). Non basta un edificio riuscito per completare una capacità generica |
| Combattimento e personaggi | Combo, carica con scatto, guardia frontale, gruppi, locomozione e ragdoll | Consolidare ritmo e leggibilità nel circuito V02, morte/ripartenza; varietà nemici successiva. [Combattimento](MEADOW_COMBAT.md) |
| Progressione e salvataggi | Traits/Run storici, dati salvati degli addon, memoria NPC | Mancano progressione e ripresa coerenti del circuito integrato: proprietà editor e memoria NPC non equivalgono al salvataggio del mondo giocato. Criterio V02 nella roadmap mondo |
| NPC e narrativa | Quattro capsule parlanti, servizio condiviso locale, memoria isolata, fallback | Packaging offline su macchina pulita, coerenza del testo, eventi canonici. [Integrazione](NPC_AI_INTEGRATION.md). Nessuna autorità del modello su premi/quest |
| Resa visiva | Studio dipinto, vegetazione, acqua, giorno/notte, filtro e DOF regolabile | Confronti visivi, preset persistenti per il pannello P ancora assenti; outline sospeso. [Scena integrata](INTEGRATED_LANDSCAPE.md), [dati artistici](ART_STUDY_DATA.md) |
| Prestazioni e distribuzione | Cache, generazione incrementale, streaming e benchmark locali | Misure lungo percorso completo, picchi CPU/GPU, costo DOF, export pulito. [Performance](PERFORMANCE.md) e verifiche V02 |

## Ordine di lavoro

1. V02 sul circuito esistente: assegnazione, incontro, esito concreto, ritorno/scorciatoia, salvataggio e morte/ripartenza. Criteri dettagliati nella roadmap mondo; non duplicare card qui.
2. Validare leggibilità e prestazioni di quel percorso a 1152×648; separare caricamento, gioco e picchi. Un dato medio non chiude il budget.
3. Ramo editor: chiudere il confronto A07 richiesto dalla roadmap, poi B01.1 su una casa rettangolare. Conservare gli elementi manuali e un solo Undo per gesto; raccordi B02/B03 successivi.
4. Rifiniture artistiche dove il percorso evidenzia problemi. Espansione globale, altri generatori, voce e ragdoll più complesso non sono il prossimo incremento.

## Regole dei TODO

- `WORLD_GENERATION_ROADMAP.md` e `ARCHITECTURE_GENERATOR_ROADMAP.md` sono le fonti delle card dei generatori; la sezione mondo dentro la seconda è una copia generata.
- `GENERATOR_KANBAN.md` è una vista dei generatori, non di tutto il prodotto. Rigenerare con `python tools/update_generator_board.py`; mai correggere le card direttamente nella board.
- FATTO significa soddisfare il criterio della singola card. Una sottofase conclusa non chiude automaticamente la macrofase.
- Stato corrente, decisioni future e risultati storici devono essere esplicitamente distinti. Le caselle della vecchia consegna NPC non sono lavoro da riavviare.
- Nessun file di codice va eliminato perché una sua descrizione è vecchia: controllare anche riferimenti Godot e risorse binarie.

## Mappa della documentazione

| Documento | Ruolo |
|---|---|
| README, ARCHITECTURE, MEADOW_COMBAT, CAMERA | Guida corrente e punti di ingresso nel codice |
| BUILDING_RECIPES, HOUSE_AUTHORING, WORLD_GENERATION, ART_STUDY_DATA | Contratti e capacità degli strumenti; leggere i limiti delle singole prove |
| INTEGRATED_LANDSCAPE | Stato in apertura, seguito da diario degli incrementi; le revisioni datate non sono tutte simultaneamente valide |
| EXPANDED_LANDSCAPE, BORGO_EXPLORATION_CIRCUIT, PERFORMANCE | Risultati di campioni e limiti; prestazioni legate alla revisione misurata |
| EDITOR_PERFORMANCE | Diagnosi storica specifica della selezione terreno, complementare a PERFORMANCE |
| COMPONENTS, DIRECTIONAL_COMBO | Inventario storico / meccanica precedente; non guida corrente del player |
| LOCAL_NPC_AI_TODO | Handoff storico conservato; TODO attivi nell'integrazione NPC |
| NPC_AI_RUNTIME | Manuale del laboratorio; integrazione corrente descritta in NPC_AI_INTEGRATION |
