# Render PDF pages to PNG using the Windows built-in PDF rasterizer (Windows.Data.Pdf).
# This PC has no poppler/pdftoppm and no Python, but Windows 10/11 ships a PDF
# renderer in WinRT -- reachable from PowerShell via the WinRT projection.
#
# usage: pdfrender.ps1 -Pdf <file.pdf> -OutDir <dir> [-Width 1600] [-Pages "1,2"]

param([Parameter(Mandatory=$true)][string]$Pdf,
      [Parameter(Mandatory=$true)][string]$OutDir,
      [int]$Width = 1600,
      [string]$Pages = '')
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Runtime.WindowsRuntime
$rtExt = [System.WindowsRuntimeSystemExtensions]

# AsTask has three overloads; pick the IAsyncOperation<T> one (returns a value)
# and the IAsyncAction one (returns nothing) separately.
$asTaskOp = ($rtExt.GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
$asTaskAct = ($rtExt.GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction' })[0]

function Await($op, $type) {
    $t = $asTaskOp.MakeGenericMethod($type).Invoke($null, @($op))
    $t.Wait(-1) | Out-Null
    $t.Result
}
function AwaitAction($act) {
    $t = $asTaskAct.Invoke($null, @($act))
    $t.Wait(-1) | Out-Null
}

# force the WinRT type projections to load
[Windows.Storage.StorageFile,   Windows.Storage,  ContentType=WindowsRuntime] | Out-Null
[Windows.Storage.StorageFolder, Windows.Storage,  ContentType=WindowsRuntime] | Out-Null
[Windows.Data.Pdf.PdfDocument,  Windows.Data.Pdf, ContentType=WindowsRuntime] | Out-Null

$Pdf    = (Resolve-Path -LiteralPath $Pdf).Path
if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$OutDir = (Resolve-Path -LiteralPath $OutDir).Path

$srcFile = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($Pdf))    ([Windows.Storage.StorageFile])
$doc     = Await ([Windows.Data.Pdf.PdfDocument]::LoadFromFileAsync($srcFile))  ([Windows.Data.Pdf.PdfDocument])
$folder  = Await ([Windows.Storage.StorageFolder]::GetFolderFromPathAsync($OutDir)) ([Windows.Storage.StorageFolder])

$base = [System.IO.Path]::GetFileNameWithoutExtension($Pdf)
$want = if ($Pages) { $Pages -split ',' | ForEach-Object { [int]$_.Trim() } } else { 1..$doc.PageCount }

Write-Host ("$base : $($doc.PageCount) page(s)")
foreach ($p in $want) {
    if ($p -lt 1 -or $p -gt $doc.PageCount) { continue }
    $page = $doc.GetPage($p - 1)
    $name = "{0}_p{1:00}.png" -f $base, $p
    $dest = Await ($folder.CreateFileAsync($name, [Windows.Storage.CreationCollisionOption]::ReplaceExisting)) ([Windows.Storage.StorageFile])
    $stream = Await ($dest.OpenAsync([Windows.Storage.FileAccessMode]::ReadWrite)) ([Windows.Storage.Streams.IRandomAccessStream])
    $opts = New-Object Windows.Data.Pdf.PdfPageRenderOptions
    $opts.DestinationWidth = [uint32]$Width
    AwaitAction ($page.RenderToStreamAsync($stream, $opts))
    $stream.Dispose()
    $page.Dispose()
    Write-Host ("  -> {0}" -f (Join-Path $OutDir $name))
}
$doc = $null
