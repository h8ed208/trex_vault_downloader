<#
.SYNOPSIS
    Downloads the PDF and EPUB editions of every publication in the
    T.REX ARMS Field Manual Vault (https://www.trex-arms.com/field-manual-vault).

.DESCRIPTION
    1. Builds an index of publication pages by paging through every listing
       on the vault (collections, branches, types, functions, echelons, and
       a few combinations, since no single listing pages all the way through).
    2. Visits each publication page and downloads its PDF and/or EPUB into
       <OutputDir>\pdf and <OutputDir>\epub.

    The script is resumable: files that already exist are skipped and partial
    downloads are written to *.part first, so you can stop it (Ctrl+C) and run
    it again at any time. The index is cached in <OutputDir>\publications.txt;
    use -Recrawl to rebuild it.

.PARAMETER OutputDir
    Where to save everything. Defaults to a "downloads" folder next to this script.

.PARAMETER Formats
    Which formats to download: pdf, epub, or both (default).

.PARAMETER Collection
    Limit to one or more collections: current, recent-archive, lessons-learned, historic.
    Default is all of them.

.PARAMETER Recrawl
    Ignore the cached index and rebuild it from the website.

.PARAMETER IndexOnly
    Build the index and stop without downloading anything.

.PARAMETER DelayMs
    Pause between requests, in milliseconds, to go easy on the server. Default 250.

.EXAMPLE
    .\Get-FieldManuals.ps1
    Download everything (PDF + EPUB) into .\downloads

.EXAMPLE
    .\Get-FieldManuals.ps1 -OutputDir "D:\Manuals" -Formats epub -Collection current
    Only the EPUBs of current doctrine, saved to D:\Manuals
#>
[CmdletBinding()]
param(
    [string]$OutputDir,
    [ValidateSet('pdf', 'epub')]
    [string[]]$Formats = @('pdf', 'epub'),
    [ValidateSet('current', 'recent-archive', 'lessons-learned', 'historic')]
    [string[]]$Collection,
    [switch]$Recrawl,
    [switch]$IndexOnly,
    [int]$DelayMs = 250
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'   # Invoke-WebRequest is far faster without the progress bar
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

if (-not $OutputDir) { $OutputDir = Join-Path $PSScriptRoot 'downloads' }
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$OutputDir = (Resolve-Path $OutputDir).Path

$Base      = 'https://www.trex-arms.com'
$VaultUrl  = "$Base/field-manual-vault"
$UserAgent = 'Mozilla/5.0 (compatible; trex-vault-downloader; +https://github.com/)'
$AllColls  = @('current', 'recent-archive', 'lessons-learned', 'historic')
$Branches  = @('army', 'usmc', 'navy', 'joint', 'af')

$suffix    = if ($Collection) { '_' + (($Collection | Sort-Object) -join '+') } else { '' }
$IndexFile = Join-Path $OutputDir "publications$suffix.txt"
$LogFile   = Join-Path $OutputDir 'download_log.txt'
$FailFile  = Join-Path $OutputDir 'failed.txt'

function Write-Log([string]$Message) {
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

function Get-Html([string]$Url) {
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        try {
            return (Invoke-WebRequest -Uri $Url -UserAgent $UserAgent -UseBasicParsing -TimeoutSec 60).Content
        } catch {
            Write-Log "  retry $attempt for $Url : $($_.Exception.Message)"
            Start-Sleep -Seconds (5 * $attempt)
        }
    }
    return $null
}

function Get-PublicationSlugs([string]$Html) {
    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    $pattern = '(?:https://www\.trex-arms\.com)?/field-manual-vault/([a-z0-9][a-z0-9\.\-_]*)(?=["''#?])'
    foreach ($m in [regex]::Matches($Html, $pattern, 'IgnoreCase')) {
        $slug = $m.Groups[1].Value.ToLower()
        if ($slug -notin @('faq', 'citations')) { [void]$set.Add($slug) }
    }
    return , $set
}

# ---------------------------------------------------------------- index ----
$index = New-Object 'System.Collections.Generic.HashSet[string]'

if ((Test-Path $IndexFile) -and -not $Recrawl) {
    Get-Content $IndexFile | Where-Object { $_ } | ForEach-Object { [void]$index.Add($_) }
    Write-Log "Using cached index: $($index.Count) publications ($IndexFile). Use -Recrawl to rebuild."
} else {
    Write-Log 'Building index of publications (this takes several minutes)...'
    $mainHtml = Get-Html $VaultUrl
    if (-not $mainHtml) { Write-Log 'Could not reach the vault. Check your internet connection.'; exit 1 }

    # The vault shows this "Recommended" list on every page, and falls back to it past the last page.
    $recommended = Get-PublicationSlugs $mainHtml

    # Every filter value offered on the main page (fn, type, ech, ...)
    $discovered = New-Object 'System.Collections.Generic.List[string]'
    foreach ($m in [regex]::Matches($mainHtml, '[?&;](coll|branch|type|fn|ech)=([^"''&<>\s#]+)')) {
        $q = "$($m.Groups[1].Value)=$($m.Groups[2].Value)"
        if (-not $discovered.Contains($q)) { $discovered.Add($q) }
    }
    $fnFilters = @($discovered | Where-Object { $_ -like 'fn=*' })

    # Listings to crawl. Large listings stop paging early, so smaller combinations fill the gaps.
    $listings = New-Object 'System.Collections.Generic.List[string]'
    function Add-Listing([string]$q) { if (-not $listings.Contains($q)) { $listings.Add($q) } }

    if ($Collection) {
        foreach ($c in $Collection) {
            Add-Listing "coll=$c"
            foreach ($b in $Branches)  { Add-Listing "coll=$c&branch=$b" }
            foreach ($f in $fnFilters) { Add-Listing "coll=$c&$f" }
        }
    } else {
        foreach ($c in $AllColls) { Add-Listing "coll=$c" }
        foreach ($q in $discovered) { if ($q -notlike 'coll=*') { Add-Listing $q } }
        foreach ($c in $AllColls) { foreach ($b in $Branches) { Add-Listing "coll=$c&branch=$b" } }
        foreach ($b in $Branches) { foreach ($f in $fnFilters) { Add-Listing "branch=$b&$f" } }
    }

    $n = 0
    foreach ($q in $listings) {
        $n++
        $page = 1; $misses = 0; $prevKey = ''
        while ($page -le 200) {
            $html = Get-Html "$VaultUrl`?$q&page=$page"
            if (-not $html) { break }
            $slugs = Get-PublicationSlugs $html
            $real  = @($slugs | Where-Object { -not $recommended.Contains($_) } | Sort-Object)
            # Recommended slugs only count when they appear alongside real results
            if ($real.Count -gt 0) { foreach ($s in $slugs) { [void]$index.Add($s) } }
            $key = $real -join ','
            if ($real.Count -eq 0 -or $key -eq $prevKey) { $misses++ } else { $misses = 0 }
            $prevKey = $key
            if ($misses -ge 2) { break }
            $page++
            Start-Sleep -Milliseconds $DelayMs
        }
        Write-Log ("Index [{0}/{1}] {2}: {3} pages, {4} publications so far" -f $n, $listings.Count, $q, $page, $index.Count)
    }

    $index | Sort-Object | Set-Content -Path $IndexFile
    Write-Log "Index complete: $($index.Count) publications saved to $IndexFile"
}

if ($IndexOnly) { Write-Log 'IndexOnly set; not downloading.'; exit 0 }

# ------------------------------------------------------------ download ----
foreach ($f in $Formats) { New-Item -ItemType Directory -Force -Path (Join-Path $OutputDir $f) | Out-Null }

$slugs = @($index | Sort-Object)
$total = $slugs.Count
$i = 0; $got = 0; $have = 0; $fail = 0; $noLinks = 0

foreach ($slug in $slugs) {
    $i++
    $html = Get-Html "$VaultUrl/$slug"
    if (-not $html) {
        Write-Log "[$i/$total] FAILED to load page $slug"
        Add-Content -Path $FailFile -Value "$VaultUrl/$slug"
        $fail++; continue
    }

    $urls = [regex]::Matches($html, 'https://files\.trex-arms\.com/(pdf|epub)/[^"''\s<>]+?\.(pdf|epub)', 'IgnoreCase') |
            ForEach-Object { $_.Value } | Select-Object -Unique
    if (-not $urls) { Write-Log "[$i/$total] no download links on $slug"; $noLinks++; continue }

    foreach ($url in $urls) {
        $ext = [IO.Path]::GetExtension($url).TrimStart('.').ToLower()
        if ($ext -notin $Formats) { continue }

        $name = [Uri]::UnescapeDataString(($url -split '/')[-1])
        $dest = Join-Path (Join-Path $OutputDir $ext) $name
        if (Test-Path $dest) { $have++; continue }

        $tmp = "$dest.part"; $ok = $false
        for ($attempt = 1; $attempt -le 4 -and -not $ok; $attempt++) {
            try {
                Invoke-WebRequest -Uri $url -UserAgent $UserAgent -UseBasicParsing -TimeoutSec 1800 -OutFile $tmp
                Move-Item -Force $tmp $dest
                $ok = $true
            } catch {
                Write-Log "  retry $attempt for $name : $($_.Exception.Message)"
                Start-Sleep -Seconds (10 * $attempt)
            }
        }

        if ($ok) {
            $got++
            Write-Log ("[{0}/{1}] {2} ({3:N1} MB)" -f $i, $total, $name, ((Get-Item $dest).Length / 1MB))
        } else {
            Remove-Item -ErrorAction SilentlyContinue $tmp
            Add-Content -Path $FailFile -Value $url
            Write-Log "[$i/$total] FAILED $url"
            $fail++
        }
    }
    Start-Sleep -Milliseconds $DelayMs
}

Write-Log "Done. Downloaded: $got  Already had: $have  Failed: $fail  Pages without links: $noLinks"
if ($fail -gt 0) { Write-Log "Failed items are listed in $FailFile. Run the script again to retry them." }
