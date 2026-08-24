# Inject data rows into a blank NetEase OA travel-expense template.
#
# The template must NOT be rebuilt from scratch: its hidden _easeflow_import_info_
# sheet carries the token that tells the importer which form this is. So we copy
# the master and patch only xl/worksheets/sheet1.xml inside the zip.
#
# Values are written as inline strings (t="inlineStr") because that is what the
# server's own generator uses for the header row -- same shape, no sharedStrings.
# An empty field in the TSV means "omit the cell entirely" (decision D10: the
# person-name columns must be absent, not blank).
#
# usage: buildxlsx.ps1 -Master <blank.xlsx> -Out <out.xlsx> -Tsv <rows.tsv>

param([Parameter(Mandatory=$true)][string]$Master,
      [Parameter(Mandatory=$true)][string]$Out,
      [Parameter(Mandatory=$true)][string]$Tsv)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function XmlEsc([string]$s) {
    $s.Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;').Replace('"','&quot;')
}
function ColName([int]$i) {   # 1 -> A
    [char](64 + $i)
}

$rows = @()
foreach ($line in [System.IO.File]::ReadAllLines($Tsv, [System.Text.Encoding]::UTF8)) {
    if ($line.Trim() -eq '' -or $line.StartsWith('#')) { continue }
    $rows += ,($line -split "`t")
}
if ($rows.Count -eq 0) { throw "no data rows in $Tsv" }
$nCols = ($rows | ForEach-Object { $_.Count } | Measure-Object -Maximum).Maximum

Copy-Item -LiteralPath $Master -Destination $Out -Force
$zip = [System.IO.Compression.ZipFile]::Open((Resolve-Path -LiteralPath $Out).Path, 'Update')
try {
    $entry = $zip.Entries | Where-Object { $_.FullName -eq 'xl/worksheets/sheet1.xml' }
    if (-not $entry) { throw "sheet1.xml not found in $Out" }

    $sr = New-Object System.IO.StreamReader($entry.Open(), [System.Text.Encoding]::UTF8)
    $xml = $sr.ReadToEnd(); $sr.Close()

    $sb = New-Object System.Text.StringBuilder
    $r = 1
    foreach ($cells in $rows) {
        $r++
        [void]$sb.Append("<row r=""$r"">")
        for ($c = 1; $c -le $nCols; $c++) {
            $v = if ($c -le $cells.Count) { $cells[$c-1] } else { '' }
            if ($v -eq '') { continue }          # omit the cell entirely (D10)
            $ref = "$(ColName $c)$r"
            [void]$sb.Append("<c r=""$ref"" s=""$c"" t=""inlineStr""><is><t>$(XmlEsc $v)</t></is></c>")
        }
        [void]$sb.Append("</row>")
    }

    $lastRef = "A1:$(ColName $nCols)$r"
    $xml = [regex]::Replace($xml, '<dimension ref="[^"]*"\s*/>', "<dimension ref=""$lastRef""/>")
    $xml = $xml -replace '</sheetData>', ($sb.ToString() + '</sheetData>')

    $entry.Delete()
    $new = $zip.CreateEntry('xl/worksheets/sheet1.xml', [System.IO.Compression.CompressionLevel]::Optimal)
    $sw = New-Object System.IO.StreamWriter($new.Open(), (New-Object System.Text.UTF8Encoding($false)))
    $sw.Write($xml); $sw.Close()
} finally { $zip.Dispose() }

Write-Host ("{0}  <- {1} data row(s), {2} col(s)" -f (Split-Path -Leaf $Out), $rows.Count, $nCols)
