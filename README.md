# Klee Viewer

Questo repository comprende tutto il sorgente per la visualizzazione dell'edizione digidale del manoscritto di Paul Klee.

## Struttura del repository

* `doc` <br />
Contiene tutta la documentazione del repository: la **struttura adottata del TEI**, il **modello XSLT** e il **contenuto del pacchetto `klee-viewer`**.
* `lib` <br />
Vi sono tutte le **librerie** utili alla trasformazione dall'XML di Euporia in XML TEI (Saxon).
* `references` <br />
Comprende alcuni documenti che possono essere utili ai fini dello sviluppo (un esempio di Pavese e alcuni appunti tratti da un seminario)
* `src` <br />
Tutto il sorgente di conversione da XML del DSL in Euporia. Le sottocartelle principali sono le seguenti:
  * `conversion` <br />
  I file principali di versione: in **`input`** sono inclusi i sorgenti da convertire, in **`output`** il risultato delle conversioni, mentre in **`stylesheet`** i fogli di conversione.
  * `euporia_schemas` <br />
  Alcuni file utili per ricostruire la conversione in XML TEI cercando di capire il tag adatto allo scopo.
