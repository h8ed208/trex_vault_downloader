# T.REX Field Manual Vault Downloader

A PowerShell script that downloads the **PDF and EPUB** editions of the publications in the
[T.REX ARMS Field Manual Vault](https://www.trex-arms.com/field-manual-vault) and sorts them
into `pdf` and `epub` folders.

The vault hosts thousands of U.S. military field manuals, technical manuals and handbooks.
Each has its own page with a PDF and an EPUB link. This script finds every publication page
and downloads both files for you.

## Quick start (Windows)

1. Download this repository (**Code → Download ZIP**) and unzip it.
2. Double-click **`Download.bat`**.
3. Files are saved to a `downloads` folder next to the script:

```
downloads/
├── pdf/     ← one .pdf per publication
├── epub/    ← one .epub per publication
├── publications.txt   (cached index of publication pages)
├── download_log.txt
└── failed.txt         (only if something failed)
```

Leave the window open until it says **Done**. You can close it at any time and double-click
`Download.bat` again later. Files you already have are skipped, so it picks up where it stopped.

## Size and time

A full run in November 2026 found **3,678 publications**, which is **7,356 files**. The whole
download took a little over an hour on a fast connection. Plan for **well over 100 GB** of disk
space if you download everything.

> **OneDrive / Dropbox / Google Drive users:** if you run this inside a synced folder (for example
> your Windows Desktop when OneDrive backup is on), the sync app will try to upload everything.
> Use `-OutputDir` to save somewhere outside the synced folder.

## Options

Run from PowerShell, or pass the same options to `Download.bat`:

| Option | What it does |
|---|---|
| `-OutputDir <path>` | Where to save files. Default: `.\downloads` |
| `-Formats pdf` / `-Formats epub` | Download only one format. Default: both |
| `-Collection <name>` | Only `current`, `recent-archive`, `lessons-learned` and/or `historic` |
| `-IndexOnly` | Build the list of publications without downloading anything |
| `-Recrawl` | Rebuild the cached publication list (to pick up newly added manuals) |
| `-DelayMs <n>` | Pause between requests in milliseconds. Default: 250 |

Examples:

```powershell
# Everything, saved to another drive
.\Get-FieldManuals.ps1 -OutputDir "D:\Field Manuals"

# Only EPUBs of current doctrine
.\Get-FieldManuals.ps1 -Formats epub -Collection current

# Same thing using the batch file
Download.bat -Formats epub -Collection current
```

If PowerShell refuses to run the script, use `Download.bat`, or run:

```powershell
powershell -ExecutionPolicy Bypass -File .\Get-FieldManuals.ps1
```

## Requirements

- Windows 10/11 with the built-in Windows PowerShell 5.1, **or**
- [PowerShell 7+](https://github.com/PowerShell/PowerShell) on Windows, macOS or Linux
  (`pwsh ./Get-FieldManuals.ps1`)

There's nothing else to install.

## How it works

1. **Index:** the vault's listings are paginated, and long listings stop paging before the end.
   So the script pages through every listing it can find (collections, branches, types,
   functions, echelons, and some combinations of those) and merges the results into one list
   of publication pages. The list is cached in `publications.txt`.
2. **Download:** for each publication page it reads the `files.trex-arms.com` PDF and EPUB
   links, then downloads them to a `.part` file and renames it when the download finishes. Each
   request is retried up to 4 times.

## Known limitations

- The vault advertises about 4,215 manuals, but its public listings only reach about 3,680 of
  them. Publications that never show up in any listing can't be found by this script.
- If the site changes its layout or URLs, the script may need updating.

## Be considerate

T.REX ARMS hosts this archive for free. The default delay keeps requests polite, so please don't
lower it much or run many copies in parallel. Consider supporting them if you find the vault
useful.

## Disclaimer

This project is not affiliated with or endorsed by T.REX ARMS. It only downloads files the site
already offers for public download. The publications themselves are U.S. government documents.
Check each document's distribution statement before you redistribute it.

## License

[MIT](LICENSE)
