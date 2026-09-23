# Studio del file RocksLowPoly.blend

Ispezione diretta tramite Blender MCP, senza modificare la scena o il file. File aperto: `C:/Users/jonny/Downloads/RocksLowPoly.blend`; Blender dichiara 5.2.0 LTS. Video indicato dall’utente: https://www.youtube.com/watch?v=n1_NMIV7A5U — “Easy Geometry Nodes - Low-poly Rocks Blender 5.1”, ALL THE WORKS (titolo/autore verificati tramite oEmbed; video non visionato integralmente).

## Principio verificato

**Forma di controllo → distribuzione sulla superficie → rocce sorgente orientate → eventuale fusione.** La forma principale esiste prima della distribuzione. Non è prodotta da una griglia di scatole, da file equidistanti, o da corsi di blocchi sovrapposti.

### A: affioramenti blu, RockDistributeA

- Mesh di controllo: 32 vertici in tre componenti con 8, 8 e 16 vertici. Le componenti sono già forme inclinate/affusolate; la silhouette non viene inventata dal nodo di distribuzione.
- Collection `RockCorner`: tre mesh distinte, 52/56/56 vertici; facce poligonali irregolari, non cubi semplicemente smussati.
- Distribute Points on Faces: **POISSON**, distanza minima 0,1; Density Factor 0,6; Density Max effettiva 4,0. Seed distribuzione 26.
- Collection Info separa e ripristina le trasformazioni dei figli. Instance on Points usa Pick Instance.
- Allineamento dell’asse locale X alla normale della superficie. Rotazione casuale attorno allo Z locale successiva all’allineamento: intervallo 0…46,2 radianti nel grafo (non gradi). Seed rotazione 10.
- Scala uniforme casuale tra Scale e Scale+0,5: attualmente 1…1,5, seed 5. Seconda variazione locale vettoriale tra (1,1,1) e (1,2;1,2;2).
- Join Geometry conserva anche la mesh di controllo; Realize Instances rende la composizione una geometria esplicita.
- Modificatori attivi dopo i nodi: **Voxel Remesh**, voxel 0,03 e adaptivity 0,05; poi **Decimate ratio 0,05**; Auto Smooth; UVUnwrapAuto.
- Risultato valutato al momento dell’ispezione: 8716 vertici, 16861 poligoni. Questo conteggio riguarda l’oggetto completo, non una singola roccia.

La continuità di questo esempio dipende anche dal remesh. Riprodurre solo lo scatter non basta a riprodurne le saldature e le cavità.

### B: bordo roccioso su volume, RockDistributeB

- Mesh di controllo: una componente di 38 vertici, con pareti curve e superficie inclinata.
- Collection `RockRec`: sei mesh, circa 80–81 vertici ciascuna.
- Distribuzione Poisson, distanza minima 0, Density Factor 1, Density Max 8,5, seed 6. La modalità si chiama Poisson, ma con distanza minima zero non impone una separazione positiva.
- Selezione delle facce tramite confronto della componente Z della normale con 0,3, tolleranza 0,55: privilegia un intervallo di orientamenti, invece di ricoprire indiscriminatamente sopra e sotto.
- Allineamento asse Y alla normale; piccole rotazioni locali casuali: X/Y ±0,15, Z ±0,5 radianti.
- Scala locale tra (0,9;0,9;0,7) e (1,1;1,1;1,3), seed 10. Traslazione locale Y casuale da -0,1 a +0,7.
- La mesh di controllo viene conservata insieme alle rocce. Remesh e Decimate sono presenti **ma disabilitati in viewport**. Risultato attuale: 25047 vertici, 25607 poligoni.

Questo esempio dimostra che una forma di controllo adatta e uno scatter orientato possono già funzionare senza fusione volumetrica.

### C: percorsi, RockDistributrCurve

- Dieci spline Bézier, da 2 a 5 punti ciascuna; raggi dei punti attualmente tutti pari a 1.
- Resample Curve: modo Length, passo 0,5.
- Curve Circle: risoluzione 4, raggio 1. Curve to Mesh: scala 0,5, senza tappi. La curva genera quindi una **superficie tubolare**, non una fila di posizioni centrali.
- Poisson sulla superficie: distanza 0,1, Density Factor 0,6, Density Max effettiva 4,41, seed 114.
- Collection RockCorner. Scala uniforme 0,5…1,0, seed 27; ulteriore scala locale con massimo (1,5;1,5;2,2).
- Realize Instances e materiale StoneSnow; UVUnwrapAuto2. Nessun remesh attivo. Risultato attuale: 23164 vertici, 13832 poligoni.
- **Particolarità da non copiare ciecamente:** Curve Tangent viene catturata, ma finisce nell’ingresso Rotation di Align Rotation to Vector; il Vector del nodo è fisso (0,0,1), asse Z. Non è corretto descrivere questo collegamento come un allineamento standard della roccia alla tangente. In Godot serve definire e verificare un riferimento locale coerente usando tangente e normale.

## Parametri: default e valori reali

Sono stati letti sia i default dell’interfaccia sia gli override effettivi. Differiscono: ad esempio Density Max A è 4 e non il default 3; Scale C è 0,5 e non 0,8; Randomize C è 114 e non 2. In questa versione di Blender gli override sono esposti da `modifier.properties.inputs.<socket>.value`, non dai vecchi IDProperties. I numeri riportati sopra sono quelli reali ove collegati al modificatore.

## Trasposizione sensata in Godot

1. Conservare un involucro principale modificabile: cresta, base, spalle, inclinazione, profilo verticale. Deve avere già una silhouette riconoscibile quando il dettaglio è spento.
2. I percorsi devono produrre una superficie con sezione variabile e quota, e i volumi una superficie di controllo. Un rettangolo estruso non basta come forma predefinita di ogni affioramento.
3. Campionare triangoli in proporzione all’area; applicare distanza minima e maschere di orientamento. Distribuire sulle pareti e sulle spalle, non solo sul piano XZ e non in righe/colonne.
4. Usare poche forme sorgente curate con grandi fratture, spalle e tagli irregolari. Orientarle sulla superficie e limitarne le variazioni di scala/rotazione; non adattare ogni pezzo alla larghezza di una cella.
5. Separare dimensioni della forma di controllo e dimensioni delle rocce. Allargare o alzare l’involucro deve ricampionare la superficie, mantenendo una taglia sensata dei pezzi. La scala oggetto Blender è comunque una trasformazione del risultato: non è una funzione magica che impedisce lo stiramento. Va distinta dall’editing della mesh/curva di controllo.
6. Affrontare la fusione solo dove serve il risultato A. Valutare una fusione locale volumetrica e semplificazione dopo una prova di costo; non promettere la stessa resa con soli oggetti sovrapposti, né remesh completo a ogni movimento del mouse.
7. Validare prima tre forme di controllo (cresta inclinata, volume con spalla, curva con sezione variabile), poi confrontarle con e senza dettaglio e a scala non uniforme. I test di collisione e determinismo non sostituiscono questo confronto visivo.

## Stato dei tentativi precedenti

Le griglie, i corsi verticali e la successiva suddivisione a lastre non sono trasposizioni di questi nodi. La suddivisione a lastre resta uno studio separato per ponti rocciosi, su indicazione esplicita dell’utente. Questo studio non certifica l’implementazione attuale né promette equivalenza visiva con Blender.
