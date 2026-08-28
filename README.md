# WebDAVSync

KOReader plugin for safely synchronizing new books from a WebDAV server to local Kindle storage.

## Features

- **Reuses existing WebDAV connections** configured in KOReader CloudStorage — no new server setup required.
- **Recursive sync** of remote folders (e.g. `Author/Series/*.epub`).
- **Never deletes** local files. Never overwrites existing files.
- **Restricted to `/mnt/us/`** — no risk of touching system partitions.
- **Temp file + rename** strategy for safe downloads.
- **Analyze mode** shows what would be synced before any changes are made.

## Requirements

- Kindle with jailbreak.
- KOReader v2026.07.1 or later.
- At least one WebDAV server already configured in **KOReader > Cloud Storage**.

## Installation

1. Connect the Kindle to your computer via USB.
2. Copy the `webdavsync.koplugin` folder to:
   ```
   /mnt/us/koreader/plugins/
   ```
3. Restart KOReader. The plugin appears under **Menu > WebDAVSync**.

> If updating from a previous version, delete the old `webdavsync.koplugin` folder first.

## How it works

### 1. Configure

Open **WebDAVSync > Settings** and select:

- **WebDAV server** — choose from servers already configured in Cloud Storage.
- **Local destination** — folder under `/mnt/us/` where books will be synced (e.g. `Libros/Synced`). Created automatically if it doesn't exist.

### 2. Analyze

Run **WebDAVSync > Analyze** to see a comparison between local and remote files:

- **Only local** — files on Kindle but not on the server.
- **Only remote** — files on the server but not on the Kindle (would be downloaded).
- **Same size** — files present in both locations with matching sizes.
- **Different size** — files present in both locations with different sizes.

This is read-only — nothing is downloaded or changed.

### 3. Synchronize

> Not implemented yet. Coming after Analyze is fully validated.

Will download only new files (`remote_only`), preserving the remote folder structure. Will never delete or overwrite existing local files.

## Project structure

```
webdavsync.koplugin/
├── _meta.lua               Plugin metadata
├── main.lua                Entry point (WidgetContainer)
├── webdavsync/
│   ├── config.lua          Settings, CloudStorage servers, local paths
│   ├── menu.lua            Menu construction
│   ├── analyze.lua         Local scan + comparison
│   └── synchronize.lua     Sync stub (not implemented)
├── AGENTS.md               Agent rules for development
└── README.md
```

## Safety

This plugin is designed with Kindle safety as the top priority:

- All file writes are restricted to `/mnt/us/`.
- Existing local files are never deleted or overwritten.
- WebDAV connections are handled entirely by KOReader's own tested implementation.
- Passwords and credentials are never logged or exposed.

## Development

See [AGENTS.md](AGENTS.md) for development rules and conventions.

### Debugging

```sh
# View recent crash logs
tail -n 100 /mnt/us/koreader/crash.log

# Check Lua syntax of a module
cd /mnt/us/koreader
./luajit -e "local f,e=loadfile('plugins/webdavsync.koplugin/webdavsync/analyze.lua'); print(f or e)"
```

## License

This project is provided as-is for the KOReader community.
