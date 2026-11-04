# Klee Viewer — documentazione

Edizione digitale di Paul Klee, *Beiträge zur bildnerischen Formlehre* (Istituto Italiano di Studi Germanici), su TEI Publisher 10 / Jinks e eXist-db. Edizione diplomatica a sinistra, facsimile a destra; edizioni critica e allineate nello stesso viewer.

> **Stato di questa documentazione.** Le sezioni 1–5 e 7 descrivono file riletti per intero in questa revisione (`parsedToTEI.xsl`, `klee.odd`, `klee.css`, `klee.xml`). La sezione 6 riassume parti del progetto (template Jinks, script, edizioni critica e allineata, pacchetto XAR) di cui non ho riletto il codice in questa sessione: va verificata contro i file reali prima di considerarla definitiva. Le parti da completare sono marcate **[da verificare]**.

## 1. Architettura

```
Euporia (annoParsed.xml) + ALTO (data/<num>.xml)
        │  parsedToTEI.xsl   (vedi parsedToTEI-documentazione.md)
        ▼
   klee.xml  (TEI: text + facsimile con zone e charWidth)
        │  klee.odd  →  compilazione  →  klee-web.xql  (+ CSS generato)
        ▼
 TEI Publisher 10 (pb-view, shadow DOM) + klee.css + template klee2.html
```

| Livello | File | Ruolo |
|---|---|---|
| Dati | `annoParsed.xml`, `data/*.xml` | trascrizione Euporia e geometria ALTO (eScriptorium) |
| Conversione | `parsedToTEI.xsl` | produce il TEI e decide il layout di ogni figura (`@rend`) |
| Rendering | `klee.odd` | modelli per elemento TEI; costruisce le figure come SVG in linea |
| Stile | `klee.css` | classi di layout delle figure, numeri di riga, margini |
| Interfaccia | `klee2.html` (Jinks) | struttura della pagina, toolbar, pannelli **[da verificare]** |

## 2. Struttura del TEI prodotto

- `teiHeader` con `rendition source="klee.css"`; un TEI interno con `facsimile` e `text/body`.
- `facsimile/surface[@xml:id="f<num>"]`: `lrx/lry` = dimensioni dell'immagine in px; `contentUlx`, `contentWidth` = colonna di testo; `charWidth` = px per carattere. Dentro, le `zone` delle figure (`zone_f<num>_fig<N>`), dei paragrafismi (`…_par<N>`) e della musica (`…_music<N>`), con `points` (poligono) e, per i segni in margine, `dy`.
- `body`: `div[@n]` annidati per livello dei titoli, `pb`, `ab`, `l[@n]`, `w`, `pc`, `figure[@facs][@rend]`.
- Il testo e le figure restano collegati da `figure/@facs` → `zone/@xml:id`.

## 3. Figure: dal dato alla pagina

1. **Classificazione** (XSLT): `@rend` ∈ `block`, `inline`, `float-left`, `float-right`, `row-start`, `row-next`, `out-left`, `out-right`, `par-left`, `par-right`, `gap-N`. Regole e soglie: vedi la documentazione dell'XSLT, §5.
2. **Costruzione** (ODD, `elementSpec ident="figure"`, modello `web`):
   - `svg`: SVG con `viewBox` = bounding box della zona, un `clipPath` col poligono della zona e l'immagine della pagina traslata di `(-ulx, -uly)`. Se la zona non è nel documento corrente (edizione critica, traduzioni) la cerca in `klee.xml` nella stessa collezione.
   - `figClass` = `fig-<rend>` (`fig-gap` per `gap-N`).
   - `figStyle`: in em, `k = 0,4 ÷ charWidth`; larghezza = `width:min(Wpx·k em · var(--klee-fig-scale,1), 100%)`; offset sinistro = `max(-2em, (ulx − contentUlx)·k)`. `float-right` calcola il margine destro dal bordo della colonna; `row-next` il margine dalla figura precedente; i segni in margine usano `width` e `top` (0,75 em + `dy`·k); `gap-N` usa `height: N em`. Senza `charWidth` si ricade nel layout in percentuale.
   - modello `epub`: ritaglio con `div` + `img` posizionata, sorgente = `graphic/@url`.
3. **Stile** (`klee.css`):

| Classe | Effetto |
|---|---|
| `.fig-block` | a riga intera, `clear: both` |
| `.fig-float-left/right` | `float`, il testo la avvolge |
| `figure.fig-inline` | `inline-block !important`, `vertical-align: middle`, in fondo alla riga ospite |
| `.fig-row-start/next` | `float: left`, figure affiancate |
| `.fig-par-*`, `.fig-out-*` | `position:absolute` nell'`<l>`, `translateY(-50%)`, oltre la riga verticale e i numeri di riga |
| `.fig-gap` | spaziatore verticale dopo un float |

Variabili CSS regolabili: `--klee-fig-scale` (scala di tutte le figure), `--klee-line-number-clearance` (distanza dei segni a sinistra dai numeri di riga, default 3,4 em), `--klee-rule-distance`, `--klee-rule-thickness`, `--klee-margin-mark-gap`, `--klee-text-right` (impostata da `klee-margin-rules.js` **[da verificare]**).

## 4. Altri elementi dell'ODD (`klee.odd`)

| Elemento | Resa |
|---|---|
| `pb` | epub: immagine della pagina; print: interruzione di pagina; web: `pb-facs-link`; pagina vuota: "[Empty page]" |
| `fw` | testata corrente (`top`), segnatura (`sig`) e richiamo (`catch`); solo in `view=page` |
| `l` | ogni 5ª riga: `<div data-line-n="N">` con numero grigio a margine (`::before`, `left:-3em`); le altre `display:block` |
| `pc` | spaziatura negativa per `@float` left/right/both |
| `add` / `del` / `sic` / `corr` / `hi` | colori e decorazioni per mano a matita (`#999`), cancellatura, sottolineatura; `corr` con fondo verde chiaro |
| `ab` | `type="margin"` upper/lower: colonna di 10 rem nel margine sinistro; altrimenti blocco con margine 1,25 em |
| `label` | `type="margin"` left/right: titoletti a margine (esterno o interno secondo la parità della pagina) |
| `note` | `type="explication"` in corsivo |
| `lb` | a capo, con trattino per `@break="no"` |

## 5. Funzioni dell'interfaccia (dalle note di progetto) **[da verificare]**

- Numeri di pagina pari/dispari in alto (parità calcolata in XSLT, `@rend` su `pb`).
- Linee verticali a margine, con distanza e spessore per pagina, scelta del lato e pagine in cui nasconderle (`klee-margin-rules.js`).
- Toolbar in `klee2.html`: evidenziazione dei paragrafi, numero di pagina corrente, interruttori dei livelli diplomatici (`pb-select-feature`), scambio sic/corr via JS.
- Edizione critica a tre pannelli (originale, critica, facsimile), con modalità visualizzazione e modifica (login e permessi), note critica / editoriale / di commento, comandi personalizzabili.
- Edizione allineata: testo originale e traduzione intercambiabili, facsimile a destra.
- Idea in discussione: menu "Modifica → Posiziona" per correggere a mano posizione di figure e righe, con JS e JSON.

## 6. Distribuzione **[da verificare]**

Pacchetto XAR `klee-viewer` (profili Jinks `base10`, `theme-base10`, `iiif`; palette neutra in `resources/css/palette-klee.css`). ODD in `resources/odd/`, script in `resources/scripts/`, immagini di pagina e ALTO in `resources/images/klee/` (jpg + xml omonimo). `klee-web.xql` è generato dal pulsante "Regenerate ODD" del dashboard: non si modifica a mano.

## 7. Procedura di aggiornamento e verifica

1. Modifica `parsedToTEI.xsl` → rigenera `klee.xml` con la cartella `data/` accanto al foglio di stile (`debug-figures=true()` per leggere le scelte).
2. Carica `klee.xml` nella collezione da cui il viewer apre il documento.
3. Modifica `klee.odd` → ricarica in eXist-db → **Regenerate ODD**. Controlla che non nasca un `*.invalid.xql` accanto al modulo.
4. Modifica `klee.css` → ricarica in `resources/css/` (o dove la carica il template) e svuota la cache del browser.
5. Controllo nel browser: Ispeziona → `figure` (nello shadow DOM) → verifica `class`, `style` e i CSS applicati.

| Sintomo | Probabile causa |
|---|---|
| tutte le figure `block` | `data/` mancante accanto all'XSLT, o TEI vecchio |
| classe giusta, resa sbagliata | CSS non aggiornato o regola sovrascritta dal CSS generato dall'ODD |
| figura `inline` su riga propria | il `<figure>` è dentro un wrapper `div.tei-figure…` a blocco (modello `behaviour="block"` dell'ODD): serve rendere inline il wrapper (`[class*="tei-figure"]:has(> figure.fig-inline)` in `klee.css`) |
| segno in margine sopra il numero di riga | `--klee-line-number-clearance` troppo piccola |
| modifiche all'ODD senza effetto | ODD non rigenerato, o `klee-web.xql` vecchio |

## 8. Problemi aperti

- (risolto il 2026-11-02, vedi registro) Resa di `inline`: nella schermata di p. 15 le frecce (fig2, fig3) compaiono su una riga propria nonostante `rend="inline"`. Il primo tentativo (`figure.fig-inline` con `!important`) non ha cambiato nulla. Nuova ipotesi: il wrapper a blocco `div.tei-figure…` generato dal modello `block` dell'ODD; corretto in `klee.css` rendendo inline il wrapper, da confermare nel browser (non è bastato: vedi la modifica all'ODD del 2026-11-02 (3)).
- Pagina 6: icona del paragrafismo accanto alla riga 10 e allineamento di fig5 da riverificare con i nuovi file.
- Sistemare le altre pagine una alla volta con il debug `[fig-layout]` e l'ALTO della pagina.
- Storico noto: in passato i predicati ODD su attributi (`@attr='value'`) davano risultati incoerenti; per questo la parità di pagina e la posizione dei segni passano da `@rend` e CSS.

## 9. Registro delle modifiche

| Data | Modifica |
|---|---|
| 2026-10-29 | `klee.css`: segni a sinistra oltre i numeri di riga (`--klee-line-number-clearance`); `.fig-gap`. `klee.odd`: classe/altezza `gap-N`. |
| 2026-11-02 | `parsedToTEI.xsl`: segni di una riga tra due testi → `inline`; riga che sfiora la cima del disegno non è clash. `klee.css`: `figure.fig-inline` rinforzato. |
| 2026-11-02 (2) | `klee.css`: wrapper `[class*="tei-figure"]` reso inline quando contiene `figure.fig-inline`. |
| 2026-11-02 (3) | `klee.odd`: modello `web` di `figure` con `behaviour="inline"` (il wrapper diventa `<span>`, non `<div>`): le figure `inline` restano nella riga. Richiede **Regenerate ODD**. La regola CSS sul wrapper è rimasta come rete di sicurezza. |
| 2026-11-02 (4) | `klee.css`: float senza margine inferiore e sollevato di 0,3 em, perché una figura alta circa una riga (schizzo di p. 15) non spinga di lato anche la riga successiva. Confermato nel browser: le figure `inline` ora restano nella riga (modifica all'ODD del 2026-11-02 (3)). |

## 10. Limiti noti della resa rispetto al manoscritto

- **Righe fisiche spezzate in più righe TEI.** Nel manoscritto "zu Linien" e "zu Flächen, dass wir hiezu ana-" stanno sulla stessa riga fisica di "…von Punkten →" e "…von Linien ⇉", ma la trascrizione le codifica come righe separate (`l` 10 e 12). Il viewer le mostra una sotto l'altra: non è un errore di layout delle figure, ma di segmentazione delle righe.
- **Spazio dopo un `ab`.** L'`ab` ha margine inferiore di 1,25 em: dopo l'ultima riga di un `ab` che precede una figura compare uno spazio maggiore (p. 15, tra "Punkten" e "zu Linien").
