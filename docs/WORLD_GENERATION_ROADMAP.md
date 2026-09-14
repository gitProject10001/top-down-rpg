# Pipeline dei generatori del mondo

Il concept delle quattro fazioni è un riferimento **di composizione**, non un risultato finale da copiare. Guida densità, masse, percorsi, spazi liberi e rapporti dimensionali. Non impone texture, colori, città identiche al disegno o un terreno scolpito a mano per imitarlo.

## Punto di ripartenza

G01.3b.2b: diagnostica degli ingombri e verifica della rigenerazione nell'editor/Play. Sono disponibili edifici parametrici, torri/cortine, corte singola generata, editing protetto delle posizioni e validazione degli accessori. Non sono ancora disponibili la varietà delle città del concept o una generazione completa di paesaggio roccioso/idrologia/grotte.

Il mondo attuale usa rilievo procedurale ed editing del terreno (da vincolare alla nuova direzione a quote discrete); le rocce distribuite dal WorldStream sono piccole SphereMesh sfaccettate. Non costituiscono un generatore di affioramenti stratificati, pareti o montagne.


## Vincolo di terreno e leggibilità — aggiornamento utente

**Terreno prevalentemente piatto, altezze discrete.** Niente colline continue o città interamente in pendenza. Gli insediamenti occupano un piano principale o poche terrazze orizzontali. I cambi di quota usano rampe brevi, chiaramente leggibili, con raccordi localizzati. Il contrasto fra piani si legge tramite bordo/scarpata/parete, non con una pendenza lieve estesa.

Le montagne del concept si traducono soprattutto in masse e pareti rocciose ai bordi dello spazio giocabile, o separazioni fra piattaforme; non in un heightfield collinare percorribile ovunque. Una città può sorgere **accanto** a una parete rocciosa, con strade e case in piano. Aree di combattimento, piazze e accessi principali restano orizzontali. Verificare ogni salto di quota con la camera fissa prima di aumentarne il numero.

Il modello futuro del terreno deve esporre piattaforme con ID, quota e perimetro e collegamenti tramite rampa/scala; i generatori leggono questi dati. Non introdurre rumore altimetrico continuo nel layout giocabile come impostazione predefinita. Anche laghi e fiumi vanno progettati su questi piani: bacini a quota definita, tratti fluviali leggibili e raccordi fra quote localizzati. Dettaglio irregolare consentito sulle superfici rocciose, non come ondulazione generalizzata dei percorsi.

## Separazione dei sistemi

Richiesta e seed → piano modificabile → validazione → realizzazione geometrica → scena editabile. Riutilizzare questo contratto, non un unico algoritmo universale.

- Terreno espone quota, pendenza, superfici e zone riservate.
- Rocce espongono ingombri solidi, pareti e varchi; nessuna conoscenza delle stanze.
- Acqua espone rive, profondità, direzione e attraversamenti.
- Insediamento legge queste informazioni e produce strade, piazze e richieste di edifici.
- Edifici producono volumi, aperture, interni e punti di accesso.
- Grotte collegano un ingresso nel rilievo a un proprio piano interno.

Ogni elemento generato necessita ID stabile, seed locale, override e lock. Gizmo solo dello strumento/elemento attivo. Rigenerare una roccia non deve ricalcolare le case; migliorare le stanze non deve riscrivere l'insediamento.

## Incrementi e criteri di uscita

| ID | Stato | Passo | Risultato verificabile |
|---|---|---|---|
| G01.3b.2b | FATTO | Diagnostica ingombri e verifica editor/Play | Proposta comprensibile, Undo/Redo reali, passaggi percorribili |
| R01 | TODO — prossimo prototipo ambientale | Generatore di singola roccia/affioramento | Seed, dimensioni, piani di frattura, stratificazione, spigolosità; 6 varianti con stesso linguaggio geometrico; collisione semplice |
| R02 | TODO | Composizione di gruppi rocciosi | Path/area, direzione dominante degli strati, masse grandi/medie/piccole; variazione locale senza distruggere i pezzi spostati a mano |
| R03 | TODO | Pareti e creste montuose | Pareti fra piattaforme piane, quote discrete, rampe brevi e passaggi riservati, assenza di compenetrazioni macroscopiche; LOD e budget misurati |
| W01 | TODO | Laghi editabili | Perimetro e quota dell'acqua, riva e bacino, esclusione edifici; superficie d'acqua inizialmente semplice |
| W02 | TODO | Fiumi editabili | Spline, larghezza/profondità, profilo discendente e confluenze; raccordo alle quote dei laghi; niente flussi in salita |
| W03 | TODO | Attraversamenti e rive | Ponti, guadi, approdi, passaggi e accessi alle sponde; terreno/rocce/strade leggono gli stessi vincoli |
| C01 | TODO | Ingressi di grotta | Apertura reale nel blocco roccioso, soglia percorribile, collisione coerente e leggibilità alla camera fissa |
| C02 | TODO | Piano di grotta | Stanze/cunicoli con anelli e diramazioni, quote e collegamenti; editing manuale separato dall'involucro esterno |
| G01.4 | TODO | Catalogo architettonico | Ruoli del piano associati a profili/componenti; famiglie sostituibili senza cambiare il planner |
| G01.5 | TODO | Varietà compositiva del castello | Recinti segmentati, più torri/corpi, corti e gerarchie differenti; preservazione manuale |
| S01 | TODO | Composizione urbana organica | Strade principali e secondarie, piazze, porte, edifici gerarchizzati, addensamenti e vuoti; insediamenti su piani/terrazze, collegamenti ai vincoli del paesaggio |
| S02 | TODO | Edifici urbani più articolati | Volumi aggregati, tetti collegati, facciate e accessori; le città cambiano forma oltre al colore |
| V01 | TODO | Confronto dei quattro castelli | Quattro richieste/seed tramite tool, scene editabili e stessa camera; almeno due organizzazioni strutturali distinte |
| V02 | TODO | Vertical slice città–villaggio–POI | Tempi reali di cammino, incontri, visibilità e streaming; aggiornamento delle distanze proposte dal concept |

## Come ottenere le rocce del concept

La qualità nasce dalle forme: volumi principali spigolosi, tagli orientati, strati con una direzione comune, sporgenze e fessure fra masse. Un seed può variare fratture, proporzioni e inclinazioni entro una famiglia; rumore uniforme su una sfera produce soprattutto un masso irregolare. R01 costruirà una grammatica geometrica piccola e controllabile; R02 la userà per comporre affioramenti senza ripetizioni evidenti. Il materiale attuale resta il riferimento del gioco: niente rincorsa al rendering del concept.

## Cosa manca alla città

La città illustrata mescola una fortezza dominante, edifici subordinati, corti, vie irregolari ma connesse e una relazione con il pendio. Oggi il generatore ha soprattutto una corte singola e due corpi interni: mancano catalogo dei ruoli, aggregazione urbana, sagome/recinti differenti e collocazione su superfici piane e terrazze. Per questo non dichiariamo pronta la varietà delle quattro città e non la sostituiamo con quattro recolor.

## Ordine pratico

Verifica G01.3b.2b completata; prossimo R01 come prototipo ambientale circoscritto. Alternare G01.4–G01.5 e R02–R03 senza fondere i due sistemi. W01 precede W02, e l'idrologia stabile precede i ponti e il posizionamento definitivo delle città. C01 precede la generazione degli interni delle grotte. V01 resta una consegna esplicita richiesta dall'utente.
