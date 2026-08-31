<#
  md2docx.ps1 - Convert a Markdown subset to .docx by emitting OOXML directly.

  Why not a library: this machine has no python, node, pandoc or LibreOffice,
  and Word COM automation hangs on invisible HTML import. Raw OOXML has no deps.

  Supported subset:
    # H1 (title)   ## H2   ### H3
    - bullet       two-space indent = nested bullet
    > callout (shaded, left rule)
    | table | with |---| separator row (first row = header)
    ---  horizontal rule (skipped)
    inline: **bold**  *italic*  `code`

  Usage: powershell -File md2docx.ps1 -In notes.md -Out notes.docx [-Title "Doc title"]
#>
param(
  [Parameter(Mandatory=$true)][string]$In,
  [Parameter(Mandatory=$true)][string]$Out,
  [string]$Title = ""
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression          # ZipArchive, ZipArchiveMode
Add-Type -AssemblyName System.IO.Compression.FileSystem

# ---- layout constants (twips) --------------------------------------------
$PAGE_W = 11906
$PAGE_H = 16838
$MARGIN = 1440
$CONTENT_W = $PAGE_W - (2 * $MARGIN)

function Esc([string]$s) {
  $s -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;'
}

# Split inline markdown into runs. Handles **bold**, *italic*, `code`.
# NOTE: w:rPr children are a schema-enforced SEQUENCE - rFonts, b, i, color, sz.
# Emitting them out of order makes Word report the file as corrupt.
function Runs([string]$text, [bool]$forceBold = $false) {
  $sb = New-Object System.Text.StringBuilder
  $pattern = '(\*\*[^*]+\*\*|\*[^*]+\*|`[^`]+`)'
  foreach ($tok in [regex]::Split($text, $pattern)) {
    if ([string]::IsNullOrEmpty($tok)) { continue }
    $val = $tok
    $rFonts = ''; $b = ''; $i = ''; $color = ''
    if ($forceBold) { $b = '<w:b/>' }
    if ($tok -match '^\*\*(.+)\*\*$') {
      $val = $Matches[1]; $b = '<w:b/>'
    } elseif ($tok -match '^\*(.+)\*$') {
      $val = $Matches[1]; $i = '<w:i/>'
    } elseif ($tok -match '^`(.+)`$') {
      $val = $Matches[1]
      $rFonts = '<w:rFonts w:ascii="Consolas" w:hAnsi="Consolas"/>'
      $color = '<w:color w:val="9A3412"/>'
    }
    $rpr = $rFonts + $b + $i + $color
    $r = '<w:r>'
    if ($rpr) { $r += '<w:rPr>' + $rpr + '</w:rPr>' }
    $r += '<w:t xml:space="preserve">' + (Esc $val) + '</w:t></w:r>'
    [void]$sb.Append($r)
  }
  if ($sb.Length -eq 0) { return '<w:r><w:t xml:space="preserve"></w:t></w:r>' }
  return $sb.ToString()
}

function Para([string]$style, [string]$text) {
  $p = '<w:p><w:pPr>'
  if ($style) { $p += '<w:pStyle w:val="' + $style + '"/>' }
  $p += '</w:pPr>' + (Runs $text) + '</w:p>'
  return $p
}

function BulletPara([string]$text, [int]$level) {
  $ppr = '<w:pStyle w:val="ListParagraph"/><w:numPr><w:ilvl w:val="' + $level + '"/><w:numId w:val="1"/></w:numPr>'
  return '<w:p><w:pPr>' + $ppr + '</w:pPr>' + (Runs $text) + '</w:p>'
}

function CalloutPara([string[]]$lines) {
  $ppr = '<w:pBdr><w:left w:val="single" w:sz="24" w:space="6" w:color="14243F"/></w:pBdr>' +
         '<w:shd w:val="clear" w:fill="F2F4F8"/><w:spacing w:before="120" w:after="120"/>' +
         '<w:ind w:left="170" w:right="113"/>'
  $out = ""
  foreach ($l in $lines) {
    $out += '<w:p><w:pPr>' + $ppr + '</w:pPr>' + (Runs $l) + '</w:p>'
  }
  return $out
}

function CellBorders() {
  return '<w:tcBorders>' +
    '<w:top w:val="single" w:sz="4" w:color="8A93A5"/>' +
    '<w:left w:val="single" w:sz="4" w:color="8A93A5"/>' +
    '<w:bottom w:val="single" w:sz="4" w:color="8A93A5"/>' +
    '<w:right w:val="single" w:sz="4" w:color="8A93A5"/>' +
    '</w:tcBorders>'
}

function BuildTable([string[]]$rows) {
  $split = @()
  foreach ($r in $rows) {
    $t = $r.Trim()
    if ($t.StartsWith('|')) { $t = $t.Substring(1) }
    if ($t.EndsWith('|')) { $t = $t.Substring(0, $t.Length - 1) }
    $split += , ($t -split '\s*\|\s*')
  }
  $ncol = 0
  foreach ($c in $split) { if ($c.Count -gt $ncol) { $ncol = $c.Count } }
  if ($ncol -eq 0) { return "" }
  $w = [int][math]::Floor($CONTENT_W / $ncol)
  $last = $CONTENT_W - ($w * ($ncol - 1))

  $x = '<w:tbl><w:tblPr><w:tblW w:w="' + $CONTENT_W + '" w:type="dxa"/>' +
       '<w:tblLayout w:type="fixed"/><w:tblCellMar>' +
       '<w:top w:w="60" w:type="dxa"/><w:left w:w="90" w:type="dxa"/>' +
       '<w:bottom w:w="60" w:type="dxa"/><w:right w:w="90" w:type="dxa"/>' +
       '</w:tblCellMar></w:tblPr><w:tblGrid>'
  for ($i = 0; $i -lt $ncol; $i++) {
    if ($i -eq $ncol - 1) { $cw = $last } else { $cw = $w }
    $x += '<w:gridCol w:w="' + $cw + '"/>'
  }
  $x += '</w:tblGrid>'

  for ($ri = 0; $ri -lt $split.Count; $ri++) {
    $isHead = ($ri -eq 0)
    $x += '<w:tr>'
    if ($isHead) { $x += '<w:trPr><w:tblHeader/></w:trPr>' }
    for ($ci = 0; $ci -lt $ncol; $ci++) {
      if ($ci -eq $ncol - 1) { $cw = $last } else { $cw = $w }
      if ($ci -lt $split[$ri].Count) { $txt = $split[$ri][$ci] } else { $txt = "" }
      $x += '<w:tc><w:tcPr><w:tcW w:w="' + $cw + '" w:type="dxa"/>' + (CellBorders)
      if ($isHead) { $x += '<w:shd w:val="clear" w:fill="E8ECF3"/>' }
      $x += '</w:tcPr>'
      $x += '<w:p><w:pPr><w:pStyle w:val="TableText"/></w:pPr>' + (Runs $txt $isHead) + '</w:p>'
      $x += '</w:tc>'
    }
    $x += '</w:tr>'
  }
  $x += '</w:tbl><w:p><w:pPr><w:spacing w:after="0" w:line="120" w:lineRule="exact"/></w:pPr></w:p>'
  return $x
}

# ---- parse ---------------------------------------------------------------
$lines = [System.IO.File]::ReadAllText($In, [System.Text.Encoding]::UTF8) -split "`r?`n"
$body = New-Object System.Text.StringBuilder
$i = 0
while ($i -lt $lines.Count) {
  $ln = $lines[$i]
  $t = $ln.Trim()

  if ($t -eq "") { $i++; continue }

  if ($t.StartsWith('|')) {
    $blk = @()
    while ($i -lt $lines.Count -and $lines[$i].Trim().StartsWith('|')) {
      $blk += $lines[$i].Trim(); $i++
    }
    $blk = @($blk | Where-Object { $_ -notmatch '^\|[\s:\-\|]+\|$' })
    [void]$body.Append((BuildTable $blk))
    continue
  }

  if ($t.StartsWith('> ') -or $t -eq '>') {
    $blk = @()
    while ($i -lt $lines.Count -and ($lines[$i].Trim().StartsWith('> ') -or $lines[$i].Trim() -eq '>')) {
      $blk += ($lines[$i].Trim() -replace '^>\s?', '')
      $i++
    }
    [void]$body.Append((CalloutPara $blk))
    continue
  }

  if ($t -match '^---+$') { $i++; continue }
  if ($t -match '^#\s+(.*)') { [void]$body.Append((Para 'Title' $Matches[1])); $i++; continue }
  if ($t -match '^##\s+(.*)') { [void]$body.Append((Para 'Heading1' $Matches[1])); $i++; continue }
  if ($t -match '^###\s+(.*)') { [void]$body.Append((Para 'Heading2' $Matches[1])); $i++; continue }

  if ($ln -match '^(\s*)[-*]\s+(.*)') {
    $lvl = [math]::Min([int][math]::Floor($Matches[1].Length / 2), 2)
    [void]$body.Append((BulletPara $Matches[2] $lvl)); $i++; continue
  }

  [void]$body.Append((Para '' $t)); $i++
}

$sectPr = '<w:sectPr><w:pgSz w:w="' + $PAGE_W + '" w:h="' + $PAGE_H + '"/>' +
          '<w:pgMar w:top="' + $MARGIN + '" w:right="' + $MARGIN + '" w:bottom="' + $MARGIN +
          '" w:left="' + $MARGIN + '" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>'

$documentXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
  '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">' +
  '<w:body>' + $body.ToString() + $sectPr + '</w:body></w:document>'

# ---- styles --------------------------------------------------------------
$KFONT = 'Malgun Gothic'

# $outline: 0-9 emits w:outlineLvl, -1 means "no outline level".
# The param MUST be typed [int] - an untyped one binds "-1" as a string and
# "-1" -ge 0 does not behave numerically, which emitted an invalid
# <w:outlineLvl w:val="-1"/> and made Word reject the whole document.
function StyleDef([string]$id, [string]$name, [string]$rpr, [string]$ppr, [int]$outline = -1) {
  $s = '<w:style w:type="paragraph" w:styleId="' + $id + '"><w:name w:val="' + $name + '"/>' +
       '<w:basedOn w:val="Normal"/><w:qFormat/><w:pPr>' + $ppr
  if ($outline -ge 0 -and $outline -le 9) { $s += '<w:outlineLvl w:val="' + $outline + '"/>' }
  $s += '</w:pPr><w:rPr>' + $rpr + '</w:rPr></w:style>'
  return $s
}

$stylesXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
 '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">' +
 '<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="' + $KFONT + '" w:hAnsi="' + $KFONT +
 '" w:eastAsia="' + $KFONT + '" w:cs="' + $KFONT + '"/><w:color w:val="1A1A1A"/>' +
 '<w:sz w:val="21"/><w:szCs w:val="21"/></w:rPr></w:rPrDefault>' +
 '<w:pPrDefault><w:pPr><w:spacing w:after="100" w:line="288" w:lineRule="auto"/></w:pPr></w:pPrDefault>' +
 '</w:docDefaults>' +
 '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>' +
 (StyleDef 'Title' 'Title' '<w:b/><w:color w:val="14243F"/><w:sz w:val="38"/>' '<w:pBdr><w:bottom w:val="single" w:sz="18" w:space="4" w:color="14243F"/></w:pBdr><w:spacing w:after="160"/>' 0) +
 (StyleDef 'Heading1' 'heading 1' '<w:b/><w:color w:val="14243F"/><w:sz w:val="26"/>' '<w:pBdr><w:left w:val="single" w:sz="24" w:space="7" w:color="14243F"/></w:pBdr><w:spacing w:before="360" w:after="140"/><w:ind w:left="113"/>' 0) +
 (StyleDef 'Heading2' 'heading 2' '<w:b/><w:color w:val="33445F"/><w:sz w:val="22"/>' '<w:spacing w:before="240" w:after="100"/>' 1) +
 (StyleDef 'TableText' 'Table Text' '<w:sz w:val="19"/>' '<w:spacing w:after="0" w:line="264" w:lineRule="auto"/>' (-1)) +
 '<w:style w:type="paragraph" w:styleId="ListParagraph"><w:name w:val="List Paragraph"/>' +
 '<w:basedOn w:val="Normal"/><w:qFormat/><w:pPr><w:spacing w:after="60"/><w:contextualSpacing/></w:pPr></w:style>' +
 '</w:styles>'

# ---- numbering (bullets) -------------------------------------------------
function Lvl($i, $char, $indent) {
  return '<w:lvl w:ilvl="' + $i + '"><w:start w:val="1"/><w:numFmt w:val="bullet"/>' +
         '<w:lvlText w:val="' + $char + '"/><w:lvlJc w:val="left"/>' +
         '<w:pPr><w:ind w:left="' + $indent + '" w:hanging="227"/></w:pPr>' +
         '<w:rPr><w:rFonts w:ascii="Segoe UI Symbol" w:hAnsi="Segoe UI Symbol" w:hint="default"/></w:rPr></w:lvl>'
}

$numberingXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
 '<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">' +
 '<w:abstractNum w:abstractNumId="0"><w:multiLevelType w:val="hybridMultilevel"/>' +
 (Lvl 0 '&#8226;' 340) + (Lvl 1 '&#9702;' 680) + (Lvl 2 '&#8226;' 1020) +
 '</w:abstractNum><w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num></w:numbering>'

$contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
 '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
 '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
 '<Default Extension="xml" ContentType="application/xml"/>' +
 '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>' +
 '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>' +
 '<Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>' +
 '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>' +
 '</Types>'

$rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
 '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
 '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>' +
 '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>' +
 '</Relationships>'

$docRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
 '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
 '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>' +
 '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>' +
 '</Relationships>'

if (-not $Title) { $Title = [System.IO.Path]::GetFileNameWithoutExtension($Out) }
$now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$coreXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
 '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" ' +
 'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" ' +
 'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">' +
 '<dcterms:created xsi:type="dcterms:W3CDTF">' + $now + '</dcterms:created>' +
 '<dcterms:modified xsi:type="dcterms:W3CDTF">' + $now + '</dcterms:modified>' +
 '<dc:title>' + (Esc $Title) + '</dc:title>' +
 '</cp:coreProperties>'

# ---- package -------------------------------------------------------------
# Entries are created by hand: ZipFile.CreateFromDirectory stores Windows
# backslashes in entry names, which Word rejects. OPC requires '/'.
$enc = New-Object System.Text.UTF8Encoding($false)
$parts = [ordered]@{
  '[Content_Types].xml'            = $contentTypes
  '_rels/.rels'                    = $rootRels
  'docProps/core.xml'              = $coreXml
  'word/document.xml'              = $documentXml
  'word/styles.xml'                = $stylesXml
  'word/numbering.xml'             = $numberingXml
  'word/_rels/document.xml.rels'   = $docRels
}

if (Test-Path $Out) { Remove-Item $Out -Force }
$fs = [System.IO.File]::Open($Out, [System.IO.FileMode]::Create)
$zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
foreach ($name in $parts.Keys) {
  $entry = $zip.CreateEntry($name, [System.IO.Compression.CompressionLevel]::Optimal)
  $es = $entry.Open()
  $bytes = $enc.GetBytes($parts[$name])
  $es.Write($bytes, 0, $bytes.Length)
  $es.Close()
}
$zip.Dispose()
$fs.Close()
Write-Output ("OK  {0}  ({1:N0} bytes)" -f (Split-Path $Out -Leaf), (Get-Item $Out).Length)
