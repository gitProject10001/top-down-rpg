# W01.1 — Acqua prescritta, primo esempio

Aprire `scenes/dev/water_study.tscn`, F6. WASD per camminare dalla riva nel
lago e nell'emissario. F visualizza il campo (rosso: componente X, blu: Z);
V attiva/disattiva un vortice locale. Camera, player, viewport e luci provengono
dal rig gameplay condiviso. La reference guida acqua bassa, trasparenza e
increspature; gli effetti magici luminosi non fanno parte di questo incremento.

## Separazione dei sistemi

`addons/water_builder/water_body.gd` è un nodo tool. In Inspector espone
Boundary (XZ locale, 3–32 vertici), Flow Path (massimo 16 punti), Flow Speed,
Basin Depth e vortice. La posizione Y del nodo determina la quota della superficie.
La preview dell'acqua compare nell'editor; il fondale della scena esempio viene
costruito entrando in Play, usando gli stessi dati del perimetro.

La scena usa un unico perimetro che include lago ed emissario. Il percorso guida
un campo vettoriale; la corrente cresce avvicinandosi all'uscita, lungo X locale
in questo esempio. Non è ancora un generatore autonomo di fiumi da spline.

Il fondale dell'esempio è una griglia triangolata con collisione, raccordata alla
riva e profonda circa 40 cm. La superficie non è un pavimento: il giocatore
cammina sul fondale. Mancano ancora nuoto, variazione di velocità e zone proibite.

Il materiale ha colore dipendente dalla distanza dalla riva, trasparenza,
normali animate, linee luminose procedurali e schiuma di bordo. Le linee sono
un'approssimazione artistica delle caustiche sulla superficie, non luce simulata
sul fondale. La profondità è derivata dal perimetro, non dal depth buffer.

## Perché non importare tutta la shallow-water simulation

Esaminato `rpg-3d/addons/sim_water/shaders/swe_sim.gdshader`: evolve altezza,
velocità e schiuma, con accoppiamento, vincoli di passo e correzioni specifiche.
Non viene copiato né eseguito quel solver. Qui il livello resta costante:
nessun trasporto di massa, riempimento, allagamento o instabilità di integrazione.

W01.3a: caustiche cellulari deformate, linee curve interrotte da variazioni locali
di intensità. Sostituito il prodotto periodico di sinusoidi che produceva una
scacchiera. Rimangono un effetto artistico di superficie, da rifinire sul fondale.

Il campo guida due fasi di scorrimento interpolate, evitando deformazioni visive
che crescono senza limite. Il vortice è un campo tangenziale con attenuazione
locale; non risucchia acqua. Le interazioni usano otto onde analitiche a durata
massima di due secondi, ora irregolari e attenuate. W04.1 aggiunge 16 campioni
di scia orientati dalla velocità, schiuma discontinua e perturbazione delle normali.
Gli spruzzi sono 48 piccole mesh in un MultiMesh, riutilizzate; emissione ai lati
del personaggio, traiettoria balistica e durata massima di 0,6 secondi.
Da fermo e sulla terra non vengono emesse scie. Non ci sono ancora riflessioni
contro ostacoli, spostamento di massa o collegamento alle animazioni dei singoli piedi.

## Verifiche e prossimi passi

`tools/check_water_study.gd`: ingresso e uscita reali, collisione fondale,
onde nel lago ma non sulla terra, comandi campo/vortice.
`--capture-water` salva `captures/water_study.png` con il player nel lago.

- W01.2: disegno perimetro e gizmo contestuali, Undo/Redo, errori su incroci;
  fondale e riva aggiornabili anche in editor, senza riscrivere il terreno manuale.
- W01.3: profilo di riva più naturale, fondale visibile con dettaglio, riflessi
  e caustiche meno ripetitive; confronto reference con le luci del gioco.
- W02: spline indipendente, larghezza e quota per tratto, campo continuo nelle
  curve/confluenze, nessuna dipendenza dall'asse X dell'esempio.
- W03: guadi, ponti e raccordi; maschere di ostacolo e riserve per altri builder.
- W04: interazioni locali più ricche, scie e spruzzi, oggetti galleggianti guidati
  dal campo; aggiungere simulazione solo quando un comportamento la richiede.

W01 e W02 restano aperti. Questo esempio dimostra il flusso di rendering e Play,
non completa ancora il builder di laghi e fiumi.
