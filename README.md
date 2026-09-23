# Top-Down RPG

Progetto Godot 4.6 / Forward+ / Jolt: laboratorio di RPG dall'alto e strumenti riutilizzabili per costruire mondo, edifici e paesaggio.

## Da dove partire

- **[Stato per macrosistemi e priorità](docs/PROJECT_STATUS.md)**: cosa funziona, cosa manca e fonti dei TODO.
- **Scena di lavoro:** aprire `scenes/dev/integrated_landscape.tscn` e avviare la scena corrente (F6 nell'editor).
- **F5 / avvio predefinito:** apre ancora `scenes/dev/hearth_village_playable.tscn`, campione precedente. Non confondere i suoi comandi con quelli del laboratorio integrato.
- [Architettura corrente](docs/ARCHITECTURE.md), [scena integrata](docs/INTEGRATED_LANDSCAPE.md), [combattimento](docs/MEADOW_COMBAT.md), [camera](docs/CAMERA.md).

## Comandi della scena integrata

| Comando | Azione |
|---|---|
| WASD / levetta sinistra | Movimento; dentro gli edifici camminata predefinita |
| Ctrl | Inverte passo/corsa |
| Click sinistro | Combo; tenere carica il fendente con scatto, rilasciare attacca |
| Destro / Shift | Guardia frontale / schivata |
| B | Estrae o reinfodera sul fianco sinistro |
| Centrale mouse | Lock-on |
| E | Parla con NPC vicino, altrimenti interagisce con porta |
| O | Panoramica |
| F6 nel gioco | Pannello ciclo giorno–notte |
| F7 | Confronto della resa artistica |
| P | Pannello filtro pittorico e profondità di campo; P/Esc chiude |
| 1 / 2 / 3 / 5 | Città / guado / lago / borgo |
| 4 / R | Prova combattimento / ripartenza incontro |

F8 nell'editor ferma il gioco. Le regolazioni del pannello P sono temporanee e il gameplay si ferma mentre è aperto.

## Strumenti e roadmap

Le capacità riutilizzabili appartengono agli addon; la scena contiene composizione e tarature. Si sviluppano qui, riusando quando utile il laboratorio `rpg-3d` senza modificarlo implicitamente.

- [Roadmap architettura](docs/ARCHITECTURE_GENERATOR_ROADMAP.md): House/Castle e authoring assistito.
- [Roadmap mondo](docs/WORLD_GENERATION_ROADMAP.md): World, terreno, rocce, acqua, vegetazione e V02.
- [Kanban generato](docs/GENERATOR_KANBAN.md): aggiornare le roadmap sorgenti, poi `python tools/update_generator_board.py`.
- [NPC locali](docs/NPC_AI_INTEGRATION.md): quattro interlocutori, fallback e limiti.
- [Performance](docs/PERFORMANCE.md): cache, streaming e protocolli; i risultati dei campioni non garantiscono 60 fps ovunque.

Il circuito esplorativo è ancora una prova: quest persistenti, ricompense e ripresa completa del mondo giocato restano da realizzare. Nessun download automatico dei modelli NPC e nessun peso in Git.
