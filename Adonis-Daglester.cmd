@echo off
setlocal DisableDelayedExpansion
title Adonis Daglester
echo Adonis Daglester - Minecraft world backup and private transfer
echo.
echo This one file includes everything. No extra files or installs are needed.
echo Close Minecraft and Lunar, then pick the world in the window.
echo Your original world is only read. Only the verified ZIP is shared.
echo Wormhole upload uses installed Microsoft Edge and copies the private link.
echo Keep Edge open until the host has finished downloading.
echo.
set "ADONIS_DAGLESTER_FILE=%~f0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; try { $raw=[IO.File]::ReadAllText($env:ADONIS_DAGLESTER_FILE,[Text.Encoding]::UTF8); $parts=[regex]::Split($raw,'(?m)^::ADONIS_FILE:([A-Za-z0-9.-]+)\r?\n'); $allowed=@('Backup-MinecraftWorld.ps1','Send-WorldToWormhole.ps1','START-HERE.md','HOSTING-GUIDE.md'); if($parts.Length -ne 9){throw 'The file is incomplete. Download Adonis-Daglester.cmd again.'}; $seen=@{}; for($i=1;$i -lt $parts.Length;$i+=2){ $name=$parts[$i]; if($allowed -cnotcontains $name -or $seen.ContainsKey($name)){throw 'Unexpected included file.'}; $seen[$name]=$true }; $bundleDir=Join-Path ([IO.Path]::GetTempPath()) ('Adonis-Daglester-'+[Guid]::NewGuid().ToString('N')); [void][IO.Directory]::CreateDirectory($bundleDir); for($i=1;$i -lt $parts.Length;$i+=2){[IO.File]::WriteAllText((Join-Path $bundleDir $parts[$i]),$parts[$i+1],[Text.UTF8Encoding]::new($false))}; Write-Host ('Included scripts and instructions: '+$bundleDir); & (Join-Path $bundleDir 'Backup-MinecraftWorld.ps1') -Easy } catch { Write-Host ('Could not start Adonis Daglester: '+$_.Exception.Message) -ForegroundColor Red; exit 1 }"
set "adonisResult=%ERRORLEVEL%"
echo.
if not "%adonisResult%"=="0" echo The task stopped. Read the message above; do not send incomplete output.
pause
exit /b %adonisResult%

:: The scripts below are readable source, not additional batch commands.
:: This launcher exits above before CMD reaches the included source.
::ADONIS_FILE:Backup-MinecraftWorld.ps1
#requires -Version 5.1
<#
Adonis Daglester - Minecraft Java / Lunar world backup, using Windows PowerShell and .NET.
READ ONLY toward the selected world: no writes, deletes, repairs, or lock creation.
No downloaded code, administrator rights, or permanent policy changes.
After verification, Easy mode automatically selects the ZIP on wormhole.app in Edge.
Inspect this file in Notepad before running it. Keep Minecraft closed throughout.

Easy use: double-click the self-contained Adonis-Daglester.cmd.
Normal use: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Backup-MinecraftWorld.ps1
Optional: add -WorldPath 'D:\Games\saves\Our World' -OutputFolder 'D:\Backups'
Or: add -SavesPath 'D:\LunarInstance\saves' to choose from another saves folder.
#>
[CmdletBinding()]
param(
    [string]$WorldPath,
    [string]$SavesPath = (Join-Path $env:APPDATA '.minecraft\saves'),
    [string]$OutputFolder = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Minecraft-Backups'),
    [switch]$Easy,
    [switch]$ManualShare
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-FullFolderPath([string]$Path) {
    $expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
    $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($expanded)
    $full = [IO.Path]::GetFullPath($full)
    if ($full -eq [IO.Path]::GetPathRoot($full)) { return $full }
    return $full.TrimEnd([IO.Path]::DirectorySeparatorChar)
}

function Assert-NoLinks([string]$Path) {
    # Check ancestors too: a junction can otherwise bypass the output-inside-world check.
    $current = $Path
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            $attributes = [IO.File]::GetAttributes($current)
            if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Linked/junction/cloud-placeholder paths are not supported: $current. Use a fully local ordinary folder."
            }
        }
        $current = [IO.Path]::GetDirectoryName($current)
    }
}

function Assert-GameClosed {
    # Deliberately conservative: unrelated Java apps also have to be closed.
    $running = @(Get-Process | Where-Object {
        $_.ProcessName -match '^(java|javaw|minecraft.*|lunar.*)$'
    })
    if ($running.Count -gt 0) {
        $names = ($running | Select-Object -ExpandProperty ProcessName -Unique) -join ', '
        throw "Close Minecraft, Lunar Client, their launchers, and Java apps, then retry. Still running: $names. Nothing will be force-closed."
    }
}

function Select-WorldWithWindow([string]$SavesFolder) {
    $form = [Windows.Forms.Form]::new()
    $form.Text = 'Adonis Daglester - choose your world'
    $form.ClientSize = [Drawing.Size]::new(600, 365)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true

    $label = [Windows.Forms.Label]::new()
    $label.Text = "Select your world below. If it is missing, click Browse for world.`r`nThe original world will only be read. Keep Minecraft and Lunar closed."
    $label.SetBounds(15, 15, 570, 45)
    $form.Controls.Add($label)

    $list = [Windows.Forms.ListBox]::new()
    $list.SetBounds(15, 65, 570, 230)
    $list.DisplayMember = 'Name'
    $form.Controls.Add($list)
    if (Test-Path -LiteralPath $SavesFolder -PathType Container) {
        Assert-NoLinks $SavesFolder
        foreach ($candidate in @(Get-ChildItem -LiteralPath $SavesFolder -Directory -Force | Sort-Object Name)) {
            if (Test-Path -LiteralPath (Join-Path $candidate.FullName 'level.dat') -PathType Leaf) {
                [void]$list.Items.Add($candidate)
            }
        }
    }

    $browse = [Windows.Forms.Button]::new()
    $browse.Text = 'Browse for world...'
    $browse.SetBounds(15, 315, 165, 32)
    $form.Controls.Add($browse)
    $start = [Windows.Forms.Button]::new()
    $start.Text = 'Back up this world'
    $start.SetBounds(290, 315, 175, 32)
    $start.Enabled = $false
    $form.Controls.Add($start)
    $cancel = [Windows.Forms.Button]::new()
    $cancel.Text = 'Cancel'
    $cancel.SetBounds(475, 315, 110, 32)
    $cancel.DialogResult = [Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancel)
    $form.CancelButton = $cancel
    $form.AcceptButton = $start

    $list.Add_SelectedIndexChanged({ $start.Enabled = $list.SelectedIndex -ge 0 })
    $start.Add_Click({
        if ($list.SelectedIndex -ge 0) {
            $form.Tag = $list.SelectedItem.FullName
            $form.DialogResult = [Windows.Forms.DialogResult]::OK
        }
    })
    $browse.Add_Click({
        $picker = [Windows.Forms.FolderBrowserDialog]::new()
        try {
            $picker.Description = 'Select the WORLD folder containing level.dat (not the saves folder).'
            $picker.ShowNewFolderButton = $false
            if (Test-Path -LiteralPath $SavesFolder -PathType Container) { $picker.SelectedPath = $SavesFolder }
            if ($picker.ShowDialog($form) -eq [Windows.Forms.DialogResult]::OK) {
                if (Test-Path -LiteralPath (Join-Path $picker.SelectedPath 'level.dat') -PathType Leaf) {
                    $form.Tag = $picker.SelectedPath
                    $form.DialogResult = [Windows.Forms.DialogResult]::OK
                } else {
                    [void][Windows.Forms.MessageBox]::Show($form, 'Choose the world folder with level.dat directly inside it.', 'Choose a world', 'OK', 'Information')
                }
            }
        } finally { $picker.Dispose() }
    })
    if ($list.Items.Count -gt 0) { $list.SelectedIndex = 0 }
    try {
        if ($form.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) { return [string]$form.Tag }
        return $null
    } finally { $form.Dispose() }
}

function Get-StreamHash([IO.Stream]$Stream) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($Stream)).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-WorldInventory([string]$Root, [switch]$HashFiles) {
    $items = [System.Collections.Generic.List[object]]::new()
    $pending = [System.Collections.Generic.Stack[string]]::new()
    $pending.Push($Root)
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        # .NET enumeration includes hidden/system/dot files. No wildcard expansion.
        foreach ($path in [IO.Directory]::GetFileSystemEntries($directory)) {
            $attributes = [IO.File]::GetAttributes($path)
            if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "World contains a linked/junction/cloud-placeholder item: $path. Nothing was skipped; backup stopped."
            }
            $relative = $path.Substring($Root.Length + 1).Replace('\', '/')
            $isDirectory = ($attributes -band [IO.FileAttributes]::Directory) -ne 0
            $length = [long]0
            $hash = $null
            if ($isDirectory) {
                $pending.Push($path)
                $modified = [IO.Directory]::GetLastWriteTimeUtc($path).Ticks
            } else {
                $info = [IO.FileInfo]::new($path)
                $length = $info.Length
                $modified = $info.LastWriteTimeUtc.Ticks
                if ($HashFiles) {
                    $inputStream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
                    try { $hash = Get-StreamHash $inputStream }
                    finally { $inputStream.Dispose() }
                    $info.Refresh()
                    if ($length -ne $info.Length -or $modified -ne $info.LastWriteTimeUtc.Ticks) {
                        throw "World changed while reading: $relative. Close all writers and retry."
                    }
                }
            }
            $items.Add([pscustomobject]@{
                RelativePath = $relative; Directory = $isDirectory; Length = $length
                ModifiedUtcTicks = $modified; Attributes = [int]$attributes; SHA256 = $hash
            })
        }
    }
    return $items.ToArray() | Sort-Object -Property RelativePath
}

function Assert-SameInventory($Before, $After) {
    if ($Before.Count -ne $After.Count) { throw 'World files/folders changed during backup. Retry with Minecraft closed.' }
    for ($i = 0; $i -lt $Before.Count; $i++) {
        $a = $Before[$i]; $b = $After[$i]
        if ($a.RelativePath -cne $b.RelativePath -or $a.Directory -ne $b.Directory -or
            $a.Length -ne $b.Length -or $a.ModifiedUtcTicks -ne $b.ModifiedUtcTicks -or
            $a.Attributes -ne $b.Attributes -or $a.SHA256 -cne $b.SHA256) {
            throw "World changed during backup: $($a.RelativePath). No verified backup published."
        }
    }
}

$worldLock = $null
$stage = $null
$published = $false
try {
    if ($Easy) {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        [Windows.Forms.Application]::EnableVisualStyles()
    }
    Write-Host "`nAdonis Daglester - your original Minecraft world is only read." -ForegroundColor Cyan
    Write-Host 'Save and Quit, then fully exit Minecraft and Lunar Client. Keep them closed until DONE.'
    Write-Host 'Pause cloud sync and other tools that could edit the world.'
    if (-not $ManualShare) { Write-Host 'After verification, the finished ZIP can be automatically uploaded to wormhole.app in a separate Edge window.' }
    Assert-GameClosed

    if (-not $WorldPath -and $Easy) {
        $WorldPath = Select-WorldWithWindow (Get-FullFolderPath $SavesPath)
        if (-not $WorldPath) { throw 'Cancelled: no world selected.' }
    }
    if (-not $WorldPath) {
        $saves = Get-FullFolderPath $SavesPath
        $worlds = @()
        if (Test-Path -LiteralPath $saves -PathType Container) {
            Assert-NoLinks $saves
            $worlds = @(Get-ChildItem -LiteralPath $saves -Directory -Force | Where-Object {
                Test-Path -LiteralPath (Join-Path $_.FullName 'level.dat') -PathType Leaf
            } | Sort-Object Name)
        }
        Write-Host "`nWorlds in: $saves"
        for ($i = 0; $i -lt $worlds.Count; $i++) { Write-Host ('{0}. {1}' -f ($i + 1), $worlds[$i].Name) }
        Write-Host 'Choose a number, or paste the full WORLD folder path (the folder containing level.dat).'
        $choice = (Read-Host 'World').Trim().Trim('"')
        $number = 0
        if ([int]::TryParse($choice, [ref]$number) -and $number -ge 1 -and $number -le $worlds.Count) {
            $WorldPath = $worlds[$number - 1].FullName
        } elseif (-not [string]::IsNullOrWhiteSpace($choice)) {
            $WorldPath = $choice
        } else { throw 'No world selected.' }
    }

    $world = Get-FullFolderPath $WorldPath
    if ($world -eq [IO.Path]::GetPathRoot($world)) { throw 'Choose a world folder, not a drive root.' }
    if (-not (Test-Path -LiteralPath $world -PathType Container) -or
        -not (Test-Path -LiteralPath (Join-Path $world 'level.dat') -PathType Leaf)) {
        throw 'Select a Java Edition world folder with level.dat directly inside it (not saves, not a ZIP).'
    }
    Assert-NoLinks $world
    $output = Get-FullFolderPath $OutputFolder
    Assert-NoLinks $output
    if ($output.Equals($world, [StringComparison]::OrdinalIgnoreCase) -or
        $output.StartsWith($world + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The backup output folder must be outside the selected world.'
    }

    Write-Host "`nSelected: $world"
    Write-Host "Backup location: $output"
    if ($Easy) {
        $sharingDescription = if ($ManualShare) { 'After verification, Wormhole will open for manual sharing.' } else { 'After verification, the ZIP will be automatically selected and uploaded on wormhole.app in a separate Edge window.' }
        $confirmation = [Windows.Forms.MessageBox]::Show(
            "Back up this world?`r`n$world`r`n`r`nConfirm Minecraft and Lunar are fully closed and will stay closed until DONE.`r`nThe original world is only read.`r`n`r`n$sharingDescription",
            'Minecraft must be closed', [Windows.Forms.MessageBoxButtons]::YesNo,
            [Windows.Forms.MessageBoxIcon]::Question, [Windows.Forms.MessageBoxDefaultButton]::Button2)
        if ($confirmation -ne [Windows.Forms.DialogResult]::Yes) { throw 'Cancelled: Minecraft must be closed.' }
    } else {
        if ((Read-Host 'Type CLOSED to confirm Minecraft/Lunar are fully closed and will stay closed') -cne 'CLOSED') {
            throw 'Cancelled: Minecraft must be closed.'
        }
    }
    Assert-GameClosed

    $lockPath = Join-Path $world 'session.lock'
    if (Test-Path -LiteralPath $lockPath) {
        Assert-NoLinks $lockPath
        # Open EXISTING lock read-only. Deny writes/deletes while backing up on Windows.
        # Never create, overwrite, delete, or repair session.lock.
        $worldLock = [IO.File]::Open($lockPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    } else {
        Write-Host 'No session.lock exists. Keep Minecraft closed; source hashes will still be checked.' -ForegroundColor Yellow
    }

    Add-Type -AssemblyName System.IO.Compression
    Write-Host "`n1/4 Reading and hashing ALL world files (including hidden files)..."
    $before = @(Get-WorldInventory $world -HashFiles)
    $files = @($before | Where-Object { -not $_.Directory })
    $totalBytes = [long]0
    foreach ($item in $files) { $totalBytes += $item.Length }
    Write-Host ('{0} files, {1:N2} GB uncompressed. Verification reads the world more than once.' -f $files.Count, ($totalBytes / 1GB))

    [void][IO.Directory]::CreateDirectory($output)
    $suffix = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $stage = Join-Path $output ('.incomplete-' + $suffix)
    [void][IO.Directory]::CreateDirectory($stage)
    $zipPath = Join-Path $stage 'Minecraft-World.zip'
    $archiveStream = $null; $archive = $null
    Write-Host '2/4 Creating ZIP...'
    try {
        $archiveStream = [IO.File]::Open($zipPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $archive = [IO.Compression.ZipArchive]::new($archiveStream, [IO.Compression.ZipArchiveMode]::Create, $true)
        # A fixed outer folder makes installation unambiguous, regardless of the original name.
        [void]$archive.CreateEntry('world/')
        foreach ($item in $before) {
            $entryName = 'world/' + $item.RelativePath
            if ($item.Directory) {
                $entry = $archive.CreateEntry($entryName + '/')
            } else {
                $entry = $archive.CreateEntry($entryName, [IO.Compression.CompressionLevel]::Optimal)
            }
            # Set metadata BEFORE opening an entry for writing (required in Create mode).
            $stamp = [DateTime]::new($item.ModifiedUtcTicks, [DateTimeKind]::Utc)
            if ($stamp.Year -lt 1980) { $stamp = [DateTime]::new(1980, 1, 1, 0, 0, 0, [DateTimeKind]::Utc) }
            if ($stamp.Year -gt 2107) { $stamp = [DateTime]::new(2107, 12, 31, 23, 59, 58, [DateTimeKind]::Utc) }
            $entry.LastWriteTime = [DateTimeOffset]::new($stamp)
            $entry.ExternalAttributes = $item.Attributes
            if (-not $item.Directory) {
                $inputStream = $null; $entryStream = $null
                try {
                    $sourcePath = Join-Path $world $item.RelativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)
                    $inputStream = [IO.File]::Open($sourcePath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
                    $entryStream = $entry.Open()
                    $inputStream.CopyTo($entryStream, 1048576)
                } finally {
                    if ($entryStream) { $entryStream.Dispose() }
                    if ($inputStream) { $inputStream.Dispose() }
                }
            }
        }
    } finally {
        if ($archive) { $archive.Dispose() }
        if ($archiveStream) { $archiveStream.Dispose() }
    }

    Write-Host '3/4 Reopening ZIP and verifying every file SHA-256 and length...'
    $archiveStream = $null; $archive = $null
    try {
        $archiveStream = [IO.File]::OpenRead($zipPath)
        $archive = [IO.Compression.ZipArchive]::new($archiveStream, [IO.Compression.ZipArchiveMode]::Read, $true)
        if ($archive.Entries.Count -ne ($before.Count + 1)) { throw 'ZIP entry count verification failed.' }
        foreach ($item in $before) {
            $entryName = 'world/' + $item.RelativePath
            if ($item.Directory) { $entryName += '/' }
            $entry = $archive.GetEntry($entryName)
            if ($null -eq $entry -or $entry.Length -ne $item.Length) { throw "ZIP missing/wrong length: $entryName" }
            if (-not $item.Directory) {
                $entryStream = $entry.Open()
                try { $entryHash = Get-StreamHash $entryStream }
                finally { $entryStream.Dispose() }
                if ($entryHash -cne $item.SHA256) { throw "ZIP checksum mismatch: $entryName" }
            }
        }
    } finally {
        if ($archive) { $archive.Dispose() }
        if ($archiveStream) { $archiveStream.Dispose() }
    }

    Write-Host '4/4 Rechecking the source, then writing the ZIP checksum...'
    $after = @(Get-WorldInventory $world -HashFiles)
    Assert-SameInventory $before $after
    Assert-GameClosed
    $zipStream = [IO.File]::OpenRead($zipPath)
    try { $zipHash = Get-StreamHash $zipStream }
    finally { $zipStream.Dispose() }
    $utf8 = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText((Join-Path $stage 'Minecraft-World.zip.sha256'), "$zipHash  Minecraft-World.zip`r`n", $utf8)
    $manifest = [ordered]@{
        Format = 'MinecraftWorldBackup-v1'; CreatedUtc = [DateTime]::UtcNow.ToString('o')
        Archive = 'Minecraft-World.zip'; SHA256 = $zipHash
        FileCount = $files.Count; UncompressedBytes = $totalBytes
        Verification = 'Every ZIP file matched source SHA256 and length; source inventory and hashes rechecked.'
        Items = $before
    }
    [IO.File]::WriteAllText((Join-Path $stage 'Minecraft-World.manifest.json'), ($manifest | ConvertTo-Json -Depth 6), $utf8)
    $handoff = @"
MINECRAFT JAVA WORLD - VERIFIED TRANSFER

Minecraft-World.zip SHA-256:
$zipHash

All world files, including hidden files, were included under world/.
Every archived file was read back and matched to its source SHA-256 and length.
The source inventory and hashes were checked again. The original was only read.
This verifies a faithful copy, NOT that the world is malware-free or game-valid.

SENDER (friend with the world):
1. Scan the ZIP with your antivirus. No scan is performed by this script.
2. Easy mode automatically selects Minecraft-World.zip on https://wormhole.app.
3. Send the COMPLETE private link, including everything after #, to the host.
4. Paste the copied share link into chat. Send this SHA-256 separately too.
5. Keep the upload page open until the host finishes downloading.
6. Tell the host the exact Minecraft version, loader, mods and datapacks used.

HOST (recipient):
You do not need to run the sender's PowerShell script.
Compare this command's output with the hash sent separately in chat:
Get-FileHash -LiteralPath '.\Minecraft-World.zip' -Algorithm SHA256
Scan the ZIP and extracted folder with antivirus; leave protection enabled.
Extract to a NEW empty folder. world\level.dat must exist directly inside world.
Do not run executable/script/JAR files that happen to be inside the world.
Get the dedicated server software separately from its official source.
Use the same Minecraft version and required server mods. Keep the ZIP untouched.
With the server stopped, place world beside server.properties; use level-name=world.
Keep online-mode=true; enable white-list=true and enforce-whitelist=true.
See START-HERE.md supplied with the script for server setup and inventory notes.

The ZIP contains the world folder, not the whole client or a server installer.
Any custom files inside the world are included too: inspect them before sharing.
Files outside the world (mods, configs, shaders, client settings) are not included.
ZIP does not preserve NTFS permissions or alternate data streams; it includes normal
world file contents, hidden files and empty directories. No exclusions were applied.
"@
    [IO.File]::WriteAllText((Join-Path $stage 'TRANSFER-INFO.txt'), $handoff, $utf8)
    $final = Join-Path $output ('Minecraft-World-' + $suffix)
    [IO.Directory]::Move($stage, $final)
    $published = $true
} catch {
    Write-Host "`nBACKUP STOPPED: $($_.Exception.Message)" -ForegroundColor Red
    if ($stage -and (Test-Path -LiteralPath $stage)) {
        Write-Host "Incomplete output is here; DO NOT SEND IT: $stage"
    }
    Write-Host 'The script did not write to or delete anything in the original world.'
    exit 1
} finally {
    if ($worldLock) { $worldLock.Dispose() }
}

if ($published) {
    Write-Host "`nDONE - VERIFIED BACKUP: $final" -ForegroundColor Green
    Write-Host "ZIP SHA-256: $zipHash"
    Write-Host 'Read TRANSFER-INFO.txt. Scan the ZIP before sharing. This was not a malware scan.'
    Write-Host 'Your friend runs this backup; the recipient hosts the server. The world is unchanged.'
    Write-Host 'The original world is unchanged. Only the verified ZIP will be selected for sharing.'
    try {
        $openSharing = [bool]$Easy
        if (-not $Easy) { $openSharing = (Read-Host 'Share the verified ZIP on Wormhole now? [y/N]') -match '^(y|yes)$' }
        if ($openSharing) {
            if ($ManualShare) {
                Start-Process 'https://wormhole.app/'
                Start-Process -FilePath 'explorer.exe' -ArgumentList ('/select,"' + (Join-Path $final 'Minecraft-World.zip') + '"')
            } else {
                $uploader = Join-Path $PSScriptRoot 'Send-WorldToWormhole.ps1'
                if (-not (Test-Path -LiteralPath $uploader -PathType Leaf)) { throw 'The upload helper is missing. Run the single-file launcher again.' }
                & $uploader -ZipPath (Join-Path $final 'Minecraft-World.zip') -ExpectedSHA256 $zipHash
            }
        }
    } catch {
        Write-Host "Automatic sharing could not be confirmed: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host 'Your VERIFIED BACKUP is safe. No share link is being claimed as ready.'
        Write-Host 'For manual sharing, drag the highlighted ZIP onto Wormhole. Close any failed transfer-only Edge window.'
        try {
            Start-Process 'https://wormhole.app/'
            Start-Process -FilePath 'explorer.exe' -ArgumentList ('/select,"' + (Join-Path $final 'Minecraft-World.zip') + '"')
        } catch { Write-Host "Open https://wormhole.app manually. ZIP folder: $final" }
    }
}
::ADONIS_FILE:Send-WorldToWormhole.ps1
#requires -Version 5.1
<#
Automatically selects a verified ZIP on https://wormhole.app in installed Microsoft Edge.
Uses only Windows PowerShell/.NET and Edge's documented browser automation interface.
No downloaded code, browser extensions, administrator access, or existing browser profiles.
Only the supplied ZIP is selected. Clipboard receives the private share link, not a message.
Keep this dedicated browser window open until the recipient finishes downloading.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ZipPath,
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedSHA256
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-BrowserCommand($Connection, [string]$Method, [hashtable]$Parameters = @{}) {
    $Connection.Id++
    $id = $Connection.Id
    $json = @{ id = $id; method = $Method; params = $Parameters } | ConvertTo-Json -Depth 12 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $timeout = [Threading.CancellationTokenSource]::new(15000)
    try {
        $segment = [ArraySegment[byte]]::new($bytes)
        $Connection.Socket.SendAsync($segment, [Net.WebSockets.WebSocketMessageType]::Text, $true, $timeout.Token).GetAwaiter().GetResult()
        while ($true) {
            $message = [IO.MemoryStream]::new()
            try {
                $buffer = [byte[]]::new(65536)
                do {
                    $received = $Connection.Socket.ReceiveAsync([ArraySegment[byte]]::new($buffer), $timeout.Token).GetAwaiter().GetResult()
                    if ($received.MessageType -eq [Net.WebSockets.WebSocketMessageType]::Close) { throw 'The transfer browser was closed.' }
                    $message.Write($buffer, 0, $received.Count)
                    if ($message.Length -gt 4194304) { throw 'Unexpectedly large browser response.' }
                } while (-not $received.EndOfMessage)
                $reply = [Text.Encoding]::UTF8.GetString($message.ToArray()) | ConvertFrom-Json
            } finally { $message.Dispose() }
            if ($reply.PSObject.Properties['method']) {
                if ($reply.method -eq 'Page.fileChooserOpened') { $Connection.FileChooser = $reply.params }
                continue
            }
            if ($reply.PSObject.Properties['id'] -and $reply.id -eq $id) {
                if ($reply.PSObject.Properties['error']) { throw "Browser automation failed: $($reply.error.message)" }
                return $reply.result
            }
        }
    } finally { $timeout.Dispose() }
}

function Get-PageValue($Connection, [string]$Expression) {
    $reply = Invoke-BrowserCommand $Connection 'Runtime.evaluate' @{
        expression = $Expression; returnByValue = $true; userGesture = $true
    }
    if ($reply.PSObject.Properties['exceptionDetails']) { throw 'Wormhole page inspection failed.' }
    if (-not $reply.result.PSObject.Properties['value']) { return $null }
    return $reply.result.value
}

function Get-TransferTarget([int]$Port) {
    $request = [Net.WebRequest]::Create("http://127.0.0.1:$Port/json/list")
    $request.Proxy = $null
    $request.Timeout = 2000
    $request.ReadWriteTimeout = 2000
    $response = $null; $reader = $null
    try {
        $response = $request.GetResponse()
        $reader = [IO.StreamReader]::new($response.GetResponseStream())
        $targets = $reader.ReadToEnd() | ConvertFrom-Json
        foreach ($target in $targets) {
            if ($target.type -eq 'page' -and $target.url -match '^https://wormhole\.app(?:/|$)') { return $target }
        }
        return $null
    } finally {
        if ($reader) { $reader.Dispose() }
        if ($response) { $response.Dispose() }
    }
}

$zipStream = $null
$connection = $null
$browser = $null
$linkReady = $false
try {
    $ZipPath = [IO.Path]::GetFullPath($ZipPath)
    $zipStream = [IO.File]::Open($ZipPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $actualHash = [BitConverter]::ToString($sha.ComputeHash($zipStream)).Replace('-', '') }
    finally { $sha.Dispose() }
    if ($actualHash -ine $ExpectedSHA256) { throw 'ZIP checksum changed. Upload was not started.' }

    $edge = $null
    foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramFiles, $env:LOCALAPPDATA)) {
        if (-not $base) { continue }
        $candidate = Join-Path $base 'Microsoft\Edge\Application\msedge.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $edge = $candidate; break }
    }
    if (-not $edge) { throw 'Microsoft Edge was not found. The verified ZIP is still available for manual sharing.' }

    # Fresh, transfer-only profile. Never attach to normal tabs, cookies, or signed-in accounts.
    $transferProfile = Join-Path ([IO.Path]::GetTempPath()) ('Minecraft-Wormhole-' + [Guid]::NewGuid().ToString('N'))
    $activePortFile = Join-Path $transferProfile 'DevToolsActivePort'
    $arguments = '--no-first-run --no-default-browser-check --new-window --remote-debugging-address=127.0.0.1 --remote-debugging-port=0 --user-data-dir="' + $transferProfile + '" https://wormhole.app/'
    Write-Host 'Opening a separate Microsoft Edge window for the verified ZIP...'
    $browser = Start-Process -FilePath $edge -ArgumentList $arguments -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(40)
    $port = 0
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path -LiteralPath $activePortFile) {
            $lines = [IO.File]::ReadAllLines($activePortFile)
            if ($lines.Length -gt 0 -and [int]::TryParse($lines[0], [ref]$port) -and $port -gt 0 -and $port -lt 65536) { break }
        }
        Start-Sleep -Milliseconds 250
    }
    if (-not $port) { throw 'Edge automation did not start. Your computer may block browser automation.' }
    # Never use a debugging listener exposed to the local network.
    $listeners = @([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners() | Where-Object { $_.Port -eq $port })
    if ($listeners.Count -eq 0) { throw 'The local transfer browser is not listening.' }
    foreach ($listener in $listeners) {
        if (-not [Net.IPAddress]::IsLoopback($listener.Address)) { throw 'Refusing a browser automation listener outside this computer.' }
    }

    $target = $null
    $deadline = [DateTime]::UtcNow.AddSeconds(60)
    while ([DateTime]::UtcNow -lt $deadline -and -not $target) {
        try { $target = Get-TransferTarget $port } catch { $target = $null }
        if (-not $target) { Start-Sleep -Milliseconds 500 }
    }
    if (-not $target) { throw 'The Wormhole page did not load. Check the connection and try again.' }
    $socketUri = [Uri]$target.webSocketDebuggerUrl
    if ($socketUri.Scheme -ne 'ws' -or -not $socketUri.IsLoopback -or $socketUri.Port -ne $port) {
        throw 'Unexpected browser automation endpoint.'
    }
    $socket = [Net.WebSockets.ClientWebSocket]::new()
    $socket.Options.Proxy = $null
    $connection = @{ Socket = $socket; Id = 0; FileChooser = $null }
    $timeout = [Threading.CancellationTokenSource]::new(15000)
    try { $socket.ConnectAsync($socketUri, $timeout.Token).GetAwaiter().GetResult() }
    finally { $timeout.Dispose() }

    [void](Invoke-BrowserCommand $connection 'Page.enable')
    [void](Invoke-BrowserCommand $connection 'Page.setInterceptFileChooserDialog' @{ enabled = $true })
    $deadline = [DateTime]::UtcNow.AddSeconds(60)
    $fileSelected = $false
    $menuOpened = $false
    $chooserRequested = $false
    while ([DateTime]::UtcNow -lt $deadline -and -not $fileSelected) {
        $origin = Get-PageValue $connection 'location.origin'
        if ($origin -eq 'null') { Start-Sleep -Milliseconds 500; continue }
        if ($origin -ne 'https://wormhole.app') { throw 'The browser is not on the secure Wormhole site. Nothing was selected.' }
        # A standard file input is enough; no simulated typing or clipboard pastes.
        $document = Invoke-BrowserCommand $connection 'DOM.getDocument' @{ depth = 0 }
        $fileInputNode = Invoke-BrowserCommand $connection 'DOM.querySelector' @{
            nodeId = $document.root.nodeId; selector = 'input[type="file"]:not([webkitdirectory])'
        }
        if ($fileInputNode.nodeId -gt 0) {
            [void](Invoke-BrowserCommand $connection 'DOM.setFileInputFiles' @{ nodeId = $fileInputNode.nodeId; files = @($ZipPath) })
            $fileSelected = $true
        } elseif ($connection.FileChooser) {
            [void](Invoke-BrowserCommand $connection 'DOM.setFileInputFiles' @{ backendNodeId = $connection.FileChooser.backendNodeId; files = @($ZipPath) })
            $fileSelected = $true
        } else {
            # Wormhole may create its file input only after opening its Select files menu.
            if (-not $menuOpened) {
                $menuOpened = [bool](Get-PageValue $connection "(() => { const b = document.querySelector('button[id^=menu-button]'); if (!b) return false; b.click(); return true; })()")
            } elseif (-not $chooserRequested) {
                $chooserRequested = [bool](Get-PageValue $connection "(() => { const b = document.querySelector('button[id^=menu-list][id*=menuitem]'); if (!b) return false; b.click(); return true; })()")
            }
            Start-Sleep -Milliseconds 500
        }
    }
    if (-not $fileSelected) { throw 'The Wormhole file picker could not be automated. The site may have changed.' }
    Write-Host 'Verified ZIP selected on Wormhole. Waiting for a private link...'

    # Read only the page URL and visible link fields. Never inspect browser storage or credentials.
    $readState = @'
(() => {
  if (location.origin !== 'https://wormhole.app') return { error: 'origin' };
  const valid = /^https:\/\/wormhole\.app\/[A-Za-z0-9_-]{3,128}#[A-Za-z0-9_=-]{16,256}$/;
  const candidates = [location.href];
  for (const e of document.querySelectorAll('input,textarea,a,button')) {
    if (e.value) candidates.push(e.value.trim());
    if (e.href) candidates.push(e.href);
    if (e.textContent && e.textContent.length < 600) candidates.push(e.textContent.trim());
  }
  const headings = Array.from(document.querySelectorAll('h1,h2,h3,[role="alert"]'), e => e.textContent.trim());
  const failed = headings.some(t => /^(upload failed|transfer failed|something went wrong|file too large)\b/i.test(t));
  const phase = headings.some(t => /^Uploaded\b/i.test(t)) ? 'uploaded' :
    headings.some(t => /^Direct transfer\b/i.test(t)) ? 'direct' : 'pending';
  return { link: candidates.find(v => valid.test(v)) || null, phase, failed };
})()
'@
    $deadline = [DateTime]::UtcNow.AddMinutes(10)
    $state = $null
    $link = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        $state = Get-PageValue $connection $readState
        if ($null -ne $state) {
            if ($state.PSObject.Properties['error']) { throw 'Wormhole left its secure transfer page.' }
            if ($state.failed) { throw 'Wormhole reported a transfer error. Check the browser window.' }
            if ($state.link) { $link = [string]$state.link; break }
        }
        Start-Sleep -Milliseconds 750
    }
    if (-not $link -or $link -cnotmatch '^https://wormhole\.app/[A-Za-z0-9_-]{3,128}#[A-Za-z0-9_=-]{16,256}$') {
        throw 'A complete private share link was not confirmed. Check Wormhole in the browser.'
    }
    $notePath = Join-Path ([IO.Path]::GetDirectoryName($ZipPath)) 'WORMHOLE-LINK.txt'
    $note = "$link`r`n`r`nZIP SHA-256: $ExpectedSHA256`r`n`r`nThe link exists; the upload may still be running. Keep the Edge window and PC awake until the recipient has downloaded and checked the ZIP.`r`nKeep the complete link private, including the part after #.`r`n"
    [IO.File]::WriteAllText($notePath, $note, [Text.UTF8Encoding]::new($false))
    $linkReady = $true
    $copied = $false
    for ($attempt = 0; $attempt -lt 5 -and -not $copied; $attempt++) {
        try { Set-Clipboard -Value $link; $copied = $true } catch { Start-Sleep -Milliseconds 150 }
    }
    if (-not $copied) { Write-Host 'Clipboard is busy. The link is saved in WORMHOLE-LINK.txt.' }
    Write-Host "`nWORMHOLE LINK READY: $link" -ForegroundColor Green
    if ($copied) { Write-Host 'Link copied. Paste it into your chat with the host.' }
    Write-Host "Also saved here: $notePath"
    Write-Host 'IMPORTANT: A link is not proof the upload is finished. Keep the Edge window and PC awake until the host finishes downloading.' -ForegroundColor Yellow
    Write-Host 'Use this separate window only for this transfer. Close it when the host confirms receipt.'
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $message = if ($copied) { 'Your Wormhole link is copied. Paste it into your chat with the host.' } else { 'Your Wormhole link is saved in WORMHOLE-LINK.txt beside the ZIP.' }
        [void][Windows.Forms.MessageBox]::Show("$message`r`n`r`nKeep the Edge window and PC awake until the host finishes downloading. The upload may still be running.", 'World link ready', 'OK', 'Information')
    } catch { Write-Host 'Read the share link above or open WORMHOLE-LINK.txt.' }
} finally {
    # On failure close ONLY our isolated browser; never terminate the user's normal browser.
    if (-not $linkReady -and $connection -and $connection.Socket.State -eq [Net.WebSockets.WebSocketState]::Open) {
        try { [void](Invoke-BrowserCommand $connection 'Browser.close') } catch { }
    }
    if (-not $linkReady -and $browser) {
        try { $browser.Refresh(); if (-not $browser.HasExited) { [void]$browser.CloseMainWindow() } } catch { }
    }
    if ($connection) { $connection.Socket.Dispose() }
    if ($zipStream) { $zipStream.Dispose() }
}
::ADONIS_FILE:START-HERE.md
# Adonis Daglester

Your friend sends the Minecraft world; you host it.

## Your friend — on the Windows PC with the world

1. Save and Quit, then **fully exit Minecraft, Lunar Client and their launchers**. Keep them closed during backup. Pause any sync/editing tools working on the world.
2. Download **Adonis-Daglester.cmd** and double-click it. **That one file contains everything needed**: it unpacks its readable scripts into its own temporary folder and runs them. No ZIP to extract, commands to type, administrator rights, extra downloads or installs. **Microsoft Edge must already be installed.** The launcher permits its included scripts only in its own PowerShell process; antivirus and permanent settings stay enabled/unchanged.
3. Pick your world in the window and click **Back up this world**, then confirm the game is closed and the verified ZIP can be sent to **wormhole.app**. If it is missing, click **Browse for world…** and choose the **world folder containing `level.dat`**. If unsure of the location, use the game's **Edit → Open World Folder** before quitting, where available.
4. Wait for **DONE — VERIFIED BACKUP**. Find `Minecraft-World.zip` in the printed folder under **Documents\Minecraft-Backups**. Hidden files are included. The original is only read. Each ZIP file is checked by SHA-256, and the source is rechecked for changes. **Do not send `.incomplete-` output.**
5. A separate Edge window opens [Wormhole](https://wormhole.app/) and automatically selects the verified ZIP for upload. **The private link is copied to the clipboard** once the site provides one. Paste it into your chat with the host. A backup copy is saved in **WORMHOLE-LINK.txt** beside the ZIP. Send the displayed SHA-256 separately too, plus the **exact Minecraft version and mod/loader details**.

**Keep the Edge window and PC awake until the host finishes downloading.** A copied link does not mean uploading is finished. Wormhole provides encrypted, expiring links; its [FAQ](https://wormhole.app/faq) says transfers over 5 GB require both browsers online. Anyone with the complete link can download it. Do not post it publicly.

If automatic sharing fails, the verified ZIP is kept and highlighted for manual upload. Site changes, network errors or computer policy can prevent browser automation. No link is claimed as ready unless a complete Wormhole share link was detected. If the clipboard is busy, use WORMHOLE-LINK.txt.

## You — receive it and host

1. Download the ZIP. Compare this result with the hash your friend sent:

   ```powershell
   Get-FileHash -LiteralPath '.\Minecraft-World.zip' -Algorithm SHA256
   ```

   Scan the ZIP and extracted folder. Hashes verify matching bytes, **not absence of malware**. Do not execute unknown files inside the world; obtain server software separately from official sources.

2. Follow **HOSTING-GUIDE.md**: use the matching game/server mods and Java; stop the server; copy the extracted `world` beside `server.properties`; set `level-name=world`. Check that `world\level.dat` exists without an extra nested `world`.
3. Keep `online-mode=true`, enable `white-list=true` and `enforce-whitelist=true`, then add your friends with `whitelist add Username` in the server console. Test all dimensions and player inventories before opening access.
4. Use an SSD, moderate view/simulation distances, regular stopped-server backups and a host that stays awake. Keep the original ZIP. The hosting guide covers setup, port access, old singleplayer inventory quirks and 24/7 upkeep.

**Limits:** This packages only the selected world. Client mods/configs elsewhere are not included. Keep writers closed; linked/cloud-placeholder items cause a stop. There is no automatic malware scan. The scripts and link-reading logic were checked, but Windows/Edge and live Wormhole execution were unavailable here for an end-to-end test.
::ADONIS_FILE:HOSTING-GUIDE.md
# Adonis Daglester — hosting guide

Send your friend **Adonis-Daglester.cmd**. It is self-contained: they double-click this one file on the **Windows PC that already has the world**, without arranging extra files. Its readable PowerShell scripts and instructions are included inside the file and unpack into a unique temporary folder. They send you the resulting world ZIP; you run the dedicated server. **START-HERE.md** has the short instructions. The command-line method below remains available as an alternative using the unpacked scripts.

## Your friend: make the backup

1. Note the world's **exact Minecraft version**, mod loader, mods and datapacks. Save and Quit, then fully close Minecraft, Lunar Client and their launchers. Keep them closed until the script says **DONE**. Pause cloud sync or other tools editing the world.
2. Keep both `.ps1` files and the launcher together. Right-click them → **Edit** or open them in Notepad to inspect them. They are readable source: no downloaded code, administrator access or permanent settings changes. Easy mode automatically selects the verified ZIP on Wormhole in a separate Edge window; normal command-line mode asks whether to share it.
3. Open **Windows PowerShell** normally, go to the folder containing the script, and run:

   ```powershell
   cd "$HOME\Downloads"
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Backup-MinecraftWorld.ps1
   ```

   `Bypass` applies only to that PowerShell process so an inspected, unsigned script can run. It does not turn off antivirus or change the computer's permanent execution policy. Do not run as administrator. Follow any organization policy on managed PCs.

4. Choose a numbered world from `%APPDATA%\.minecraft\saves`, or paste the actual **world folder containing `level.dat`**. Type `CLOSED` when asked. Lunar can use a separate game directory: if the world is missing, before closing the game use **Singleplayer → select world → Edit → Open World Folder**, where available, and copy that folder's path. Lunar documents separate instance directories in its [June 2026 recap](https://www-new.lunarclient.com/news/lunar-client-monthly-recap-june-2026).
5. Wait for **DONE**. Backups go into **Documents\Minecraft-Backups\Minecraft-World-date-id** by default. Have free disk space at least equal to the world's uncompressed size, plus a margin. Large worlds take time because the script hashes the source, reads back the ZIP, and rechecks the source.

Optional alternate paths:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Backup-MinecraftWorld.ps1 -WorldPath 'D:\Games\saves\Our World' -OutputFolder 'D:\Backups'
```

The script includes **every ordinary file, hidden/system file, subfolder and empty folder** beneath the selected world: dimensions, datapacks, player data and custom files. It opens source files read-only; never removes/creates `session.lock`; refuses output inside the world; and stops on inaccessible files or detected changes. Existing `session.lock` is held read-only during backup. Links, junctions and cloud placeholders cause a stop rather than a silent omission. Use a fully local copy if needed; the script does not make one for you.

The ZIP uses a consistent outer folder named `world`. File contents are preserved; ZIP is not a complete NTFS image and does not preserve permissions or alternate data streams. Mods/configs elsewhere in the game directory, Lunar settings and client resource packs elsewhere are **not included**. There are no file exclusions inside the world.

If it stops: keep the original, fix the stated issue and retry. Never send a folder beginning `.incomplete-`; it can be deleted later. No software can promise a coherent live backup while another program edits the source: keeping Minecraft and other writers closed is required.

## Your friend: send it privately

1. Keep antivirus enabled. For extra reassurance, scan the kit before running it, and scan the world ZIP when you receive it: right-click → **Show more options → Scan with Microsoft Defender**, or use the installed antivirus. [Microsoft's instructions](https://support.microsoft.com/en-gb/windows/experience/scan-an-item-with-windows-security?epb=1). The script itself does **not** scan for malware and does not wait for a scan before uploading.
2. With the double-click launcher, installed **Microsoft Edge** opens a separate transfer window at [Wormhole](https://wormhole.app/). The verified ZIP is automatically selected on the page; no dragging or file selection is required. The helper uses [Edge's browser automation interface](https://learn.microsoft.com/en-us/microsoft-edge/devtools/protocol/), through a temporary connection restricted to this computer and a fresh transfer-only browser profile. It does not attach to your ordinary tabs or signed-in profile. Use that window only for the transfer and close it after receipt. Its temporary profile may use extra disk space under Windows' temporary folder.
3. Once Wormhole provides a complete share link, it is **copied to the clipboard** and saved beside the ZIP as **WORMHOLE-LINK.txt**. Paste it privately into your chat with the host. The complete link includes everything after `#`. Send the script's **SHA-256** separately too, with the exact game version and mod details. You do not need the backup script to receive the world. A copied link means the transfer link is ready; it is **not confirmation that the upload has finished**.
4. Keep that browser tab and PC awake until you confirm download. Wormhole advertises encrypted, expiring transfers up to 10 GB; its FAQ says files up to 5 GB are stored for 24 hours and larger transfers require both browsers online. Check the live site's current limits. Anyone with the full link can access the transfer: do not post it publicly. [Security design](https://wormhole.app/security), [transfer limits](https://wormhole.app/faq).

If the world exceeds the live limit, use a private, recipient-restricted cloud share instead. Keep the same ZIP and verify its checksum after download.

If Edge is unavailable, blocked by policy, or Wormhole's page changes, the backup remains intact and the script falls back to opening the website and highlighting the ZIP for manual sharing. It does not claim an upload or a link succeeded. For manual mode explicitly, add `-ManualShare` to the backup command. Closing the transfer window early can interrupt uploads or direct transfers; wait for the host to confirm the ZIP's hash.

## You: verify, then install the world

1. Download the ZIP and compare this built-in command's hash with the hash your friend sent in chat:

   ```powershell
   Get-FileHash -LiteralPath '.\Minecraft-World.zip' -Algorithm SHA256
   ```

   Match all 64 hexadecimal characters (case does not matter). A match proves the downloaded bytes match what your friend hashed; it does **not** prove a file is virus-free. Scan the ZIP and extracted folder too. Keep antivirus on, show file extensions, and do not run scripts, EXEs or JARs that happen to be inside the world. Download server software separately from its official source. Known datapacks can run in-game commands; retain only content you trust when preparing the **server copy**.

2. Start with the **same Minecraft version** the world last used. Lunar is a client, not the dedicated server. For an unmodded world, use Mojang's [Java server](https://www.minecraft.net/en-us/download/server), or [Paper](https://docs.papermc.io/paper/getting-started/) for plugins/performance after testing your farms and redstone. Paper can change gameplay and cannot load Fabric/Forge content mods. For modded worlds, install the matching Fabric/Forge/NeoForge server, loader version, server-compatible mods, dependencies and relevant configs. Do not copy client-only mods onto the server. [Paper compatibility and migration notes](https://docs.papermc.io/paper/migration/).

3. Install the Java release required by that **specific server version**. Examples: Minecraft 1.20.5–1.21.11 uses Java 21; 26.1 introduced Java 25. Earlier versions differ. Check the server/loader documentation. [Mojang 1.20.5 notes](https://www.minecraft.net/en-us/article/minecraft-java-edition-1-20-5), [Mojang 26.1 notes](https://www.minecraft.net/en-us/article/minecraft-java-edition-26-1).

4. In a **new server folder**, run the official server once to generate its files. Read `eula.txt` and only set `eula=true` if you accept the terms. Let it start, then type `stop` in the console and wait for it to exit. For a simple Vanilla/Paper setup, rename the downloaded server JAR to `server.jar` and use:

   ```text
   java -Xms1G -Xmx4G -jar server.jar nogui
   ```

   This example allows up to 4 GB for Java; leave memory for the operating system. Modded servers may need their supplied launch command and different memory. Do not point the server at your friend's original save.

5. Extract the ZIP into a separate empty folder. With the server **stopped**, move its generated `world` folder aside, then copy the extracted **world** folder beside `server.properties`. Do not merge it into an existing world. The result must be `server-folder\world\level.dat`, **not** `server-folder\world\world\level.dat`. On an existing server, first back up the whole server, including any sibling dimension folders, and follow its import procedure. Paper handles Vanilla imports; dimension layout depends on game/server version, so do not manually rearrange Nether/End folders using an old guide.

6. Before starting, edit these settings in `server.properties`:

   ```properties
   level-name=world
   online-mode=true
   white-list=true
   enforce-whitelist=true
   enable-rcon=false
   enable-query=false
   server-ip=
   view-distance=8
   simulation-distance=6
   max-players=10
   ```

   Set the player limit to your group size. Keep remote management disabled unless deliberately secured. Start the server, then enter these **console commands without a leading slash**, substituting real Java usernames:

   ```text
   whitelist add YourUsername
   whitelist add FriendsUsername
   whitelist on
   ```

   Keep account authentication on and give operator permission only to trusted admins. [Server settings reference](https://docs.papermc.io/paper/reference/server-properties/).

7. Join locally first (`localhost` when playing on the hosting PC). Check builds, Nether/End, inventories, Ender chests, XP, advancements and datapacks before inviting everyone. On **pre-26.1 worlds**, the original singleplayer host's character may be in `level.dat`'s `Player` data rather than the UUID file the server uses. If it is missing/stale, stop and migrate that character on a **copy** with a suitable NBT editor; keep the original ZIP intact. In 26.1, Mojang changed this to `singleplayer_uuid` and `players/data`. Use the same legitimate account and keep online mode enabled. [Mojang's world storage changes](https://www.minecraft.net/en-us/article/minecraft-java-edition-26-1).

8. For access from outside your home, allow/forward **only the game's TCP port** (normally 25565) to the server, or use a trusted private VPN. Do not expose remote console, file sharing or router administration. Never disable the firewall. A home connection behind CGNAT may require ISP help, a VPN or a hosting provider. Share your address only with friends.

## Keep it healthy 24/7

- Use an SSD, a CPU with good per-core performance and enough RAM; 4 GB is a starting point for a small mostly vanilla group, not a guarantee. Watch actual load before increasing it. Keep view/simulation distances moderate and avoid excessive ticking mobs, hoppers, farms and chunk loaders. Profile lag before adding random optimization plugins. [Paper troubleshooting](https://docs.papermc.io/paper/basic-troubleshooting/).
- Disable host sleep, keep power/network stable, and arrange startup after reboot using your host's normal service/panel. Run the server as a regular user. A 24/7 server still needs maintenance windows.
- Make daily, rotating **off-machine backups** and test restores. Simplest safe method: `stop`, wait for exit, back up the entire server, then restart. This script is for a **closed singleplayer world**, not live server backups. Older Paper versions can keep dimensions in sibling folders.
- Keep server, Java, mods and plugins updated from official sources after testing a copy. Preserve the untouched transfer ZIP before any upgrade; do not downgrade an upgraded world.

**Validation note:** The scripts were reviewed, their structure checked, and the link-reading logic checked against local page fixtures. Windows PowerShell/Edge and live Wormhole execution were unavailable here for an end-to-end run. The backup success message only appears after ZIP/source checks pass; the share-link message requires a complete Wormhole URL. Byte verification does not establish that an already-damaged world is playable.
