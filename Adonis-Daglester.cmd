@echo off
setlocal DisableDelayedExpansion
title Adonis Daglester
echo Adonis Daglester - Minecraft world backup
echo Close Minecraft and Lunar, then choose your world.
echo After verification, select the highlighted ZIP on Wormhole yourself.
echo.
set "ADONIS_DAGLESTER_FILE=%~f0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; try { $raw=[IO.File]::ReadAllText($env:ADONIS_DAGLESTER_FILE,[Text.Encoding]::UTF8); $parts=[regex]::Split($raw,'(?m)^::ADONIS_POWERSHELL\r?\n'); if($parts.Length -ne 2){throw 'Incomplete file. Download Adonis-Daglester.cmd again.'}; $codeFolder=Join-Path ([IO.Path]::GetTempPath()) ('Adonis-Daglester-'+[Guid]::NewGuid().ToString('N')); [void][IO.Directory]::CreateDirectory($codeFolder); $scriptFile=Join-Path $codeFolder 'Backup-MinecraftWorld.ps1'; [IO.File]::WriteAllText($scriptFile,$parts[1],[Text.UTF8Encoding]::new($false)); & $scriptFile } catch { Write-Host ('Could not start Adonis Daglester: '+$_.Exception.Message) -ForegroundColor Red; exit 1 }"
set "adonisResult=%ERRORLEVEL%"
echo.
pause
exit /b %adonisResult%

:: Included readable PowerShell source. CMD exits before reaching this section.
::ADONIS_POWERSHELL
#requires -Version 5.1
<#
Adonis Daglester. Reads a closed Minecraft Java world, verifies a ZIP, then opens
Wormhole and highlights the ZIP. No upload, browser control, or clipboard access.
The selected world's files are never written to, deleted, or repaired.
#>
[CmdletBinding()]
param(
    [string]$WorldPath,
    [string]$OutputFolder = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Minecraft-Backups')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-FullFolder([string]$Path) {
    $expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
    $full = [IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($expanded))
    if ($full -eq [IO.Path]::GetPathRoot($full)) { return $full }
    return $full.TrimEnd([IO.Path]::DirectorySeparatorChar)
}

function Assert-NoLinks([string]$Path) {
    # Check ancestors too, so junctions cannot bypass the output-folder check.
    while ($Path) {
        if (Test-Path -LiteralPath $Path) {
            if (([IO.File]::GetAttributes($Path) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Use a fully local folder without links, junctions or cloud placeholders: $Path"
            }
        }
        $Path = [IO.Path]::GetDirectoryName($Path)
    }
}

function Get-StreamHash([IO.Stream]$Stream) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($Stream)).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Copy-AndHash([IO.Stream]$Source, [IO.Stream]$Destination, [byte[]]$Buffer) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        while (($count = $Source.Read($Buffer, 0, $Buffer.Length)) -gt 0) {
            $Destination.Write($Buffer, 0, $count)
            [void]$sha.TransformBlock($Buffer, 0, $count, $Buffer, 0)
        }
        [void]$sha.TransformFinalBlock([byte[]]::new(0), 0, 0)
        return [BitConverter]::ToString($sha.Hash).Replace('-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
}

function Get-WorldItems([string]$Root, [switch]$HashFiles) {
    $items = [Collections.Generic.List[object]]::new()
    $folders = [Collections.Generic.Stack[string]]::new()
    $folders.Push($Root)
    while ($folders.Count -gt 0) {
        # .NET includes hidden/system/dot files and reports inaccessible items as errors.
        foreach ($path in [IO.Directory]::GetFileSystemEntries($folders.Pop())) {
            $attributes = [IO.File]::GetAttributes($path)
            if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Linked/cloud item found; nothing was skipped: $path" }
            $isFolder = ($attributes -band [IO.FileAttributes]::Directory) -ne 0
            $length = [long]0; $hash = $null
            if ($isFolder) {
                $folders.Push($path)
                $modified = [IO.Directory]::GetLastWriteTimeUtc($path).Ticks
            } else {
                $info = [IO.FileInfo]::new($path)
                $length = $info.Length; $modified = $info.LastWriteTimeUtc.Ticks
                if ($HashFiles) {
                    $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
                    try { $hash = Get-StreamHash $stream } finally { $stream.Dispose() }
                    $info.Refresh()
                    if ($length -ne $info.Length -or $modified -ne $info.LastWriteTimeUtc.Ticks) { throw "World changed while reading: $path" }
                }
            }
            $items.Add([pscustomobject]@{
                Path = $path.Substring($Root.Length + 1).Replace('\', '/')
                Folder = $isFolder; Length = $length; Modified = $modified
                Attributes = [int]$attributes; SHA256 = $hash
            })
        }
    }
    return $items.ToArray() | Sort-Object Path
}

function Assert-Unchanged($Before, $After) {
    if ($Before.Count -ne $After.Count) { throw 'World files/folders changed. Keep Minecraft closed and retry.' }
    for ($i = 0; $i -lt $Before.Count; $i++) {
        $a = $Before[$i]; $b = $After[$i]
        if ($a.Path -cne $b.Path -or $a.Folder -ne $b.Folder -or $a.Length -ne $b.Length -or
            $a.Modified -ne $b.Modified -or $a.Attributes -ne $b.Attributes -or $a.SHA256 -cne $b.SHA256) {
            throw "World changed during backup: $($a.Path)"
        }
    }
}

$worldLock = $null
$stage = $null
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.IO.Compression
    [Windows.Forms.Application]::EnableVisualStyles()
    Write-Host 'Adonis Daglester - close Minecraft and Lunar before continuing.'
    if (-not $WorldPath) {
        $picker = [Windows.Forms.FolderBrowserDialog]::new()
        try {
            $picker.Description = 'Adonis Daglester: choose the WORLD folder containing level.dat, not the saves folder.'
            $picker.ShowNewFolderButton = $false
            $saves = Join-Path $env:APPDATA '.minecraft\saves'
            if (Test-Path -LiteralPath $saves -PathType Container) { $picker.SelectedPath = $saves }
            if ($picker.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { Write-Host 'Cancelled.'; exit 1 }
            $WorldPath = $picker.SelectedPath
        } finally { $picker.Dispose() }
    }
    $world = Get-FullFolder $WorldPath
    if ($world -eq [IO.Path]::GetPathRoot($world) -or -not (Test-Path -LiteralPath (Join-Path $world 'level.dat') -PathType Leaf)) {
        throw 'Choose a Java world folder with level.dat directly inside it.'
    }
    Assert-NoLinks $world
    $output = Get-FullFolder $OutputFolder
    Assert-NoLinks $output
    if ($output.Equals($world, [StringComparison]::OrdinalIgnoreCase) -or
        $output.StartsWith($world + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The backup folder must be outside the world.'
    }
    $answer = [Windows.Forms.MessageBox]::Show(
        "Back up this world?`r`n$world`r`n`r`nMinecraft and Lunar must be fully closed. Keep them closed until DONE, and pause tools editing or syncing this world.`r`n`r`nThe original is only read. After verification, Wormhole opens for you to select the ZIP yourself.",
        'Adonis Daglester', [Windows.Forms.MessageBoxButtons]::YesNo,
        [Windows.Forms.MessageBoxIcon]::Question, [Windows.Forms.MessageBoxDefaultButton]::Button2)
    if ($answer -ne [Windows.Forms.DialogResult]::Yes) { Write-Host 'Cancelled.'; exit 1 }
    $lockPath = Join-Path $world 'session.lock'
    if (Test-Path -LiteralPath $lockPath) {
        Assert-NoLinks $lockPath
        # Open only an EXISTING lock, read-only. Windows denies writers while held.
        $worldLock = [IO.File]::Open($lockPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    } else { Write-Host 'No session.lock exists. Keeping Minecraft closed is essential.' -ForegroundColor Yellow }

    Write-Host '1/3 Listing all world files...'
    $before = @(Get-WorldItems $world)
    [void][IO.Directory]::CreateDirectory($output)
    $suffix = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $stage = Join-Path $output ('.incomplete-' + $suffix)
    [void][IO.Directory]::CreateDirectory($stage)
    $zipPath = Join-Path $stage 'Minecraft-World.zip'
    $buffer = [byte[]]::new(1048576)
    $zipStream = $null; $zip = $null
    Write-Host '2/3 Creating ZIP and hashing files as they are copied...'
    try {
        $zipStream = [IO.File]::Open($zipPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $zip = [IO.Compression.ZipArchive]::new($zipStream, [IO.Compression.ZipArchiveMode]::Create, $true)
        [void]$zip.CreateEntry('world/')
        foreach ($item in $before) {
            $entryName = 'world/' + $item.Path
            if ($item.Folder) { $entryName += '/' }
            $entry = $zip.CreateEntry($entryName, [IO.Compression.CompressionLevel]::Optimal)
            # ZIP metadata must be set before writing the entry. Dates are limited by ZIP.
            $stamp = [DateTime]::new($item.Modified, [DateTimeKind]::Utc)
            if ($stamp.Year -lt 1980) { $stamp = [DateTime]::new(1980, 1, 1, 0, 0, 0, [DateTimeKind]::Utc) }
            if ($stamp.Year -gt 2107) { $stamp = [DateTime]::new(2107, 12, 31, 23, 59, 58, [DateTimeKind]::Utc) }
            $entry.LastWriteTime = [DateTimeOffset]::new($stamp)
            $entry.ExternalAttributes = $item.Attributes
            if ($item.Folder) { continue }
            $source = $null; $destination = $null
            try {
                $source = [IO.File]::Open((Join-Path $world $item.Path), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
                if ($source.Length -ne $item.Length) { throw "World file size changed: $($item.Path)" }
                $destination = $entry.Open()
                $item.SHA256 = Copy-AndHash $source $destination $buffer
            } finally {
                try { if ($destination) { $destination.Dispose() } }
                finally { if ($source) { $source.Dispose() } }
            }
        }
    } finally {
        try { if ($zip) { $zip.Dispose() } }
        finally { if ($zipStream) { $zipStream.Dispose() } }
    }

    Write-Host '3/3 Reading back the ZIP and rechecking the source...'
    $zipStream = $null; $zip = $null
    try {
        $zipStream = [IO.File]::OpenRead($zipPath)
        $zip = [IO.Compression.ZipArchive]::new($zipStream, [IO.Compression.ZipArchiveMode]::Read, $true)
        if ($zip.Entries.Count -ne ($before.Count + 1)) { throw 'ZIP entry count mismatch.' }
        foreach ($item in $before) {
            $entryName = 'world/' + $item.Path
            if ($item.Folder) { $entryName += '/' }
            $entry = $zip.GetEntry($entryName)
            if ($null -eq $entry -or $entry.Length -ne $item.Length) { throw "ZIP missing/wrong length: $entryName" }
            if ($item.Folder) { continue }
            $stream = $entry.Open()
            try { $hash = Get-StreamHash $stream } finally { $stream.Dispose() }
            if ($hash -cne $item.SHA256) { throw "ZIP checksum mismatch: $entryName" }
        }
    } finally {
        try { if ($zip) { $zip.Dispose() } }
        finally { if ($zipStream) { $zipStream.Dispose() } }
    }
    $after = @(Get-WorldItems $world -HashFiles)
    Assert-Unchanged $before $after
    $stream = [IO.File]::OpenRead($zipPath)
    try { $zipHash = Get-StreamHash $stream } finally { $stream.Dispose() }
    $utf8 = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText((Join-Path $stage 'Minecraft-World.zip.sha256'), "$zipHash  Minecraft-World.zip`r`n", $utf8)
    $notes = @"
Minecraft Java world transfer
ZIP SHA-256: $zipHash

All files under the world, including hidden files and empty folders, are in world/.
Every ZIP file was verified by length and SHA-256. The source was rechecked.
Scan the ZIP with antivirus. This script does not perform a malware scan.
Select Minecraft-World.zip on https://wormhole.app and privately send the full link.
Send the hash separately in your normal chat, plus the exact game/mod versions.
Keep the upload page and PC awake until the recipient finishes downloading.

Recipient: compare Get-FileHash -LiteralPath '.\Minecraft-World.zip' -Algorithm SHA256
with the hash from the sender, then scan and extract into a new empty folder.
Use matching Minecraft/server mods. With the server stopped, place world beside
server.properties and set level-name=world. Keep online-mode=true and whitelist on.
Keep the original ZIP. Mods/configs outside the world folder are not included.
Checksums verify matching bytes, not that files are malware-free or game-valid.
"@
    [IO.File]::WriteAllText((Join-Path $stage 'TRANSFER-INFO.txt'), $notes, $utf8)
    $final = Join-Path $output ('Minecraft-World-' + $suffix)
    [IO.Directory]::Move($stage, $final)
} catch {
    Write-Host "BACKUP STOPPED: $($_.Exception.Message)" -ForegroundColor Red
    if ($stage -and (Test-Path -LiteralPath $stage)) { Write-Host "Do not send incomplete output: $stage" }
    exit 1
} finally { if ($worldLock) { $worldLock.Dispose() } }

Write-Host "`nDONE - VERIFIED BACKUP: $final" -ForegroundColor Green
Write-Host "ZIP SHA-256: $zipHash"
Write-Host 'On Wormhole, choose the highlighted Minecraft-World.zip, then copy its link yourself.'
$openFailed = $false
try { Start-Process 'https://wormhole.app/' }
catch { $openFailed = $true; Write-Host 'Open https://wormhole.app in your browser.' }
try { Start-Process -FilePath 'explorer.exe' -ArgumentList ('/select,"' + (Join-Path $final 'Minecraft-World.zip') + '"') }
catch { $openFailed = $true; Write-Host "Open the backup folder manually: $final" }
if ($openFailed) { Write-Host 'Backup verified; opening a window failed.'; exit 2 }
exit 0
