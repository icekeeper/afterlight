[CmdletBinding()]
param()

$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$distDirectory=Join-Path $projectRoot 'dist'
$executable=Join-Path $distDirectory 'AFTERLIGHT.exe'
if(-not(Test-Path -LiteralPath $executable -PathType Leaf)) {
    throw 'Build the demo with build.ps1 before packaging a release.'
}

Copy-Item -LiteralPath (Join-Path $projectRoot 'README.md') -Destination $distDirectory -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs') -Destination $distDirectory -Recurse -Force
$packageFiles=@($executable,(Join-Path $distDirectory 'README.md'),(Join-Path $distDirectory 'docs'))
$license=Join-Path $projectRoot 'LICENSE'
if(Test-Path -LiteralPath $license) {
    $distLicense=Join-Path $distDirectory 'LICENSE'
    Copy-Item -LiteralPath $license -Destination $distLicense -Force
    $packageFiles+=$distLicense
}
$zip=Join-Path $distDirectory 'AFTERLIGHT-Windows11-x64.zip'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipStream=[IO.File]::Open($zip,[IO.FileMode]::Create)
try {
    $archive=[IO.Compression.ZipArchive]::new($zipStream,[IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach($inputPath in $packageFiles) {
            $item=Get-Item -LiteralPath $inputPath
            $files=if($item.PSIsContainer){Get-ChildItem -LiteralPath $inputPath -File -Recurse}else{@($item)}
            foreach($file in $files) {
                $entryName=$file.FullName.Substring($distDirectory.Length+1).Replace('\','/')
                [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$file.FullName,$entryName,[IO.Compression.CompressionLevel]::Optimal) | Out-Null
            }
        }
    } finally {$archive.Dispose()}
} finally {$zipStream.Dispose()}

$downloads=@($executable,$zip)
$preview=Join-Path $distDirectory 'AFTERLIGHT-visual-preview.mp4'
if(Test-Path -LiteralPath $preview){$downloads+=$preview}
$checksums=foreach($file in $downloads) {
    '{0}  {1}' -f (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant(),[IO.Path]::GetFileName($file)
}
$checksums | Set-Content -LiteralPath (Join-Path $distDirectory 'SHA256SUMS.txt') -Encoding ASCII
Get-Item -LiteralPath $zip | Select-Object FullName,Length
