[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Baseline,
    [string]$Candidate = (Join-Path $PSScriptRoot '..\dist\AFTERLIGHT.exe'),
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\build\size-equivalence'),
    [switch]$ReuseBaseline
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$Baseline = (Resolve-Path -LiteralPath $Baseline).Path
$Candidate = (Resolve-Path -LiteralPath $Candidate).Path
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
$results = @()
$previous = $null
if ($ReuseBaseline) {
    $previous = Get-Content -LiteralPath (Join-Path $OutputDirectory 'equivalence.json') -Raw | ConvertFrom-Json
    if ($previous.BaselineSHA256 -ne (Get-FileHash -LiteralPath $Baseline).Hash) { throw 'Cached results belong to a different baseline executable.' }
}
if (-not ('AfterlightPcmComparison' -as [type])) { Add-Type -TypeDefinition @'
public static class AfterlightPcmComparison {
    public static double[] Compare(byte[] original, byte[] candidate) {
        if (original.Length != candidate.Length || original.Length < 44) throw new System.Exception("WAV lengths differ");
        for (int i=0;i<44;i++) if (original[i]!=candidate[i]) throw new System.Exception("WAV formats differ");
        double squaredError=0,signal=0; int maximum=0,changed=0;
        for (int i=44;i<original.Length;i+=2) {
            int a=System.BitConverter.ToInt16(original,i), b=System.BitConverter.ToInt16(candidate,i), difference=System.Math.Abs(a-b);
            maximum=System.Math.Max(maximum,difference); if(difference!=0) changed++;
            squaredError+=(double)difference*difference; signal+=(double)a*a;
        }
        return new double[] {maximum,changed,squaredError==0?999:10*System.Math.Log10(signal/squaredError)};
    }
}
'@
}
function Run-Demo([string]$exe, [string[]]$arguments) {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $process = Start-Process -FilePath $exe -ArgumentList $arguments -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "Demo failed ($($process.ExitCode)): $exe $arguments" }
    return $timer.Elapsed.TotalMilliseconds
}
# Visuals remain exact. The size-oriented synth build permits a one-step error
# in 16-bit PCM, measured below; no sample rate, duration or layer is changed.
$cases = @(@{Name='score'; Extension='wav'; Arguments=@('--export-wav')})
foreach ($t in @('14','44','62','65.9','66','84','98','114','117.9','118','140','145.5','149.9','150','156','168')) {
    $cases += @{Name="frame-$t-1080p"; Extension='bmp'; Arguments=@('--quality','3','--capture',$t)}
}
$cases += @{Name='menu'; Extension='bmp'; Arguments=@('--capture-menu')}
foreach ($quality in @('1','2')) {
    $cases += @{Name="quality-$quality"; Extension='bmp'; Arguments=@('--quality',$quality,'--capture','92')}
}
foreach ($t in @('65.95','146')) {
    $cases += @{Name="warp-$t"; Extension='bmp'; Arguments=@('--warp','--quality','1','--capture',$t)}
}
foreach ($case in $cases) {
    $paths = @{}
    $elapsed = @{}
    foreach ($version in @('baseline','candidate')) {
        $path = Join-Path $OutputDirectory "$version-$($case.Name).$($case.Extension)"
        $exe = if ($version -eq 'baseline') { $Baseline } else { $Candidate }
        if ($ReuseBaseline -and $version -eq 'baseline') {
            $reference = @($previous.Cases | Where-Object { $_.Case -eq $case.Name })
            if ($reference.Count -ne 1 -or (Get-FileHash -LiteralPath $path).Hash -ne $reference[0].BaselineSHA256) { throw "Invalid cached baseline: $($case.Name)" }
            $elapsed[$version] = $reference[0].BaselineElapsedMs
        } else {
            $elapsed[$version] = Run-Demo $exe ($case.Arguments + @('"' + $path + '"'))
        }
        $paths[$version] = $path
    }
    $originalHash = (Get-FileHash -LiteralPath $paths.baseline -Algorithm SHA256).Hash
    $newHash = (Get-FileHash -LiteralPath $paths.candidate -Algorithm SHA256).Hash
    $identical = $originalHash -eq $newHash
    $audio = $null
    $passed = $identical
    if ($case.Name -eq 'score') {
        $comparison = [AfterlightPcmComparison]::Compare([IO.File]::ReadAllBytes($paths.baseline),[IO.File]::ReadAllBytes($paths.candidate))
        $audio = [PSCustomObject]@{MaximumSampleError=$comparison[0]; ChangedSamples=$comparison[1]; SignalToErrorDB=$comparison[2]}
        $passed = $comparison[0] -le 1
    }
    $results += [PSCustomObject]@{ Case=$case.Name; Passed=$passed; Identical=$identical; Audio=$audio; BaselineElapsedMs=$elapsed.baseline; CandidateElapsedMs=$elapsed.candidate; BaselineSHA256=$originalHash; CandidateSHA256=$newHash }
    Write-Host ("{0}: {1}" -f $case.Name, $(if($identical){'IDENTICAL'}elseif($passed){'PASS (PCM error at most 1 / 32768)'}else{'FAIL'}))
}
$before = Get-Item -LiteralPath $Baseline
$after = Get-Item -LiteralPath $Candidate
$report = [PSCustomObject]@{
    BaselineBytes = $before.Length
    CandidateBytes = $after.Length
    ReductionPercent = [Math]::Round(100 * (1 - $after.Length / $before.Length), 3)
    BaselineSHA256 = (Get-FileHash -LiteralPath $Baseline -Algorithm SHA256).Hash
    CandidateSHA256 = (Get-FileHash -LiteralPath $Candidate -Algorithm SHA256).Hash
    Passed = @($results | Where-Object { -not $_.Passed }).Count -eq 0
    Cases = $results
}
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'equivalence.json') -Encoding UTF8
if (-not $report.Passed) { throw 'Output equivalence failed. See equivalence.json.' }
Write-Host "PASS: all $($results.Count) visual/audio checks passed; $($report.ReductionPercent)% smaller."
