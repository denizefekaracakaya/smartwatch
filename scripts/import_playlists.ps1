# Rebuilds Spotify playlists on the Docker server from the songs it already has.
# Run it in PowerShell (not Git Bash):
#
#   .\scripts\import_playlists.ps1 -Source "C:\Users\me\Downloads\Spotify Account Data\Playlist1.json" -User me@example.com
#   .\scripts\import_playlists.ps1 -Source "C:\Users\me\Downloads\yolculuk.csv" -User me@example.com     # Exportify
#   .\scripts\import_playlists.ps1 -Source "C:\Users\me\Projects\liste" -User me@example.com             # every .csv/.json in a folder
#   .\scripts\import_playlists.ps1 -Source "https://open.spotify.com/playlist/..." -User me@example.com  # needs API keys
#   add -DryRun to only see what would match.
#
# Only titles/artists are imported — audio is never downloaded from Spotify. Tracks that are not on the
# server are collected in "eksik-sarkilar.csv" so you can add them with add_music.ps1.
param(
    [Parameter(Mandatory = $true)] [string] $Source,
    [Parameter(Mandatory = $true)] [string] $User,
    [switch] $DryRun
)
# "Continue": docker writes progress to stderr, which Windows PowerShell 5.1 would turn into terminating
# errors under "Stop". Exit codes are checked explicitly instead.
$ErrorActionPreference = "Continue"
Set-Location (Join-Path $PSScriptRoot "..")

$tmp = "/tmp/playlists-" + [guid]::NewGuid().ToString("N").Substring(0, 8)
$extra = @()
if ($DryRun) { $extra += "--dry-run" }
$missingRows = New-Object System.Collections.Generic.List[string]

function Invoke-Import([string] $arg, [string[]] $more, [string[]] $envArgs) {
    # Missing tracks of this run are written inside the container, then appended to the local report.
    docker compose exec -T @envArgs api python -m app.cli import-playlists $arg --user $User `
        --missing-out "$tmp/missing.csv" @more @extra
    if ($LASTEXITCODE -ne 0) { throw "import failed for $arg" }
    $local = New-TemporaryFile
    docker compose cp "api:$tmp/missing.csv" $local.FullName 2>&1 | Out-Null
    $lines = Get-Content -Encoding UTF8 $local.FullName
    Remove-Item $local.FullName
    if ($missingRows.Count -eq 0 -and $lines.Count -gt 0) { $missingRows.Add($lines[0]) }  # header once
    foreach ($line in ($lines | Select-Object -Skip 1)) { $missingRows.Add($line) }
}

docker compose exec -T api mkdir -p $tmp | Out-Null
try {
    if ($Source -match '^(https?://|spotify:)') {
        if (-not $env:SPOTIFY_CLIENT_ID -or -not $env:SPOTIFY_CLIENT_SECRET) {
            throw "Set `$env:SPOTIFY_CLIENT_ID and `$env:SPOTIFY_CLIENT_SECRET first (see KURULUM.md)."
        }
        Invoke-Import $Source @() @("-e", "SPOTIFY_CLIENT_ID=$env:SPOTIFY_CLIENT_ID", "-e", "SPOTIFY_CLIENT_SECRET=$env:SPOTIFY_CLIENT_SECRET")
    }
    else {
        $item = Get-Item -LiteralPath $Source -ErrorAction Stop
        $files = if ($item.PSIsContainer) {
            Get-ChildItem -LiteralPath $item.FullName -File | Where-Object { $_.Extension -in ".csv", ".json" }
        } else { @($item) }
        if (-not $files) { throw "No .csv or .json files in $Source" }
        $i = 0
        foreach ($file in $files) {
            $i++
            # Copy under a plain name: playlist file names often contain emoji or curly quotes.
            $remote = "$tmp/source$i$($file.Extension.ToLower())"
            docker compose cp $file.FullName "api:$remote" 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "could not copy $($file.Name) to the server (is it running?)" }
            $more = @()
            if ($file.Extension -eq ".csv") { $more = @("--name", ($file.BaseName -replace "_", " ")) }
            Invoke-Import $remote $more @()
        }
    }
    if ($missingRows.Count -gt 1) {
        $out = Join-Path (Get-Location) "eksik-sarkilar.csv"
        [System.IO.File]::WriteAllLines($out, $missingRows, (New-Object System.Text.UTF8Encoding $true))
        Write-Host "Missing tracks ($($missingRows.Count - 1)): $out"
    }
}
finally {
    docker compose exec -T --user root api rm -rf $tmp | Out-Null
}
