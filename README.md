# XMLtoTEI

Questo repository comprende tutto il materiale di riferimento per poter lavorare sulla conversione dell’XML dei Klee di Euporia in XML/TEI tramite XSLT.

Nella cartella lib c’è sia il DTD di TEI pronto per essere importato, sia una copia del Saxon con il quale compilare XML e XSLT per ottenere l’XML/TEI.

Per compilare usare questa istruzione:

<pre><b>java -jar</b> ./lib/saxon-he-12.9.jar -s:annoParsed.xml -xsl:parsedToTEI.xsl -o:parsed.xml</pre>

## Posizionamento delle figure

Le trasformazioni standard ed EPUB usano lo stesso algoritmo, basato sulle coordinate ALTO:

1. La colonna di testo è stimata dai blocchi `MainZone` con larghezza almeno pari al 50% del blocco più largo; mediane dei margini riducono l'effetto di annotazioni isolate.
2. Le figure composte da più blocchi ALTO usano il loro bounding box complessivo, così ritaglio e classificazione condividono la stessa geometria.
3. Figure sulla stessa riga devono avere una sovrapposizione verticale di almeno il 50% dell'altezza minore, un'estensione complessiva entro la colonna e nessuna riga di testo interposta.
4. L'analisi della pagina identifica figure a blocco, piccole figure inline e possibili gruppi sulla stessa riga usando sovrapposizione verticale, larghezza della colonna e righe di testo interposte.
5. Nell'edizione web ogni figura viene comunque isolata nel flusso verticale: non usa float né posizionamenti laterali, che potevano far sovrapporre immagini, didascalie e testo. La larghezza relativa ricavata dalla pagina viene mantenuta, centrata e limitata alla colonna; le proporzioni del ritaglio restano invariate.

I valori sono soglie iniziali calibrate sui dati ALTO dell'edizione e possono essere affinati dopo un controllo visivo delle pagine anomale.
Quando una figura è associata a più regioni ALTO distanti, il bounding box può includere contenuto intermedio: queste annotazioni vanno verificate alla fonte.
