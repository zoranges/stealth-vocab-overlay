# Stealth Vocab Overlay

A lightweight Windows desktop overlay for reviewing vocabulary with minimal visual presence. It shows words in a small transparent floating window and supports auto rotation, manual navigation, focus mode, familiar/unknown word lists, and a searchable catalog.

The app is built with Windows PowerShell and WPF. It does not require Python, Node.js, or any third-party runtime. On Windows 10 or Windows 11, users can unzip the project and run it directly.

## Features

- Transparent floating word overlay
- Auto rotation and manual navigation
- Global next-word hotkey, default `F8`
- Adjustable opacity, position, window size, font size, and rotation speed
- Opacity can be set as low as about `0.03` for an almost invisible overlay
- Text presets and readability enhancement for complex wallpapers
- Focus mode:
  - Mouse wheel switches words
  - Left click marks the word as familiar
  - Right click marks the word as unknown
  - Custom familiar/unknown hotkeys, default `A` and `D`
  - `Esc` exits focus mode
  - `Enter` opens settings
- Study deck selection:
  - All
  - Unclassified
  - Familiar
  - Unknown
- Remembers the last position separately for each study deck
- Supports jumping to a specific start number in the current deck
- Imports familiar or unknown word-list JSON files from any location
- Catalog window with separate tabs for:
  - All
  - Unclassified
  - Familiar
  - Unknown
- Familiar and unknown words are saved as separate local JSON files
- One-click packaging script for sharing a clean release zip

## Quick Start

1. Download or clone this repository.
2. Keep these files in the same folder:
   - `stealth_vocab_wpf.ps1`
   - the bundled `.bat` launcher
   - the main vocabulary JSON file
3. Double-click the bundled `.bat` launcher.
4. A small floating vocabulary window will appear on the desktop.

If Windows shows a security prompt, choose to continue running it. The app does not need network access and does not require installation.

## Controls

| Action | Result |
|---|---|
| Click the overlay without dragging | Open settings |
| Hold left mouse button and drag anywhere on the overlay | Move the overlay |
| Double-click the overlay | Next word |
| `F8` | Global next word |
| `Space` / `Right Arrow` | Next word |
| `Left Arrow` | Previous word |
| `Enter` | Open settings |
| Mouse wheel in focus mode | Switch words |
| Left click in focus mode | Mark as familiar |
| Right click in focus mode | Mark as unknown |
| `A` / `D` in focus mode | Default familiar / unknown hotkeys, configurable |
| `Esc` in focus mode | Exit focus mode |

## Settings

Settings take effect immediately and are saved to `stealth_vocab_wpf_settings.json`.

Available settings include:

- Opacity, from about `0.03` to `1.0`
- Width and height
- English word font size
- Meaning font size
- Rotation interval
- Manual next-word hotkey
- Text presets
- Readability enhancement
- Study deck
- Start number
- Import familiar-word JSON
- Import unknown-word JSON
- Auto rotation
- Show or hide meaning, part of speech, page number, index, and mode
- Always on top
- Light background helper
- Random order
- Lock position
- Focus mode

## Vocabulary Data

The main vocabulary file is:

```text
main-vocabulary.json
```

Expected structure:

```json
[
  {
    "english": "panorama",
    "meanings": [
      {
        "pos": "n.",
        "meanings": ["panorama", "overview"]
      }
    ],
    "page": 1
  }
]
```

On startup and when rebuilding the catalog, the app reads these local files if they exist:

```text
familiar-words.json
unknown-words.json
```

You can copy those files into the app directory, or import them from the settings window. The app will then refresh the deck state and generate:

```text
unclassified-words.json
```

Generated local data files:

| File | Purpose |
|---|---|
| `stealth_vocab_wpf_settings.json` | Personal settings |
| the familiar-word JSON file | Words marked as familiar |
| the unknown-word JSON file | Words marked as unknown |
| the unclassified-word JSON file | Automatically computed unclassified words |

These files are ignored by Git and are not included in the clean sharing package.

## Sharing

Run:

```text
package-release.ps1
```

The script creates a zip package similar to:

```text
stealth-vocab-overlay_YYYYMMDD.zip
```

The package includes only the files required to run the app. It does not include personal settings, familiar words, unknown words, or unclassified words.

Recipient instructions:

1. Extract the zip file.
2. Open the extracted app folder.
3. Double-click the bundled `.bat` launcher.

## Files

| File | Purpose |
|---|---|
| `stealth_vocab_wpf.ps1` | Main app |
| the bundled `.bat` launcher | Launcher |
| the main vocabulary JSON file | Main vocabulary database |
| the Chinese user guide | User guide |
| the short sharing guide | Short sharing guide |
| the package builder script | Clean package builder |
| `.gitignore` | Excludes personal data and generated files |

## Requirements

- Windows 10 or Windows 11
- PowerShell 5.1
- WPF / .NET Framework desktop components

These are normally available by default on Windows.

## Privacy

The app does not upload data and does not require network access. Settings, familiar words, unknown words, and unclassified words are stored only in the local app folder.

## License

MIT License


