# Kanban dei generatori

Board locale versionata, generata dalle tabelle delle roadmap. DOING include le macrofasi parziali; non significa che ci siano più agenti al lavoro. DONE riguarda il criterio della singola card, non l'intero sistema.

**Priorità: A07 — geometrie architettoniche, prima di B01.1. Prossimo A07.6: cupola e profilo curvo.** Generazione globale da seed e V01 rimandati; R03.3 in backlog. Le card RIMANDATO restano in TODO con stato esplicito.

Le card mantengono gli stati delle roadmap. Il criterio di uscita e le dipendenze sono nelle tabelle collegate; prima di iniziare una card TODO, verificare quelle dipendenze.

Aggiornare stati e criteri nelle tabelle, poi eseguire `python tools/update_generator_board.py`. I link delle card aprono la roadmap di riferimento. Non modificare questa board generata a mano.

| TODO | DOING | DONE |
|---|---|---|
| **[B01.1](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Facciata assistita: finestre su volume rettangolare<br>TODO | **[A02a](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Componenti agganciati: balcone + porta<br>IN CORSO | **[A00](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Analisi delle 21 immagini e roadmap<br>FATTO |
| **[B01.2](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Editing e diagnostica degli elementi automatici<br>TODO | **[A02](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Composizione di più volumi rettangolari<br>IN CORSO | **[A01](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Profilo architettonico minimo e contratto versionato<br>FATTO |
| **[B02](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Campate e dettagli coerenti<br>TODO | **[A03](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Coperture indipendenti e parti aperte<br>IN CORSO | **[A07.4](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Torri segmentate a 8/12/16 facce<br>FATTO |
| **[B03](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Assistenza nei raccordi fra volumi e accessori<br>TODO | **[A07](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Piante poligonali, torri e coperture curve<br>IN CORSO | **[A07.5](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Copertura conica della torre<br>FATTO |
| **[B04](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Esempio costruito da reference tramite builder<br>TODO | **[A08](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Primo Castle Builder: cortina, torri e porta<br>IN CORSO | **[G01.3b.2b](WORLD_GENERATION_ROADMAP.md)** — Diagnostica ingombri e verifica editor/Play<br>FATTO |
| **[A04](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Piani e interni coerenti con i volumi<br>TODO | **[A09](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Complessi articolati e castelli multilivello<br>IN CORSO | **[R01.1](WORLD_GENERATION_ROADMAP.md)** — Roccia parametrica<br>FATTO |
| **[A05](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Facciate e strutture per campate<br>TODO | **[R01](WORLD_GENERATION_ROADMAP.md)** — Generatore di singola roccia/affioramento<br>IN CORSO — prototipo disponibile | **[R02.1](WORLD_GENERATION_ROADMAP.md)** — Gruppi su guida<br>FATTO |
| **[A06](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Due archetipi completi con profili architettonici<br>TODO | **[R02](WORLD_GENERATION_ROADMAP.md)** — Composizione di gruppi rocciosi<br>IN CORSO — R02.1–R02.3 verificati | **[R02.2](WORLD_GENERATION_ROADMAP.md)** — Fascia libera<br>FATTO |
| **[A07.6](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Cupola e profilo curvo<br>TODO | **[R03](WORLD_GENERATION_ROADMAP.md)** — Pareti e creste montuose<br>IN CORSO — R03.1–R03.2 verificati | **[R02.3](WORLD_GENERATION_ROADMAP.md)** — Addensamenti e raccordi<br>FATTO |
| **[A07.7](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Consolidamento A07 e percorso giocabile<br>TODO |  | **[R03.1](WORLD_GENERATION_ROADMAP.md)** — Terrazza piana<br>FATTO |
| **[G01](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Composizione da metadati, separata dai builder<br>RIMANDATO |  | **[R03.2](WORLD_GENERATION_ROADMAP.md)** — Accesso alla terrazza<br>FATTO |
| **[A10](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Rovine strutturali controllabili<br>TODO |  |  |
| **[A11](ARCHITECTURE_GENERATOR_ROADMAP.md)** — Integrazione insediamento e consolidamento<br>TODO |  |  |
| **[R03.3](WORLD_GENERATION_ROADMAP.md)** — Ciglio e sagoma della terrazza<br>TODO |  |  |
| **[W01](WORLD_GENERATION_ROADMAP.md)** — Laghi editabili<br>TODO |  |  |
| **[W02](WORLD_GENERATION_ROADMAP.md)** — Fiumi editabili<br>TODO |  |  |
| **[W03](WORLD_GENERATION_ROADMAP.md)** — Attraversamenti e rive<br>TODO |  |  |
| **[C01](WORLD_GENERATION_ROADMAP.md)** — Ingressi di grotta<br>TODO |  |  |
| **[C02](WORLD_GENERATION_ROADMAP.md)** — Piano di grotta<br>TODO |  |  |
| **[G01.4](WORLD_GENERATION_ROADMAP.md)** — Catalogo architettonico<br>TODO |  |  |
| **[G01.5](WORLD_GENERATION_ROADMAP.md)** — Varietà compositiva del castello<br>RIMANDATO |  |  |
| **[S01](WORLD_GENERATION_ROADMAP.md)** — Composizione urbana organica<br>RIMANDATO |  |  |
| **[S02](WORLD_GENERATION_ROADMAP.md)** — Edifici urbani più articolati<br>TODO |  |  |
| **[V01](WORLD_GENERATION_ROADMAP.md)** — Confronto dei quattro castelli<br>RIMANDATO |  |  |
| **[V02](WORLD_GENERATION_ROADMAP.md)** — Vertical slice città–villaggio–POI<br>TODO |  |  |
