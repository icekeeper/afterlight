[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InputDirectory,
    [Parameter(Mandatory)][string]$OutputPath,
    [ValidateRange(1,120)][int]$FrameRate=30,
    [string]$AudioPath='',
    [ValidateRange(0,86400)][double]$AudioStartSeconds=0,
    [ValidateRange(0,99999)][int]$StartNumber=0,
    [string]$FFmpegPath=''
)

# Developer preview tool only; the Windows executable has no FFmpeg dependency.
# Portable binary from the provider linked by https://ffmpeg.org/download.html.
$ErrorActionPreference='Stop'
$ffmpegExecutable=$FFmpegPath
if(-not $ffmpegExecutable) {
    $command=Get-Command ffmpeg -ErrorAction SilentlyContinue
    if($command){$ffmpegExecutable=$command.Source}
    else {$ffmpegExecutable=Join-Path $PSScriptRoot 'ffmpeg/ffmpeg-9.0.1-essentials_build/bin/ffmpeg.exe'}
}
if(-not(Test-Path -LiteralPath $ffmpegExecutable -PathType Leaf)) {
    throw 'FFmpeg was not found. Pass -FFmpegPath with the path to ffmpeg.exe, or add FFmpeg to PATH.'
}
$frameDirectory=(Resolve-Path -LiteralPath $InputDirectory).Path
$framePattern=Join-Path $frameDirectory 'frame%04d.bmp'
$firstFrame=Join-Path $frameDirectory ('frame{0:D4}.bmp' -f $StartNumber)
if(-not(Test-Path -LiteralPath $firstFrame -PathType Leaf)) {
    throw "The first expected frame is missing: $firstFrame"
}
$encoderArguments=@('-hide_banner','-loglevel','warning','-y',
    '-framerate',[string]$FrameRate,'-start_number',[string]$StartNumber,'-i',$framePattern)
if($AudioPath) {
    $audioFile=(Resolve-Path -LiteralPath $AudioPath).Path
    $audioOffset=$AudioStartSeconds.ToString('0.######',[Globalization.CultureInfo]::InvariantCulture)
    $encoderArguments+=@('-ss',$audioOffset,'-i',$audioFile,'-map','0:v:0','-map','1:a:0')
}
$encoderArguments+=@('-c:v','libx264','-preset','medium','-crf','18','-pix_fmt','yuv420p','-movflags','+faststart')
if($AudioPath) {$encoderArguments+=@('-c:a','aac','-b:a','192k','-shortest')}
$encoderArguments+=@($OutputPath)
& $ffmpegExecutable @encoderArguments
if($LASTEXITCODE -ne 0) {throw "FFmpeg failed with exit code $LASTEXITCODE"}
Get-Item -LiteralPath $OutputPath | Select-Object FullName,Length
