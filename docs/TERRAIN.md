# Terreno: materiale attuale e crescita del mondo

Il terreno del villaggio misura attualmente 100 × 100 metri, collisione inclusa. La mesh piatta ha due triangoli: il dettaglio è nel materiale. Dieci km² equivalgono a un quadrato di circa 3162 × 3162 metri.

## Materiale implementato

`shaders/pixelart/ground_clear.gdshader` legge la posizione XZ in coordinate mondo. La pittura esistente rimane una decorazione locale ruotata di 45 gradi, larga 32 metri; conserva i sentieri nel centro del villaggio. Ai bordi sfuma verso colori procedurali d'erba e terra, eliminando il prolungamento dei pixel della texture oltre il suo rettangolo.

Il fondo usa il dipinto originale come superficie principale. Il noise non sostituisce i pennelli: varia leggermente tono e saturazione a scale diverse, così la grana resta coerente con l'illustrazione. Questo mantiene la qualità del villaggio e lascia il materiale adattabile a superfici più grandi.

Nel materiale del Ground, gli shader parameters controllano `grass_dark`, `grass_light`, `earth_color`, `patch_metres`, `painting_center`, `painting_size` e `border_blend`. Per estendere il mondo non bisogna aumentare `painting_size`: allargherebbe anche il disegno dei sentieri. Il materiale è pensato per terreno prevalentemente orizzontale; pareti ripide richiederanno una proiezione adatta.

`detail_metres` controlla la scala della variazione fine (default 3 metri); `patch_metres` le chiazze (12 metri). Per passare a 400 metri modificare sia `Ground > Mesh > Size` sia `Ground/Collision/Shape > Shape > Size` in X/Z. Non scalare le pennellate. Il terreno rimane piatto e non ha barriere ai bordi.

## Maschera delle strade

Selezionare `Pixel/View/Ground`, aprire `Surface Material Override > 0 > Shader Parameters` e attivare `use_road_mask`. La scena ha già assegnata `terrain_roads.svg`, una curva di esempio nell'area esterna al villaggio. È disattivata per default.

La maschera è dato lineare: nero non modifica il terreno, rosso aggiunge terra battuta, verde pietrisco. Il canale blu è riservato a una futura esclusione vegetazione e al momento non è letto. I toni intermedi sfumano i bordi; il noise li rende leggermente irregolari. La maschera si applica anche sopra il dipinto centrale.

`road_mask_center` è il centro XZ in coordinate mondo; `road_mask_size` l'estensione in metri. L'SVG fornito ha viewBox 0–100: con estensione 100 m, (50,50) corrisponde all'origine, X cresce verso +X, Y verso +Z. Modificare la curva SVG e salvare per aggiornare il percorso. La dimensione della maschera è indipendente dalla scala della texture della strada. Fuori dall'estensione la maschera non ha effetto.

È una superficie colorata: non scava il terreno e non crea ciuffi o collisioni aggiuntive. Un editor di curve Godot e lo scattering sono passi successivi.

## Passi successivi proposti, non ancora implementati

1. Suddividere geometria e collisioni in chunk, caricando quelli attorno al player; scegliere risoluzione e distanza in base a misure di prestazioni.
2. Aggiungere eventualmente curve editabili in Godot che producano la maschera già supportata dal materiale.
3. Distribuire alberi con un seed stabile per chunk, escludendo strade, edifici e pendii. Raggruppare le istanze per zona per consentire il culling.
4. Introdurre distanze di dettaglio per vegetazione, collisioni e ombre. Misurare memoria, tempi di caricamento e frame time prima di popolare tutti i 10 km².

Lo streaming e lo scattering non sono implementati. Verificati import e rendering Forward+ della scena, vista estesa e dettaglio con maschera abilitata. Le catture di controllo sono temporanee sotto `.godot`, non dipendenze del gioco.
