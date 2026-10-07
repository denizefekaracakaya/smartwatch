# Adds audio files from a folder on this PC to the running Docker server.
#
#   .\scripts\add_music.ps1 "D:\Muzik"            # songs
#   .\scripts\add_music.ps1 "D:\Podcastlar" -Kind podcast
#
# Supported: mp3, m4a, aac, ogg, opus, flac, wav (subfolders included). Title/artist/album come from the
# file tags; files without tags are named from "Artist - Title.mp3". Re-running is safe (duplicates are
# skipped). Only add audio you own or are licensed to use.
param(
    [Parameter(Mandatory = $true)] [string] $Folder,
    [ValidateSet("song", "podcast")] [string] $Kind = "song"
)
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

$source = (Resolve-Path $Folder).Path
$count = (Get-ChildItem $source -Recurse -File -Include *.mp3, *.m4a, *.aac, *.ogg, *.opus, *.flac, *.wav).Count
if ($count -eq 0) { throw "No audio files found in $source" }
Write-Host "$count audio files found, copying to the server..."

$target = "/tmp/import-" + [guid]::NewGuid().ToString("N").Substring(0, 8)
docker compose cp "$source" "api:$target"
if ($LASTEXITCODE -ne 0) { throw "docker compose cp failed (is the stack running? docker compose up -d)" }
try {
    docker compose exec -T api python -m app.cli ingest $target --kind $Kind
}
finally {
    docker compose exec -T --user root api rm -rf $target | Out-Null
}
