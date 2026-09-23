# Primo circuito: borgo, guado, torre, ritorno

## Prova disponibile

La scena integrata conserva i sei lotti del borgo, la chiesa, la locanda, i quattro NPC, la città e il fiume. **Non è stato rigenerato il villaggio.**

Premere **5** per raggiungere il borgo e seguire la strada verso ovest, fino all’uscita presso `(15, 23)`. La prova inizia avvicinandosi, senza una nuova conversazione o assegnazione da parte degli NPC.

1. Uscita ovest del borgo esistente.
2. Attraversamento del guado esistente a Z=21; checkpoint sulla riva occidentale.
3. Sentiero nel bosco verso la torre, con radura e due predoni.
4. Dopo averli sconfitti, ritorno sul sentiero già conosciuto.
5. Nuovo attraversamento dello stesso guado e rientro all'uscita del borgo.

**R** riprende l'incontro della torre mentre è attivo; il comando del vecchio incontro nel prato resta disponibile fuori da questa fase. **4** continua a raggiungere la prova di combattimento preesistente. Dialoghi e pausa fermano la progressione del circuito. Con `--no-enemies` si può provare soltanto la percorrenza.

## Riutilizzo e dati autoriali

- House Builder: torre indipendente `TorreDelGuado`, Volume di pietra con aperture e merli, identità `borgo_circuit:watchtower`. È un volume di prova riconoscibile, non ancora la rovina dipinta del concept.
- World: l'ExplorationRoute esistente ora ammette rami separati. Shader del terreno, esclusione degli alberi e copertura dell'erba leggono gli stessi tracciati. Il ramo non sostituisce il percorso periferico precedente.
- `addons/world_editor/exploration_circuit.gd`: checkpoint ordinati, segnali di avanzamento, misure di distanza e tempo, condizione opzionale per proseguire. Non assegna inventario, premi o missioni agli NPC.
- `scripts/village/borgo_exploration_trial.gd`: composizione della prova e HUD; riusa IntegratedEncounter, PackDirector e i predoni esistenti. Nessuna seconda implementazione del combattimento. Il nuovo incontro si avvia solo avvicinandosi alla torre dopo il guado.
- `BorgoCircuit` nella scena: checkpoint modificabili. I cartelli sono stati rimossi perché il testo non era leggibile alla camera normale. Gli alberi che invadono il passaggio/radura sono ricollocati conservando `metadata/pre_circuit_position`; quelli liberati dalla rimozione del vecchio ramo sono ripristinati dove possibile.

Lo stato di avanzamento è **temporaneo e riparte caricando la scena**. La persistenza delle quest, dialoghi dedicati, ricompense, sigilli, porte condizionate e scorciatoie sbloccabili non sono implementati da questa prova. Il concept completo non viene esteso al resto della mappa.

## Misure e verifica

`tools/check_borgo_circuit.tscn` usa il controller reale del giocatore e percorre il sentiero di andata e ritorno, guado compreso. Prima prova: circa **159,9 m**, **28,55 s**, senza un combattimento giocato normalmente. Nel test i predoni vengono sconfitti tramite il componente Health per verificare la condizione di progressione; questo non misura difficoltà o durata dell'incontro. Tutti i checkpoint passano, i sei lotti originali restano presenti.

La radura ha raggio nominale 10 m; la torre è 5,8 × 5,8 m, pareti alte 8,5 m. La sagoma fa da riferimento oltre gli alberi; l'inquadratura ravvicinata non ne mostra sempre la sommità. Catture: `captures/circuit_tower.png` e `captures/circuit_overview.png`.

**Conclusione di scala:** è un piccolo circuito di esplorazione, non una zona che da sola sostenga una lunga quest. Prima di aggiungere altre destinazioni, valutare sul campo incontro, orientamento e pause narrative. Evitare di gonfiare i tempi con deviazioni artificiali.

Ultima verifica: `BORGO_CIRCUIT_RESULT []`; 159,9 m in 29,63 s inclusa la pausa di cattura. A 1152×648, presso il borgo: mediana frame 16,603 ms, p95 18,231 ms; GPU mediana 15,760 ms, p95 17,325 ms. Sono valori del campione, non una garanzia di 60 fps su tutta la mappa.

Dopo modifiche manuali ai rami, rigenerare lo studio artistico o riaprire la scena per aggiornare la cache di copertura dell’erba; il solo aggiornamento dello shader non rigenera quella cache.

Il test termina ancora con il messaggio PagedAllocator già presente nelle prove integrate; non è dichiarato risolto qui.

## Correzione di leggibilità del bivio

Rimosso il ramo meridionale: non offriva una scelta distinta e introduceva una terza direzione equivalente. Dal guado si percorre un breve tratto della strada della città, larga 5 m; presso `(-12, 20)` si stacca il sentiero della torre, con centro battuto di circa 1,1 m e transizione fino a 2,7 m totali. Shader ed esclusione dell’erba usano le stesse larghezze. Il ritorno ripercorre il sentiero: nessun checkpoint invisibile obbliga a cercare una seconda strada.

Il tracciato mantiene distanza dal vecchio incontro nel prato. Il test ora avvia anche quell’incontro per verificare che la nuova escursione non lo attivi accidentalmente. Cattura del bivio alla camera normale in `captures/circuit_junction.png`. Le misure precedenti descrivono il circuito a due rami, ora superato.

Verifica dopo la correzione: `BORGO_CIRCUIT_RESULT []`, percorso effettivo **138,2 m in 26,12 s**, escluso un combattimento giocato normalmente. Il vecchio incontro nel prato non entra in ingaggio. A 1152×648: frame mediano **16,694 ms**, p95 **17,290 ms**; GPU mediana **7,099 ms**, p95 **7,201 ms**. La cattura alla camera normale conferma la differenza di larghezza; la riconoscibilità della destinazione fuori inquadratura resta da valutare giocando, senza affidarsi al testo dei cartelli.
