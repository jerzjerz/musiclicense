# Extract text from a PDF whose fonts are Identity-H CID subsets.
#
# Word/Edge both fail on these files: the glyph ids mean nothing without the
# font's /ToUnicode CMap. But the CMap is embedded, so we can do the mapping
# ourselves -- inflate every stream, read the CMap, then walk the content
# stream's show-text operators and translate each 2-byte code.
#
# usage: pdftext.ps1 <file.pdf>

param([Parameter(Mandatory=$true)][string]$Path)
$ErrorActionPreference = 'Stop'

$bytes = [System.IO.File]::ReadAllBytes($Path)
$latin = [System.Text.Encoding]::GetEncoding(28591).GetString($bytes)

function Inflate([byte[]]$buf, [int]$off, [int]$len) {
    # NOTE: the bytes between the end of the deflate data and the `endstream`
    # keyword make DeflateStream throw on the final read. That is expected --
    # keep whatever was decoded before the throw instead of discarding it.
    foreach ($skip in @(2,0)) {          # try zlib header first, then raw deflate
        $out = [System.IO.MemoryStream]::new()
        try {
            # ::new() -- New-Object unrolls the byte[] into separate arguments
            $ms  = [System.IO.MemoryStream]::new($buf, $off + $skip, $len - $skip)
            $ds  = [System.IO.Compression.DeflateStream]::new($ms, [System.IO.Compression.CompressionMode]::Decompress)
            $tmp = New-Object byte[] 8192
            while ($true) {
                $n = $ds.Read($tmp, 0, $tmp.Length)
                if ($n -le 0) { break }
                $out.Write($tmp, 0, $n)
            }
            $ds.Dispose()
        } catch { }
        if ($out.Length -gt 0) { return $out.ToArray() }
    }
    return $null
}

# --- collect every stream object ------------------------------------------
$blobs = @()
$i = 0
while (($s = $latin.IndexOf('stream', $i)) -ge 0) {
    if ($s -ge 3 -and $latin.Substring($s - 3, 3) -eq 'end') { $i = $s + 6; continue }
    $d = $s + 6
    if ($d -lt $latin.Length -and $latin[$d] -eq "`r") { $d++ }
    if ($d -lt $latin.Length -and $latin[$d] -eq "`n") { $d++ }
    $e = $latin.IndexOf('endstream', $d)
    if ($e -lt 0) { break }
    $inf = Inflate $bytes $d ($e - $d)
    if ($inf) { $blobs += ,$inf }
    $i = $e + 9
}

# --- build the CID -> unicode map from any /ToUnicode CMap ----------------
$map = @{}
foreach ($b in $blobs) {
    $t = [System.Text.Encoding]::GetEncoding(28591).GetString($b)
    if ($t -notmatch 'beginbfchar|beginbfrange') { continue }

    foreach ($m in [regex]::Matches($t, '(?s)beginbfchar(.*?)endbfchar')) {
        foreach ($p in [regex]::Matches($m.Groups[1].Value, '<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>')) {
            $src = [Convert]::ToInt32($p.Groups[1].Value, 16)
            $dstHex = $p.Groups[2].Value
            $sb = New-Object System.Text.StringBuilder
            for ($k = 0; $k + 4 -le $dstHex.Length; $k += 4) {
                [void]$sb.Append([char][Convert]::ToInt32($dstHex.Substring($k,4),16))
            }
            $map[$src] = $sb.ToString()
        }
    }
    foreach ($m in [regex]::Matches($t, '(?s)beginbfrange(.*?)endbfrange')) {
        foreach ($p in [regex]::Matches($m.Groups[1].Value, '<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>')) {
            $lo  = [Convert]::ToInt32($p.Groups[1].Value,16)
            $hi  = [Convert]::ToInt32($p.Groups[2].Value,16)
            $dst = [Convert]::ToInt32($p.Groups[3].Value,16)
            for ($c = $lo; $c -le $hi -and ($c - $lo) -lt 65535; $c++) { $map[$c] = [string][char]($dst + $c - $lo) }
        }
    }
}
Write-Output ("[cmap entries: {0}]" -f $map.Count)

# --- decode the show-text operators in the content streams ----------------
foreach ($b in $blobs) {
    $t = [System.Text.Encoding]::GetEncoding(28591).GetString($b)
    if ($t -notmatch '\bTJ\b|\bTj\b') { continue }

    $line = New-Object System.Text.StringBuilder
    # show-text operands come as hex <..> OR as literal (..) strings holding
    # raw 2-byte CIDs; PDFium emits the numbers as literals, so handle both.
    $pat = '(?s)(\[(?:\\.|[^\]\\])*\]\s*TJ)|(<[0-9A-Fa-f]+>\s*Tj)|(\((?:\\.|[^()\\])*\)\s*Tj)|(\bTd\b)|(\bTD\b)|(\bT\*\b)|(\bET\b)'
    foreach ($op in [regex]::Matches($t, $pat)) {
        $v = $op.Value
        if ($v -match '^(Td|TD|T\*|ET)$') {
            if ($line.Length -gt 0) { Write-Output $line.ToString(); [void]$line.Clear() }
            continue
        }
        foreach ($tok in [regex]::Matches($v, '(?s)<([0-9A-Fa-f]+)>|\((?:\\.|[^()\\])*\)')) {
            $codes = New-Object System.Collections.Generic.List[int]
            if ($tok.Value.StartsWith('<')) {
                $hex = $tok.Groups[1].Value
                for ($k = 0; $k + 4 -le $hex.Length; $k += 4) { $codes.Add([Convert]::ToInt32($hex.Substring($k,4),16)) }
            } else {
                $s = $tok.Value.Substring(1, $tok.Value.Length - 2)
                $raw = New-Object System.Collections.Generic.List[int]
                $k = 0
                while ($k -lt $s.Length) {
                    if ($s[$k] -eq '\') {
                        $k++
                        if ($k -ge $s.Length) { break }
                        $c = $s[$k]
                        if ($c -ge '0' -and $c -le '7') {
                            $oct = ''
                            while ($k -lt $s.Length -and $oct.Length -lt 3 -and $s[$k] -ge '0' -and $s[$k] -le '7') { $oct += $s[$k]; $k++ }
                            $raw.Add([Convert]::ToInt32($oct,8))
                            continue
                        }
                        switch ($c) {
                            'n' { $raw.Add(10) } 'r' { $raw.Add(13) } 't' { $raw.Add(9) }
                            'b' { $raw.Add(8) }  'f' { $raw.Add(12) }
                            default { $raw.Add([int][char]$c) }
                        }
                        $k++
                    } else { $raw.Add([int][char]$s[$k]); $k++ }
                }
                for ($k = 0; $k + 1 -lt $raw.Count; $k += 2) { $codes.Add($raw[$k] * 256 + $raw[$k+1]) }
            }
            foreach ($cid in $codes) {
                if ($map.ContainsKey($cid)) { [void]$line.Append($map[$cid]) } else { [void]$line.Append('?') }
            }
        }
    }
    if ($line.Length -gt 0) { Write-Output $line.ToString() }
}
