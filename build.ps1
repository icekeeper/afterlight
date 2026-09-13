[CmdletBinding()]
param(
    [string]$ZigPath = '',
    [switch]$DownloadToolchain
)

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$toolsDirectory = Join-Path $projectRoot 'tools'
$buildDirectory = Join-Path $projectRoot 'build'
$distDirectory = Join-Path $projectRoot 'dist'
$zigVersion = '0.13.0'
$zigArchiveName = "zig-windows-x86_64-$zigVersion"
$zigArchiveHash = 'd859994725ef9402381e557c60bb57497215682e355204d754ee3df75ee3c158'
$zigDownloadUrl = "https://ziglang.org/download/$zigVersion/$zigArchiveName.zip"

foreach ($directory in @($toolsDirectory, $buildDirectory, $distDirectory)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
}

if (-not $ZigPath) {
    $ZigPath = Join-Path $toolsDirectory "$zigArchiveName\zig.exe"
}
if (-not (Test-Path -LiteralPath $ZigPath -PathType Leaf)) {
    if (-not $DownloadToolchain) {
        throw 'Zig 0.13.0 was not found. Run .\build.ps1 -DownloadToolchain, or pass -ZigPath C:\path\to\zig.exe.'
    }
    $archivePath = Join-Path $toolsDirectory "$zigArchiveName.zip"
    if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
        Write-Host 'Downloading the portable Zig 0.13.0 toolchain...'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $zigDownloadUrl -OutFile $archivePath -UseBasicParsing
    }
    if ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash -ne $zigArchiveHash) {
        throw "The Zig archive failed SHA-256 verification. Remove $archivePath and retry."
    }
    Expand-Archive -LiteralPath $archivePath -DestinationPath $toolsDirectory -Force
    $ZigPath = Join-Path $toolsDirectory "$zigArchiveName\zig.exe"
}
$ZigPath = (Resolve-Path -LiteralPath $ZigPath).Path

foreach ($source in @('main.cpp', 'soundtrack.cpp', 'soundtrack.h', 'scene.hlsl', 'shader-compile.cpp', 'resources.rc', 'verify-imports.ps1')) {
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $source) -PathType Leaf)) {
        throw "Missing source file: $source"
    }
}

$previousGlobalCache = $env:ZIG_GLOBAL_CACHE_DIR
$previousLocalCache = $env:ZIG_LOCAL_CACHE_DIR
$env:ZIG_GLOBAL_CACHE_DIR = Join-Path $buildDirectory 'zig-global-cache'
$env:ZIG_LOCAL_CACHE_DIR = Join-Path $buildDirectory 'zig-local-cache'
Push-Location -LiteralPath $projectRoot
try {
    $actualVersion = (& $ZigPath version | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $actualVersion -ne $zigVersion) {
        throw "This build expects Zig $zigVersion; received '$actualVersion'."
    }

    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    $shaderCache = Join-Path $buildDirectory 'scene_bytecode.h'
    $shaderInputs = @(Get-ChildItem -LiteralPath $projectRoot -Filter 'scene*.hlsl') + @(Get-Item -LiteralPath (Join-Path $projectRoot 'shader-compile.cpp')) + @(Get-Item -LiteralPath $PSCommandPath)
    $shaderNeedsBuild = -not (Test-Path -LiteralPath $shaderCache)
    if (-not $shaderNeedsBuild) {
        $cacheTime = (Get-Item -LiteralPath $shaderCache).LastWriteTimeUtc
        $shaderNeedsBuild = @($shaderInputs | Where-Object { $_.LastWriteTimeUtc -gt $cacheTime }).Count -gt 0
    }
    if ($shaderNeedsBuild) {
    Write-Host 'Compiling the scene shader...'
    & $ZigPath c++ -target x86_64-windows-gnu -std=c++17 -O2 -static 'shader-compile.cpp' '-ld3dcompiler_47' -o 'build/shader-compile.exe'
    if ($LASTEXITCODE -ne 0) { throw "Shader compiler build failed (exit $LASTEXITCODE)." }
    $bytecodeHeader = "#pragma once`n"
    $shaderPrograms = @(
        @('scene.hlsl', 'SceneBytecode', 'PSMain', 'ps_4_0'),
        @('scene_volume_cache.hlsl', 'NurseryBytecode', 'PSMain', 'ps_4_0'),
        @('scene_resolve.hlsl', 'ResolveBytecode', 'PSMain', 'ps_4_0'),
        @('scene_particles.hlsl', 'FragmentVertexBytecode', 'VSMain', 'vs_4_0'),
        @('scene_particles.hlsl', 'FragmentPixelBytecode', 'PSMain', 'ps_4_0')
    )
    foreach ($program in $shaderPrograms) {
        $binary = Join-Path $buildDirectory ($program[1] + '.cso')
        & (Join-Path $buildDirectory 'shader-compile.exe') $program[0] $binary $program[2] $program[3]
        if ($LASTEXITCODE -ne 0) { throw "Shader compilation failed for $($program[1]) (exit $LASTEXITCODE)." }
        $compiledShader = [System.IO.File]::ReadAllBytes($binary)
        $shaderBytecodeText = '0x' + [BitConverter]::ToString($compiledShader).Replace('-', ',0x')
        $bytecodeHeader += "static const unsigned char $($program[1])[] = {`n" + $shaderBytecodeText + "`n};`n"
    }
    [System.IO.File]::WriteAllText((Join-Path $buildDirectory 'scene_bytecode.h'), $bytecodeHeader, $utf8WithoutBom)
    } else { Write-Host 'Reusing the compiled scene shader.' }

    Write-Host 'Compiling Windows resources...'
    & $ZigPath rc '/:auto-includes' 'none' '/fo' 'build/afterlight.res' 'resources.rc'
    if ($LASTEXITCODE -ne 0) { throw "Resource compilation failed (exit $LASTEXITCODE)." }

    Write-Host 'Building AFTERLIGHT for Windows 11 x64...'
    $compilerArguments = @(
        'c++', '-target', 'x86_64-windows-gnu', '-std=c++17', '-O2', '-static', '-Wl,--subsystem,windows',
        '-DUNICODE', '-D_UNICODE', '-DWIN32_LEAN_AND_MEAN', '-DNOMINMAX',
        '-Ibuild', 'main.cpp', 'soundtrack.cpp', 'build/afterlight.res',
        '-ld3d11', '-ldxgi', '-ld3dcompiler_47', '-lwinmm', '-lgdi32', '-luser32', '-lole32', '-luuid',
        '-o', 'dist/AFTERLIGHT.exe'
    )
    & $ZigPath @compilerArguments
    if ($LASTEXITCODE -ne 0) { throw "C++ compilation failed (exit $LASTEXITCODE)." }

    & (Join-Path $projectRoot 'verify-imports.ps1') -Executable (Join-Path $distDirectory 'AFTERLIGHT.exe') -Summary

    Copy-Item -LiteralPath (Join-Path $projectRoot 'README.md') -Destination (Join-Path $distDirectory 'README.md') -Force
    Copy-Item -LiteralPath (Join-Path $projectRoot 'docs') -Destination $distDirectory -Recurse -Force
    $licensePath=Join-Path $projectRoot 'LICENSE'
    if(Test-Path -LiteralPath $licensePath){Copy-Item -LiteralPath $licensePath -Destination $distDirectory -Force}
    $executable = Get-Item -LiteralPath (Join-Path $distDirectory 'AFTERLIGHT.exe')
    Write-Host ("Built {0} ({1:N2} MB)" -f $executable.FullName, ($executable.Length / 1MB))
} finally {
    Pop-Location
    $env:ZIG_GLOBAL_CACHE_DIR = $previousGlobalCache
    $env:ZIG_LOCAL_CACHE_DIR = $previousLocalCache
}
