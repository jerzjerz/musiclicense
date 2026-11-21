# Pull the original images out of a PDF and record where each one sits on its page.
#
# Why: a deck that arrives as PDF only (HTML/Keynote source not available) can be
# rebuilt as HTML if we have (a) the embedded images at full resolution and (b) the
# box each image is drawn in. pdfrender.ps1 only gives flattened page bitmaps.
#
# What it does: walks the page tree, interprets each content stream (q/Q/cm/re/W/Do,
# recursing into Form XObjects), and for every image `Do` computes the image box and
# the visible box after clipping. JPEG streams (DCTDecode) are written byte-for-byte;
# Flate RGB(+SMask) images are rebuilt as PNG with alpha.
#
# Output: <OutDir>\img\objNNN.jpg|png  and  <OutDir>\placements.tsv
#   page, name, obj, file, imgW, imgH, vis X/Y/W/H, box X/Y/W/H
#   -- coordinates are top-left origin, scaled so the page is -CssWidth px wide.
#   box == vis      -> the image is shown whole
#   box larger      -> cropped (object-fit: cover); (vis-box)/(boxSize-visSize) = position
#
# Tested on Chrome/Skia-printed decks (PDF 1.4, no object streams).
#
# usage: pdfimages.ps1 -Pdf <file.pdf> -OutDir <dir> [-CssWidth 1920]
param([Parameter(Mandatory=$true)][string]$Pdf,
      [Parameter(Mandatory=$true)][string]$OutDir,
      [double]$CssWidth = 1920)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
# pixel repacking in a PowerShell loop takes minutes per megapixel -> do it in C#
Add-Type -TypeDefinition @"
public static class PdfPix {
    public static byte[] ToBgra(byte[] raw, byte[] alpha, int w, int h, int nc, int stride) {
        byte[] buf = new byte[stride * h];
        for (int y = 0; y < h; y++) {
            int ro = y * w * nc, bo = y * stride;
            for (int x = 0; x < w; x++) {
                int si = ro + x * nc, di = bo + x * 4;
                if (nc == 1) { buf[di] = raw[si]; buf[di + 1] = raw[si]; buf[di + 2] = raw[si]; }
                else { buf[di] = raw[si + 2]; buf[di + 1] = raw[si + 1]; buf[di + 2] = raw[si]; }
                buf[di + 3] = (alpha != null) ? alpha[y * w + x] : (byte)255;
            }
        }
        return buf;
    }
}
"@

$bytes = [IO.File]::ReadAllBytes($Pdf)
$latin = [Text.Encoding]::GetEncoding(28591)
$s = $latin.GetString($bytes)
New-Item -ItemType Directory -Force $OutDir | Out-Null
$imgDir = Join-Path $OutDir 'img'
New-Item -ItemType Directory -Force $imgDir | Out-Null

function Inflate([byte[]]$buf, [int]$off, [int]$len) {
    foreach ($skip in @(2, 0)) {
        $out = [IO.MemoryStream]::new()
        try {
            $ms = [IO.MemoryStream]::new($buf, $off + $skip, $len - $skip)
            $ds = [IO.Compression.DeflateStream]::new($ms, [IO.Compression.CompressionMode]::Decompress)
            $tmp = New-Object byte[] 65536
            while ($true) { $n = $ds.Read($tmp, 0, $tmp.Length); if ($n -le 0) { break }; $out.Write($tmp, 0, $n) }
        } catch { }
        if ($out.Length -gt 0) { return $out.ToArray() }
    }
    return [byte[]]@()
}

# ---- object access -------------------------------------------------------
$objCache = @{}
function Get-Obj([int]$n) {
    if ($objCache.ContainsKey($n)) { return $objCache[$n] }
    $m = [regex]::Match($s, "(?<![0-9])$n 0 obj\s*")
    if (-not $m.Success) { return $null }
    $i = $m.Index + $m.Length
    $r = @{ num = $n; dict = ''; body = ''; streamOff = -1; streamLen = 0 }
    if ($s[$i] -eq '<' -and $s[$i + 1] -eq '<') {
        $depth = 0; $j = $i
        while ($j -lt $s.Length) {
            if ($s[$j] -eq '<' -and $s[$j + 1] -eq '<') { $depth++; $j += 2; continue }
            if ($s[$j] -eq '>' -and $s[$j + 1] -eq '>') { $depth--; $j += 2; if ($depth -eq 0) { break }; continue }
            $j++
        }
        $r.dict = $s.Substring($i, $j - $i)
        $sm = [regex]::Match($s.Substring($j, [Math]::Min(20, $s.Length - $j)), '^\s*stream(\r\n|\n)')
        if ($sm.Success) {
            $r.streamOff = $j + $sm.Length
            $lm = [regex]::Match($r.dict, '/Length\s+(\d+)(\s+0\s+R)?')
            if ($lm.Success) {
                if ($lm.Groups[2].Success) {
                    $lo = Get-Obj ([int]$lm.Groups[1].Value)
                    $r.streamLen = [int]($lo.body.Trim())
                } else { $r.streamLen = [int]$lm.Groups[1].Value }
            }
        }
    } else {
        $e = $s.IndexOf('endobj', $i)
        $r.body = $s.Substring($i, $e - $i)
    }
    $objCache[$n] = $r
    return $r
}
function Get-StreamBytes($o) {
    if ($o.streamOff -lt 0) { return [byte[]]@() }
    if ($o.dict -match '/Filter\s*/FlateDecode') { return Inflate $bytes $o.streamOff $o.streamLen }
    $raw = New-Object byte[] $o.streamLen
    [Array]::Copy($bytes, $o.streamOff, $raw, 0, $o.streamLen)
    return $raw
}
function Resolve-Dict([string]$dictText, [string]$key) {
    # returns the value text for /key: either an inline << >> dict or the dict of the referenced object
    $m = [regex]::Match($dictText, "/$key\s+(\d+)\s+0\s+R")
    if ($m.Success) { $o = Get-Obj ([int]$m.Groups[1].Value); return $o.dict }
    $m = [regex]::Match($dictText, "/$key\s*<<")
    if (-not $m.Success) { return '' }
    $i = $m.Index + $m.Length - 2; $depth = 0; $j = $i
    while ($j -lt $dictText.Length) {
        if ($dictText[$j] -eq '<' -and $dictText[$j + 1] -eq '<') { $depth++; $j += 2; continue }
        if ($dictText[$j] -eq '>' -and $dictText[$j + 1] -eq '>') { $depth--; $j += 2; if ($depth -eq 0) { break }; continue }
        $j++
    }
    return $dictText.Substring($i, $j - $i)
}
function Get-XObjects([string]$resDict) {
    $x = Resolve-Dict $resDict 'XObject'
    $map = @{}
    foreach ($m in [regex]::Matches($x, '/([^\s/<>\[\]]+)\s+(\d+)\s+0\s+R')) { $map[$m.Groups[1].Value] = [int]$m.Groups[2].Value }
    return $map
}

# ---- images --------------------------------------------------------------
function Save-Image($o) {
    $d = $o.dict
    $w = [int]([regex]::Match($d, '/Width\s+(\d+)').Groups[1].Value)
    $h = [int]([regex]::Match($d, '/Height\s+(\d+)').Groups[1].Value)
    $name = "obj{0:D3}" -f $o.num
    if ($d -match '/Filter\s*/DCTDecode') {
        $raw = New-Object byte[] $o.streamLen
        [Array]::Copy($bytes, $o.streamOff, $raw, 0, $o.streamLen)
        $p = Join-Path $imgDir "$name.jpg"
        [IO.File]::WriteAllBytes($p, $raw)
        return @{ file = "$name.jpg"; w = $w; h = $h }
    }
    if ($d -match '/Filter\s*/FlateDecode') {
        $raw = Inflate $bytes $o.streamOff $o.streamLen
        $gray = ($d -match '/ColorSpace\s*/DeviceGray')
        $alpha = $null
        $sm = [regex]::Match($d, '/SMask\s+(\d+)\s+0\s+R')
        if ($sm.Success) { $so = Get-Obj ([int]$sm.Groups[1].Value); $alpha = Inflate $bytes $so.streamOff $so.streamLen }
        if ($gray -and -not $sm.Success) { return $null }   # a bare SMask: used via its parent
        $bmp = New-Object System.Drawing.Bitmap $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $rect = New-Object System.Drawing.Rectangle 0, 0, $w, $h
        $bd = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::WriteOnly, $bmp.PixelFormat)
        $stride = $bd.Stride
        $nc = 3; if ($gray) { $nc = 1 }
        $buf = [PdfPix]::ToBgra([byte[]]$raw, [byte[]]$alpha, $w, $h, $nc, $stride)
        [Runtime.InteropServices.Marshal]::Copy($buf, 0, $bd.Scan0, $buf.Length)
        $bmp.UnlockBits($bd)
        $p = Join-Path $imgDir "$name.png"
        $bmp.Save($p, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        return @{ file = "$name.png"; w = $w; h = $h }
    }
    return $null
}

# ---- content interpreter -------------------------------------------------
$tokRe = [regex]'\((?:\\.|[^\\)])*\)|<[0-9A-Fa-f\s]*>|<<|>>|\[|\]|/[^\s/\[\]<>(){}%]*|-?(?:\d+\.?\d*|\.\d+)|[A-Za-z''"*]+'
function Mul($m1, $m2) {  # m1 x m2  (apply m1 first)
    # NOTE: comma binds tighter than * and + in PowerShell -> every element must be parenthesised
    $a = ($m1[0]*$m2[0] + $m1[1]*$m2[2]); $b = ($m1[0]*$m2[1] + $m1[1]*$m2[3])
    $c = ($m1[2]*$m2[0] + $m1[3]*$m2[2]); $d = ($m1[2]*$m2[1] + $m1[3]*$m2[3])
    $e = ($m1[4]*$m2[0] + $m1[5]*$m2[2] + $m2[4]); $f = ($m1[4]*$m2[1] + $m1[5]*$m2[3] + $m2[5])
    return @($a, $b, $c, $d, $e, $f)
}
function Pt($m, $x, $y) { return @(($m[0]*$x + $m[2]*$y + $m[4]), ($m[1]*$x + $m[3]*$y + $m[5])) }
function BoxOf($m, $x0, $y0, $x1, $y1) {
    $pts = @((Pt $m $x0 $y0), (Pt $m $x1 $y0), (Pt $m $x0 $y1), (Pt $m $x1 $y1))
    $xs = $pts | ForEach-Object { $_[0] }; $ys = $pts | ForEach-Object { $_[1] }
    return @(($xs | Measure-Object -Minimum).Minimum, ($ys | Measure-Object -Minimum).Minimum,
             ($xs | Measure-Object -Maximum).Maximum, ($ys | Measure-Object -Maximum).Maximum)
}
function Inter($a, $b) {
    return @([Math]::Max($a[0], $b[0]), [Math]::Max($a[1], $b[1]), [Math]::Min($a[2], $b[2]), [Math]::Min($a[3], $b[3]))
}
$script:found = New-Object System.Collections.ArrayList
$script:imgInfo = @{}

function Run-Content([byte[]]$data, $xobjs, $ctm0, $clip0, [int]$page, [int]$depth) {
    $txt = $latin.GetString($data)
    $ctm = $ctm0; $clip = $clip0
    $stack = New-Object System.Collections.Stack
    $ops = New-Object System.Collections.ArrayList
    $path = $null; $clipPending = $false
    foreach ($m in $tokRe.Matches($txt)) {
        $t = $m.Value
        if ($t -match '^-?(\d|\.)' ) { [void]$ops.Add([double]$t); continue }
        if ($t[0] -eq '/' -or $t[0] -eq '(' -or $t[0] -eq '<' -or $t[0] -eq '[' -or $t[0] -eq ']' -or $t -eq '>>') { [void]$ops.Add($t); continue }
        switch -CaseSensitive ($t) {
            'q' { $stack.Push(@($ctm, $clip)) }
            'Q' { if ($stack.Count -gt 0) { $st = $stack.Pop(); $ctm = $st[0]; $clip = $st[1] } }
            'cm' { if ($ops.Count -ge 6) { $mm = @($ops[$ops.Count-6], $ops[$ops.Count-5], $ops[$ops.Count-4], $ops[$ops.Count-3], $ops[$ops.Count-2], $ops[$ops.Count-1]); $ctm = Mul $mm $ctm } }
            're' { if ($ops.Count -ge 4) { $x=$ops[$ops.Count-4]; $y=$ops[$ops.Count-3]; $w=$ops[$ops.Count-2]; $h=$ops[$ops.Count-1]
                     $b = BoxOf $ctm $x $y ($x+$w) ($y+$h)
                     if ($path -eq $null) { $path = $b } else { $path = @([Math]::Min($path[0],$b[0]),[Math]::Min($path[1],$b[1]),[Math]::Max($path[2],$b[2]),[Math]::Max($path[3],$b[3])) } } }
            { $_ -in @('m','l') } { if ($ops.Count -ge 2) { $p = Pt $ctm $ops[$ops.Count-2] $ops[$ops.Count-1]
                     if ($path -eq $null) { $path = @($p[0],$p[1],$p[0],$p[1]) } else { $path = @([Math]::Min($path[0],$p[0]),[Math]::Min($path[1],$p[1]),[Math]::Max($path[2],$p[0]),[Math]::Max($path[3],$p[1])) } } }
            'c' { if ($ops.Count -ge 6) { for ($k = 0; $k -lt 3; $k++) { $p = Pt $ctm $ops[$ops.Count-6+2*$k] $ops[$ops.Count-5+2*$k]
                     if ($path -eq $null) { $path = @($p[0],$p[1],$p[0],$p[1]) } else { $path = @([Math]::Min($path[0],$p[0]),[Math]::Min($path[1],$p[1]),[Math]::Max($path[2],$p[0]),[Math]::Max($path[3],$p[1])) } } } }
            { $_ -in @('W','W*') } { $clipPending = $true }
            { $_ -in @('n','f','f*','F','B','B*','b','b*','S','s') } {
                if ($clipPending -and $path -ne $null) { $clip = Inter $clip $path }
                $clipPending = $false; $path = $null }
            'Do' {
                $nm = [string]$ops[$ops.Count-1]; $nm = $nm.Substring(1)
                if ($xobjs.ContainsKey($nm)) {
                    $o = Get-Obj $xobjs[$nm]
                    if ($o.dict -match '/Subtype\s*/Image') {
                        $box = BoxOf $ctm 0 0 1 1
                        $vis = Inter $clip $box
                        if ($vis[2] -gt $vis[0] -and $vis[3] -gt $vis[1]) {
                            [void]$script:found.Add(@{ page=$page; name=$nm; obj=$o.num; box=$box; vis=$vis })
                        }
                    } elseif ($o.dict -match '/Subtype\s*/Form' -and $depth -lt 6) {
                        $fm = @(1,0,0,1,0,0)
                        $mm = [regex]::Match($o.dict, '/Matrix\s*\[([^\]]+)\]')
                        if ($mm.Success) { $fm = @($mm.Groups[1].Value.Trim() -split '\s+' | ForEach-Object { [double]$_ }) }
                        $c2 = Mul $fm $ctm
                        $cl = $clip
                        $bb = [regex]::Match($o.dict, '/BBox\s*\[([^\]]+)\]')
                        if ($bb.Success) { $v = @($bb.Groups[1].Value.Trim() -split '\s+' | ForEach-Object { [double]$_ }); $cl = Inter $clip (BoxOf $c2 $v[0] $v[1] $v[2] $v[3]) }
                        $fres = Resolve-Dict $o.dict 'Resources'
                        $fx = Get-XObjects $fres
                        Run-Content (Get-StreamBytes $o) $fx $c2 $cl $page ($depth + 1)
                    }
                }
            }
        }
        $ops.Clear()
    }
}

# ---- pages ---------------------------------------------------------------
$catM = [regex]::Match($s, '/Type\s*/Catalog\b[^>]*?/Pages\s+(\d+)\s+0\s+R')
if (-not $catM.Success) { $catM = [regex]::Match($s, '/Pages\s+(\d+)\s+0\s+R[^>]*?/Type\s*/Catalog') }
$rootPages = Get-Obj ([int]$catM.Groups[1].Value)
$pagesObjM = [regex]::Match($rootPages.dict, '/Kids\s*\[([^\]]+)\]')
$kids = New-Object System.Collections.ArrayList
function Walk-Kids([string]$kidsText) {
    foreach ($r in [regex]::Matches($kidsText, '(\d+)\s+0\s+R')) {
        $ko = Get-Obj ([int]$r.Groups[1].Value)
        if ($ko.dict -match '/Type\s*/Pages') { $km = [regex]::Match($ko.dict, '/Kids\s*\[([^\]]+)\]'); Walk-Kids $km.Groups[1].Value }
        else { [void]$kids.Add($ko.num) }
    }
}
Walk-Kids $pagesObjM.Groups[1].Value
Write-Host ("pages: " + $kids.Count)
$pn = 0
foreach ($k in $kids) {
    $pn++
    $po = Get-Obj $k
    $mb = @(0,0,1440,810)
    $mbm = [regex]::Match($po.dict, '/MediaBox\s*\[([^\]]+)\]')
    if ($mbm.Success) { $mb = @($mbm.Groups[1].Value.Trim() -split '\s+' | ForEach-Object { [double]$_ }) }
    if ($pn -eq 1) { $script:pageW = $mb[2] - $mb[0]; $script:pageH = $mb[3] - $mb[1] }   # report uses page 1's size
    $res = Resolve-Dict $po.dict 'Resources'
    $xo = Get-XObjects $res
    $cm = [regex]::Match($po.dict, '/Contents\s+(\d+)\s+0\s+R')
    $data = [byte[]]@()
    if ($cm.Success) { $data = Get-StreamBytes (Get-Obj ([int]$cm.Groups[1].Value)) }
    else {
        $ca = [regex]::Match($po.dict, '/Contents\s*\[([^\]]+)\]')
        if ($ca.Success) { $ms = [IO.MemoryStream]::new(); foreach ($r in [regex]::Matches($ca.Groups[1].Value, '(\d+)\s+0\s+R')) { $b2 = Get-StreamBytes (Get-Obj ([int]$r.Groups[1].Value)); $ms.Write($b2, 0, $b2.Length); $ms.WriteByte(10) }; $data = $ms.ToArray() }
    }
    try { Run-Content $data $xo @(1,0,0,1,0,0) $mb $pn 0 } catch { Write-Host ("page $pn ERROR: " + $_.Exception.Message); Write-Host $_.ScriptStackTrace; Write-Host $_.InvocationInfo.PositionMessage; throw }
}

# ---- save images + report ------------------------------------------------
$scale = $CssWidth / $script:pageW
$ph = $script:pageH
$lines = New-Object System.Collections.ArrayList
[void]$lines.Add("page`tname`tobj`tfile`timgW`timgH`tvisX`tvisY`tvisW`tvisH`tboxX`tboxY`tboxW`tboxH")
foreach ($f in $script:found) {
    if (-not $script:imgInfo.ContainsKey($f.obj)) { $script:imgInfo[$f.obj] = Save-Image (Get-Obj $f.obj) }
    $ii = $script:imgInfo[$f.obj]
    if ($ii -eq $null) { continue }
    $v = $f.vis; $b = $f.box
    $vx = $v[0]*$scale; $vy = ($ph - $v[3])*$scale; $vw = ($v[2]-$v[0])*$scale; $vh = ($v[3]-$v[1])*$scale
    $bx = $b[0]*$scale; $by = ($ph - $b[3])*$scale; $bw = ($b[2]-$b[0])*$scale; $bh = ($b[3]-$b[1])*$scale
    [void]$lines.Add(("{0}`t{1}`t{2}`t{3}`t{4}`t{5}`t{6:F0}`t{7:F0}`t{8:F0}`t{9:F0}`t{10:F0}`t{11:F0}`t{12:F0}`t{13:F0}" -f $f.page, $f.name, $f.obj, $ii.file, $ii.w, $ii.h, $vx, $vy, $vw, $vh, $bx, $by, $bw, $bh))
}
[IO.File]::WriteAllLines((Join-Path $OutDir 'placements.tsv'), $lines)
Write-Host ("placements: " + ($lines.Count - 1) + "  images saved: " + $script:imgInfo.Count)
