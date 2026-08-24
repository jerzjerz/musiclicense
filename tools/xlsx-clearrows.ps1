# Turn a filled workbook back into a blank template: drop every row after the
# header. sharedStrings is left untouched on purpose -- the _easeflow_import_info_
# token lives there and the hidden sheet references it by index.
param([Parameter(Mandatory=$true)][string]$In,
      [Parameter(Mandatory=$true)][string]$Out,
      [Parameter(Mandatory=$true)][string]$LastCol)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

Copy-Item -LiteralPath $In -Destination $Out -Force
$zip = [System.IO.Compression.ZipFile]::Open((Resolve-Path -LiteralPath $Out).Path, 'Update')
try {
    $e  = $zip.Entries | Where-Object { $_.FullName -eq 'xl/worksheets/sheet1.xml' }
    $sr = New-Object System.IO.StreamReader($e.Open(), [System.Text.Encoding]::UTF8)
    $xml = $sr.ReadToEnd(); $sr.Close()

    $before = ([regex]::Matches($xml, '<row ')).Count
    $xml = [regex]::Replace($xml, '(?s)<row r="(?!1")[0-9]+"[^>]*>.*?</row>', '')
    $dimRef = "A1:" + $LastCol + "1"
    $xml = [regex]::Replace($xml, '<dimension ref="[^"]*"\s*/>', "<dimension ref=`"$dimRef`"/>")
    $after = ([regex]::Matches($xml, '<row ')).Count

    $e.Delete()
    $n  = $zip.CreateEntry('xl/worksheets/sheet1.xml', [System.IO.Compression.CompressionLevel]::Optimal)
    $sw = New-Object System.IO.StreamWriter($n.Open(), (New-Object System.Text.UTF8Encoding($false)))
    $sw.Write($xml); $sw.Close()
    Write-Host ("stripped {0} -> {1} row(s), dimension {2}" -f $before, $after, $dimRef)
} finally { $zip.Dispose() }
