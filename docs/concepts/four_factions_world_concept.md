# Concept del mondo — quattro fazioni

Proposta visiva, non modifica la scena né i generatori. I nomi delle fazioni sono provvisori.

Base: export dall'alto del mondo attuale, circa 1732 × 1732 m. Velocità di riferimento: `scripts/player.gd`, move_speed = 6 m/s; la scena principale non mostra un override esplicito di questa proprietà. Tempi teorici senza combattimento, ostacoli o pause.

- Quattro piccole città fortificate, diametro indicativo 150–210 m, con forme architettoniche differenti.
- Sei villaggi, 40–70 m, distribuiti lungo i collegamenti.
- Anello stradale tra città e due connessioni trasversali, più deviazioni brevi e percorsi alternativi.
- Circa dodici punti d'interesse. Obiettivo di cadenza lungo le vie principali: 150–250 m, cioè 25–42 s di corsa libera; percorsi città-città indicativamente 720–1440 m, cioè 2–4 minuti.
- Rilievi a nordovest/nord e a est, due laghi, drenaggio verso sud. Tre ponti e un guado creano passaggi significativi.
- Conservare il crocevia e il piccolo rudere/campo centrale della mappa esportata.

| Centro provvisorio | Posizione approssimativa | Carattere architettonico |
|---|---|---|
| Roccaferro | Nordovest | Cittadella in pietra, cava e passo |
| Valfronda | Nordest | Sale lignee, palizzate, terrazze forestali |
| Rivachiara | Sudovest | Borgo commerciale, mulini e approdo |
| Cenerossa | Sudest | Torri, pietra scura e corti delle fucine |

La scala e i tempi sono vincoli di progettazione proposti. Il bitmap generato non è una planimetria metrica certificata: posizioni, ingombri, idrologia e percorrenze devono essere ricostruiti e verificati nel builder prima dell'implementazione. La mappa precisa rimane l'export originale. La proposta non implica che montagna, acqua e quattro famiglie architettoniche siano già supportate dal generatore.

Generazione: strumento image_gen integrato; riferimento `captures/balcony_attachment/design_map_world_reference.png` derivato dall'export 8K senza modifiche semantiche.

## Prompt utilizzato

undefined



## Risultato v1

Immagine: `four_factions_world_v1.png`. Generata con image_gen integrato al secondo tentativo, dopo un errore di rete. Verifica visiva: quattro centri etichettati, il rudere centrale riconoscibile, rilievi nordoccidentali/orientali, sistema fluviale e percorsi con ponti. L’immagine è illustrativa con edifici e rilievi leggermente inclinati: la barra metrica è indicativa, non certifica misure pixel-per-metro. La differenziazione architettonica tra le città fortificate è ancora parziale.
