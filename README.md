# Adonis Daglester

A Windows script for backing up a Minecraft Java world and sending it to a friend to host.

## Use

1. Download `Adonis-Daglester.cmd` on the PC with the world.
2. Save and quit Minecraft, then close Minecraft and Lunar Client completely.
3. Double-click the file, pick the world, and confirm.
4. Wait while it creates and checks the ZIP.
5. When the Wormhole link is copied, paste it into your chat.

Keep the Edge window open and the PC awake until your friend finishes downloading. The link can appear before the upload is finished.

You only need the one `.cmd` file. It contains the PowerShell scripts and unpacks them into a temporary folder when run. Requires Windows PowerShell 5.1 or newer and an installed copy of Microsoft Edge. No administrator access or extra downloads.

## The backup

The script reads the original world and writes the backup outside it. It includes hidden files, all dimensions, player data, datapacks and any other files inside the world folder.

It checks each archived file against the source using SHA-256, then rechecks the source for changes. If verification fails, it stops without marking the backup complete.

Backups go under:

```text
Documents\Minecraft-Backups\Minecraft-World-<date>-<id>\
```

That folder contains the world ZIP, checksum, file manifest and transfer notes. A detected share link is also saved as `WORMHOLE-LINK.txt`.

## If something fails

- **World missing:** use Browse and select the folder containing `level.dat`.
- **Game still running:** close Minecraft, Lunar, their launchers and any Java apps, then retry.
- **Upload failed:** the verified ZIP is kept for manual sharing. Edge settings, network problems or changes to Wormhole can break automatic uploading.

Do not send output from a folder named `.incomplete-`.

## Receiving the world

Compare the downloaded ZIP's hash with the one the sender gives you:

```powershell
Get-FileHash -LiteralPath '.\Minecraft-World.zip' -Algorithm SHA256
```

Use the matching Minecraft version and required server mods. With the server stopped, extract the ZIP and place `world` beside `server.properties`. Set `level-name=world`; check that `world\level.dat` exists without another `world` folder nested inside it.

Keep the original ZIP before making changes. Mods and configs stored outside the world folder need to be transferred separately.

## Status

Early version. The scripts and link handling have been checked locally, but the full Windows, Edge and Wormhole flow has not been tested end to end yet.

The files are readable in Notepad. Checksums confirm matching bytes, not that a file is free of malware. Keep antivirus enabled and share the complete Wormhole link privately.
