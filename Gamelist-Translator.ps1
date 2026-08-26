# Gamelist-Translator By Schmurtz
#
# Translate games descriptions in gamelist.xml from EmulationStation
# (thanks to a powershell script and Google Translate).
# https://github.com/schmurtzm/Gamelist-Translator
#
# V1.0 - 2022-04-20
#   - You can change the target language inside the script.
#   - Create backup of the original gamelist.xml before modification.
#   - Should support accents / UTF8 in the right way.
#
# V1.1 - 2022-04-20
#   - Count the total number of characters sent to translation.
#
# ---------------------------------------------------------------------------
# RetroBat Gamelist Translator
#
# This project is a fork of the original Gamelist-Translator script.
#
# Main additions:
#   - Interactive translation service selection
#   - Google Translate
#   - DeepL
#   - Interactive source and target language selection
#   - Translation cache
#   - XML validation
#   - UTF-8 handling
#   - Safe backups
#   - HTTP 429 handling
#   - Progress saving
#   - Resume after interruption
#   - Periodic progress saving
#   - Final translation summary
#   - Original descriptions kept if translation fails
#
# Maintained by: theJim
# GitHub: https://github.com/theJim69/Gamelist-Translator
# ---------------------------------------------------------------------------

# Usage:
# Gamelist-Translator.ps1 "C:\RetroBat\roms\ports\gamelist.xml"

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
# DeepL translation
# ------------------------------------------------------------

function Invoke-DeepLTranslation {
    param(
        [string]$Text,
        [string]$SourceLanguage,
        [string]$TargetLanguage
    )

    if ([string]::IsNullOrWhiteSpace($env:DEEPL_API_KEY)) {
        throw "DEEPL_API_KEY is not configured."
    }

    $Source = $SourceLanguage.ToUpper()
    $Target = $TargetLanguage.ToUpper()

    if ($Source -eq "AUTO") {
        $Source = $null
    }

    $TextList = [System.Collections.Generic.List[string]]::new()
    $TextList.Add($Text)

    $Body = @{
        text        = $TextList
        target_lang = $Target
    }

    if ($null -ne $Source) {
        $Body.source_lang = $Source
    }

    $Headers = @{
        Authorization = "DeepL-Auth-Key $($env:DEEPL_API_KEY)"
    }

    $JsonBody = $Body | ConvertTo-Json -Compress

    $Response = Invoke-RestMethod `
        -Uri "https://api-free.deepl.com/v2/translate" `
        -Method Post `
        -Headers $Headers `
        -ContentType "application/json; charset=utf-8" `
        -Body $JsonBody `
        -ErrorAction Stop

    if (
        $null -eq $Response -or
        $null -eq $Response.translations -or
        @($Response.translations).Count -eq 0
    ) {
        throw "DeepL returned an empty translation response."
    }

    $Translation = [string](@($Response.translations)[0].text)

    if ([string]::IsNullOrWhiteSpace($Translation)) {
        throw "DeepL returned an empty translation."
    }

    return $Translation
}

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
# Google Translate
# ------------------------------------------------------------

function Invoke-GoogleTranslation {
    param(
        [string]$Text,
        [string]$SourceLanguage,
        [string]$TargetLanguage
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "Google Translate received an empty text."
    }

    $EncodedText = [System.Uri]::EscapeDataString($Text)

    $Uri = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=$SourceLanguage&tl=$TargetLanguage&dt=t&q=$EncodedText"

    $UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"

    Write-Host "Google request via curl.exe..."

    # --------------------------------------------------------
    # Execute curl
    # --------------------------------------------------------

    $CurlOutput = & curl.exe `
    -A "$UserAgent" `
    --silent `
    --show-error `
    --write-out "`n__HTTP_STATUS__:%{http_code}" `
    --url "$Uri" `
    2>&1

$CurlExitCode = $LASTEXITCODE

if ($CurlExitCode -ne 0) {
    throw "curl.exe failed with exit code $CurlExitCode."
}

$ResponseText = ($CurlOutput | ForEach-Object {
    [string]$_
}) -join "`n"

if ($ResponseText -notmatch "__HTTP_STATUS__:(\d+)\s*$") {
    throw "Unable to determine HTTP status returned by Google Translate."
}

$HttpStatus = [int]$Matches[1]

$JsonText = $ResponseText -replace "`r?`n__HTTP_STATUS__:\d+\s*$", ""

if ($HttpStatus -eq 429) {
    throw "HTTP 429"
}

if ($HttpStatus -lt 200 -or $HttpStatus -ge 300) {
    throw "Google Translate returned HTTP $HttpStatus."
}

if ([string]::IsNullOrWhiteSpace($JsonText)) {
    throw "Google Translate returned an empty response."
}

try {
    $Response = $JsonText | ConvertFrom-Json -ErrorAction Stop
}
catch {
    throw "Google Translate returned invalid JSON."
}

if (
    $null -eq $Response -or
    $null -eq $Response[0]
) {
    throw "Google Translate returned an invalid response."
}

return $Response

    # --------------------------------------------------------
    # Convert curl output to one string
    # --------------------------------------------------------

    $ResponseText = ($CurlOutput | ForEach-Object {
        [string]$_
    }) -join "`n"

    if ([string]::IsNullOrWhiteSpace($ResponseText)) {
        throw "Google Translate returned an empty response."
    }

    # --------------------------------------------------------
    # Extract HTTP status
    # --------------------------------------------------------

    if ($ResponseText -notmatch "__HTTP_STATUS__:(\d+)\s*$") {
        throw "Unable to determine HTTP status returned by Google Translate."
    }

    $HttpStatus = [int]$Matches[1]

    # Remove the HTTP status marker from the JSON
    $JsonText = $ResponseText -replace "`r?`n__HTTP_STATUS__:\d+\s*$", ""

    # --------------------------------------------------------
    # HTTP status handling
    # --------------------------------------------------------

    if ($HttpStatus -eq 429) {
        throw "HTTP 429: Google Translate rate limiting requests."
    }

    if ($HttpStatus -lt 200 -or $HttpStatus -ge 300) {
        throw "Google Translate returned HTTP $HttpStatus."
    }

    if ([string]::IsNullOrWhiteSpace($JsonText)) {
        throw "Google Translate returned an empty JSON response."
    }

    # --------------------------------------------------------
    # Parse JSON
    # --------------------------------------------------------

    try {
        $Response = $JsonText | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Google Translate returned invalid JSON. Raw response: $JsonText"
    }

    if (
        $null -eq $Response -or
        $null -eq $Response[0]
    ) {
        throw "Google Translate returned an invalid response."
    }

    return $Response
}

# ------------------------------------------------------------
# Translation service selection
# ------------------------------------------------------------

function Select-TranslationService {

    Write-Host ""
    Write-Host "========================================"
    Write-Host "Select translation service"
    Write-Host "========================================"
    Write-Host "1. Google Translate"
    Write-Host "2. DeepL"

    do {

        $choice = Read-Host "Selection"

        switch ($choice) {

            "1" {
                return "google"
            }

            "2" {
                return "deepl"
            }

            default {
                Write-Host "Invalid selection." -ForegroundColor Yellow
            }
        }

    } while ($true)
}

$TranslationService = Select-TranslationService

if ($TranslationService -eq "deepl") {

    if ([string]::IsNullOrWhiteSpace($env:DEEPL_API_KEY)) {

        Write-Host ""
        Write-Host "ERROR : DEEPL_API_KEY is not configured." -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "DeepL API key detected." -ForegroundColor Green
}

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
Write-Host "Service : $TranslationService"
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

        $loaded = Get-Content `
            -LiteralPath $CachePath `
            -Raw |
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
            Set-Content `
                -LiteralPath $CachePath `
                -Encoding UTF8

        Write-Host "Translation cache saved : $CachePath"

    }
    catch {

        Write-Host "WARNING : Unable to save translation cache." `
            -ForegroundColor Yellow

        Write-Host "Details : $($_.Exception.Message)"
    }
}

# ------------------------------------------------------------
# Progress
# ------------------------------------------------------------

$StartIndex = 0

if (Test-Path -LiteralPath $ProgressPath) {

    try {

        $progress = Get-Content `
            -LiteralPath $ProgressPath `
            -Raw |
            ConvertFrom-Json

        if (
            $progress.File -eq $filePath -and
            $progress.TranslationService -eq $TranslationService -and
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

    param(
        [int]$NextIndex
    )

    $data = [ordered]@{
        File               = $filePath
        TranslationService = $TranslationService
        SourceLanguage     = $SourceLanguage
        TargetLanguage     = $TargetLanguage
        NextGameIndex      = $NextIndex
    }

    try {

        $data |
            ConvertTo-Json |
            Set-Content `
                -LiteralPath $ProgressPath `
                -Encoding UTF8

    }
    catch {

        Write-Host "WARNING : Unable to save progress." `
            -ForegroundColor Yellow
    }
}

# ------------------------------------------------------------
# Backup
# ------------------------------------------------------------

$timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"

$backupPath = Join-Path `
    $directory `
    "${baseName}_${timestamp}.xml"

Write-Host "Creating backup file : $backupPath"

try {

    Copy-Item `
        -LiteralPath $filePath `
        -Destination $backupPath `
        -ErrorAction Stop

    Write-Host "Backup successfully created : $backupPath"

}
catch {

    Write-Host "ERROR : Unable to create backup." `
        -ForegroundColor Red

    Write-Host $_.Exception.Message

    return
}

# ------------------------------------------------------------
# Load XML
# ------------------------------------------------------------

try {

    [xml]$xmlDoc = (
        Select-Xml `
            -LiteralPath $filePath `
            -XPath /
    ).Node

}
catch {

    Write-Host "ERROR : Invalid XML file." `
        -ForegroundColor Red

    Write-Host $_.Exception.Message

    return
}

if ($null -eq $xmlDoc.gameList) {

    Write-Host "ERROR : <gameList> element not found." `
        -ForegroundColor Red

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

    $cacheKey = "$TranslationService|$SourceLanguage|$TargetLanguage|$Text"

    if ($Cache.ContainsKey($cacheKey)) {

        $Translation = $Cache[$cacheKey]

        Write-Host "************ Translation from cache ************"
        Write-Host $Translation

        $game.desc = $Translation

        $CachedCount++

    }
    else {

        if (
            $i -gt $StartIndex -and
            $RequestDelaySeconds -gt 0
        ) {

            Start-Sleep -Seconds $RequestDelaySeconds
        }

        try {

            Write-Host "Translation request..."

            # ------------------------------------------------
            # DeepL
            # ------------------------------------------------

            if ($TranslationService -eq "deepl") {

                $Translation = Invoke-DeepLTranslation `
                    -Text $Text `
                    -SourceLanguage $SourceLanguage `
                    -TargetLanguage $TargetLanguage
            }

            # ------------------------------------------------
            # Google Translate
            # ------------------------------------------------

            else {

                $Response = Invoke-GoogleTranslation `
                    -Text $Text `
                    -SourceLanguage $SourceLanguage `
                    -TargetLanguage $TargetLanguage

                if (
                    $null -eq $Response -or
                    $null -eq $Response[0] -or
                    $null -eq $Response[0][0] -or
                    [string]::IsNullOrWhiteSpace(
                        [string]$Response[0][0][0]
                    )
                ) {

                    throw "Invalid translation response."
                }

                # Google can split a translation into several segments.
                # Rebuild the complete translation.

                $Translation = (
                    $Response[0] |
                    ForEach-Object {

                        if (
                            $null -ne $_ -and
                            $_.Count -gt 0
                        ) {

                            [string]$_.Item(0)
                        }
                    }
                ) -join ""

                if ([string]::IsNullOrWhiteSpace($Translation)) {

                    throw "Empty translation returned by Google Translate."
                }
            }

            if ([string]::IsNullOrWhiteSpace($Translation)) {

                throw "Empty translation returned by $TranslationService."
            }

            Write-Host "************ Translation ************"
            Write-Host $Translation

            $game.desc = $Translation

            $TranslatedCount++

            $Cache[$cacheKey] = $Translation
        }
        catch {

            $ErrorMessage = $_.Exception.Message

            # ------------------------------------------------
            # HTTP 429
            # ------------------------------------------------

            if (
                $ErrorMessage -like "*HTTP 429*" -or
                $ErrorMessage -like "*Too Many Requests*"
            ) {

                Write-Host ""
                Write-Host "Google Translate returned HTTP 429 (Too Many Requests)." `
                    -ForegroundColor Yellow

                Write-Host "Google Translate is rate limiting requests."
                Write-Host "Translation will stop to protect current progress."

                $FailedCount++

                $StoppedBy429 = $true

                # Save before stopping.
                Save-Progress $i
                Save-Cache

                break
            }

            # ------------------------------------------------
            # Other translation errors
            # ------------------------------------------------

            Write-Host `
                "Translation failed - original description kept." `
                -ForegroundColor Yellow

            Write-Host "Details : $ErrorMessage"

            $FailedCount++

            Save-Progress ($i + 1)

            continue
        }
    }

    # --------------------------------------------------------
    # Save every N games
    # --------------------------------------------------------

    if ((($i + 1) % $SaveEvery) -eq 0) {

        Write-Host ""
        Write-Host "Saving progress..."

        Save-Progress ($i + 1)
        Save-Cache

        try {

            $xmlDoc.Save($filePath)

            Write-Host `
                "Progress saved : $($i + 1) games processed."

        }
        catch {

            Write-Host `
                "WARNING : Unable to save XML during progress save." `
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

    Write-Host `
        "WARNING : Translation stopped because $TranslationService returned HTTP 429." `
        -ForegroundColor Yellow

    Write-Host "Progress saved before stopping."
}

try {

    $settings = New-Object System.Xml.XmlWriterSettings

    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)
    $settings.Indent = $true
    $settings.NewLineChars = "`r`n"

    $writer = [System.Xml.XmlWriter]::Create(
        $filePath,
        $settings
    )

    try {

        $xmlDoc.Save($writer)
    }
    finally {

        $writer.Close()
    }

    Write-Host "XML saved as UTF-8."

}
catch {

    Write-Host `
        "ERROR : Unable to save XML." `
        -ForegroundColor Red

    Write-Host $_.Exception.Message

    return
}

# ------------------------------------------------------------
# Remove progress file after successful completion
# ------------------------------------------------------------

if (-not $StoppedBy429) {

    if (Test-Path -LiteralPath $ProgressPath) {

        Remove-Item `
            -LiteralPath $ProgressPath `
            -Force
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