# Rebuild the procedural, multi-resolution ICO using only PowerShell and .NET.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$sizes = @(16, 32, 48, 64)
$images = @()
foreach ($size in $sizes) {
    $stream = New-Object System.IO.MemoryStream
    $bitmap = New-Object System.Drawing.Bitmap($size, $size)
    for ($row = 0; $row -lt $size; $row++) {
        for ($column = 0; $column -lt $size; $column++) {
            $x = (($column + 0.5) / $size - 0.5) * 2.0
            $y = (($row + 0.5) / $size - 0.5) * 2.0
            $r = [Math]::Sqrt($x * $x + $y * $y)
            $rim = [Math]::Exp(-[Math]::Abs($r - 0.44) * 85)
            $glow = [Math]::Exp(-[Math]::Abs($r - 0.44) * 13) * 0.30
            $angle = [Math]::Atan2($y, $x)
            $warm = (1 + [Math]::Cos($angle + 0.70)) * 0.5
            $u = $x * 0.91 - $y * 0.414
            $v = $x * 0.414 + $y * 0.91
            $ellipse = [Math]::Sqrt(($u / 0.77) * ($u / 0.77) + ($v / 0.18) * ($v / 0.18))
            $orbit = [Math]::Exp(-[Math]::Abs($ellipse - 1) * 26) * 0.70
            if ($r -lt 0.425 -and $v -lt 0) { $orbit = 0 }
            $light = $rim + $glow
            $red = 9 + 215 * $warm * $light + 44 * $orbit
            $green = 16 + (175 - 35 * $warm) * $light + 172 * $orbit
            $blue = 26 + (230 - 160 * $warm) * $light + 222 * $orbit
            if ($r -lt 0.405) {
                $red = 4 + 34 * $orbit
                $green = 7 + 135 * $orbit
                $blue = 13 + 177 * $orbit
            }
            $starX = [Math]::Abs($x - 0.52)
            $starY = [Math]::Abs($y + 0.52)
            $star = [Math]::Exp(-($starX * 85 + $starY * 20)) + [Math]::Exp(-($starX * 20 + $starY * 85))
            $red += 220 * $star
            $green += 234 * $star
            $blue += 248 * $star
            $color = [System.Drawing.Color]::FromArgb(255, [byte][Math]::Min(255, $red), [byte][Math]::Min(255, $green), [byte][Math]::Min(255, $blue))
            $bitmap.SetPixel($column, $row, $color)
        }
    }
    # Windows 11 loads PNG entries directly from ICO resources. Preserve every
    # resolution and RGBA pixel while encoding them losslessly.
    $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
    $images += ,$stream.ToArray()
    $bitmap.Dispose()
    $stream.Dispose()
}
$file = [System.IO.File]::Create((Join-Path $PSScriptRoot 'afterlight.ico'))
$icoWriter = New-Object System.IO.BinaryWriter($file)
$icoWriter.Write([uint16]0)
$icoWriter.Write([uint16]1)
$icoWriter.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $icoWriter.Write([byte]$sizes[$i])
    $icoWriter.Write([byte]$sizes[$i])
    $icoWriter.Write([byte]0)
    $icoWriter.Write([byte]0)
    $icoWriter.Write([uint16]1)
    $icoWriter.Write([uint16]32)
    $icoWriter.Write([uint32]$images[$i].Length)
    $icoWriter.Write([uint32]$offset)
    $offset += $images[$i].Length
}
foreach ($bytes in $images) { $icoWriter.Write([byte[]]$bytes) }
$icoWriter.Dispose()
$file.Dispose()
Write-Host 'Created assets/afterlight.ico'
