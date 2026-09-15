# T01 — Alberi: studio Blender → Godot

## Obiettivo e riferimento

Due asset confrontabili nel gioco: latifoglia con chioma asimmetrica e pino alto,
diradato, con tronco visibile. Questo è un primo studio del nuovo flusso, non
una sostituzione globale della foresta né una dichiarazione di equivalenza alla reference.

Fonte: Trung Duy Nguyen, [video indicato dall'utente](https://www.youtube.com/watch?v=cDWnrVxoWhU)
e [versione scritta dello stesso workflow](https://trungduyng.substack.com/p/speedtree-to-blender-anime-tree-workflow).
YouTube non era direttamente riproducibile dal fetch; lo studio usa il testo
dell'autore e l'ispezione del suo progetto già aperto in Blender.

Il metodo combina struttura ramificata in SpeedTree, foglie trasparenti,
normali trasferite da volumi guida, shader a fasce e AO. Il vento passa a Blender
tramite cache PC2. Sono questi gli elementi da separare nella pipeline.

## Implementazione attuale

- `tools/build_foliage_study.py`: costruzione originale in Blender, nessuna mesh
  o texture del tutorial redistribuita. Crea scene nuove; non salva sul file aperto.
- Tronco e ramificazioni: percorsi espliciti, raggi decrescenti, radici.
  Latifoglia larga e curva; pino più verticale, rami inferiori privi di foglie.
- Ciuffi: quad con maschera procedurale RGBA 512². Foglie larghe e aghi hanno
  maschere differenti; nessuna fotografia incollata sull'intera chioma.
- Normali: campionate analiticamente dagli ellissoidi dei ciuffi, esportate nel GLB.
  È un adattamento del trasferimento di normali, non un modificatore Data Transfer
  live. I `CrownGuide` restano nel sorgente come riferimenti; spostarli da soli
  non rigenera le foglie.
- Colori vertice: R contiene un'approssimazione della cavità del ciuffo; non è
  un bake AO fisico. Il materiale Godot aggiunge ombre reali e AO della scena.
- Shader Blender di preview e shader Godot distinti. La palette Godot risponde
  alle luci attraverso le normali esportate. La preview Blender viene creata
  dopo l'export, perché Shader to RGB non è un materiale glTF portabile.
- Vento Godot: oscillazione lenta e dettaglio veloce sui vertici della chioma;
  non riproduce la simulazione gerarchica/PC2 di SpeedTree. Tronco statico.
- Ogni asset ha una collisione semplice sul tronco, niente collisione per foglia.

## Utilizzo

Aprire `scenes/dev/foliage_study.tscn`, F6; WASD usa il giocatore del progetto.
La camera resta fissa per confrontare silhouette e scala. Trascinare in altre
scene `scenes/props/study_broadleaf.tscn` e `study_pine.tscn`.

Il sorgente è `art_source/foliage_study.blend`. Le due scene contengono geometria,
guide, materiali, sole e camera. I GLB si trovano in `assets/models/foliage_study`.
I JSON adiacenti registrano percorsi e ciuffi: sono un report della costruzione,
non ancora input di un editor. Modificare i parametri nel builder e rieseguirlo
in Blender per rigenerare; un nuovo run scrive nuovamente gli asset di studio.
Per modifiche manuali Blender, conservare una copia e riesportare solo Leaves
e Branches della scena scelta; non esportare le guide.

## Verifica e budget

`tools/check_foliage_study.gd` controlla isolamento dei due export, colori,
normali, materiale runtime, collisione e limite di 12.000 triangoli per albero.
Latifoglia: 7.168 triangoli; pino: 8.360. Due superfici per asset.
`--capture-foliage` sulla scena salva `captures/foliage_study.png` e chiude.
Le prestazioni di una foresta non sono certificate dal frame rate di due alberi:
occorrono test di overdraw, ombre, distanze e LOD.

## Prossimi incrementi

T01.2: confronto artistico alla camera di gioco, tronchi meno angolari, ombre
meno chiuse, distribuzione dei ciuffi meno regolare; approvazione visiva.
T01.3: editor dei percorsi/guide e rebuild locale che preservi interventi manuali.
T01.4: LOD, istanze, distanza ombre, stress test della foresta, visibilità giocatore
e integrazione nel catalogo del world editor. Evitare la sostituzione globale
prima di queste verifiche.
