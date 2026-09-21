# Extract text from a PDF that uses a NON-embedded CJK font via a UniXX-UCS2/UTF16 CMap
# (e.g. /STSong-Light or /Heiti with /Encoding /UniGB-UCS2-H or /UniGB-UTF16-H -- what
# HTML-to-PDF exporters emit for Chinese when they do not subset a font).
#
# Why this exists: poppler's pdftotext needs the Adobe CMap files for these encodings
# (poppler-data), which this PC does not have -- it prints
#   "Couldn't find 'UniGB-UCS2-H' CMap file for 'Adobe-GB1' collection"
# and drops every Chinese run. But these CMaps map Unicode code points to CIDs, so the
# bytes in the content stream ARE UTF-16BE: decoding them needs no CMap at all.
#
# Latin runs are printed too, but if the Latin fonts are embedded Identity-H subsets
# their bytes are glyph ids, not text -- garbage here, while plain `pdftotext` reads
# them fine via /ToUnicode. So: pdftotext for the Latin half, this tool for the CJK half.
#
# Sibling tools: pdftext.ps1 (embedded Identity-H subsets -- needs the /ToUnicode CMap),
# pdfrender.ps1 (image-only PDFs -- rasterize, then OCR).
#
# usage: pdfcjktext.ps1 -Pdf <file.pdf> [-Out <out.txt>] [-CjkFont F4] [-ShowFont]
#   -CjkFont   resource name of the CJK font as it appears in the content stream, e.g.
#              F4 or china-s. Find it in the page's /Font dict: the key whose object
#              has the CJK /BaseFont. Run once with -ShowFont to list what got used.
#   -ShowFont  prefix every line with the font that drew it (use this to find -CjkFont).

param([Parameter(Mandatory=$true)][string]$Pdf,
      [string]$Out = '',
      [string]$CjkFont = 'F4',
      [switch]$ShowFont)
$ErrorActionPreference = 'Stop'

$Pdf = (Resolve-Path -LiteralPath $Pdf).Path
if ($Out -eq '') { $Out = [IO.Path]::ChangeExtension($Pdf, '.cjk.txt') }

$bytes = [IO.File]::ReadAllBytes($Pdf)
$latin = [Text.Encoding]::GetEncoding(28591)   # byte-preserving: 1 char == 1 byte
$u16   = [Text.Encoding]::BigEndianUnicode
$s     = $latin.GetString($bytes)
$sb    = New-Object Text.StringBuilder

function Inflate([byte[]]$buf, [int]$off, [int]$len) {
    # Returns $null for a stream that is not deflate (already-plain content streams).
    # The bytes between the deflate data and `endstream` make DeflateStream throw on
    # the final read -- that is expected, keep whatever decoded before the throw.
    foreach ($skip in @(2, 0)) {               # zlib header first, then raw deflate
        $out = [IO.MemoryStream]::new()
        try {
            # ::new() on purpose -- New-Object unrolls the byte[] into separate arguments
            $ms  = [IO.MemoryStream]::new($buf, $off + $skip, $len - $skip)
            $ds  = [IO.Compression.DeflateStream]::new($ms, [IO.Compression.CompressionMode]::Decompress)
            $tmp = New-Object byte[] 8192
            while ($true) {
                $n = $ds.Read($tmp, 0, $tmp.Length)
                if ($n -le 0) { break }
                $out.Write($tmp, 0, $n)
            }
        } catch { }
        if ($out.Length -gt 0) { return $out.ToArray() }
    }
    return $null
}

# A PDF literal string is bytes, not text: undo the escapes and hand back raw bytes.
function LitBytes([string]$lit) {
    $out = New-Object Collections.Generic.List[byte]
    $i = 0
    while ($i -lt $lit.Length) {
        if ([int]$lit[$i] -eq 92) {            # backslash
            $i++
            if ($i -ge $lit.Length) { break }
            $n = $lit[$i]
            if ($n -ge '0' -and $n -le '7') {  # \ddd octal, up to 3 digits
                $oct = ''
                while ($i -lt $lit.Length -and $lit[$i] -ge '0' -and $lit[$i] -le '7' -and $oct.Length -lt 3) {
                    $oct += $lit[$i]; $i++
                }
                $out.Add([byte]([Convert]::ToInt32($oct, 8)))
                continue
            }
            switch ($n) {
                'n' { $out.Add(10) } 'r' { $out.Add(13) } 't' { $out.Add(9) }
                'b' { $out.Add(8) }  'f' { $out.Add(12) }
                default { $out.Add([byte][int][char]$n) }   # \( \) \\ -> the char itself
            }
            $i++
        } else {
            $out.Add([byte][int][char]$lit[$i]); $i++
        }
    }
    ,$out.ToArray()
}

function HexBytes([string]$h) {
    $h = $h -replace '[^0-9A-Fa-f]', ''
    if ($h.Length -eq 0) { return ,(New-Object byte[] 0) }
    if ($h.Length % 2 -ne 0) { $h += '0' }     # PDF pads a trailing nibble with 0
    $out = New-Object byte[] ($h.Length / 2)
    for ($i = 0; $i -lt $h.Length; $i += 2) { $out[$i / 2] = [Convert]::ToInt32($h.Substring($i, 2), 16) }
    ,$out
}

# Built from char codes on purpose: a literal '\\' in the pattern is one backslash too
# many/few depending on how this file was written, and that bug is silent (the regex
# still compiles, it just never matches the escaped-paren case).
$B   = [string][char]92
$B2  = $B + $B
$lit = $B + '(' + '((?:' + $B2 + '.|[^' + $B2 + ')])*)' + $B + ')'
$pat = '/([\w\-]+)\s+[\d\.]+\s+Tf' + '|' + $lit + '\s*Tj' +
       '|<([0-9A-Fa-f\s]+)>\s*Tj' + '|\[((?:[^\[\]])*)\]\s*TJ'
$re     = [regex]$pat
$reItem = [regex]($lit + '|<([0-9A-Fa-f\s]+)>')

$idx = 0; $streams = 0
while ($true) {
    $i = $s.IndexOf('stream', $idx); if ($i -lt 0) { break }
    $j = $i + 6
    if ($j -lt $s.Length -and $s[$j] -eq "`r") { $j++ }
    if ($j -lt $s.Length -and $s[$j] -eq "`n") { $j++ }
    $k = $s.IndexOf('endstream', $j); if ($k -lt 0) { break }
    $idx = $k + 9
    $len = $k - $j
    if ($len -le 2) { continue }

    $raw = Inflate $bytes $j $len
    if ($null -ne $raw) { $txt = $latin.GetString($raw) }
    else                { $txt = $s.Substring($j, $len) }   # uncompressed content stream
    if ($txt.IndexOf(' Tj') -lt 0 -and $txt.IndexOf('TJ') -lt 0) { continue }
    $streams++

    $font = ''
    foreach ($m in $re.Matches($txt)) {
        if ($m.Groups[1].Success) { $font = $m.Groups[1].Value; continue }
        $parts = New-Object Collections.Generic.List[byte]
        if ($m.Groups[2].Success)     { $parts.AddRange((LitBytes $m.Groups[2].Value)) }
        elseif ($m.Groups[3].Success) { $parts.AddRange((HexBytes $m.Groups[3].Value)) }
        elseif ($m.Groups[4].Success) {
            foreach ($mm in $reItem.Matches($m.Groups[4].Value)) {
                if ($mm.Groups[1].Success) { $parts.AddRange((LitBytes $mm.Groups[1].Value)) }
                else                       { $parts.AddRange((HexBytes $mm.Groups[2].Value)) }
            }
        }
        if ($parts.Count -eq 0) { continue }
        $arr = $parts.ToArray()
        if ($font -eq $CjkFont) { $line = $u16.GetString($arr) } else { $line = $latin.GetString($arr) }
        if ($line.Trim() -eq '') { continue }
        if ($ShowFont) { [void]$sb.AppendLine('[' + $font + '] ' + $line) }
        elseif ($font -eq $CjkFont) { [void]$sb.AppendLine($line) }
    }
}

[IO.File]::WriteAllText($Out, $sb.ToString(), (New-Object Text.UTF8Encoding($true)))
Write-Host ("streams with text: " + $streams + " -> " + $Out)
if (-not $ShowFont) { Write-Host ("  (only /" + $CjkFont + " runs; re-run with -ShowFont to see every font)") }
