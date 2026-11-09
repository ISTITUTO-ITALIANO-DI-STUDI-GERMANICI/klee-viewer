<xsl:stylesheet
  xmlns="http://www.tei-c.org/ns/1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:alto="http://www.loc.gov/standards/alto/ns-v4#"
  xmlns:xs="http://www.w3.org/2001/XMLSchema"
  xmlns:kf="http://klee-viewer/functions"
  xmlns:tei="http://www.tei-c.org/ns/1.0"
  version="2.0"
  xpath-default-namespace="http://himeros.eu/euporia"
  exclude-result-prefixes="alto kf tei">

  <xsl:output method="xml" encoding="UTF-8" indent="yes" omit-xml-declaration="no" />

  <xsl:strip-space elements="*"/>
  <xsl:param name="lang" select="'und'"/>
  <!-- Set to true() to print, for every figure, the layout chosen and the rule that chose it
       (xsl:message), e.g.  figure #5 of 83049: block (coverage 0.18 < 0.4) -->

  <!-- Identity of the critical <text> (further <text> elements will get their own values) -->
  <xsl:param name="critical-id" select="'klee_crit'"/>
  <xsl:param name="critical-type" select="'critical'"/>
  <xsl:param name="critical-lang" select="'de'"/>
 
  <xsl:param name="debug-figures" select="false()"/>

  <xsl:key name="fig-by-id"
    match="apparatoFigureItem"
    use="normalize-space(replace(figId, '\s+', ''))"/>

  <!-- Glue a trailing word-break hyphen to the preceding word ("Längs -" -> "Längs-").
       Only a plain hyphen-minus preceded by a letter is touched, so numeric ranges
       such as "143 - 146" stay as they are. -->
  <xsl:function name="kf:glue-hyphen" as="xs:string">
    <xsl:param name="s" as="xs:string"/>
    <xsl:sequence select="replace($s, '(\p{L})[\s&#160;]+-$', '$1-')"/>
  </xsl:function>

  <!-- A line that holds nothing but one bracket (figures anchored on it are ignored). -->
  <xsl:function name="kf:lone-bracket" as="xs:boolean">
    <xsl:param name="l" as="element(tei:l)"/>
    <xsl:param name="type" as="xs:string"/>
    <xsl:sequence select="
      count($l/tei:pc) eq 1
      and $l/tei:pc/@type = $type
      and empty($l/*[not(self::tei:pc or self::tei:figure)])
      and not(normalize-space(string-join($l/text(), '')))"/>
  </xsl:function>

  <!-- Lone opening-bracket lines, indexed by the next <l> in document order. -->
  <xsl:key name="lone-open"
    match="tei:l[kf:lone-bracket(., 'bracketOpen')]"
    use="generate-id(following::tei:l[1])"/>

  <!-- the lone-bracket line itself is dropped (its n is simply skipped) -->
  <xsl:template match="tei:l[kf:lone-bracket(., 'bracketOpen')][following::tei:l]"
                mode="glue-bracket"/>

  <!-- the next line receives the bracket, after any leading margin figures -->
  <xsl:template match="tei:l[key('lone-open', generate-id(.), root(.))]"
                mode="glue-bracket" priority="2">
    <xsl:variable name="open" select="key('lone-open', generate-id(.), root(.))[1]"/>
    <xsl:variable name="lead"
      select="tei:figure[not(preceding-sibling::*[not(self::tei:figure)])]"/>
    <xsl:copy>
      <xsl:copy-of select="@*"/>
      <xsl:copy-of select="$open/tei:figure"/>
      <xsl:copy-of select="$lead"/>
      <xsl:copy-of select="$open/tei:pc"/>
      <xsl:apply-templates select="node()[not(. intersect $lead)]" mode="glue-bracket"/>
    </xsl:copy>
  </xsl:template>

  <!-- Printed page number of a source <page>: first <num> of numbZone,
       otherwise the first purely numeric <seg> -->
  <xsl:function name="kf:page-number" as="xs:string">
    <xsl:param name="page" as="element()"/>
    <xsl:sequence select="normalize-space(
        if ($page/numbZone//num) then $page/numbZone//num[1]
        else $page/numbZone//seg[matches(normalize-space(.), '^\d+$')][1])"/>
  </xsl:function>

  <!-- ALTO document of a source <page>; empty sequence if the file is not available -->
  <xsl:function name="kf:alto" as="document-node()?">
    <xsl:param name="page" as="element()"/>
    <xsl:variable name="path"
      select="concat('data/', normalize-space($page/facsimile/num), '.xml')"/>
    <xsl:sequence select="if (doc-available($path)) then document($path) else ()"/>
  </xsl:function>

  <!-- Side of the page a margin text sits on. Outer margin: left on even pages,
       right on odd pages; the inner margin is the opposite. -->
  <xsl:function name="kf:margin-place" as="xs:string">
    <xsl:param name="pageNum" as="xs:integer"/>
    <xsl:param name="inner" as="xs:boolean"/>
    <xsl:sequence select="if (($pageNum mod 2 = 0) != $inner) then 'left' else 'right'"/>
  </xsl:function>

  <!-- Median of a numeric sequence: used to derive a per-page "content frame"
       (typical left/right edge of the main text column) that is robust to a
       single outlier block (e.g. a label/annotation reaching the page edge),
       unlike a plain min/max bounding box. -->
  <xsl:function name="kf:median" as="xs:double">
    <xsl:param name="values" as="xs:double*"/>
    <xsl:variable name="sorted" as="xs:double*">
      <xsl:perform-sort select="$values">
        <xsl:sort select="."/>
      </xsl:perform-sort>
    </xsl:variable>
    <xsl:variable name="n" select="count($sorted)"/>
    <xsl:choose>
      <xsl:when test="$n eq 0">
        <xsl:sequence select="0"/>
      </xsl:when>
      <xsl:when test="$n mod 2 eq 1">
        <xsl:sequence select="$sorted[($n + 1) idiv 2]"/>
      </xsl:when>
      <xsl:otherwise>
        <xsl:sequence select="($sorted[$n idiv 2] + $sorted[$n idiv 2 + 1]) div 2"/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:function>

  <!-- MainZone blocks belonging to the actual text column, filtering out
       short annotation-like blocks (e.g. a lone "do" ditto mark) that are
       much narrower than the page's real column. -->
  <xsl:function name="kf:column-blocks" as="element(alto:TextBlock)*">
    <xsl:param name="altoDoc"/>
    <xsl:variable name="mainZoneTagIds" select="$altoDoc//alto:OtherTag[@LABEL = 'MainZone']/@ID"/>
    <xsl:variable name="blocks"
      select="$altoDoc//alto:TextBlock[tokenize(normalize-space(@TAGREFS), '\s+') = $mainZoneTagIds]"/>
    <xsl:variable name="widths" select="for $b in $blocks return xs:double($b/@WIDTH)"/>
    <xsl:variable name="maxW" select="if (exists($widths)) then max($widths) else 0"/>
    <xsl:sequence select="$blocks[xs:double(@WIDTH) ge 0.5 * $maxW]"/>
  </xsl:function>

  <xsl:function name="kf:content-ulx" as="xs:double">
    <xsl:param name="altoDoc"/>
    <xsl:variable name="lefts" select="for $b in kf:column-blocks($altoDoc) return xs:double($b/@HPOS)"/>
    <!-- min, not median: blocks wrapped around a float start further right and
         can outnumber the full-width ones -->
    <xsl:sequence select="if (exists($lefts)) then min($lefts) else 0"/>
  </xsl:function>

  <xsl:function name="kf:content-width" as="xs:double">
    <xsl:param name="altoDoc"/>
    <xsl:variable name="blocks" select="kf:column-blocks($altoDoc)"/>
    <xsl:variable name="lefts" select="for $b in $blocks return xs:double($b/@HPOS)"/>
    <xsl:variable name="rights" select="for $b in $blocks return xs:double($b/@HPOS) + xs:double($b/@WIDTH)"/>
    <xsl:variable name="ulx" select="if (exists($lefts)) then min($lefts) else 0"/>
    <xsl:variable name="right" select="if (exists($rights)) then kf:median($rights) else xs:double($altoDoc//alto:Page/@WIDTH)"/>
    <xsl:sequence select="$right - $ulx"/>
  </xsl:function>

  <!-- Median TextLine height within the text column, used as the "typical
       line" scale to classify small vs. tall figures (hRatio). -->
  <xsl:function name="kf:median-line-height" as="xs:double">
    <xsl:param name="altoDoc"/>
    <xsl:variable name="heights" select="for $l in kf:column-blocks($altoDoc)//alto:TextLine return xs:double($l/@HEIGHT)"/>
    <xsl:sequence select="if (exists($heights)) then kf:median($heights) else 0"/>
  </xsl:function>

  <!-- Typical width in ALTO px of one character of the transcribed text
       (median of line width / characters over the column lines of >= 12 chars).
       Figures are sized in units of this, so they keep the manuscript's
       proportion to the letters. 0 when the page has too few lines. -->
  <xsl:function name="kf:char-width" as="xs:double">
    <xsl:param name="altoDoc"/>
    <xsl:variable name="ratios" select="
      for $l in kf:column-blocks($altoDoc)//alto:TextLine,
        $len in string-length(normalize-space(string-join($l/alto:String/@CONTENT, ' ')))
      return if ($len ge 12) then xs:double($l/@WIDTH) div $len else ()"/>
    <xsl:sequence select="if (count($ratios) ge 3) then kf:median($ratios) else 0"/>
  </xsl:function>

  <!-- Horizontal extent (min, max) of a polygon (flat x1,y1,x2,y2,... sequence)
       inside the band y0..y1; empty if the polygon does not reach the band. -->
  <xsl:function name="kf:poly-x-range" as="xs:double*">
    <xsl:param name="poly" as="xs:double*"/>
    <xsl:param name="y0" as="xs:double"/>
    <xsl:param name="y1" as="xs:double"/>
    <xsl:variable name="n" select="count($poly) idiv 2"/>
    <xsl:variable name="xs" as="xs:double*" select="
      for $i in 1 to $n,
        $j in (if ($i eq $n) then 1 else $i + 1),
        $xa in $poly[2 * $i - 1], $ya in $poly[2 * $i],
        $xb in $poly[2 * $j - 1], $yb in $poly[2 * $j],
        $lo in min(($ya, $yb)), $hi in max(($ya, $yb))
      return
        if ($hi lt $y0 or $lo gt $y1) then ()
        else if ($ya eq $yb) then ($xa, $xb)
        else for $y in (max(($lo, $y0)), min(($hi, $y1)))
          return $xa + ($y - $ya) div ($yb - $ya) * ($xb - $xa)"/>
    <xsl:sequence select="if (exists($xs)) then (min($xs), max($xs)) else ()"/>
  </xsl:function>

  <!-- Outline of figure #ordinal as flat x,y pairs: the ALTO polygon when the zone is
       a single block, otherwise its bounding rectangle (same rule as alto-zone). -->
  <xsl:function name="kf:fig-poly" as="xs:double*">
    <xsl:param name="altoDoc"/>
    <xsl:param name="ordinal" as="xs:integer"/>
    <xsl:variable name="tagIds"
      select="$altoDoc//alto:OtherTag[@LABEL = concat('GraphicZone:figure#', $ordinal)]/@ID"/>
    <xsl:variable name="blocks"
      select="$altoDoc//alto:TextBlock[tokenize(normalize-space(@TAGREFS), '\s+') = $tagIds]"/>
    <xsl:variable name="b" select="kf:fig-box($altoDoc, $ordinal)"/>
    <xsl:choose>
      <xsl:when test="count($blocks) eq 1 and $blocks/alto:Shape/alto:Polygon/@POINTS">
        <xsl:sequence select="for $t in tokenize(normalize-space($blocks/alto:Shape/alto:Polygon/@POINTS), '\s+') return xs:double($t)"/>
      </xsl:when>
      <xsl:when test="exists($b)">
        <xsl:sequence select="($b[1], $b[2], $b[3], $b[2], $b[3], $b[4], $b[1], $b[4])"/>
      </xsl:when>
    </xsl:choose>
  </xsl:function>

  <!-- Side of a text line relative to a figure outline, within the band they share:
       'none' (not beside it), 'left', 'right', or 'clash' (the text overlaps the drawing).
       The outline is used, not its bounding box, so text tucked into a notch of the
       zone counts as beside it. $tol (about one letter) absorbs sloppy line boxes. -->
  <xsl:function name="kf:line-side" as="xs:string">
    <xsl:param name="line" as="element(alto:TextLine)"/>
    <xsl:param name="poly" as="xs:double*"/>
    <xsl:param name="fy0" as="xs:double"/>
    <xsl:param name="fy1" as="xs:double"/>
    <xsl:param name="tol" as="xs:double"/>
    <xsl:variable name="ly0" select="xs:double($line/@VPOS)"/>
    <xsl:variable name="lh" select="xs:double($line/@HEIGHT)"/>
    <xsl:variable name="b0" select="max(($ly0, $fy0))"/>
    <xsl:variable name="b1" select="min(($ly0 + $lh, $fy1))"/>
    <!-- The outline is probed on the core of the shared band only (15% trimmed at both ends):
         a line box that merely grazes a corner or a step of the outline by a few pixels
         (p. 17: "in einem rechten Winkel)" vs. the step of fig 11) is not a clash. -->
    <xsl:variable name="trim" select="0.15 * ($b1 - $b0)"/>
    <xsl:variable name="xr" select="kf:poly-x-range($poly, $b0 + $trim, $b1 - $trim)"/>
    <xsl:variable name="lx0" select="xs:double($line/@HPOS)"/>
    <xsl:variable name="lx1" select="$lx0 + xs:double($line/@WIDTH)"/>
    <xsl:sequence select="
      if ($b1 - $b0 lt 0.5 * min(($lh, $fy1 - $fy0)) or empty($xr)) then 'none'
      else if ($lx0 ge $xr[2] - $tol) then 'right'
      else if ($lx1 le $xr[1] + $tol) then 'left'
      else 'clash'"/>
  </xsl:function>

  <!-- TextLines of the main text column only (margins, music, graphics excluded) -->
  <xsl:function name="kf:main-lines" as="element(alto:TextLine)*">
    <xsl:param name="altoDoc"/>

    <xsl:variable name="tagIds"
      select="$altoDoc//alto:OtherTag[@LABEL = 'MainZone']/@ID"/>

    <xsl:sequence
      select="$altoDoc//alto:TextBlock[
          tokenize(normalize-space(@TAGREFS), '\s+') = $tagIds
        ]//alto:TextLine"/>
  </xsl:function>

  <!-- Bounding box (x0, y0, x1, y1) of the first block of figure #ordinal; empty if missing -->

  <xsl:function name="kf:fig-box" as="xs:double*">
    <xsl:param name="altoDoc"/>
    <xsl:param name="ordinal" as="xs:integer"/>

    <xsl:variable name="tagIds"
      select="$altoDoc//alto:OtherTag[
          @LABEL = concat('GraphicZone:figure#', $ordinal)
        ]/@ID"/>

    <xsl:variable name="blocks"
      select="$altoDoc//alto:TextBlock[
          tokenize(normalize-space(@TAGREFS), '\s+') = $tagIds
        ]"/>

    <xsl:if test="exists($blocks)">
      <xsl:sequence select="(
          min(for $b in $blocks return xs:double($b/@HPOS)),
          min(for $b in $blocks return xs:double($b/@VPOS)),
          max(for $b in $blocks return
              xs:double($b/@HPOS) + xs:double($b/@WIDTH)),
          max(for $b in $blocks return
              xs:double($b/@VPOS) + xs:double($b/@HEIGHT))
        )"/>
    </xsl:if>
  </xsl:function>

  <!-- ======================= Paragraphisms =======================
       The short strokes in the outer margin that mark the start of a paragraph. They are drawn on
       the ALTO page as GraphicZone:paragraphism#N and are not in the Euporia source, so they are
       built from the ALTO alone: a <zone> in the facsimile (like the figures) and a <figure
       type="paragraphism"> anchored to the text line they stand beside. -->

  <!-- Baseline y of a TextLine: mean of the y values of its BASELINE (centre of the box if it has none) -->
  <xsl:function name="kf:baseline-y" as="xs:double">
    <xsl:param name="line" as="element(alto:TextLine)"/>
    <xsl:variable name="t" select="tokenize(normalize-space($line/@BASELINE), '\s+')[. != '']"/>
    <xsl:variable name="ys" select="for $i in 1 to (count($t) idiv 2) return xs:double($t[2 * $i])"/>
    <xsl:sequence select="if (exists($ys)) then avg($ys) else xs:double($line/@VPOS) + xs:double($line/@HEIGHT) div 2"/>
  </xsl:function>

  <!-- y of the baseline of each physical line of the main text column, top to bottom.
       Headings, interlinear additions and text inside figures do not make a row of their own;
       baselines closer than half a median line height are the same row. The Euporia source has one
       <l> per physical line, so row n corresponds to the n-th <l> of the page's mainZones
       (without the section headings). -->
  <xsl:function name="kf:text-rows" as="xs:double*">
    <xsl:param name="altoDoc"/>
    <xsl:variable name="skipTags"
      select="$altoDoc//alto:OtherTag[matches(@LABEL, '^(HeadingLine|CustomLine:addition|CustomLine:textinfigure)')]/@ID"/>
    <xsl:variable name="ys" as="xs:double*">
      <xsl:perform-sort select="
        for $l in kf:main-lines($altoDoc)[not(tokenize(normalize-space(@TAGREFS), '\s+') = $skipTags)]
        return kf:baseline-y($l)">
        <xsl:sort select="."/>
      </xsl:perform-sort>
    </xsl:variable>
    <xsl:variable name="tol" select="0.5 * kf:median-line-height($altoDoc)"/>
    <xsl:variable name="ends" select="
      (0, (for $i in 2 to count($ys) return if ($ys[$i] - $ys[$i - 1] gt $tol) then $i - 1 else ()), count($ys))"/>
    <xsl:sequence select="
      for $r in 1 to (count($ends) - 1)
      return avg($ys[position() gt $ends[$r] and position() le $ends[$r + 1]])"/>
  </xsl:function>

  <!-- Bounding box (x0, y0, x1, y1) of paragraphism #ordinal; empty if missing -->
  <xsl:function name="kf:par-box" as="xs:double*">
    <xsl:param name="altoDoc"/>
    <xsl:param name="ordinal" as="xs:integer"/>
    <xsl:variable name="tagIds"
      select="$altoDoc//alto:OtherTag[@LABEL = concat('GraphicZone:paragraphism#', $ordinal)]/@ID"/>
    <xsl:variable name="blocks"
      select="$altoDoc//alto:TextBlock[tokenize(normalize-space(@TAGREFS), '\s+') = $tagIds]"/>
    <xsl:if test="exists($blocks)">
      <xsl:sequence select="(
          min(for $b in $blocks return xs:double($b/@HPOS)),
          min(for $b in $blocks return xs:double($b/@VPOS)),
          max(for $b in $blocks return xs:double($b/@HPOS) + xs:double($b/@WIDTH)),
          max(for $b in $blocks return xs:double($b/@VPOS) + xs:double($b/@HEIGHT))
        )"/>
    </xsl:if>
  </xsl:function>

  <!-- Numbers N of the GraphicZone:paragraphism#N zones of the page that have a block, ascending -->
  <xsl:function name="kf:par-ordinals" as="xs:integer*">
    <xsl:param name="altoDoc"/>
    <xsl:variable name="all" as="xs:integer*">
      <xsl:perform-sort select="
        for $t in $altoDoc//alto:OtherTag[matches(@LABEL, '^GraphicZone:paragraphism#\d+$')]
        return xs:integer(replace($t/@LABEL, '^GraphicZone:paragraphism#(\d+)$', '$1'))">
        <xsl:sort select="."/>
      </xsl:perform-sort>
    </xsl:variable>
    <xsl:sequence select="for $n in $all return if (exists(kf:par-box($altoDoc, $n))) then $n else ()"/>
  </xsl:function>

  <!-- Distance (px) from the middle of a text line to its baseline: the middle of the line box
       in the viewer is a little above the baseline -->
  <xsl:function name="kf:line-middle-offset" as="xs:double">
    <xsl:param name="altoDoc"/>
    <xsl:sequence select="0.3 * kf:median-line-height($altoDoc)"/>
  </xsl:function>

  <!-- Index (in $rows) of the text row a box (x0, y0, x1, y1) stands beside: the one whose middle
       is closest to the middle of the box -->
  <xsl:function name="kf:box-row" as="xs:integer?">
    <xsl:param name="altoDoc"/>
    <xsl:param name="b" as="xs:double*"/>
    <xsl:param name="rows" as="xs:double*"/>
    <xsl:if test="exists($b) and exists($rows)">
      <xsl:variable name="cy" select="($b[2] + $b[4]) div 2"/>
      <xsl:variable name="off" select="kf:line-middle-offset($altoDoc)"/>
      <xsl:variable name="d" select="for $r in $rows return abs($cy - ($r - $off))"/>
      <xsl:sequence select="index-of($d, min($d))[1]"/>
    </xsl:if>
  </xsl:function>

  <!-- Vertical offset (px of the scan) of the middle of a box from the middle of its text row;
       positive = lower than the line. 0 when there is no row. -->
  <xsl:function name="kf:box-dy" as="xs:double">
    <xsl:param name="altoDoc"/>
    <xsl:param name="b" as="xs:double*"/>
    <xsl:param name="rows" as="xs:double*"/>
    <xsl:variable name="row" select="kf:box-row($altoDoc, $b, $rows)"/>
    <xsl:sequence select="
      if (empty($row)) then 0
      else ($b[2] + $b[4]) div 2 - ($rows[$row] - kf:line-middle-offset($altoDoc))"/>
  </xsl:function>

  <xsl:function name="kf:par-row" as="xs:integer?">
    <xsl:param name="altoDoc"/>
    <xsl:param name="ordinal" as="xs:integer"/>
    <xsl:param name="rows" as="xs:double*"/>
    <xsl:sequence select="kf:box-row($altoDoc, kf:par-box($altoDoc, $ordinal), $rows)"/>
  </xsl:function>

  <xsl:function name="kf:par-dy" as="xs:double">
    <xsl:param name="altoDoc"/>
    <xsl:param name="ordinal" as="xs:integer"/>
    <xsl:param name="rows" as="xs:double*"/>
    <xsl:sequence select="kf:box-dy($altoDoc, kf:par-box($altoDoc, $ordinal), $rows)"/>
  </xsl:function>

  <!-- Number of the <l> (among the $nLines lines of the page's mainZones) that ALTO row $row
       corresponds to. Equal numbers when ALTO and source agree; otherwise the row is scaled, so a
       mark still lands close to the right place. -->
  <xsl:function name="kf:target-line" as="xs:integer?">
    <xsl:param name="row" as="xs:integer?"/>
    <xsl:param name="nRows" as="xs:integer"/>
    <xsl:param name="nLines" as="xs:integer"/>
    <xsl:sequence select="
      if (empty($row) or $nLines eq 0) then ()
      else if ($nRows eq $nLines) then $row
      else max((1, min(($nLines, xs:integer(round($row * $nLines div $nRows))))))"/>
  </xsl:function>

  <!-- Outer margin the stroke is in: 'left' or 'right' of the middle of the text column -->
  <xsl:function name="kf:par-side" as="xs:string">
    <xsl:param name="altoDoc"/>
    <xsl:param name="ordinal" as="xs:integer"/>
    <xsl:variable name="b" select="kf:par-box($altoDoc, $ordinal)"/>
    <xsl:sequence select="
      if (exists($b) and ($b[1] + $b[3]) div 2 ge kf:content-ulx($altoDoc) + kf:content-width($altoDoc) div 2)
        then 'right' else 'left'"/>
  </xsl:function>

  <!-- A small figure that stands in the outer margin, entirely beside the text column (like the
       dotted arrow and the dot left of the rule on p. 6): 'out-left' / 'out-right', else ''.
       Such a figure does not belong to the text flow: klee.css hangs it in the margin, beyond the
       vertical rule, at the height where it appears in the flow. Anything wider than about ten
       letters, or touching a text line, keeps the normal layouts. -->
  <xsl:function name="kf:fig-margin" as="xs:string">
    <xsl:param name="altoDoc"/>
    <xsl:param name="ordinal" as="xs:integer"/>
    <xsl:variable name="b" select="kf:fig-box($altoDoc, $ordinal)"/>
    <xsl:variable name="chw" select="kf:char-width($altoDoc)"/>
    <xsl:choose>
      <xsl:when test="empty($b) or $chw le 0 or $b[3] - $b[1] gt 10 * $chw">
        <xsl:sequence select="''"/>
      </xsl:when>
      <xsl:otherwise>
        <xsl:variable name="x0" select="kf:content-ulx($altoDoc)"/>
        <xsl:variable name="x1" select="$x0 + kf:content-width($altoDoc)"/>
        <xsl:variable name="poly" select="kf:fig-poly($altoDoc, $ordinal)"/>
        <xsl:variable name="clash"
          select="kf:main-lines($altoDoc)[kf:line-side(., $poly, $b[2], $b[4], 0.5 * $chw) = 'clash']"/>
        <xsl:sequence select="
          if (exists($clash)) then ''
          else if ($b[3] le $x0 + 0.5 * $chw) then 'out-left'
          else if ($b[1] ge $x1 - 0.5 * $chw) then 'out-right'
          else ''"/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:function>

  <!-- Two figures form a row when they share a horizontal band (>= 50% of the
       smaller height), are mostly side by side (b on the right of a, bbox overlap
       <= 40% of the smaller width) and no text line sits between them. -->
  <xsl:function name="kf:fig-same-row" as="xs:boolean">
    <xsl:param name="altoDoc"/>
    <xsl:param name="a" as="xs:integer"/>
    <xsl:param name="b" as="xs:integer"/>
    <xsl:variable name="ba" select="kf:fig-box($altoDoc, $a)"/>
    <xsl:variable name="bb" select="kf:fig-box($altoDoc, $b)"/>
    <xsl:choose>
      <xsl:when test="empty($ba) or empty($bb)">
        <xsl:sequence select="false()"/>
      </xsl:when>
      <xsl:otherwise>
        <xsl:variable name="y0" select="max(($ba[2], $bb[2]))"/>
        <xsl:variable name="y1" select="min(($ba[4], $bb[4]))"/>
        <xsl:variable name="wMin" select="min(($ba[3] - $ba[1], $bb[3] - $bb[1]))"/>
        <xsl:variable name="hMin" select="min(($ba[4] - $ba[2], $bb[4] - $bb[2]))"/>
        <xsl:variable name="between" select="kf:main-lines($altoDoc)[
            min((xs:double(@VPOS) + xs:double(@HEIGHT), $y1)) - max((xs:double(@VPOS), $y0))
            ge 0.5 * min((xs:double(@HEIGHT), $y1 - $y0))
            and xs:double(@HPOS) + xs:double(@WIDTH) div 2 gt $ba[3]
            and xs:double(@HPOS) + xs:double(@WIDTH) div 2 lt $bb[1]]"/>
        <xsl:sequence select="
          $y1 - $y0 ge 0.5 * $hMin
          and $bb[1] ge $ba[1]
          and $ba[3] - $bb[1] le 0.4 * $wMin
          and $bb[3] - $ba[1] le kf:content-width($altoDoc)
          and $ba[1] ge kf:content-ulx($altoDoc) - 2 * kf:char-width($altoDoc)
          and $bb[3] le kf:content-ulx($altoDoc) + kf:content-width($altoDoc) + 2 * kf:char-width($altoDoc)
          and empty($between)"/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:function>

  <!-- 'row-start' / 'row-next' if the figure belongs to a row, '' otherwise -->
  <xsl:function name="kf:fig-row" as="xs:string">
    <xsl:param name="altoDoc"/>
    <xsl:param name="ordinal" as="xs:integer"/>
    <xsl:variable name="hasPrev" select="kf:fig-same-row($altoDoc, $ordinal - 1, $ordinal)"/>
    <xsl:variable name="hasNext" select="kf:fig-same-row($altoDoc, $ordinal, $ordinal + 1)"/>
    <xsl:sequence select="if ($hasPrev) then 'row-next' else if ($hasNext) then 'row-start' else ''"/>
  </xsl:function>

  <!-- Layout of a standalone figure, decided from the text lines sharing its band.
       Each line counts as left/right of the figure according to its horizontal centre.
       no text beside / text overlapping / wider than half the column -> block
       small figure with text on its left                            -> inline
       text only on the right                                        -> float-left
       text only on the left                                         -> float-right
       A figure with text beside only its LOWER part (e.g. a sketch whose last lines wrap around it)
       is a float too, with a gap: the vertical distance (em) from the top of the figure to the
       first line beside it, rendered as a spacer figure (see kf:fig-gap and the 'gap-' @rend).
       Returns <v rend="..." why="..." gap="em"/>; $ordinal and $altoDoc are only used for messages. -->

  <xsl:function name="kf:fig-layout" as="element()">
    <xsl:param name="altoDoc"/>
    <xsl:param name="ordinal" as="xs:integer"/>

    <xsl:variable name="box" select="kf:fig-box($altoDoc, $ordinal)"/>

    <xsl:variable name="verdict" as="element()">
      <xsl:choose>
        <xsl:when test="empty($box)">
          <v rend="block" why="no figure box in the ALTO" gap="0"/>
        </xsl:when>
        <xsl:otherwise>
          <xsl:variable name="fx0" select="$box[1]"/>
          <xsl:variable name="fy0" select="$box[2]"/>
          <xsl:variable name="fx1" select="$box[3]"/>
          <xsl:variable name="fy1" select="$box[4]"/>
          <xsl:variable name="fw" select="$fx1 - $fx0"/>
          <xsl:variable name="fh" select="$fy1 - $fy0"/>
          <xsl:variable name="mlh" select="kf:median-line-height($altoDoc)"/>
          <xsl:variable name="cw" select="kf:content-width($altoDoc)"/>
          <xsl:variable name="chw" select="kf:char-width($altoDoc)"/>
          <xsl:variable name="tol" select="if ($chw gt 0) then $chw else 0.02 * $cw"/>
          <xsl:variable name="poly" select="kf:fig-poly($altoDoc, $ordinal)"/>

          <xsl:variable name="sides" as="element()*">
            <xsl:for-each select="kf:main-lines($altoDoc)">
              <xsl:variable name="s" select="kf:line-side(., $poly, $fy0, $fy1, $tol)"/>
              <!-- a line that only brushes the top of the drawing (its baseline lies in the upper third
                   of the figure, e.g. ascenders touching the peak of a sketch) is above it, not a clash -->
              <xsl:if test="$s ne 'none' and not($s = 'clash' and kf:baseline-y(.) le $fy0 + 0.35 * $fh)">
                <l side="{$s}" x0="{@HPOS}" x1="{xs:double(@HPOS) + xs:double(@WIDTH)}"
                   y0="{@VPOS}" y1="{xs:double(@VPOS) + xs:double(@HEIGHT)}"
                   ov="{min((xs:double(@VPOS) + xs:double(@HEIGHT), $fy1)) - max((xs:double(@VPOS), $fy0))}"/>
              </xsl:if>
            </xsl:for-each>
          </xsl:variable>
          <xsl:variable name="left" select="$sides[@side = 'left']"/>
          <xsl:variable name="right" select="$sides[@side = 'right']"/>
          <xsl:variable name="clash" select="$sides[@side = 'clash']"/>
          <!-- share of the figure's height that has text beside it -->
          <xsl:variable name="coverage"
            select="min((1, sum(for $x in ($left, $right) return xs:double($x/@ov)) div $fh))"/>
          <!-- characters spanned by figure + text beside it: must fit the narrowest column -->
          <xsl:variable name="maxChars" select="78"/>
          <xsl:variable name="spanRight"
            select="if (exists($right)) then max(for $x in $right return xs:double($x/@x1)) - $fx0 else 0"/>
          <xsl:variable name="spanLeft"
            select="if (exists($left)) then $fx1 - min(for $x in $left return xs:double($x/@x0)) else 0"/>
          <!-- text that wraps only the lower part of a tall figure: it starts at or below the top of
               the figure and reaches at least the middle of it -->
          <xsl:variable name="beside" select="($left, $right)"/>
          <xsl:variable name="firstTop" select="if (exists($beside)) then min(for $x in $beside return xs:double($x/@y0)) else $fy0"/>
          <xsl:variable name="lastBottom" select="if (exists($beside)) then max(for $x in $beside return xs:double($x/@y1)) else $fy0"/>
          <xsl:variable name="lowerWrap"
            select="exists($beside) and $fh gt 2 * $mlh and $lastBottom ge $fy0 + 0.5 * $fh"/>
          <!-- distance from the top of the figure to the first line beside it, in em of the text -->
          <xsl:variable name="gapEm"
            select="if ($lowerWrap and $chw gt 0) then max((0, $firstTop - $fy0)) * 0.4 div $chw else 0"/>
          <xsl:variable name="cov" select="format-number($coverage, '0.00')"/>

          <xsl:choose>
            <xsl:when test="empty($sides)">
              <v rend="block" why="no text line beside the figure" gap="0"/>
            </xsl:when>

            <!-- small sign sitting in a line: the line may span it (clash) -->
            <xsl:when test="$fh le 1.5 * $mlh and $fw le 0.15 * $cw
              and (every $c in $clash satisfies (xs:double($c/@x0) le $fx0 and xs:double($c/@x1) ge $fx1))">
              <v rend="inline" why="small sign inside a line" gap="0"/>
            </xsl:when>

            <!-- one-line sign standing between two pieces of text of the same row (e.g. an arrow
                 between "Punkten" and "zu Linien"): inline, hosted by the line before it -->
            <xsl:when test="$fh le 1.5 * $mlh and $fw le 0.25 * $cw and exists($left) and exists($right) and empty($clash)">
              <v rend="inline" why="one-line sign between text on its left and right" gap="0"/>
            </xsl:when>

            <xsl:when test="exists($clash)">
              <v rend="block" why="{count($clash)} line(s) overlap the drawing (clash)" gap="0"/>
            </xsl:when>

            <xsl:when test="$fw ge 0.82 * $cw">
              <v rend="block" why="figure wider than 82% of the column" gap="0"/>
            </xsl:when>

            <xsl:when test="$coverage lt 0.4 and not($lowerWrap)">
              <v rend="block" why="coverage {$cov} &lt; 0.4 and the text does not wrap the lower half" gap="0"/>
            </xsl:when>

            <xsl:when test="exists($left) and exists($right)">
              <v rend="block" why="text on both sides" gap="0"/>
            </xsl:when>

            <xsl:when test="exists($left)">
              <xsl:choose>
                <xsl:when test="$chw gt 0 and $spanLeft div $chw gt $maxChars">
                  <v rend="block" why="figure + text beside it span more than {$maxChars} characters" gap="0"/>
                </xsl:when>
                <xsl:otherwise>
                  <v rend="float-right" why="text on the left only (coverage {$cov}, gap {format-number($gapEm, '0.##')}em)" gap="{$gapEm}"/>
                </xsl:otherwise>
              </xsl:choose>
            </xsl:when>

            <xsl:otherwise>
              <xsl:choose>
                <xsl:when test="$chw gt 0 and $spanRight div $chw gt $maxChars">
                  <v rend="block" why="figure + text beside it span more than {$maxChars} characters" gap="0"/>
                </xsl:when>
                <xsl:otherwise>
                  <v rend="float-left" why="text on the right only (coverage {$cov}, gap {format-number($gapEm, '0.##')}em)" gap="{$gapEm}"/>
                </xsl:otherwise>
              </xsl:choose>
            </xsl:otherwise>
          </xsl:choose>
        </xsl:otherwise>
      </xsl:choose>
    </xsl:variable>

    <xsl:if test="$debug-figures">
      <xsl:message>[fig-layout] figure #<xsl:value-of select="$ordinal"/>: <xsl:value-of select="$verdict/@rend"/> (<xsl:value-of select="$verdict/@why"/>)</xsl:message>
    </xsl:if>
    <xsl:sequence select="$verdict"/>
  </xsl:function>

  <xsl:function name="kf:fig-side" as="xs:string">
    <xsl:param name="altoDoc"/>
    <xsl:param name="ordinal" as="xs:integer"/>
    <xsl:sequence select="string(kf:fig-layout($altoDoc, $ordinal)/@rend)"/>
  </xsl:function>

  <!-- Spacer (em) to put after a float so that the text beside it starts level with the first
       line that has text beside it in the manuscript; 0 for every other layout -->
  <xsl:function name="kf:fig-gap" as="xs:double">
    <xsl:param name="fig" as="element()"/>
    <xsl:variable name="page" select="$fig/ancestor::page[1]"/>
    <xsl:variable name="altoDoc" select="kf:alto($page)"/>
    <xsl:variable name="ordinal" select="count($fig/preceding-sibling::graphZoneFig) + 1"/>
    <xsl:variable name="v" select="if ($altoDoc) then kf:fig-layout($altoDoc, $ordinal) else ()"/>
    <xsl:sequence select="if ($v/@rend = ('float-left', 'float-right')) then xs:double($v/@gap) else 0"/>
  </xsl:function>

  <!-- True when figure $fig is a float (or starts a row) that begins at or below the bottom of an
       earlier float / row of the page (within about one line height). Without a break the browser
       would put it beside that earlier float; in the manuscript it stands under it (p. 17: fig 12
       under fig 10 + fig 11). Emitted as <figure rend="clear"/> before the figure. -->
  <xsl:function name="kf:fig-needs-clear" as="xs:boolean">
    <xsl:param name="fig" as="element()"/>
    <xsl:variable name="page" select="$fig/ancestor::page[1]"/>
    <xsl:variable name="altoDoc" select="kf:alto($page)"/>
    <xsl:variable name="ordinal" select="count($fig/preceding-sibling::graphZoneFig) + 1"/>
    <xsl:choose>
      <xsl:when test="empty($altoDoc) or $ordinal le 1">
        <xsl:sequence select="false()"/>
      </xsl:when>
      <xsl:otherwise>
        <xsl:variable name="mine" select="kf:fig-rend($fig)"/>
        <xsl:variable name="box" select="kf:fig-box($altoDoc, $ordinal)"/>
        <xsl:variable name="tol" select="kf:median-line-height($altoDoc)"/>
        <!-- bottoms of the earlier figures that float -->
        <xsl:variable name="bottoms" select="
          for $p in $fig/preceding-sibling::graphZoneFig
          return if (kf:fig-rend($p) = ('float-left', 'float-right', 'row-start', 'row-next'))
            then kf:fig-box($altoDoc, count($p/preceding-sibling::graphZoneFig) + 1)[4] else ()"/>
        <xsl:sequence select="
          $mine = ('float-left', 'float-right', 'row-start')
          and exists($box) and exists($bottoms)
          and (some $b in $bottoms satisfies $box[2] ge $b - $tol)
          and not($mine = 'row-next')
          and kf:fig-rend($fig/preceding-sibling::graphZoneFig[1]) ne 'row-start'"/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:function>

  <!-- Layout of the figure that graphZoneFig $fig stands for: out-left / out-right (in the outer
       margin, see kf:fig-margin), row-start / row-next (side by side), else inline / float-left /
       float-right / block. A figure is only put in the margin when the page has a line to hang it on. -->
  <xsl:function name="kf:fig-rend" as="xs:string">
    <xsl:param name="fig" as="element()"/>
    <xsl:variable name="page" select="$fig/ancestor::page[1]"/>
    <xsl:variable name="figOrdinal" select="count($fig/preceding-sibling::graphZoneFig) + 1"/>
    <xsl:variable name="altoDoc" select="kf:alto($page)"/>
    <xsl:variable name="inMargin" select="
      if ($altoDoc and exists($page//mainZone//line[not(ancestor::sectionHeading)]) and exists(kf:text-rows($altoDoc)))
        then kf:fig-margin($altoDoc, $figOrdinal) else ''"/>
    <xsl:sequence select="
      if (not($altoDoc)) then 'block'
      else if ($inMargin != '') then $inMargin
      else if (kf:fig-row($altoDoc, $figOrdinal) != '') then kf:fig-row($altoDoc, $figOrdinal)
      else string(kf:fig-layout($altoDoc, $figOrdinal)/@rend)
      "/>
  </xsl:function>

  <!-- The <l> an inline figure must be attached to: the line right before it
       (or the last line of the preceding <ab>) -->
  <xsl:function name="kf:host-line" as="element()?">
    <xsl:param name="fig" as="element()"/>
    <xsl:variable name="p"
      select="$fig/preceding-sibling::*[not(self::tei:figure[@rend = 'inline'])][1]"/>
    <xsl:sequence select="($p/self::tei:l, $p/self::tei:ab/tei:l[last()])[1]"/>
  </xsl:function>

  <!-- We define a particular ALTO zone from an eScriptorium XML -->
  <xsl:template name="alto-zone">
    <xsl:param name="zoneId" as="xs:string"/>
    <xsl:param name="blocks" as="element(alto:TextBlock)*" select="."/>
    <!-- paragraphisms only: offset of the stroke from the middle of its text row (px of the scan) -->
    <xsl:param name="dy" as="xs:double?" select="()"/>
    <xsl:variable name="x0" select="min(for $b in $blocks return xs:double($b/@HPOS))"/>
    <xsl:variable name="y0" select="min(for $b in $blocks return xs:double($b/@VPOS))"/>
    <xsl:variable name="x1" select="max(for $b in $blocks return xs:double($b/@HPOS) + xs:double($b/@WIDTH))"/>
    <xsl:variable name="y1" select="max(for $b in $blocks return xs:double($b/@VPOS) + xs:double($b/@HEIGHT))"/>
    <zone>
      <xsl:attribute name="xml:id"><xsl:value-of select="$zoneId"/></xsl:attribute>
      <xsl:attribute name="ulx"><xsl:value-of select="format-number($x0, '0')"/></xsl:attribute>
      <xsl:attribute name="uly"><xsl:value-of select="format-number($y0, '0')"/></xsl:attribute>
      <xsl:attribute name="lrx"><xsl:value-of select="format-number($x1, '0')"/></xsl:attribute>
      <xsl:attribute name="lry"><xsl:value-of select="format-number($y1, '0')"/></xsl:attribute>
      <xsl:if test="exists($dy)">
        <xsl:attribute name="dy"><xsl:value-of select="format-number($dy, '0.#')"/></xsl:attribute>
      </xsl:if>
      <xsl:attribute name="points">
        <xsl:choose>
          <xsl:when test="count($blocks) = 1">
            <xsl:variable name="coords"
              select="tokenize(normalize-space($blocks[1]/alto:Shape/alto:Polygon/@POINTS), '\s+')"/>
            <xsl:for-each select="1 to (count($coords) idiv 2)">
              <xsl:variable name="i" select="."/>
              <xsl:if test="$i gt 1"><xsl:text> </xsl:text></xsl:if>
              <xsl:value-of select="concat($coords[2 * $i - 1], ',', $coords[2 * $i])"/>
            </xsl:for-each>
          </xsl:when>
          <xsl:otherwise>
            <xsl:value-of select="concat($x0, ',', $y0, ' ', $x1, ',', $y0, ' ', $x1, ',', $y1, ' ', $x0, ',', $y1)"/>
          </xsl:otherwise>
        </xsl:choose>
      </xsl:attribute>
    </zone>
  </xsl:template>

  <xsl:template match="tei:l" mode="attach-inline">
    <xsl:variable name="me" select="."/>
    <!-- figures are siblings of the <ab>, not of its last <l> -->
    <xsl:variable name="anchor"
      select="if (parent::tei:ab and empty(following-sibling::tei:l)) then parent::tei:ab else ."/>
    <xsl:copy>
      <xsl:copy-of select="@*"/>
      <xsl:apply-templates select="node()" mode="attach-inline"/>
      <xsl:copy-of select="$anchor/following-sibling::tei:figure[@rend = 'inline'][kf:host-line(.) is $me]"/>
    </xsl:copy>
  </xsl:template>

  <!-- already emitted inside the host line: drop the standalone copy -->
  <xsl:template match="tei:figure[@rend = 'inline'][exists(kf:host-line(.))]" mode="attach-inline"/>

  <!-- A line that belongs to the numbered main text -->
  <xsl:function name="kf:counted-line" as="xs:boolean">
    <xsl:param name="l" as="element(tei:l)"/>
    <xsl:sequence select="not($l/parent::tei:label or $l/parent::tei:note
        or $l/parent::tei:ab[@type = 'margin'])"/>
  </xsl:function>

  <!-- Counted lines grouped by the page (<pb>) they stand on -->
  <xsl:key name="counted-lines-by-pb"
    match="tei:l[kf:counted-line(.)]"
    use="generate-id(preceding::tei:pb[1])"/>

  <!-- Wraps the runs of orphan <l> among $nodes in <ab>, then converts everything -->
  <xsl:template name="l-to-lb-children">
    <xsl:param name="nodes" as="node()*"/>
    <xsl:for-each-group select="$nodes" group-adjacent="exists(self::tei:l)">
      <xsl:choose>
        <xsl:when test="current-grouping-key()">
          <ab>
            <xsl:apply-templates select="current-group()" mode="l-to-lb"/>
          </ab>
        </xsl:when>
        <xsl:otherwise>
          <xsl:apply-templates select="current-group()" mode="l-to-lb"/>
        </xsl:otherwise>
      </xsl:choose>
    </xsl:for-each-group>
  </xsl:template>

  <xsl:template match="tei:div" mode="l-to-lb">
    <xsl:copy>
      <xsl:copy-of select="@*"/>
      <xsl:call-template name="l-to-lb-children">
        <xsl:with-param name="nodes" select="node()"/>
      </xsl:call-template>
    </xsl:copy>
  </xsl:template>

  <!-- Main-text line: numbered milestone, then the content of the old <l> -->
  <xsl:template match="tei:l[kf:counted-line(.)]" mode="l-to-lb">
    <xsl:variable name="me" select="."/>
    <xsl:variable name="onPage"
      select="key('counted-lines-by-pb', generate-id(preceding::tei:pb[1]), root(.))"/>
    <!-- Counted line: an <l> element carrying its number on the page -->
    <l n="{count($onPage[. &lt;&lt; $me]) + 1}">
      <xsl:apply-templates select="node()" mode="l-to-lb"/>
    </l>
  </xsl:template>

  <!-- Line of a heading-like / marginal / note block: plain break between lines -->
  <xsl:template match="tei:l" mode="l-to-lb">
    <xsl:if test="preceding-sibling::tei:l"><lb/></xsl:if>
    <xsl:apply-templates select="node()" mode="l-to-lb"/>
  </xsl:template>

  <!-- Diplomatic edition: <l> becomes <line>, same @n -->
  <xsl:template match="tei:l" mode="source-doc">
    <line>
      <xsl:copy-of select="@*"/>
      <xsl:apply-templates select="node()" mode="source-doc"/>
    </line>
  </xsl:template>

  <!-- Diplomatic edition: phiAdd is omitted (supplied text inside figure captions is kept) -->
  <xsl:template match="tei:supplied[not(ancestor::tei:figure)]" mode="source-doc"/>

  <!-- Diplomatic edition: phiSub becomes a <seg> instead of a <choice> -->
  <xsl:template match="tei:choice[@rend = 'phiSub']" mode="source-doc">
    <seg type="phiSub">
      <xsl:apply-templates select="node()" mode="source-doc"/>
    </seg>
  </xsl:template>

  <!-- Identity copy shared by all the tree-rewriting passes -->
  <xsl:template match="node() | @*" mode="glue-bracket attach-inline l-to-lb source-doc edition">
    <xsl:copy><xsl:apply-templates select="@* | node()" mode="#current"/></xsl:copy>
  </xsl:template>

  <!-- Edition copy: every <pb> gets an xml:id prefixed with the id of its edition,
       so that a view can open one page of that edition by id -->
  <xsl:template match="tei:pb" mode="edition">
    <xsl:param name="edition-id" tunnel="yes"/>
    <pb xml:id="{$edition-id}_{substring-before(@facs, '.jpg')}">
      <xsl:copy-of select="@*"/>
    </pb>
  </xsl:template>

  <!-- Deletions are omitted in critical edition (del from phiDel; sic from deletion / pencilDeletion).
       <sic> inside figure captions (deletion_app) is kept, as for supplied in the diplomatic. -->
  <xsl:template match="tei:del | tei:sic[not(ancestor::tei:figure)]" mode="edition"/>

  <!-- Critical edition: additions and corrections are unwrapped (the <add> and <corr> tags is dropped, their content is kept).
       <add> and <corr> inside figure captions keeps its markup so far, as for sic and supplied. -->
  <xsl:template match="tei:add[not(ancestor::tei:figure)] | tei:corr[not(ancestor::tei:figure)]" mode="edition">
    <xsl:apply-templates select="node()" mode="edition"/>
  </xsl:template>

  <!-- One <text> of the corpus: its identity attributes plus the numbered content -->
  <xsl:template name="edition-text">
    <xsl:param name="id" as="xs:string"/>
    <xsl:param name="edition-lang" as="xs:string?"/>
    <xsl:param name="type" as="xs:string"/>
    <xsl:param name="content" as="node()*"/>
    <text xml:id="{$id}">
      <xsl:if test="$edition-lang">
        <xsl:attribute name="xml:lang" select="$edition-lang"/>
      </xsl:if>
      <xsl:attribute name="type" select="$type"/>
      <body>
        <xsl:apply-templates select="$content" mode="edition">
          <xsl:with-param name="edition-id" select="$id" tunnel="yes"/>
        </xsl:apply-templates>
      </body>
    </text>
  </xsl:template>

  <!-- MAIN TEMPLATE -->
  <xsl:template match="/">

    <xsl:processing-instruction name="teipublisher">odd="klee.odd" template="klee2.html" view="page" media="web print epub"</xsl:processing-instruction>

    <xsl:variable name="flatBody">
      <xsl:apply-templates/>
    </xsl:variable>

    <!-- Move inline figures into the end of the preceding line -->
    <xsl:variable name="withInline">
      <xsl:apply-templates select="$flatBody/node()" mode="attach-inline"/>
    </xsl:variable>
    <!-- Merge lone "(" lines into the following line -->
    <xsl:variable name="glued">
      <xsl:apply-templates select="$withInline/node()" mode="glue-bracket"/>
    </xsl:variable>
      
    <xsl:variable name="nested">
      <xsl:call-template name="nest-headings">
        <xsl:with-param name="nodes" select="$glued/node()"/>
      </xsl:call-template>
    </xsl:variable>

    <!-- Numbering pass: runs once, feeds all editions -->
    <xsl:variable name="numbered">
      <xsl:call-template name="l-to-lb-children">
        <xsl:with-param name="nodes" select="$nested/node()"/>
      </xsl:call-template>
    </xsl:variable>

    <TEI version="3.3.0">

      <!-- teiHeader corpus -->
      <teiHeader>
        
        <fileDesc>
          <titleStmt>
            <title>Beiträge zur bildnerischen Formlehre.</title>
          </titleStmt>
          <publicationStmt>
            <publisher>Istituto Italiano di Studi Germanici - IISG</publisher>
          </publicationStmt>
          <respStmt>
            <resp>Trascrizione e marcatura a cura di</resp>
            <name xml:id="HH">Hansmichael Hohenegger</name>
          </respStmt>
          <respStmt>
            <resp>Modello di codifica a cura di</resp>
            <name xml:id="TM">Tiziana Mancinelli</name>
            <name xml:id="CG">Calogero Giudice</name>
          </respStmt>
          <sourceDesc/>
        </fileDesc>

        <encodingDesc>
          <tagsDecl>
            <rendition source="klee.css"/>
          </tagsDecl>
        </encodingDesc>

        <profileDesc>
          <langUsage>
            <language ident="de">Deutsch</language>
          </langUsage>
        </profileDesc>

        <revisionDesc>
        </revisionDesc>
      </teiHeader>

      <facsimile>
        <!-- Cover and inner cover (pages -2 and -1) -->
        <surface xml:id="f65281">
          <graphic url="https://escriptorium.d4science.org/media/documents/3/65281.jpg"/>
        </surface>
        <surface xml:id="f67096">
          <graphic url="https://escriptorium.d4science.org/media/documents/3/67096.jpg"/>
        </surface>
        <!-- Other pages -->
        <xsl:for-each select="//page[facsimile/num]">
          <xsl:variable name="fid" select="normalize-space(facsimile/num)"/>
          <xsl:variable name="altoDoc" select="kf:alto(.)"/>
          <!-- Content frame -->
          <xsl:variable name="contentUlx" select="kf:content-ulx($altoDoc)"/>
          <xsl:variable name="contentWidth" select="kf:content-width($altoDoc)"/>
          <surface>
            <xsl:attribute name="xml:id">
              <xsl:value-of select="concat('f', $fid)" />
            </xsl:attribute>
            <xsl:attribute name="ulx">0</xsl:attribute>
            <xsl:attribute name="uly">0</xsl:attribute>
            <xsl:attribute name="lrx"><xsl:value-of select="$altoDoc//alto:Page/@WIDTH"/></xsl:attribute>
            <xsl:attribute name="lry"><xsl:value-of select="$altoDoc//alto:Page/@HEIGHT"/></xsl:attribute>
            <xsl:if test="$altoDoc and $contentWidth gt 0">
              <xsl:attribute name="contentUlx"><xsl:value-of select="format-number($contentUlx, '0')"/></xsl:attribute>
              <xsl:attribute name="contentWidth"><xsl:value-of select="format-number($contentWidth, '0')"/></xsl:attribute>
              <xsl:if test="kf:char-width($altoDoc) gt 0">
                <xsl:attribute name="charWidth"><xsl:value-of select="format-number(kf:char-width($altoDoc), '0.##')"/></xsl:attribute>
              </xsl:if>
            </xsl:if>
            <graphic>
              <xsl:attribute name="url">
                <xsl:value-of select="concat('https://escriptorium.d4science.org/media/documents/3/', $fid, '.jpg')"/>
              </xsl:attribute>
            </graphic>
            <!-- Zones derived from ALTO MusicZone tags -->
            <xsl:if test="$altoDoc">
              <xsl:for-each select="$altoDoc//alto:OtherTag[@LABEL = 'MusicZone']">
                <xsl:variable name="tagId" select="@ID"/>
                <xsl:variable name="musicOrdinal" select="position()"/>
                <xsl:variable name="blocks"
                  select="$altoDoc//alto:TextBlock[tokenize(normalize-space(@TAGREFS), '\s+') = $tagId]"/>
                <xsl:if test="exists($blocks)">
                  <xsl:call-template name="alto-zone">
                    <xsl:with-param name="zoneId" select="concat('zone_f', $fid, '_music', $musicOrdinal)"/>
                    <xsl:with-param name="blocks" select="$blocks"/>
                  </xsl:call-template>
                </xsl:if>
              </xsl:for-each>
              <xsl:for-each select="$altoDoc//alto:OtherTag[matches(@LABEL, '^GraphicZone:figure#\d+$')]">
                <xsl:variable name="tagId" select="@ID"/>
                <xsl:variable name="figOrdinal"
                  select="xs:integer(replace(@LABEL, '^GraphicZone:figure#(\d+)$', '$1'))"/>
                <xsl:variable name="blocks"
                  select="$altoDoc//alto:TextBlock[tokenize(normalize-space(@TAGREFS), '\s+') = $tagId]"/>
                <xsl:if test="exists($blocks)">
                  <xsl:call-template name="alto-zone">
                    <xsl:with-param name="zoneId" select="concat('zone_f', $fid, '_fig', $figOrdinal)"/>
                    <xsl:with-param name="blocks" select="$blocks"/>
                    <!-- a figure in the outer margin hangs on a text line: offset from its middle -->
                    <xsl:with-param name="dy" select="
                      if (kf:fig-margin($altoDoc, $figOrdinal) != '')
                        then kf:box-dy($altoDoc, kf:fig-box($altoDoc, $figOrdinal), kf:text-rows($altoDoc))
                      else ()"/>
                  </xsl:call-template>
                </xsl:if>
              </xsl:for-each>
              <!-- Paragraphisms (GraphicZone:paragraphism#N): same kind of zone as the figures -->
              <xsl:variable name="rows" select="kf:text-rows($altoDoc)"/>
              <xsl:for-each select="kf:par-ordinals($altoDoc)">
                <xsl:variable name="parOrdinal" select="."/>
                <xsl:variable name="tagId"
                  select="$altoDoc//alto:OtherTag[@LABEL = concat('GraphicZone:paragraphism#', $parOrdinal)]/@ID"/>
                <xsl:call-template name="alto-zone">
                  <xsl:with-param name="zoneId" select="concat('zone_f', $fid, '_par', $parOrdinal)"/>
                  <xsl:with-param name="blocks"
                    select="$altoDoc//alto:TextBlock[tokenize(normalize-space(@TAGREFS), '\s+') = $tagId]"/>
                  <xsl:with-param name="dy" select="kf:par-dy($altoDoc, $parOrdinal, $rows)"/>
                </xsl:call-template>
              </xsl:for-each>
            </xsl:if>
          </surface>
        </xsl:for-each>
        <!-- Final three pages -->
        <surface xml:id="f83236">
          <graphic url="https://escriptorium.d4science.org/media/documents/3/83236.jpg"/>
        </surface>
        <surface xml:id="f83587">
          <graphic url="https://escriptorium.d4science.org/media/documents/3/83587.jpg"/>
        </surface>
        <surface xml:id="f83602">
          <graphic url="https://escriptorium.d4science.org/media/documents/3/83602.jpg"/>
        </surface>
      </facsimile>

      <!-- Diplomatic edition -->
      <sourceDoc>
        <xsl:attribute name="xml:id">klee_dipl</xsl:attribute>
        <xsl:attribute name="type">diplomatic</xsl:attribute>
        <xsl:attribute name="xml:lang">de</xsl:attribute>
        <xsl:apply-templates select="$numbered/node()" mode="source-doc"/>
      </sourceDoc>

      <!-- Empty standOff before TEI children -->
      <standOff/>


      <teiCorpus version="3.3.0" xmlns="http://www.tei-c.org/ns/1.0">
        
      <!-- Single editions (critical, aligned, etc.) -->
      <!-- Critical edition -->
        <TEI>
          <teiHeader>
            <fileDesc>
              <titleStmt>
                <title></title>
              </titleStmt>
              <publicationStmt>
                <p><xsl:value-of select="$lang"/></p>
              </publicationStmt>
              <sourceDesc>
                <msDesc>
                  <handDesc>
                    <handNote medium="pencil" xml:id="pencil">Text written with pencil.</handNote>
                  </handDesc>
                </msDesc>
              </sourceDesc>
            </fileDesc>
            <profileDesc>
              <langUsage>
                <language ident="de">Deutsch</language>
              </langUsage>
            </profileDesc>
          </teiHeader>

          <xsl:call-template name="edition-text">
            <xsl:with-param name="id" select="$critical-id"/>
            <xsl:with-param name="edition-lang" select="$critical-lang"/>
            <xsl:with-param name="type" select="$critical-type"/>
            <xsl:with-param name="content" select="$numbered/node()"/>
          </xsl:call-template>

        </TEI>

        <!-- Other editions -->
      
        
      </teiCorpus>

    </TEI>
  </xsl:template>

  <!-- Cleaning from Euporia symbols -->
  <xsl:template match="
    deletion/text()           |
    replace/text()            |
    addition/text()           |
    subspencilAddition/text() |
    subspencilDeletion/text() |
    pencilAddition/text()     |
    pencilDeletion/text()     |
    pencil/text()             |
    phiDel/text()             |
    phiAdd/text()             |
    phiSub/text()             |
    operation/text()          |
    substitution/text()       |
    mrgTextZoneUp/text()      |
    mrgTextZoneOut/text()     |
    expl/text()
                  "/>

  <xsl:template match="text()">
    <xsl:value-of select="."/>
  </xsl:template>

  <xsl:template match="
    apparatoFigure |
    placeholder" />

  <!-- Managing punctuation -->

  <xsl:template name="render-punct">
    <xsl:param name="char"/>

    <pc>
      <!-- Which type of punctuation -->
      <xsl:attribute name="type">
        <xsl:choose>
          <xsl:when test="$char = '.'">period</xsl:when>
          <xsl:when test="$char = ','">comma</xsl:when>
          <xsl:when test="$char = ';'">semicolon</xsl:when>
          <xsl:when test="$char = ':'">colon</xsl:when>
          <xsl:when test="$char = '!'">exclam</xsl:when>
          <xsl:when test="$char = '?'">quest</xsl:when>
          <xsl:when test="$char = ('-', '–', '—')">dash</xsl:when>
          <xsl:when test="$char = ('…', '...')">ellipsis</xsl:when>
          <xsl:when test="$char = ('(', '[')">bracketOpen</xsl:when>
          <xsl:when test="$char = (')', ']')">bracketClose</xsl:when>
          <xsl:when test="$char = '«'">quoteOpen</xsl:when>
          <xsl:when test="$char = '»'">quoteClose</xsl:when>
          <xsl:when test="$char = '/'">slash</xsl:when>
          <xsl:otherwise>punct</xsl:otherwise>
        </xsl:choose>
      </xsl:attribute>

      <!-- Where it joins -->
      <xsl:if test="$char != '*'">
        <xsl:attribute name="float">
          <xsl:choose>
            <xsl:when test="$char = ('.', ',', ';', ':', '!', '?', ')', ']', '»', '…', '...')">left</xsl:when>
            <xsl:when test="$char = ('(', '[', '«')">right</xsl:when>
            <xsl:otherwise>both</xsl:otherwise>
          </xsl:choose>
        </xsl:attribute>
      </xsl:if>

      <!-- How strong it is -->
      <xsl:attribute name="force">
        <xsl:choose>
          <xsl:when test="$char = ('.', '!', '?', '…', '...')">strong</xsl:when>
          <xsl:when test="$char = (',', ';', ':')">weak</xsl:when>
          <xsl:when test="$char = ('-', '–', '—', '/', '(', ')', '[', ']', '«', '»')">inter</xsl:when>
          <xsl:otherwise>inter</xsl:otherwise>
        </xsl:choose>
      </xsl:attribute>

      <xsl:value-of select="$char"/>

    </pc>

  </xsl:template>

  <!-- Main structure -->
  <xsl:template match="*[local-name()='div']">
    <!-- The source div is just a per-scan grouping (one per <page>); real
         sectioning comes from <head>/@n via nest-headings below, so we
         simply flatten through here instead of emitting a div ourselves. -->
    <xsl:apply-templates/>
  </xsl:template>

  <!--
       Turns the flat sequence of <head>/<pb>/<ab>/... produced above into
       properly nested <div>s, one per section, with the section <head> as
       its first child.
  -->
  <xsl:template name="nest-headings">
    <xsl:param name="nodes" as="node()*"/>

    <!-- If I want to exclude margin headings, just add "[not(@type = 'margin')]" 
         in the select below (after [local-name() = 'head']) -->
    <xsl:variable name="headLevels"
      select="for $h in $nodes[local-name() = 'head']
        return xs:integer($h/@n)"/>

    <xsl:choose>
      <xsl:when test="empty($headLevels)">
        <xsl:sequence select="$nodes"/>
      </xsl:when>
      <xsl:otherwise>
        <xsl:variable name="minLevel" select="min($headLevels)"/>
        <!-- A <pb> immediately followed by the boundary head belongs to the
             page the NEW section starts on, not to the section that is
             ending, so it must open the new group together with that head
             (pb first, then head) rather than trail off the previous one. -->
        <xsl:for-each-group select="$nodes"
          group-starting-with="
            *[local-name() = 'pb'][following-sibling::*[1]
              [local-name() = 'head'][not(@type = 'margin')][xs:integer(@n) = $minLevel]]
            | *[local-name() = 'head'][not(@type = 'margin')][xs:integer(@n) = $minLevel]
            [not(preceding-sibling::*[1][local-name() = 'pb'])]">
          <xsl:choose>
            <xsl:when test="local-name() = 'head' and not(@type = 'margin') and xs:integer(@n) = $minLevel">
              <div n="{$minLevel}">
                <xsl:if test="@type"><xsl:attribute name="type" select="@type"/></xsl:if>
                <xsl:sequence select="."/>
                <xsl:call-template name="nest-headings">
                  <xsl:with-param name="nodes" select="current-group()[position() gt 1]"/>
                </xsl:call-template>
              </div>
            </xsl:when>
            <xsl:when test="local-name() = 'pb'">
              <!-- Group starts with a pb whose very next sibling is the
                   boundary head: keep the pb as the section's own first
                   child, immediately followed by its head - both direct
                   children of the div, unwrapped. -->
              <div n="{$minLevel}">
                <xsl:if test="current-group()[2]/@type">
                  <xsl:attribute name="type" select="current-group()[2]/@type"/>
                </xsl:if>
                <xsl:sequence select="current-group()[1]"/>
                <xsl:sequence select="current-group()[2]"/>
                <xsl:call-template name="nest-headings">
                  <xsl:with-param name="nodes" select="current-group()[position() gt 2]"/>
                </xsl:call-template>
              </div>
            </xsl:when>
            <xsl:otherwise>
              <!-- Content before the first boundary head at this depth (or
                   deeper-level heads trapped between shallower siblings). -->
              <xsl:call-template name="nest-headings">
                <xsl:with-param name="nodes" select="current-group()"/>
              </xsl:call-template>
            </xsl:otherwise>
          </xsl:choose>
        </xsl:for-each-group>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <xsl:template match="page">
    <pb>
      <xsl:attribute name="n" select="kf:page-number(.)"/>
      <xsl:attribute name="facs">
        <xsl:value-of select="normalize-space(facsimile//num)"/>
        <xsl:text>.jpg</xsl:text>
      </xsl:attribute>
    </pb>

    <xsl:apply-templates select="node()[
        self::mainZone
        or self::graphZoneFig
        or self::mrgTextZoneUp
        or self::mrgTextZoneOut
        or self::hdLineMargin
        or self::apparatoFigure
      ]"/>
  </xsl:template>

  <xsl:template match="mainZone">
    <xsl:for-each-group select="*" group-starting-with="openPar | sectionHeading">
      <xsl:choose>
        <xsl:when test="self::openPar">
          <ab n="{position()}">
            <xsl:apply-templates select="current-group()[not(self::openPar)]"/>
          </ab>
        </xsl:when>
        <xsl:otherwise>
          <xsl:apply-templates select="current-group()"/>
        </xsl:otherwise>
      </xsl:choose>
    </xsl:for-each-group>
  </xsl:template>

  <!-- Figures -->

  <xsl:template match="graphZoneFig">
    <xsl:variable name="figRend" select="kf:fig-rend(.)"/>
    <!-- figures in the outer margin are emitted by the text line they stand beside (paragraphism-marks) -->
    <xsl:if test="not(starts-with($figRend, 'out-'))">
      <xsl:if test="kf:fig-needs-clear(.)">
        <figure rend="clear"/>
      </xsl:if>
      <xsl:call-template name="fig-element">
        <xsl:with-param name="figRend" select="$figRend"/>
      </xsl:call-template>
      <!-- text beside only the lower part of the figure: spacer that pushes the next line down
           (rendered by the ODD as <figure class="fig-gap" style="height:...em">) -->
      <xsl:variable name="gap" select="kf:fig-gap(.)"/>
      <xsl:if test="$gap ge 0.5">
        <figure rend="gap-{format-number($gap, '0.##')}"/>
      </xsl:if>
    </xsl:if>
  </xsl:template>

  <!-- The <figure> of a graphZoneFig (context node) with the given layout -->
  <xsl:template name="fig-element">
    <xsl:param name="figRend" as="xs:string"/>
    <xsl:variable name="fid" select="normalize-space(replace(figId, '\s+', ''))"/>
    <xsl:variable name="item" select="key('fig-by-id', $fid)"/>
    <xsl:variable name="pageNum" select="normalize-space(ancestor::page[1]/facsimile/num)"/>
    <xsl:variable name="figOrdinal" select="count(preceding-sibling::graphZoneFig) + 1"/>

    <figure facs="#zone_f{$pageNum}_fig{$figOrdinal}" rend="{$figRend}">
      <xsl:if test="$item/label">
        <head rend="italic">
          <xsl:apply-templates select="$item/label" mode="fig"/>
        </head>
      </xsl:if>
      <xsl:if test="$item/textinfig">
        <figDesc>
          <xsl:apply-templates select="$item/textinfig" mode="fig"/>
        </figDesc>
      </xsl:if>
    </figure>
  </xsl:template>

  <xsl:template match="musicZone">
    <xsl:variable name="pageNum" select="normalize-space(ancestor::page[1]/facsimile/num)"/>
    <xsl:variable name="musicOrdinal" select="count(preceding-sibling::musicZone) + 1"/>

    <figure type="music" facs="#zone_f{$pageNum}_music{$musicOrdinal}">
      <head><xsl:value-of select="normalize-space(musicId)"/></head>
    </figure>
  </xsl:template>

  <xsl:template match="text()" mode="fig">
    <xsl:value-of select="."/>
  </xsl:template>

  <xsl:template match="line_app" mode="fig">
    <xsl:apply-templates mode="fig"/>
  </xsl:template>

  <xsl:template match="text()[normalize-space(.) = '|']" mode="fig">
    <lb />
  </xsl:template>

  <xsl:template match="seginfig" mode="fig">
    <w>
      <xsl:value-of select="normalize-space(.)"/>
    </w>
    <xsl:text> </xsl:text>
  </xsl:template>

  <xsl:template match="punctinfig" mode="fig">
    <xsl:variable name="char" select="normalize-space(.)"/>
    <xsl:call-template name="render-punct">
      <xsl:with-param name="char" select="$char"/>
    </xsl:call-template>
  </xsl:template>

  <xsl:template match="textSeqinfig" mode="fig">
    <xsl:apply-templates mode="fig"/>
  </xsl:template>

  <xsl:template match="label" mode="fig">
    <xsl:call-template name="strip-outer-brackets">
      <xsl:with-param name="nodes" select="node()"/>
    </xsl:call-template>
  </xsl:template>

  <xsl:template match="textinfig" mode="fig">
    <xsl:call-template name="strip-outer-brackets">
      <xsl:with-param name="nodes" select="node()"/>
    </xsl:call-template>
  </xsl:template>

  <xsl:template name="strip-outer-brackets">
    <xsl:param name="nodes"/>
    <xsl:for-each select="$nodes">
      <xsl:variable name="isFirst" select="position() = 1"/>
      <xsl:variable name="isLast" select="position() = last()"/>
      <xsl:choose>

        <xsl:when test="($isFirst or $isLast) and self::punctinfig and normalize-space(.) = ('(', ')', '[', ']')"/>

        <xsl:when test="self::text() and ($isFirst or $isLast)">
          <xsl:variable name="v1" select="if ($isFirst) then replace(., '^(\s*)[\(\[]', '$1') else ."/>
          <xsl:variable name="v2" select="if ($isLast) then replace($v1, '[\)\]](\s*)$', '$1') else $v1"/>
          <xsl:value-of select="$v2"/>
        </xsl:when>
        <xsl:otherwise>
          <xsl:apply-templates select="." mode="fig"/>
        </xsl:otherwise>
      </xsl:choose>
    </xsl:for-each>
  </xsl:template>

  <xsl:template match="operation_app" mode="fig">
    <xsl:apply-templates mode="fig"/>
  </xsl:template>

  <xsl:template match="addition_app" mode="fig">
    <add><xsl:apply-templates mode="fig"/></add>
  </xsl:template>

  <xsl:template match="deletion_app" mode="fig">
    <sic><xsl:apply-templates mode="fig"/></sic>
  </xsl:template>

  <xsl:template match="phiAdd_app" mode="fig">
    <supplied><xsl:apply-templates mode="fig"/></supplied>
  </xsl:template>

  <xsl:template match="underlined | underlined_app" mode="fig">
    <hi rend="underline">
      <xsl:apply-templates
        select="node()[not(self::text()[matches(., '^\s*_\s*$')])]"
        mode="fig"/>
    </hi>
  </xsl:template>

  <!-- End figures -->

  <xsl:template match="sectionHeading">
    <xsl:variable name="level" select="string-length(translate(level, ' ', ''))"/>
    <xsl:variable name="type"  select="lower-case(normalize-space(sectionType/seg))"/>

    <!-- First <seg> ID in document order inside <l>, only if level 1 and type is PART -->
    <xsl:variable name="firstSegId"
      select="if ($level = 1 and $type = 'part')
          then generate-id((line//*[local-name()='seg'])[1])
        else ''"/>

    <xsl:choose>
      <xsl:when test="$type = 'pause'">
        <trailer rend="bold" type="pause">
          <xsl:apply-templates select="line/node()">
            <xsl:with-param name="firstSegId" select="$firstSegId" tunnel="yes"/>
          </xsl:apply-templates>
        </trailer>
      </xsl:when>
      <xsl:otherwise>
        <head n="{$level}" type="{$type}">
          <xsl:apply-templates select="line/node()">
            <xsl:with-param name="firstSegId" select="$firstSegId" tunnel="yes"/>
          </xsl:apply-templates>
        </head>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <xsl:template match="hdLineMargin">
    
    <!-- Navigate to get page number -->
    <xsl:variable name="pageNum" select="xs:integer(kf:page-number(ancestor::page[1]))"/>
    <xsl:variable name="marginPlace" select="kf:margin-place($pageNum, false())"/>

    <!-- Intentionally NOT <head>: a TOC walker that collects every <head>
         descendant (not just a div's first child) would otherwise still
         list these margin titles as flat, unnested entries. <label> is
         the correct TEI element for a non-sectioning caption/title and is
         never treated as a heading by TOC code. -->
    <label
      type="margin"
      place="{$marginPlace}"
      rend="margin-head margin-{$marginPlace}"
      n="{string-length(translate(level, ' ', ''))}">
      <xsl:apply-templates select="line"/>
    </label>
  </xsl:template>

  <xsl:template match="line">
    <l>
      <xsl:attribute name="n">
        <xsl:number level="any" count="line" from="page"/>
      </xsl:attribute>
      <xsl:call-template name="paragraphism-marks"/>
      <xsl:apply-templates/>
    </l>
  </xsl:template>

  <!-- Figures in the outer margin standing beside this line: the paragraphisms and the small
       figures kf:fig-margin finds beside the text column. Only lines of the main text qualify. Each
       mark is tied to the ALTO text row nearest to it; row n is the n-th line of the page's mainZones
       (kf:target-line scales the row when the ALTO and the source count lines differently). The
       figure is the first child of the <l>; its side (rend="par-left" / "par-right" for
       paragraphisms, "out-left" / "out-right" for figures) and its offset from the middle of the
       line (zone/@dy) come from the ALTO, its place in the margin from klee.css. -->
  <xsl:template name="paragraphism-marks">
    <xsl:if test="ancestor::mainZone and not(ancestor::sectionHeading)">
      <xsl:variable name="page" select="ancestor::page[1]"/>
      <xsl:variable name="pageNum" select="normalize-space($page/facsimile/num)"/>
      <xsl:variable name="altoDoc" select="kf:alto($page)"/>
      <xsl:if test="$altoDoc">
        <xsl:variable name="me" select="."/>
        <xsl:variable name="mainLines" select="$page//mainZone//line[not(ancestor::sectionHeading)]"/>
        <xsl:variable name="nLines" select="count($mainLines)"/>
        <xsl:variable name="idx" select="count($mainLines[. &lt;&lt; $me]) + 1"/>
        <xsl:variable name="rows" select="kf:text-rows($altoDoc)"/>
        <xsl:for-each select="kf:par-ordinals($altoDoc)">
          <xsl:variable name="parOrdinal" select="."/>
          <xsl:variable name="row" select="kf:par-row($altoDoc, $parOrdinal, $rows)"/>
          <xsl:if test="kf:target-line($row, count($rows), $nLines) eq $idx">
            <figure type="paragraphism"
                    facs="#zone_f{$pageNum}_par{$parOrdinal}"
                    rend="par-{kf:par-side($altoDoc, $parOrdinal)}"/>
          </xsl:if>
        </xsl:for-each>
        <xsl:for-each select="$page/graphZoneFig[starts-with(kf:fig-rend(.), 'out-')]">
          <xsl:variable name="figOrdinal" select="count(preceding-sibling::graphZoneFig) + 1"/>
          <xsl:variable name="row" select="kf:box-row($altoDoc, kf:fig-box($altoDoc, $figOrdinal), $rows)"/>
          <xsl:if test="kf:target-line($row, count($rows), $nLines) eq $idx">
            <xsl:call-template name="fig-element">
              <xsl:with-param name="figRend" select="kf:fig-rend(.)"/>
            </xsl:call-template>
          </xsl:if>
        </xsl:for-each>
      </xsl:if>
    </xsl:if>
  </xsl:template>

  <xsl:template match="textSeq">
    <xsl:apply-templates/>
  </xsl:template>

  <xsl:template match="mrgTextZoneLow">
    <ab type="margin" place="lower" rend="margin-lower">
      <xsl:apply-templates/>
    </ab>
  </xsl:template>

  <xsl:template match="mrgTextZoneUp">
    <ab type="margin" place="upper" rend="margin-upper">
      <xsl:apply-templates/>
    </ab>
  </xsl:template>

  <!-- Used to manage margin zones -->
  <xsl:template match="mrgTextZoneIn | mrgTextZoneOut">
    <xsl:variable name="pageNum" select="xs:integer(kf:page-number(ancestor::page[1]))"/>
    <!-- Inner zone: opposite side of the outer one -->
    <xsl:variable name="marginPlace"
      select="kf:margin-place($pageNum, exists(self::mrgTextZoneIn))"/>
    <ab type="margin" place="{$marginPlace}" rend="margin-{$marginPlace}">
      <xsl:apply-templates/>
    </ab>
  </xsl:template>

  <!-- expl = explication-->
  <xsl:template match="expl">
    <note type="explication">
      <label>
        <xsl:apply-templates select="line[1]"/>
      </label>
      <xsl:apply-templates select="line[position() > 1]"/>
    </note>
  </xsl:template>

  <!--
       Word-part dispatcher.
       A <seg> that contains a prefix/suffix (prefix, prefix_app, suffix,
       suffix_app) represents a word that is interrupted by an
       editorial operation (deletion, replace, addition, etc.).
       This must become one <w> containing inline markup (<sic>, <corr>...).
  -->
  <xsl:template match="*[local-name()='seg'][prefix or prefix_app or suffix or suffix_app]" priority="1">
    <xsl:param name="firstSegId" tunnel="yes" select="''"/>

    <!-- Usually the editorial operation (deletion, pencilAddition, etc.) wraps a
         single word-fragment (e.g. one letter), which is meant to be fused with
         the prefix/suffix into one word. Sometimes, though, it wraps a *sequence*
         of several complete words (a nested textSeq with more than one <seg>
         child) -->
    <xsl:variable name="multiTextSeq"
      select="(.//*[local-name()='textSeq'][count(*[local-name()='seg']) > 1])[1]"/>

    <xsl:choose>

      <!-- Regular case: single word-fragment glued to prefix and/or suffix -->
      <!-- mode="wordpart": Used inside a single interrupted word -->
      <!-- All templates here stay INLINE -->

      <!-- prefix/suffix become plain text, not their own <w> -->

      <xsl:when test="not($multiTextSeq)">
        <w>
          <xsl:if test="$firstSegId != '' and generate-id(.) = $firstSegId">
            <xsl:attribute name="rend">sans</xsl:attribute>
          </xsl:if>
          <xsl:apply-templates mode="wordpart"/>
        </w>
      </xsl:when>

      <!-- Split case: several words inside the operation; only the boundary
           word (first if there's a prefix, last if there's a suffix) fuses
           with the prefix/suffix text. The others become their own <w>. -->
      <xsl:otherwise>
        <xsl:variable name="thisSeg" select="."/>
        <xsl:variable name="words" select="$multiTextSeq/*[local-name()='seg']"/>
        <xsl:variable name="n" select="count($words)"/>
        <xsl:for-each select="$words">
          <xsl:variable name="pos" select="position()"/>
          <w>
            <xsl:if test="$pos = 1 and $firstSegId != '' and generate-id($thisSeg) = $firstSegId">
              <xsl:attribute name="rend">sans</xsl:attribute>
            </xsl:if>
            <xsl:apply-templates select="$thisSeg" mode="wordpart">
              <xsl:with-param name="onlySegId" select="generate-id(current())" tunnel="yes"/>
              <xsl:with-param name="includePrefix" select="$pos = 1" tunnel="yes"/>
              <xsl:with-param name="includeSuffix" select="$pos = $n" tunnel="yes"/>
            </xsl:apply-templates>
          </w>
        </xsl:for-each>
      </xsl:otherwise>

    </xsl:choose>
  </xsl:template>

  <xsl:template match="*[local-name()='seg']">
    <xsl:param name="firstSegId" tunnel="yes" select="''"/>
    <xsl:choose>
      <xsl:when test="*">
        <xsl:apply-templates/>
      </xsl:when>
      <xsl:otherwise>
        <w>
          <xsl:if test="$firstSegId != '' and generate-id(.) = $firstSegId">
            <xsl:attribute name="rend">sans</xsl:attribute>
          </xsl:if>
          <xsl:value-of select="kf:glue-hyphen(replace(., '^[\s&#160;]+|[\s&#160;]+$', ''))"/>
        </w>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <xsl:template match="punct">
    <xsl:variable name="char" select="normalize-space(.)"/>
    <xsl:call-template name="render-punct">
      <xsl:with-param name="char" select="$char"/>
    </xsl:call-template>
  </xsl:template>

  <xsl:template match="prefix | prefix_app">
    <xsl:variable name="clean" select="normalize-space(replace(., '\^', ''))"/>
    <xsl:if test="$clean != ''">
      <w type="prefix"><xsl:value-of select="$clean"/></w>
    </xsl:if>
  </xsl:template>

  <xsl:template match="suffix | suffix_app">
    <xsl:variable name="clean" select="normalize-space(replace(., '\^', ''))"/>
    <xsl:if test="$clean != ''">
      <w type="suffix"><xsl:value-of select="$clean"/></w>
    </xsl:if>
  </xsl:template>

  <xsl:template match="substitution" mode="#default wordpart">
    <choice><xsl:apply-templates mode="#current"/></choice>
  </xsl:template>

  <xsl:template match="deletion" mode="#default wordpart">
    <sic><xsl:apply-templates mode="#current"/></sic>
  </xsl:template>

  <xsl:template match="replace" mode="#default wordpart">
    <corr><xsl:apply-templates mode="#current"/></corr>
  </xsl:template>

  <xsl:template match="subspencilDeletion | pencilDeletion" mode="#default wordpart">
    <sic hand="#pencil"><xsl:apply-templates mode="#current"/></sic>
  </xsl:template>

  <xsl:template match="subspencilAddition | pencilAddition" mode="#default wordpart">
    <add hand="#pencil"><xsl:apply-templates mode="#current"/></add>
  </xsl:template>

  <xsl:template match="pencil" mode="#default wordpart">
    <hi hand="#pencil"><xsl:apply-templates mode="#current"/></hi>
  </xsl:template>

  <xsl:template match="addition" mode="#default wordpart">
    <add><xsl:apply-templates mode="#current"/></add>
  </xsl:template>

  <xsl:template match="phiDel" mode="#default wordpart">
    <del rend="strikethrough"><xsl:apply-templates mode="#current"/></del>
  </xsl:template>

  <xsl:template match="phiAdd" mode="#default wordpart">
    <supplied>
      <xsl:apply-templates mode="#current"/>
    </supplied>
  </xsl:template>

  <xsl:template match="phiSub" mode="#default wordpart">
    <choice rend="phiSub">
      <xsl:apply-templates mode="#current" />
    </choice>
  </xsl:template>

  <xsl:template match="underlined | underlined_app" mode="#default wordpart">
    <hi rend="underline">
      <xsl:apply-templates select="node()[not(self::text()[normalize-space(.) = '_'])]" mode="#current" />
    </hi>
  </xsl:template>

  <xsl:template match="prefix | prefix_app" mode="wordpart">
    <xsl:param name="includePrefix" tunnel="yes" select="true()"/>
    <xsl:if test="$includePrefix">
      <xsl:value-of select="normalize-space(replace(., '\^', ''))"/>
    </xsl:if>
  </xsl:template>

  <xsl:template match="suffix | suffix_app" mode="wordpart">
    <xsl:param name="includeSuffix" tunnel="yes" select="true()"/>
    <xsl:if test="$includeSuffix">
      <xsl:value-of select="normalize-space(replace(., '\^', ''))"/>
    </xsl:if>
  </xsl:template>

  <!-- structural wrappers: just pass through -->
  <xsl:template match="operation | textSeq" mode="wordpart">
    <xsl:apply-templates mode="wordpart"/>
  </xsl:template>

  <!-- nested seg (e.g. <seg>h </seg> inside textSeq): plain text only.
       When $onlySegId is set (split-word mode) and this seg is one of
       several sibling <seg> words, only the targeted sibling renders -
       the others are silenced so each ends up in its own <w>. -->
  <xsl:template match="*[local-name()='seg']" mode="wordpart">
    <xsl:param name="onlySegId" tunnel="yes" select="''"/>
    <xsl:choose>
      <xsl:when test="*">
        <xsl:apply-templates mode="wordpart"/>
      </xsl:when>
      <xsl:when test="$onlySegId != '' and count(../*[local-name()='seg']) > 1">
        <xsl:if test="generate-id(.) = $onlySegId">
          <xsl:value-of select="normalize-space(.)"/>
        </xsl:if>
      </xsl:when>
      <xsl:otherwise>
        <xsl:value-of select="kf:glue-hyphen(normalize-space(.))"/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <!-- strip the same Euporia editorial-symbol text nodes in wordpart mode -->
  <xsl:template match="
    deletion/text()           |
    replace/text()            |
    addition/text()           |
    subspencilAddition/text() |
    subspencilDeletion/text() |
    pencilAddition/text()     |
    pencilDeletion/text()     |
    pencil/text()             |
    phiDel/text()             |
    phiAdd/text()             |
    operation/text()          |
    substitution/text()" mode="wordpart"/>

  <!-- fallback: plain text nodes pass through verbatim -->
  <xsl:template match="text()" mode="wordpart">
    <xsl:value-of select="replace(., '\s+', ' ')"/>
  </xsl:template>

</xsl:stylesheet>