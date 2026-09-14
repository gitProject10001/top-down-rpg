# Kanban dei generatori

Board locale versionata, generata dalle tabelle delle roadmap. DOING include le macrofasi parziali; non significa che ci siano più agenti al lavoro. DONE riguarda il criterio della singola card, non l'intero sistema.

Le card mantengono gli stati delle roadmap. Il criterio di uscita e le dipendenze sono nelle tabelle collegate; prima di iniziare una card TODO, verificare quelle dipendenze.

Aggiornare stati e criteri nelle tabelle, poi eseguire `python tools/update_generator_board.py`. I link delle card aprono la roadmap di riferimento. Non modificare questa board generata a mano.

| TODO | DOING | DONE |
|---|---|---|
| **[A04](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Piani e interni coerenti con i volumi<br>TODO | **[A02a](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Componenti agganciati: balcone + porta<br>IN CORSO | **[A00](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Analisi delle 21 immagini e roadmap<br>FATTO |
| **[A05](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Facciate e strutture per campate<br>TODO | **[A02](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Composizione di più volumi rettangolari<br>IN CORSO | **[A01](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Profilo architettonico minimo e contratto versionato<br>FATTO |
| **[A06](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Due archetipi completi con profili architettonici<br>TODO | **[A03](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Coperture indipendenti e parti aperte<br>IN CORSO | **[G01.3b.2b](WORLD_GENERATION_ROADMAP.md)** — Diagnostica ingombri e verifica editor/Play<br>FATTO |
| **[A10](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Rovine strutturali controllabili<br>TODO | **[A07](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Piante poligonali, torri e coperture curve<br>IN CORSO | **[R01.1](WORLD_GENERATION_ROADMAP.md)** — Roccia parametrica<br>FATTO |
| **[A11](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Integrazione insediamento e consolidamento<br>TODO | **[A08](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Primo Castle Builder: cortina, torri e porta<br>IN CORSO | **[R02.1](WORLD_GENERATION_ROADMAP.md)** — Gruppi su guida<br>FATTO |
| **[R03.3](WORLD_GENERATION_ROADMAP.md)** — Ciglio e sagoma della terrazza<br>TODO | **[A09](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Complessi articolati e castelli multilivello<br>IN CORSO | **[R02.2](WORLD_GENERATION_ROADMAP.md)** — Fascia libera<br>FATTO |
| **[W01](WORLD_GENERATION_ROADMAP.md)** — Laghi editabili<br>TODO | **[G01](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Composizione da metadati, separata dai builder<br>IN CORSO | **[R02.3](WORLD_GENERATION_ROADMAP.md)** — Addensamenti e raccordi<br>FATTO |
| **[W02](WORLD_GENERATION_ROADMAP.md)** — Fiumi editabili<br>TODO | **[R01](WORLD_GENERATION_ROADMAP.md)** — Generatore di singola roccia/affioramento<br>IN CORSO — prototipo disponibile | **[R03.1](WORLD_GENERATION_ROADMAP.md)** — Terrazza piana<br>FATTO |
| **[W03](WORLD_GENERATION_ROADMAP.md)** — Attraversamenti e rive<br>TODO | **[R02](WORLD_GENERATION_ROADMAP.md)** — Composizione di gruppi rocciosi<br>IN CORSO — R02.1–R02.3 verificati | **[R03.2](WORLD_GENERATION_ROADMAP.md)** — Accesso alla terrazza<br>FATTO |
| **[C01](WORLD_GENERATION_ROADMAP.md)** — Ingressi di grotta<br>TODO | **[R03](WORLD_GENERATION_ROADMAP.md)** — Pareti e creste montuose<br>IN CORSO — R03.1–R03.2 verificati |  |
| **[C02](WORLD_GENERATION_ROADMAP.md)** — Piano di grotta<br>TODO |  |  |
| **[G01.4](WORLD_GENERATION_ROADMAP.md)** — Catalogo architettonico<br>TODO |  |  |
| **[G01.5](WORLD_GENERATION_ROADMAP.md)** — Varietà compositiva del castello<br>TODO |  |  |
| **[S01](WORLD_GENERATION_ROADMAP.md)** — Composizione urbana organica<br>TODO |  |  |
| **[S02](WORLD_GENERATION_ROADMAP.md)** — Edifici urbani più articolati<br>TODO |  |  |
| **[V01](WORLD_GENERATION_ROADMAP.md)** — Confronto dei quattro castelli<br>TODO |  |  |
| **[V02](WORLD_GENERATION_ROADMAP.md)** — Vertical slice città–villaggio–POI<br>TODO |  |  |
