# Builds the Android APK on Windows even though the project path contains a non-ASCII character ("ü").
#
# Flutter's shader compiler (impellerc) cannot write to non-ASCII paths ("Could not write file to
# ...\efetüfey\...\ink_sparkle.frag"), and a directory junction does not help because Flutter resolves it
# back to the real path. Mapping the project root to a temporary drive letter with `subst` does work.
#
# Usage:  .\build_apk.ps1                 # release APK
#         .\build_apk.ps1 -Mode debug
#         .\build_apk.ps1 -- --dart-define=API_BASE_URL=https://api.example.com
param(
    [ValidateSet("release", "debug")] [string] $Mode = "release",
    [Parameter(ValueFromRemainingArguments = $true)] [string[]] $FlutterArgs
)
$ErrorActionPreference = "Stop"

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$used = (Get-PSDrive -PSProvider FileSystem).Name
$letter = @("R", "S", "T", "U", "V", "W", "X", "Y", "Z") | Where-Object { $used -notcontains $_ } | Select-Object -First 1
if (-not $letter) { throw "No free drive letter for subst." }

subst "${letter}:" $projectRoot
try {
    Push-Location "${letter}:\mobile"
    flutter build apk "--$Mode" @FlutterArgs
    if ($LASTEXITCODE -ne 0) { throw "flutter build failed with exit code $LASTEXITCODE" }
    Write-Host "APK: $projectRoot\mobile\build\app\outputs\flutter-apk\app-$Mode.apk"
}
finally {
    Pop-Location
    subst "${letter}:" /D
}
