# Split a PDFium-produced, one-full-page-image-per-page PDF into single-page PDFs.
#
# The source has a plain (non-stream) xref and a flat 4-objects-per-page layout:
#   page N -> /Contents N+1, /Resources N+2 -> /XObject /Im1 N+3 (the image).
# So each output only needs those objects, renumbered 1..6, with the content and
# image streams copied byte-for-byte (no re-encode, no quality loss).
#
# usage: split.ps1 -Pdf <src> -Map <csv: pageNo,relativeOutPath> -OutRoot <dir>

param([Parameter(Mandatory=$true)][string]$Pdf,
      [Parameter(Mandatory=$true)][string]$Map,
      [Parameter(Mandatory=$true)][string]$OutRoot)
$ErrorActionPreference = 'Stop'

$bytes = [System.IO.File]::ReadAllBytes($Pdf)
$latin = [System.Text.Encoding]::GetEncoding(28591).GetString($bytes)
$ascii = [System.Text.Encoding]::ASCII

function Find-Obj([int]$num) {
    $pat = "`n$num 0 obj"
    $i = $latin.IndexOf($pat)
    if ($i -lt 0) { throw "obj $num not found" }
    return $i + $pat.Length
}

# Returns the dict text (verbatim, incl. leading EOL) and the raw stream extent.
function Get-StreamObj([int]$num) {
    $i = Find-Obj $num
    $e = $latin.IndexOf('stream', $i)
    if ($e -lt 0) { throw "no stream in obj $num" }
    $dict = $latin.Substring($i, $e - $i)
    $d = $e + 6
    if ($latin[$d] -eq "`r") { $d++ }
    if ($latin[$d] -eq "`n") { $d++ }
    $len = [int]([regex]::Match($dict, '/Length\s+(\d+)').Groups[1].Value)
    [pscustomobject]@{ Dict = $dict; Start = $d; Length = $len }
}

function Get-PlainObj([int]$num) {
    $i = Find-Obj $num
    $e = $latin.IndexOf('endobj', $i)
    return $latin.Substring($i, $e - $i).Trim()
}

$pageObjs = 4,8,12,16,20,24,28,32,36,40

$rows = Get-Content -LiteralPath $Map | Where-Object { $_.Trim() -ne '' }
foreach ($row in $rows) {
    $parts = $row -split ',', 2
    $pageNo = [int]$parts[0].Trim()
    $rel    = $parts[1].Trim()

    $pnum = $pageObjs[$pageNo - 1]
    $pageDict = Get-PlainObj $pnum
    $mb = [regex]::Match($pageDict, '/MediaBox\s*\[([^\]]*)\]').Groups[1].Value.Trim()
    $contents = Get-StreamObj ($pnum + 1)
    $resDict  = Get-PlainObj  ($pnum + 2)
    $imgName  = [regex]::Match($resDict, '/XObject\s*<<\s*/(\w+)').Groups[1].Value
    $image    = Get-StreamObj ($pnum + 3)

    $ms = [System.IO.MemoryStream]::new()
    $offsets = @{}
    function Put([string]$s) { $b = $ascii.GetBytes($s); $ms.Write($b, 0, $b.Length) }
    function PutRaw([int]$off, [int]$len) { $ms.Write($bytes, $off, $len) }
    function Mark([int]$n) { $offsets[$n] = [int]$ms.Position }

    Put "%PDF-1.7`r`n"
    $ms.Write([byte[]](0x25,0xA1,0xB3,0xC5,0xD7,0x0D,0x0A), 0, 7)   # %<binary> marker

    Mark 1; Put "1 0 obj`r`n<</Pages 2 0 R /Type/Catalog>>`r`nendobj`r`n"
    Mark 2; Put "2 0 obj`r`n<</Count 1/Kids[ 3 0 R ]/Type/Pages>>`r`nendobj`r`n"
    Mark 3; Put ("3 0 obj`r`n<</Contents 4 0 R /MediaBox[ {0}]/Parent 2 0 R /Resources 5 0 R /Type/Page>>`r`nendobj`r`n" -f $mb)

    Mark 4
    Put "4 0 obj"; Put $contents.Dict; Put "stream`r`n"
    PutRaw $contents.Start $contents.Length
    Put "`r`nendstream`r`nendobj`r`n"

    Mark 5; Put ("5 0 obj`r`n<</XObject<</{0} 6 0 R >>>>`r`nendobj`r`n" -f $imgName)

    Mark 6
    Put "6 0 obj"; Put $image.Dict; Put "stream`r`n"
    PutRaw $image.Start $image.Length
    Put "`r`nendstream`r`nendobj`r`n"

    $xref = [int]$ms.Position
    Put "xref`r`n0 7`r`n"
    Put "0000000000 65535 f `r`n"
    for ($n = 1; $n -le 6; $n++) { Put ("{0:D10} 00000 n `r`n" -f $offsets[$n]) }
    Put "trailer`r`n<</Root 1 0 R /Size 7>>`r`nstartxref`r`n$xref`r`n%%EOF`r`n"

    $out = Join-Path $OutRoot $rel
    $dir = Split-Path -Parent $out
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllBytes($out, $ms.ToArray())
    $ms.Dispose()
    $kb = [math]::Round((Get-Item -LiteralPath $out).Length / 1KB)
    Write-Host ("p{0:00} -> {1}  ({2} KB, MediaBox {3})" -f $pageNo, $rel, $kb, $mb)
}
