[CmdletBinding()]
param(
    [string]$ZigPath = '',
    [string]$UpXPath = '',
    [switch]$DownloadToolchain,
    [switch]$Unpacked
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

if (-not $Unpacked) {
    $upxVersion = '5.2.1'
    $upxArchiveName = "upx-$upxVersion-win64"
    if (-not $UpXPath) { $UpXPath = Join-Path $toolsDirectory "$upxArchiveName\upx.exe" }
    if (-not (Test-Path -LiteralPath $UpXPath -PathType Leaf)) {
        if (-not $DownloadToolchain) { throw 'UPX 5.2.1 was not found. Run .\build.ps1 -DownloadToolchain, pass -UpXPath, or use -Unpacked.' }
        $upxArchive = Join-Path $toolsDirectory "$upxArchiveName.zip"
        if (-not (Test-Path -LiteralPath $upxArchive)) {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri "https://github.com/upx/upx/releases/download/v$upxVersion/$upxArchiveName.zip" -OutFile $upxArchive -UseBasicParsing
        }
        if ((Get-FileHash -LiteralPath $upxArchive -Algorithm SHA256).Hash -ne 'eabc6792a347d45e945be7748423e7868fd01b0d2bcaa2f4b1031fd71ff69bda') { throw 'The UPX archive failed SHA-256 verification.' }
        Expand-Archive -LiteralPath $upxArchive -DestinationPath $toolsDirectory -Force
    }
    $UpXPath = (Resolve-Path -LiteralPath $UpXPath).Path
    $upxIdentity = (& $UpXPath --version | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $upxIdentity -notmatch '^upx 5\.2\.1\b') { throw "Expected UPX 5.2.1; received '$upxIdentity'." }
}

foreach ($source in @('main.cpp', 'file-output.h', 'soundtrack.cpp', 'soundtrack.h', 'scene.hlsl', 'shader-compile.cpp', 'resources.rc', 'verify-imports.ps1')) {
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

    $shaderCache = Join-Path $buildDirectory 'scene_bytecode.h'
    $shaderPrograms = @(
        @('scene.hlsl', 'SceneBytecode', 'PSMain', 'ps_4_0'),
        @('scene_volume_cache.hlsl', 'NurseryBytecode', 'PSMain', 'ps_4_0'),
        @('scene_resolve.hlsl', 'ResolveBytecode', 'PSMain', 'ps_4_0'),
        @('scene_particles.hlsl', 'FragmentVertexBytecode', 'VSMain', 'vs_4_0'),
        @('scene_particles.hlsl', 'FragmentPixelBytecode', 'PSMain', 'ps_4_0')
    )
    # Cache compiled GPU programs separately from their packed representation:
    # changing native build/packing options does not recompile the large shader.
    $shaderInputs = @(Get-ChildItem -LiteralPath $projectRoot -Filter 'scene*.hlsl') + @(Get-Item -LiteralPath (Join-Path $projectRoot 'shader-compile.cpp'))
    $newestShaderInput = ($shaderInputs | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).LastWriteTimeUtc
    $shaderConfiguration = ($shaderPrograms | ForEach-Object { $_ -join ' ' }) -join "`n"
    $shaderConfigurationPath = Join-Path $buildDirectory 'shader-config.txt'
    $shaderNeedsBuild = -not (Test-Path -LiteralPath $shaderConfigurationPath)
    if (-not $shaderNeedsBuild) { $shaderNeedsBuild = [IO.File]::ReadAllText($shaderConfigurationPath) -ne $shaderConfiguration }
    foreach ($program in $shaderPrograms) {
        $binary = Join-Path $buildDirectory ($program[1] + '.cso')
        if (-not (Test-Path -LiteralPath $binary) -or (Get-Item -LiteralPath $binary).LastWriteTimeUtc -lt $newestShaderInput) { $shaderNeedsBuild = $true }
    }
    if ($shaderNeedsBuild) {
        Write-Host 'Compiling the scene shaders...'
        & $ZigPath c++ -target x86_64-windows-gnu -std=c++17 -O2 -static 'shader-compile.cpp' '-ld3dcompiler_47' -o 'build/shader-compile.exe'
        if ($LASTEXITCODE -ne 0) { throw "Shader compiler build failed (exit $LASTEXITCODE)." }
        foreach ($program in $shaderPrograms) {
            $binary = Join-Path $buildDirectory ($program[1] + '.cso')
            & (Join-Path $buildDirectory 'shader-compile.exe') $program[0] $binary $program[2] $program[3]
            if ($LASTEXITCODE -ne 0) { throw "Shader compilation failed for $($program[1]) (exit $LASTEXITCODE)." }
        }
        [IO.File]::WriteAllText($shaderConfigurationPath, $shaderConfiguration)
    } else { Write-Host 'Reusing the compiled scene shaders.' }

    $packInputs = @(Get-Item -LiteralPath $PSCommandPath)
    foreach ($program in $shaderPrograms) {
        $binary = Join-Path $buildDirectory ($program[1] + '.cso')
        $packInputs += Get-Item -LiteralPath $binary
    }
    $packNeedsBuild = -not (Test-Path -LiteralPath $shaderCache)
    if (-not $packNeedsBuild) {
        $cacheTime = (Get-Item -LiteralPath $shaderCache).LastWriteTimeUtc
        $packNeedsBuild = @($packInputs | Where-Object { $_.LastWriteTimeUtc -gt $cacheTime }).Count -gt 0
    }
    if ($packNeedsBuild) {
        Write-Host 'Embedding the compiled shaders...'
        # Pack code and raw bytecode together at the final executable stage;
        # compressing the shaders separately gives a larger combined result.
        $bytecodeHeader = "#pragma once`n"
        foreach ($program in $shaderPrograms) {
            $compiledShader = [IO.File]::ReadAllBytes((Join-Path $buildDirectory ($program[1] + '.cso')))
            $shaderBytecodeText = '0x' + [BitConverter]::ToString($compiledShader).Replace('-', ',0x')
            $bytecodeHeader += "static const unsigned char $($program[1])[] = {`n$shaderBytecodeText`n};`n"
        }
        [IO.File]::WriteAllText("$shaderCache.new", $bytecodeHeader, (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath "$shaderCache.new" -Destination $shaderCache -Force
    } else { Write-Host 'Reusing the embedded shader bytecode.' }

    Write-Host 'Compiling Windows resources...'
    & $ZigPath rc '/:auto-includes' 'none' '/fo' 'build/afterlight.res' 'resources.rc'
    if ($LASTEXITCODE -ne 0) { throw "Resource compilation failed (exit $LASTEXITCODE)." }

    Write-Host 'Building AFTERLIGHT for Windows 11 x64...'
    # Minimize our code, but retain speed-optimized support libraries at link
    # time. Building the entire runtime for size slowed frame readback ~2 ms.
    foreach ($source in @('main', 'soundtrack')) {
        & $ZigPath c++ -target x86_64-windows-gnu -std=c++17 -Oz -flto -s '-DUNICODE' '-D_UNICODE' '-DWIN32_LEAN_AND_MEAN' '-DNOMINMAX' '-Ibuild' -c "$source.cpp" -o "build/$source.o"
        if ($LASTEXITCODE -ne 0) { throw "Compilation failed for $source (exit $LASTEXITCODE)." }
    }
    $compilerArguments = @(
        'c++', '-target', 'x86_64-windows-gnu', '-O2', '-flto', '-s', '-static', '-Wl,--subsystem,windows',
        'build/main.o', 'build/soundtrack.o', 'build/afterlight.res',
        '-ld3d11', '-ldxgi', '-ld3dcompiler_47', '-lwinmm', '-lgdi32', '-luser32', '-lole32', '-luuid',
        '-o', 'build/AFTERLIGHT-unpacked.exe'
    )
    & $ZigPath @compilerArguments
    if ($LASTEXITCODE -ne 0) { throw "C++ compilation failed (exit $LASTEXITCODE)." }

    & (Join-Path $projectRoot 'verify-imports.ps1') -Executable (Join-Path $buildDirectory 'AFTERLIGHT-unpacked.exe') -Summary
    if ($Unpacked) {
        Copy-Item -LiteralPath (Join-Path $buildDirectory 'AFTERLIGHT-unpacked.exe') -Destination (Join-Path $distDirectory 'AFTERLIGHT.exe') -Force
    } else {
        Write-Host 'Compressing the complete executable...'
        & $UpXPath --best --lzma --strip-relocs=0 --compress-resources=0 --force-overwrite -o 'dist/AFTERLIGHT.exe' 'build/AFTERLIGHT-unpacked.exe'
        if ($LASTEXITCODE -ne 0) { throw "Executable compression failed (exit $LASTEXITCODE)." }
        & $UpXPath -t 'dist/AFTERLIGHT.exe'
        if ($LASTEXITCODE -ne 0) { throw 'Packed executable integrity check failed.' }
    }

    Copy-Item -LiteralPath (Join-Path $projectRoot 'README.md') -Destination (Join-Path $distDirectory 'README.md') -Force
    Copy-Item -LiteralPath (Join-Path $projectRoot 'docs') -Destination $distDirectory -Recurse -Force
    $licensePath=Join-Path $projectRoot 'LICENSE'
    if(Test-Path -LiteralPath $licensePath){Copy-Item -LiteralPath $licensePath -Destination $distDirectory -Force}
    $executable = Get-Item -LiteralPath (Join-Path $distDirectory 'AFTERLIGHT.exe')
    Write-Host ("Built {0} ({1:N0} bytes; {2:N1} KiB)" -f $executable.FullName, $executable.Length, ($executable.Length / 1KB))
} finally {
    Pop-Location
    $env:ZIG_GLOBAL_CACHE_DIR = $previousGlobalCache
    $env:ZIG_LOCAL_CACHE_DIR = $previousLocalCache
}
