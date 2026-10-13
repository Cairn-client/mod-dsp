# Copyright (C) 2026 the Cairn contributors. SPDX-License-Identifier: GPL-3.0-only (as the project it is part of)
<#
.SYNOPSIS
    Builds the Cairn mod pack for Dyson Sphere Program (Nebula): release\Cairn-Pack-dsp-<version>.zip and release\pack-index.json
    (what the Cairn launcher reads to see a newer pack exists).

.DESCRIPTION
    An *external* pack that goes into the game's own folder (docs in the launcher repository: docs/PACKS.md, installDir ".").
    Nebula runs on BepInEx, so the pack carries both:

      mod\   the BepInEx build Dyson Sphere Program mods use (the Thunderstore package xiaoye97/BepInEx, its BepInExPack folder: the
             loader files at the game's root) and, under BepInEx\plugins\, Nebula and its API as this repository builds them
      pack.json      the contract with the launcher
      manifest.txt   MOD|<path>|<size>|<sha256>, one line per file

    The pack's version is the VERSION file (strict X.Y.Z, this project's own); Nebula's version (version.json) is the pack's "upstream".
    A file of the game's with the same name and other bytes is never overwritten by the launcher, so a BepInEx the player already has is
    reported, not replaced.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $BepInExZip,
    [string] $DistDir = 'dist\release'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$version = (Get-Content (Join-Path $root 'VERSION') -TotalCount 1).Trim()
if ($version -cnotmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') { throw "VERSION must be strict X.Y.Z, got '$version'" }
$nebulaVersion = ((Get-Content (Join-Path $root 'version.json') -Raw) | ConvertFrom-Json).version
if (-not $nebulaVersion) { throw 'could not read the Nebula version from version.json' }

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$release = Join-Path $root 'release'
$stage = Join-Path $release 'pack-stage'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
$mod = Join-Path $stage 'mod'
New-Item -ItemType Directory -Force -Path $mod | Out-Null

# the loader: the BepInExPack folder of the package, at the game's root (never a path outside the folder)
$destFull = [IO.Path]::GetFullPath($mod).TrimEnd('\') + '\'
$zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $BepInExZip))
try {
    foreach ($e in $zip.Entries) {
        if ($e.FullName.EndsWith('/') -or -not $e.FullName.StartsWith('BepInExPack/')) { continue }
        $rel = $e.FullName.Substring('BepInExPack/'.Length)
        $target = [IO.Path]::GetFullPath((Join-Path $mod ($rel -replace '/', '\')))
        if (-not $target.StartsWith($destFull, [StringComparison]::OrdinalIgnoreCase)) { throw "the archive has a path outside its folder: $($e.FullName)" }
        New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $target, $true)
    }
} finally { $zip.Dispose() }

# Nebula and its API, as this repository's build laid them out
$plugins = Join-Path $mod 'BepInEx\plugins'
foreach ($name in 'nebula-NebulaMultiplayerMod', 'nebula-NebulaMultiplayerModApi') {
    $src = Join-Path $root (Join-Path $DistDir $name)
    if (-not (Test-Path $src)) { throw "the build did not make $src" }
    $dst = Join-Path $plugins $name
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    Copy-Item (Join-Path $src '*') $dst -Recurse -Force
}
Copy-Item (Join-Path $root 'LICENSE') (Join-Path $plugins 'nebula-NebulaMultiplayerMod\nebula.LICENSE') -Force
if (Test-Path (Join-Path $root 'Licenses')) { Copy-Item (Join-Path $root 'Licenses\*') (Join-Path $plugins 'nebula-NebulaMultiplayerMod') -Recurse -Force }

foreach ($n in @('winhttp.dll', 'doorstop_config.ini', 'BepInEx\core\BepInEx.dll', 'BepInEx\plugins\nebula-NebulaMultiplayerMod\NebulaPatcher.dll', 'BepInEx\plugins\nebula-NebulaMultiplayerMod\NebulaModel.dll')) {
    if (-not (Test-Path (Join-Path $mod $n))) { throw "the pack is missing $n" }
}

function Get-Sha256([string] $Path) { (Get-FileHash $Path -Algorithm SHA256).Hash.ToLowerInvariant() }

$launcherMin = '0.3.22'
$packJson = [ordered]@{
    schema      = 2
    id          = 'dsp'
    game        = 'dsp'
    version     = $version
    upstream    = $nebulaVersion
    kind        = 'external'
    installDir  = '.'
    launcherMin = $launcherMin
}
[IO.File]::WriteAllText((Join-Path $stage 'pack.json'), (($packJson | ConvertTo-Json) + "`n"), (New-Object System.Text.UTF8Encoding($false)))

$lines = New-Object System.Collections.Generic.List[string]
foreach ($f in Get-ChildItem $mod -Recurse -File | Sort-Object FullName) {
    $rel = $f.FullName.Substring($mod.Length + 1)
    $lines.Add(('MOD|{0}|{1}|{2}' -f $rel, $f.Length, (Get-Sha256 $f.FullName)))
}
[IO.File]::WriteAllText((Join-Path $stage 'manifest.txt'), (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))

$zipName = "Cairn-Pack-dsp-$version.zip"
$zipPath = Join-Path $release $zipName
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
$fs = [IO.File]::Open($zipPath, 'Create')
try {
    $z = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($f in Get-ChildItem $stage -Recurse -File) {
            $rel = $f.FullName.Substring($stage.Length + 1) -replace '\\', '/'
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($z, $f.FullName, $rel, [System.IO.Compression.CompressionLevel]::Optimal)
        }
    } finally { $z.Dispose() }
} finally { $fs.Dispose() }

$index = [ordered]@{
    schema      = 2
    id          = 'dsp'
    game        = 'dsp'
    version     = $version
    upstream    = $nebulaVersion
    kind        = 'external'
    file        = $zipName
    sha256      = Get-Sha256 $zipPath
    size        = (Get-Item $zipPath).Length
    launcherMin = $launcherMin
}
[IO.File]::WriteAllText((Join-Path $release 'pack-index.json'), (($index | ConvertTo-Json) + "`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "pack: $zipPath ($([math]::Round((Get-Item $zipPath).Length / 1MB, 1)) MB), version $version, Nebula $nebulaVersion, $($lines.Count) files"
