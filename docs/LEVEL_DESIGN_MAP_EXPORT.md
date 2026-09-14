# Esportazione PNG per il level design

Nell'editor, con una scena aperta: **Progetto → Strumenti → Esporta mappa PNG · dall'alto** oppure **Esporta mappa PNG · isometrica**. Scegli dove salvare il PNG.

Il comando acquisisce la scena aperta con le proprietà non ancora salvate. Non salva né sposta la scena originale: prepara un'istanza temporanea in memoria, senza creare un'altra scena da gestire. Supporta scene 3D normali e la struttura Pixel/View della scena principale. Camera di esportazione ortografica: dall'alto oppure inclinazione 55°, azimut 45°. Inquadra tutta la geometria visibile, incluso il terreno.

Output principale **8192 × 8192**, renderizzato con tasselli da 2048 e margine di 32 pixel per lato, assemblati direttamente in Godot. Affianca un JSON con inquadratura, limiti e seed del world stream, più una preview leggera da 1024 pixel. Il PNG pieno può superare 100 MB; non è un ingrandimento della preview.

Il WorldStream attuale viene ricostruito interamente (784 celle) nella copia. Questa versione riduce la dimensione del render target usando tasselli, ma mantiene il mondo in memoria: il caricamento/scaricamento selettivo per tassello è un'estensione futura per mondi maggiori. Il giocatore e HUD sono nascosti; non include gizmo dell'editor. Gli altri elementi visibili della scena restano inclusi.

Per panoramiche oltre 500 m di diagonale, le ombre direzionali sono disattivate nella copia: evita artefatti delle shadow map a questa scala. Lo sfondo è uniforme per evitare ripetizioni del cielo fra tasselli. Materiali e luci restano quelli della scena; non applica il post-process full-screen della camera di gameplay. Effetti dipendenti dallo schermo possono differire ai bordi dei tasselli nonostante il margine.

Verifica GPU: tools/check_map_export.gd esporta castello dall'alto/isometrico; con --world --high esporta il mondo a 8192; aggiungere --iso per la vista isometrica. Verificati inquadratura e completamento delle celle. Gli output di prova sono in captures/balcony_attachment/design_map_*.png.

Side quest indipendente da G01: la pipeline del compositore rimane invariata.
