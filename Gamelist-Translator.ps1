# Gamelist-Translator By Schmurtz

# Translate games descriptions in gamelist.xml from EmulationStation (thanks to a powershell script and Google Translate).
# https://github.com/schmurtzm/Gamelist-Translator

# V1.0 - 2022-04-20
#   - You can change the target language inside the script.
#   - Create backup of the original gamelist.xml before modification (the backup will be named gamelist-yyyy-MM-dd_HHmmss.xml)
#   - Should support accents / UTF8 in the right way.

# V1.1 - 2022-04-20
#   - Now it count the total of characters which have been send to translation

# ---------------------------------------------------------------------------
# RetroBat Gamelist Translator
#
# This project is a fork of the original Gamelist-Translator script.
# The original version and its historical comments have been preserved above.
#
# This fork has been extended and maintained with additional features,
# improvements and fixes for RetroBat gamelist.xml translation.
#
# Main additions:
#   - Interactive source and target language selection
#   - Translation cache
#   - XML validation
#   - UTF-8 / BOM handling
#   - Safe backups
#   - HTTP 429 handling
#   - Progress saving
#   - Resume after interruption
#   - Periodic progress saving
#   - Final translation summary
#
# Maintained by: theJim
# GitHub: https://github.com/theJim69/Gamelist-Translator
# ---------------------------------------------------------------------------

# usage : run a powershell cmd then type :
# Gamelist-Translator.ps1 "c:\RetroBat\roms\ports\gamelist.xml"

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

$RequestDelaySeconds = 2
$SaveEvery = 10

$CacheFileName = ".gamelist-translator-cache.json"
$ProgressFileName = ".gamelist-translator-progress.json"

$Languages = @(
    [PSCustomObject]@{ Code = "auto"; Name = "Auto detect" }
    [PSCustomObject]@{ Code = "en";   Name = "English" }
    [PSCustomObject]@{ Code = "fr";   Name = "French" }
    [PSCustomObject]@{ Code = "es";   Name = "Spanish" }
    [PSCustomObject]@{ Code = "de";   Name = "German" }
    [PSCustomObject]@{ Code = "it";   Name = "Italian" }
    [PSCustomObject]@{ Code = "pt";   Name = "Portuguese" }
    [PSCustomObject]@{ Code = "ja";   Name = "Japanese" }
)

# ------------------------------------------------------------
# Parameters
# ------------------------------------------------------------

if ($args.Count -eq 0) {
    Write-Host "No parameters."
    Write-Host 'Usage: Gamelist-Translator.ps1 "C:\RetroBat\roms\ports\gamelist.xml"'
    return
}

if (-not (Test-Path -LiteralPath $args[0] -PathType Leaf)) {
    Write-Host "ERROR : Input file does not exist." -ForegroundColor Red
    Write-Host "File : $($args[0])"
    return
}

$filePath = (Resolve-Path -LiteralPath $args[0]).Path
$fileInfo = Get-Item -LiteralPath $filePath
$directory = $fileInfo.DirectoryName
$baseName = $fileInfo.BaseName

$CachePath = Join-Path $directory $CacheFileName
$ProgressPath = Join-Path $directory $ProgressFileName

# ------------------------------------------------------------
# Language selection
# ------------------------------------------------------------

function Select-Language {
    param(
        [string]$Title,
        [bool]$AllowAuto
    )

    Write-Host ""
    Write-Host "========================================"
    Write-Host $Title
    Write-Host "========================================"

    $list = @(
        $Languages | Where-Object {
            $AllowAuto -or $_.Code -ne "auto"
        }
    )

    for ($i = 0; $i -lt $list.Count; $i++) {
        Write-Host "$($i + 1). $($list[$i].Name) [$($list[$i].Code)]"
    }

    do {
        $choice = Read-Host "Selection"
        $number = 0

        if ([int]::TryParse($choice, [ref]$number)) {
            if ($number -ge 1 -and $number -le $list.Count) {
                return $list[$number - 1].Code
            }
        }

        Write-Host "Invalid selection." -ForegroundColor Yellow

    } while ($true)
}

$SourceLanguage = Select-Language "Select source language" $true
$TargetLanguage = Select-Language "Select target language" $false

Write-Host ""
Write-Host "----------------------------------------"
Write-Host "Source : $(
    ($Languages | Where-Object Code -eq $SourceLanguage).Name
) [$SourceLanguage]"
Write-Host "Target : $(
    ($Languages | Where-Object Code -eq $TargetLanguage).Name
) [$TargetLanguage]"
Write-Host "----------------------------------------"
Write-Host ""

# ------------------------------------------------------------
# Cache
# ------------------------------------------------------------

$Cache = @{}

if (Test-Path -LiteralPath $CachePath) {
    try {
        $loaded = Get-Content -LiteralPath $CachePath -Raw |
            ConvertFrom-Json

        foreach ($property in $loaded.PSObject.Properties) {
            $Cache[$property.Name] = [string]$property.Value
        }

        Write-Host "Translation cache loaded : $CachePath"
        Write-Host "Cached translations : $($Cache.Count)"
    }
    catch {
        Write-Host "WARNING : Unable to load translation cache."
        Write-Host "Cache will start empty."
        Write-Host "Details : $($_.Exception.Message)"
    }
}
else {
    Write-Host "Translation cache : new"
}

function Save-Cache {
    try {
        $Cache |
            ConvertTo-Json -Depth 3 |
            Set-Content -LiteralPath $CachePath -Encoding UTF8

        Write-Host "Translation cache saved : $CachePath"
    }
    catch {
        Write-Host "WARNING : Unable to save translation cache." -ForegroundColor Yellow
        Write-Host "Details : $($_.Exception.Message)"
    }
}

# ------------------------------------------------------------
# Progress
# ------------------------------------------------------------

$StartIndex = 0

if (Test-Path -LiteralPath $ProgressPath) {
    try {
        $progress = Get-Content -LiteralPath $ProgressPath -Raw |
            ConvertFrom-Json

        if (
            $progress.File -eq $filePath -and
            $progress.SourceLanguage -eq $SourceLanguage -and
            $progress.TargetLanguage -eq $TargetLanguage
        ) {
            $StartIndex = [int]$progress.NextGameIndex

            if ($StartIndex -gt 0) {
                Write-Host "Previous progress found."
                Write-Host "Resume from game index : $StartIndex"
            }
        }
    }
    catch {
        Write-Host "WARNING : Invalid progress file. Starting from beginning."
    }
}

function Save-Progress {
    param([int]$NextIndex)

    $data = [ordered]@{
        File = $filePath
        SourceLanguage = $SourceLanguage
        TargetLanguage = $TargetLanguage
        NextGameIndex = $NextIndex
    }

    try {
        $data |
            ConvertTo-Json |
            Set-Content -LiteralPath $ProgressPath -Encoding UTF8
    }
    catch {
        Write-Host "WARNING : Unable to save progress." -ForegroundColor Yellow
    }
}

# ------------------------------------------------------------
# Backup
# ------------------------------------------------------------

$timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
$backupPath = Join-Path $directory "${baseName}_${timestamp}.xml"

Write-Host "Creating backup file : $backupPath"

try {
    Copy-Item `
        -LiteralPath $filePath `
        -Destination $backupPath `
        -ErrorAction Stop

    Write-Host "Backup successfully created : $backupPath"
}
catch {
    Write-Host "ERROR : Unable to create backup." -ForegroundColor Red
    Write-Host $_.Exception.Message
    return
}

# ------------------------------------------------------------
# Load XML
# ------------------------------------------------------------

try {
    [xml]$xmlDoc = (
        Select-Xml -LiteralPath $filePath -XPath /
    ).Node
}
catch {
    Write-Host "ERROR : Invalid XML file." -ForegroundColor Red
    Write-Host $_.Exception.Message
    return
}

if ($null -eq $xmlDoc.gameList) {
    Write-Host "ERROR : <gameList> element not found." -ForegroundColor Red
    return
}

$games = @($xmlDoc.gameList.game)
$totalGames = $games.Count

Write-Host ""
Write-Host "Games found : $totalGames"
Write-Host ""

# ------------------------------------------------------------
# Translation
# ------------------------------------------------------------

$TranslatedCount = 0
$CachedCount = 0
$EmptyCount = 0
$FailedCount = 0
$TotalCharacters = 0
$StoppedBy429 = $false

for ($i = $StartIndex; $i -lt $totalGames; $i++) {

    $game = $games[$i]

    Write-Host ""
    Write-Host "------------ $($game.name) ------------"
    Write-Host ""

    $Text = [string]$game.desc

    if ([string]::IsNullOrWhiteSpace($Text)) {
        Write-Host "Description empty - translation skipped."
        $EmptyCount++
        Save-Progress ($i + 1)
        continue
    }

    Write-Host $Text
    $TotalCharacters += $Text.Length

    $cacheKey = "google|$SourceLanguage|$TargetLanguage|$Text"

    if ($Cache.ContainsKey($cacheKey)) {

        $Translation = $Cache[$cacheKey]

        Write-Host "************ Translation from cache ************"
        Write-Host $Translation

        $game.desc = $Translation
        $CachedCount++

    }
    else {

        if ($i -gt $StartIndex -and $RequestDelaySeconds -gt 0) {
            Start-Sleep -Seconds $RequestDelaySeconds
        }

        $encodedText = [System.Uri]::EscapeDataString($Text)

        $Uri = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=$SourceLanguage&tl=$TargetLanguage&dt=t&q=$encodedText"

        try {

            Write-Host "Translation request..."

            $Response = Invoke-RestMethod `
                -Uri $Uri `
                -Method Get `
                -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) PowerShell" `
                -ErrorAction Stop

            if (
                $null -eq $Response -or
                $null -eq $Response[0] -or
                $null -eq $Response[0][0] -or
                [string]::IsNullOrWhiteSpace([string]$Response[0][0][0])
            ) {
                throw "Invalid translation response."
            }

            $Translation = ($Response[0] | ForEach-Object {
    if ($null -ne $_ -and $_.Count -gt 0) {
        [string]$_.Item(0)
    }
}) -join ""

            if ([string]::IsNullOrWhiteSpace($Translation)) {
                throw "Empty translation returned by Google Translate."
            }

            Write-Host "************ Translation ************"
            Write-Host $Translation

            $game.desc = $Translation
            $TranslatedCount++

            $Cache[$cacheKey] = $Translation

        }
        catch {

            $statusCode = $null

            try {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }
            catch {}

            if ($statusCode -eq 429) {

                Write-Host "Google Translate returned HTTP 429 (Too Many Requests)." `
                    -ForegroundColor Yellow

                Write-Host "Google Translate is rate limiting requests."
                Write-Host "Translation will stop to protect current progress."

                $FailedCount++
                $StoppedBy429 = $true

                Save-Progress $i
                Save-Cache

                break
            }

            Write-Host "Translation failed - original description kept." `
                -ForegroundColor Yellow

            Write-Host "Details : $($_.Exception.Message)"

            $FailedCount++
            Save-Progress ($i + 1)
            continue
        }
    }

    # Save every N games
    if ((($i + 1) % $SaveEvery) -eq 0) {

        Write-Host ""
        Write-Host "Saving progress..."

        Save-Progress ($i + 1)
        Save-Cache

        try {
            $xmlDoc.Save($filePath)
            Write-Host "Progress saved : $($i + 1) games processed."
        }
        catch {
            Write-Host "WARNING : Unable to save XML during progress save." `
                -ForegroundColor Yellow
        }
    }

    Save-Progress ($i + 1)
}

# ------------------------------------------------------------
# Final save
# ------------------------------------------------------------

Save-Cache

if ($StoppedBy429) {
    Write-Host ""
    Write-Host "WARNING : Translation stopped because Google Translate returned HTTP 429." `
        -ForegroundColor Yellow
    Write-Host "Progress saved before stopping."
}

try {
    $xmlDoc.Save($filePath)
    Write-Host "XML saved as UTF-8."
}
catch {
    Write-Host "ERROR : Unable to save XML." -ForegroundColor Red
    Write-Host $_.Exception.Message
    return
}

# ------------------------------------------------------------
# Remove progress file after successful completion
# ------------------------------------------------------------

if (-not $StoppedBy429) {

    if (Test-Path -LiteralPath $ProgressPath) {
        Remove-Item -LiteralPath $ProgressPath -Force
    }
}

# ------------------------------------------------------------
# Final report
# ------------------------------------------------------------

Write-Host ""
Write-Host "************ Translation summary ************"
Write-Host "Translated descriptions : $TranslatedCount"
Write-Host "Cached translations     : $CachedCount"
Write-Host "Empty descriptions      : $EmptyCount"
Write-Host "Failed translations     : $FailedCount"
Write-Host "Total source characters : $TotalCharacters"

Write-Host ""
Write-Host "Gamelist updated : $filePath"
Write-Host "Backup            : $backupPath"
Write-Host "Cache             : $CachePath"

if ($StoppedBy429) {
    Write-Host "Progress          : $ProgressPath"
}