# Gamelist-Translator

Translate game descriptions in `gamelist.xml` files from EmulationStation / RetroBat using Google Translate or DeepL.

This project is a fork of the original **Gamelist-Translator** script created by **Schmurtz**.

The original project and its historical version information have been preserved, while this fork adds several features to make the translator safer and more suitable for large RetroBat collections.

## Features

- Interactive translation service selection
- Support for:
  - Google Translate
  - DeepL
- DeepL API integration
- Interactive source language selection
- Interactive target language selection
- Support for:
  - English
  - French
  - Spanish
  - German
  - Italian
  - Portuguese
  - Japanese
- Automatic source language detection
- XML validation before processing
- UTF-8 / BOM handling
- Automatic backup of the original `gamelist.xml`
- Google Translate integration using `curl.exe`
- Complete translation response reconstruction when Google splits a description into multiple segments
- Translation cache to avoid translating the same description multiple times
- Empty descriptions are automatically ignored
- HTTP status detection for Google Translate requests
- HTTP 429 (`Too Many Requests`) detection
- Safe stop when Google rate-limits requests
- Progress saving during translation
- Resume after an interruption
- Periodic progress saving
- Automatic removal of the progress file after a successful complete translation
- Final translation summary
- Original descriptions are kept if a translation fails

## Translation service selection

The translator supports two translation services:

```text
========================================
Select translation service
========================================
1. Google Translate
2. DeepL
Selection:
```

### Google Translate

Google Translate requests are performed through the Windows `curl.exe` command-line tool.

The translator checks the HTTP status returned by Google before processing the response and explicitly detects HTTP `429` (`Too Many Requests`).

### DeepL

DeepL can be selected as an alternative translation service.

DeepL requires a valid DeepL API key. The API key is requested when DeepL is selected and is not stored in the translation cache or progress file.

The selected translation service is also stored in the progress information. This prevents a translation from being resumed with a different service.

## Interactive language selection

The translator does not force a specific target language.

When the script starts, the user can select the source and target languages:

```text
========================================
Select source language
========================================
1. Auto detect [auto]
2. English [en]
3. French [fr]
4. Spanish [es]
5. German [de]
6. Italian [it]
7. Portuguese [pt]
8. Japanese [ja]

========================================
Select target language
========================================
1. English [en]
2. French [fr]
3. Spanish [es]
4. German [de]
5. Italian [it]
6. Portuguese [pt]
7. Japanese [ja]
```

This allows the same script to be used for different translation directions without modifying the source code.

## Usage

Open PowerShell and run:

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\Gamelist-Translator.ps1" "C:\RetroBat\roms\ports\gamelist.xml"
```

For example:

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\Gamelist-Translator.ps1" "C:\RetroBat\roms\mame\gamelist.xml"
```

The script will then ask for the source and target languages.

## Backup

Before modifying the `gamelist.xml`, the script creates a timestamped backup.

Example:

```text
gamelist_2026-08-26_130138.xml
```

The original file is therefore preserved before translation begins.

## Translation cache

The translator maintains a local cache of completed translations.

This prevents the same description from being sent to the selected translation service again when the same translation service, source language, target language and text are encountered.

The cache is stored as:

```text
.gamelist-translator-cache.json
```

The cache is generated automatically and should not normally be committed to the Git repository.

The cache works with both Google Translate and DeepL. Cached translations are associated with the selected translation service, source language, target language and original text.

## Google Translate and curl.exe

Google Translate requests are performed through the Windows `curl.exe` command-line tool.

This avoids compatibility problems encountered with PowerShell's native HTTP request handling and provides reliable access to the Google Translate endpoint.

The translator also retrieves the HTTP status code returned by Google for every request.

Example:

```text
Google request via curl.exe...
```

The HTTP status is checked before processing the response.

Successful requests return HTTP `200`.

If Google returns HTTP `429` (`Too Many Requests`), the translator stops the translation safely instead of continuing to send requests.

The current progress and translation cache are saved before stopping.

This protects large translation jobs from losing their progress when Google temporarily rate-limits requests.

## HTTP 429 handling

Google Translate may temporarily reject requests with HTTP 429 (`Too Many Requests`).

The translator detects the HTTP status returned by Google through `curl.exe`.

When HTTP 429 is detected:

1. The current translation is stopped.
2. The current progress is saved.
3. The translation cache is saved.
4. The XML file is saved.
5. The progress file is kept so the translation can be resumed later.

Example:

```text
Google Translate returned HTTP 429 (Too Many Requests).
Google Translate is rate limiting requests.
Translation will stop to protect current progress.
Progress saved before stopping.
```

When the translation completes successfully, the progress file is automatically removed.

The original description is always kept when a translation cannot be completed.

## Progress and resume

For large collections, translation can take a significant amount of time.

The translator periodically saves its progress and translation cache.

The progress file is:

```text
.gamelist-translator-progress.json
```

The cache file is:

```text
.gamelist-translator-cache.json
```

If the process is interrupted or Google returns HTTP 429, the progress file is kept.

When the script is launched again with the same `gamelist.xml`, source language and target language, the translator automatically resumes from the saved position.

Example:

```text
Previous progress found.
Resume from game index : 10
```

After a complete successful translation, the progress file is automatically deleted.

The translation cache is retained for future use.

## Empty descriptions

Games without a description, or with an empty `<desc>` element, are automatically skipped.

For example:

```xml
<game>
    <name>Example Game</name>
    <desc></desc>
</game>
```

will not generate a translation request.

## Translation summary

At the end of a translation, the script displays a summary including:

```text
************ Translation summary ************
Translated descriptions : 12
Cached translations     : 4
Empty descriptions      : 2
Failed translations     : 0
Total source characters : 12345
```

The final paths of the modified gamelist, backup and cache are also displayed.

## Supported XML

The translator is designed to work with standard EmulationStation / RetroBat `gamelist.xml` files.

Only game descriptions are translated.

The following information is not intentionally translated:

- game names
- paths
- images
- videos
- ratings
- metadata
- other game fields

## Version 2.1.0

Version 2.1.0 introduces DeepL as an alternative translation service and significantly improves the reliability of Google Translate requests.

Main changes:

- Added Google Translate and DeepL service selection.
- Added DeepL API support.
- Added reliable Google Translate requests through `curl.exe`.
- Added HTTP status detection and HTTP 429 handling for Google Translate.
- Added progress saving and automatic resume.
- Improved translation cache handling.
- Improved handling of Google Translate responses split into multiple segments.
- Progress files are automatically removed after a successful complete translation.

## Original project

This project is a fork of the original **Gamelist-Translator** created by **Schmurtz**.

The original version dates from April 20, 2022.

Original version history:

### V1.0 - 2022-04-20

- You can change the target language inside the script.
- Create backup of the original gamelist.xml before modification.
- Should support accents / UTF8 in the right way.

### V1.1 - 2022-04-20

- Count the total number of characters sent for translation.

The original authorship and historical information are preserved in the PowerShell script.

## Current project status

This project is currently being developed as a PowerShell-based fork.

The current version supports both Google Translate and DeepL, with translation caching, progress saving, automatic resume and safe handling of Google HTTP 429 rate limiting.

The current development priorities are:

1. Continue testing with real RetroBat `gamelist.xml` files.
2. Verify translation reliability on large collections.
3. Improve translation service handling and error reporting.
4. Define the final translation workflow and behavior.
5. Consider a future C# implementation.

## Disclaimer

Always keep a backup of your original `gamelist.xml` files.

Translation quality depends on the translation service used and the original descriptions.

This project is not affiliated with RetroBat, EmulationStation, Google or DeepL.

GitHub repository: https://github.com/theJim69/Gamelist-Translator