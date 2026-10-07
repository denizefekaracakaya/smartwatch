# Rebuilds Spotify playlists on the Docker server from the songs it already has.
#
#   .\scripts\import_playlists.ps1 -Source "C:\Users\me\Downloads\Spotify Account Data\Playlist1.json" -User me@example.com
#   .\scripts\import_playlists.ps1 -Source "C:\Users\me\Downloads\Yolculuk.csv" -User me@example.com      # Exportify
#   .\scripts\import_playlists.ps1 -Source "https://open.spotify.com/playlist/..." -User me@example.com   # needs API keys
#   add -DryRun to only see what would match.
#
# Only titles/artists are imported — audio is never downloaded from Spotify. Tracks that are not on the
# server are written to "eksik-sarkilar.csv" so you can add them with add_music.ps1.
param(
    [Parameter(Mandatory = $true)] [string] $Source,
    [Parameter(Mandatory = $true)] [string] $User,
    [switch] $DryRun
)
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

$tmp = "/tmp/playlists-" + [guid]::NewGuid().ToString("N").Substring(0, 8)
$extra = @()
if ($DryRun) { $extra += "--dry-run" }

if ($Source -match '^(https?://|spotify:)') {
    if (-not $env:SPOTIFY_CLIENT_ID -or -not $env:SPOTIFY_CLIENT_SECRET) {
        throw "Set `$env:SPOTIFY_CLIENT_ID and `$env:SPOTIFY_CLIENT_SECRET first (see KURULUM.md)."
    }
    $arg = $Source
    $envArgs = @("-e", "SPOTIFY_CLIENT_ID=$env:SPOTIFY_CLIENT_ID", "-e", "SPOTIFY_CLIENT_SECRET=$env:SPOTIFY_CLIENT_SECRET")
    docker compose exec -T api mkdir -p $tmp
}
else {
    $file = Get-Item $Source
    docker compose exec -T api mkdir -p $tmp
    docker compose cp $file.FullName "api:$tmp/$($file.Name)"
    $arg = "$tmp/$($file.Name)"
    $envArgs = @()
}
try {
    docker compose exec -T @envArgs api python -m app.cli import-playlists $arg --user $User --missing-out "$tmp/missing.csv" @extra
    if ($LASTEXITCODE -eq 0) {
        docker compose cp "api:$tmp/missing.csv" "eksik-sarkilar.csv" | Out-Null
        Write-Host "Missing tracks: $(Resolve-Path eksik-sarkilar.csv)"
    }
}
finally {
    docker compose exec -T --user root api rm -rf $tmp | Out-Null
}
