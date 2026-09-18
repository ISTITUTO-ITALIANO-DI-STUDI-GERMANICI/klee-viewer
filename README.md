# XMLtoTEI

Questo repository comprende tutto il materiale di riferimento per poter lavorare sulla conversione dell’XML dei Klee di Euporia in XML/TEI tramite XSLT.

Nella cartella lib c’è sia il DTD di TEI pronto per essere importato, sia una copia del Saxon con il quale compilare XML e XSLT per ottenere l’XML/TEI.

Per compilare usare questa istruzione:

<pre><b>java -jar</b> ./lib/saxon-he-12.9.jar -s:annoParsed.xml -xsl:parsedToTEI.xsl -o:parsed.xml</pre>
