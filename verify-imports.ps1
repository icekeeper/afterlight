param(
    [string]$Executable = (Join-Path $PSScriptRoot 'build\AFTERLIGHT-unpacked.exe'),
    [switch]$Summary
)
$ErrorActionPreference = 'Stop'
$bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Executable).Path)
function U16([int]$offset) { [BitConverter]::ToUInt16($bytes, $offset) }
function U32([int]$offset) { [BitConverter]::ToUInt32($bytes, $offset) }
$peOffset = U32 60
if ((U32 $peOffset) -ne 0x4550) { throw 'Invalid PE header.' }
$sectionCount = U16 ($peOffset + 6)
$optional = $peOffset + 24
$optionalSize = U16 ($peOffset + 20)
if ((U16 $optional) -ne 0x20b) { throw 'Expected a PE32+ executable.' }
$sections = $optional + $optionalSize
for ($sectionIndex = 0; $sectionIndex -lt $sectionCount; $sectionIndex++) {
    $name = [Text.Encoding]::ASCII.GetString($bytes, $sections + $sectionIndex * 40, 8).Trim([char]0)
    if ($name -eq 'UPX0') { throw 'Audit the ordinary executable before packing: -Executable .\build\AFTERLIGHT-unpacked.exe. A packed import table describes only its loader.' }
}
function OffsetFromRva([uint32]$rva) {
    for ($sectionIndex = 0; $sectionIndex -lt $sectionCount; $sectionIndex++) {
        $sectionOffset = $sections + $sectionIndex * 40
        $virtualSize = U32 ($sectionOffset + 8)
        $virtualAddress = U32 ($sectionOffset + 12)
        $rawSize = U32 ($sectionOffset + 16)
        $rawAddress = U32 ($sectionOffset + 20)
        if ($rva -ge $virtualAddress -and $rva -lt ($virtualAddress + [Math]::Max($virtualSize, $rawSize))) {
            return [int]($rawAddress + $rva - $virtualAddress)
        }
    }
    throw ('Unmapped RVA: 0x{0:x}' -f $rva)
}
function StringFromRva([uint32]$rva) {
    $start = OffsetFromRva $rva
    $end = $start
    while ($bytes[$end] -ne 0) { $end++ }
    return [Text.Encoding]::ASCII.GetString($bytes, $start, $end - $start)
}
$importsRva = U32 ($optional + 120)
$imports = @()
if ($importsRva) {
    $descriptor = OffsetFromRva $importsRva
    while ((U32 ($descriptor + 12)) -ne 0) {
        $imports += StringFromRva (U32 ($descriptor + 12))
        $descriptor += 20
    }
}
$imports = @($imports | Sort-Object -Unique)
$allowed = @('advapi32.dll', 'bcrypt.dll', 'd3d11.dll', 'd3dcompiler_47.dll', 'dxgi.dll', 'gdi32.dll', 'kernel32.dll', 'msvcrt.dll', 'ntdll.dll', 'ole32.dll', 'oleaut32.dll', 'rpcrt4.dll', 'secur32.dll', 'shell32.dll', 'shlwapi.dll', 'ucrtbase.dll', 'user32.dll', 'version.dll', 'winmm.dll', 'ws2_32.dll')
$unexpected = @($imports | Where-Object { $_.ToLowerInvariant() -notin $allowed -and $_ -notlike 'api-ms-win-*.dll' -and $_ -notlike 'ext-ms-win-*.dll' })
$result = [PSCustomObject]@{
    Executable = (Resolve-Path -LiteralPath $Executable).Path
    Machine = ('0x{0:X}' -f (U16 ($peOffset + 4)))
    Subsystem = (U16 ($optional + 68))
    Imports = $imports
    DelayImportTableRva = (U32 ($optional + 112 + 13 * 8))
    UnexpectedImports = $unexpected
    SHA256 = (Get-FileHash -LiteralPath $Executable -Algorithm SHA256).Hash
}
if (-not $Summary) { $result | ConvertTo-Json -Depth 3 }
if ($unexpected.Count -gt 0) { throw 'Unexpected DLL imports detected.' }
if ($result.DelayImportTableRva -ne 0) { throw 'Delay imports require an additional audit.' }
if ($result.Machine -ne '0x8664' -or $result.Subsystem -ne 2) { throw 'Expected an x64 Windows GUI executable.' }
if ($Summary) { Write-Host ('Verified x64 Windows GUI executable; all {0} DLL imports are Windows components.' -f $imports.Count) }
