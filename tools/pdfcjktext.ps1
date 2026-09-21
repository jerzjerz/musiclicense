# Extract text from a PDF that uses a NON-embedded CJK font via a UniXX-UCS2-H CMap
# (e.g. /STSong-Light with /Encoding /UniGB-UCS2-H -- what HTML-to-PDF exporters emit
# for Chinese when they do not subset a font).
#
# Why this exists: poppler's pdftotext needs the Adobe CMap files for these encodings
# (poppler-data), which this PC does not have -- it prints
#   "Couldn't find 'UniGB-UCS2-H' CMap file for 'Adobe-GB1' collection"
# and drops every Chinese run. But UCS2 CMaps map Unicode code points to CIDs, so the
# bytes in the content stream ARE UTF-16BE: decoding them needs no CMap at all.
#
# Sibling tools: pdftext.ps1 (embedded Identity-H CID subsets -- needs the /ToUnicode
# CMap), pdfrender.ps1 (image-only PDFs -- rasterize, then OCR).
#
# usage: pdfcjktext.ps1 -Pdf <file.pdf> [-Out <out.txt>] [-CjkFont F4] [-PageMark '<regex>']
#   -CjkFont   resource name of the CJK font, as it appears in the content stream.
#              Find it with: the /Font dict entry whose /BaseFont is the CJK face.
#   -PageMark  regex matching a per-page footer string; each hit starts a new
#              "PAGE n" block in the output (content streams are not in page order).

param([Parameter(Mandatory=$true)][string]$Pdf,
      [string]$Out = '',
      [string]$CjkFont = 'F4',
      [string]$PageMark = '')
$ErrorActionPreference = 'Stop'

$Pdf   = (Resolve-Path -LiteralPath $Pdf).Path
if ($Out -eq '') { $Out = [IO.Path]::ChangeExtension($Pdf, '.txt') }

$bytes = [IO.File]::ReadAllBytes($Pdf)
$latin = [Text.Encoding]::GetEncoding(28591)   # byte-preserving: 1 char == 1 byte
$u16   = [Text.Encoding]::BigEndianUnicode
$s     = $latin.GetString($bytes)
$sb    = New-Object Text.StringBuilder

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

# Built from char codes on purpose: a literal '\\' in the pattern is one backslash too
# many/few depending on how this file was written, and that bug is silent (the regex
# still compiles, it just never matches the escaped-paren case).
$B   = [string][char]92
$B2  = $B + $B
$pat = '/(F[\w\-]+)\s+[\d\.]+\s+Tf' + '|' + $B + '(' + '((?:' + $B2 + '.|[^' + $B2 + ')])*)' + $B + ')\s*Tj'
$re  = [regex]$pat

# Content streams here are uncompressed; for a FlateDecode file, inflate first
# (see Inflate() in pdftext.ps1) and run this regex over the inflated text.
$font  = ''
$pages = 0
foreach ($m in $re.Matches($s)) {
    if ($m.Groups[1].Success) { $font = $m.Groups[1].Value; continue }
    $b = LitBytes $m.Groups[2].Value
    if ($font -eq $CjkFont) { $line = $u16.GetString($b) } else { $line = $latin.GetString($b) }
    if ($PageMark -ne '' -and $line -match $PageMark) {
        $pages++
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine("########## PAGE $pages ##########")
    } else {
        [void]$sb.AppendLine($line)
    }
}

[IO.File]::WriteAllText($Out, $sb.ToString(), (New-Object Text.UTF8Encoding($true)))
Write-Host "-> $Out"
if ($PageMark -ne '') { Write-Host "   pages marked: $pages" }
