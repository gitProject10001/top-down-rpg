# House Builder: interni modificabili

Checkpoint iniziale: `e0a6b08`. GI e lightmap sono rimandati.

## Passaggio 1: dati dell'editor

Seleziona una casa e premi **Interni: crea / mostra**. `InteriorPlan` contiene
piani persistenti e nodi per stanze, muri, scale e oggetti. Aggiungi elementi
dal pannello, spostali/ruotali con W/E e ridimensionali con le maniglie azzurre.
L'Inspector espone dimensioni, porta del muro, scena dell'oggetto e blocco manuale.
Puoi anche trascinare una tua scena direttamente sotto un piano.

`_Visual` e `_Floors` sono cache interne rigenerabili: modifica i nodi dati,
non queste mesh. Salvataggio e undo delle operazioni del pannello conservano
gli elementi dell'utente. **Play casa selezionata** prepara una copia temporanea
in `user://house_builder_playtest.tscn` e avvia gli stessi dati nel banco di prova.
La scena sorgente non viene modificata dal gameplay.

## Passaggio 2: planimetria iniziale

**Genera stanze (piano attivo)** usa `seed_value` e `requested_rooms` del piano.
Il metodo riserva un ingresso longitudinale, suddivide i rettangoli residui,
costruisce il grafo delle adiacenze e apre un insieme di porte che collega le stanze.
Per case a L viene aggiunta la stanza nell'ala. I piani multipli riservano una
scala con corridoio laterale e un foro nel solaio; gli accessi delle stanze evitano
l'ingombro della scala. Per questa configurazione automatica servono almeno
6 m di larghezza e circa 6 m di profondità; altrimenti il comando spiega il limite
e mantiene la planimetria precedente. Si possono comunque disegnare soluzioni manuali.

La geometria viene verificata prima di applicarla: stanze troppo strette,
sovrapposizioni e stanze scollegate impediscono la sostituzione. Seed uguale e
parametri uguali producono lo stesso risultato. Undo ripristina la proposta precedente.

## Passaggio 3: modifiche protette

**Rigenera muri dalle stanze** aggiorna le partizioni dopo aver modificato le stanze.
Il blocco esplicito, gli elementi aggiunti a mano e le proprietà cambiate rispetto
alla generazione precedente vengono conservati. **Blocca / sblocca elemento**
permette anche di accettare una modifica come nuova base per la rigenerazione.
Gli oggetti cancellati non ricompaiono alla rigenerazione; undo della cancellazione
li ripristina. Le scene personali sotto il piano restano intatte.

Prima della sostituzione viene controllata la percorribilità su una griglia di
18 cm, con 31 cm di margine per il giocatore: una proposta che isola una stanza
viene scartata interamente, con messaggio nel pannello. È una verifica della
planimetria con porte aperte, non una simulazione completa del movimento.

## Passaggio 4: arredo opzionale

In preparazione: kit riutilizzabile e spazi di accesso liberi.
