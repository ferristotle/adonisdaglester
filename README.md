# Adonis Daglester

A Windows script that packages a Minecraft Java world into a verified ZIP for a friend to host.

## Use

1. Download `Adonis-Daglester.cmd` on the PC with the world.
2. Save and quit Minecraft, then fully close Minecraft and Lunar Client. Pause anything editing or syncing the world.
3. Double-click the file. Choose the world folder containing `level.dat` and confirm that the game is closed.
4. Wait for **DONE — VERIFIED BACKUP**.
5. Wormhole opens in your default browser, and File Explorer highlights `Minecraft-World.zip`. Select that ZIP on Wormhole, or drag it onto the page.
6. Copy the link from Wormhole and send it privately to your friend. Send the displayed SHA-256 separately too, with the exact Minecraft version and any mod details.

Keep the upload page and PC awake until your friend has finished downloading. Opening Wormhole does not start an upload.

Only the one `.cmd` file is needed. It contains a readable PowerShell script and unpacks it into a temporary folder when run. Uses Windows PowerShell 5.1 and .NET. No administrator rights, installs, browser extensions or specific browser required.

## What it checks

The original world is only read. All files inside it are included, including hidden files, dimensions, player data, datapacks and empty folders. Files are hashed as they are copied, then every ZIP entry is read back and checked by length and SHA-256. The source is read again to check that it did not change.

An existing `session.lock` is opened read-only during backup. It is never created, removed or repaired. You must keep Minecraft closed, including when a world has no lock file. Linked folders, junctions and cloud placeholders cause a stop rather than a silent omission.

Backups go under:

```text
Documents\Minecraft-Backups\Minecraft-World-<date>-<id>\
```

The folder contains `Minecraft-World.zip`, its `.sha256` checksum and `TRANSFER-INFO.txt`. A failed backup stays in a folder starting with `.incomplete-`. Do not send that output.

There is no automatic upload, browser debugging or clipboard access. If the browser or folder window fails to open, the verified ZIP stays at the printed path for manual sharing.

## Receiving the world

Compare this result with the hash the sender gave you:

```powershell
Get-FileHash -LiteralPath '.\Minecraft-World.zip' -Algorithm SHA256
```

Use the matching Minecraft version and required server mods. With the server stopped, extract into a new empty folder and place `world` beside `server.properties`. Set `level-name=world`; check that `world\level.dat` exists without another `world` folder nested inside it. Keep account authentication and the whitelist enabled.

Keep the original ZIP. Mods and configs outside the world folder are not included. ZIP does not preserve NTFS permissions or alternate data streams.

## Status

The self-contained packaging and static safeguards have been checked locally. A full Windows backup-and-restore test has not been run here. Test on a disposable world before relying on it for an important save.

The source is readable in Notepad. Checksums verify matching bytes, not that files are free of malware. Keep antivirus enabled and scan received files.
