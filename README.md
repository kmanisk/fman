# fman

> A fast, zero-dependency PowerShell font manager for Windows with Neovim-style GitHub repo shorthand support.

`fman` brings declarative, package-manager-style font management to Windows. It allows installing fonts directly from GitHub repositories using `owner/repo` shorthand, direct URLs, or local files, registers them instantly in Windows, and manages them with zero external dependencies and no administrative privileges required.

---

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
  - [1. GitHub Repository Shorthand](#1-github-repository-shorthand)
  - [2. Direct URLs and Release Archives](#2-direct-urls-and-release-archives)
  - [3. Local Files and Directories](#3-local-files-and-directories)
  - [4. Listing Installed Fonts](#4-listing-installed-fonts)
  - [5. Removing Fonts](#5-removing-fonts)
  - [6. Help and Version](#6-help-and-version)
- [How It Works](#how-it-works)
- [Command Reference](#command-reference)
- [License](#license)

---

## Features

- **GitHub Repo Shorthand**: Install fonts directly with `owner/repo` syntax (e.g., `the-moonwitch/Cozette`, `kika/fixedsys`).
- **Smart Asset Resolution**:
  - Automatically identifies and downloads release `.zip` archives.
  - Automatically downloads standalone `.ttf` and `.otf` release assets.
  - Recursively searches the Git tree for font files if no releases exist.
- **High Performance**:
  - Parallel multi-stream downloads via `curl --parallel`.
  - Fast IPv4 DNS resolution (`-4`) to eliminate S3 handshake delays.
  - Non-blocking Windows font broadcast (`SendNotifyMessage`) for sub-second execution.
- **Zero Dependencies & No Admin Required**:
  - Installs fonts per-user into `%LOCALAPPDATA%\Microsoft\Windows\Fonts`.
  - Automatically creates per-user registry entries in `HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts`.
- **Clean Grouped Listing**:
  - Groups font variant files cleanly by font family name by default.
  - Supports `-full` inspection to see every individual font file.
- **Clean Uninstallation**:
  - Automatically deletes font files and cleans up corresponding registry entries.

---

## Installation

### Method 1: Clone and Set Alias (Recommended)

1. Clone the repository to your user directory:
   ```powershell
   git clone https://github.com/kmanisk/fman.git ~/fman
   ```

2. Add the alias to your PowerShell profile:
   ```powershell
   Add-Content $PROFILE 'Set-Alias fman "$HOME\fman\fman.ps1"'
   ```

3. Reload your profile:
   ```powershell
   . $PROFILE
   ```

---

### Method 2: Wrapper Function

Add the following function to your `$PROFILE`:

```powershell
function fman { & "$HOME\fman\fman.ps1" @args }
```

---

## Usage

### 1. GitHub Repository Shorthand

`fman` automatically resolves and downloads font files from GitHub releases or repository source trees.

```powershell
# Install release containing a ZIP bundle
fman install the-moonwitch/Cozette

# Install release containing individual TTF assets
fman install kika/fixedsys

# Install font bundle from latest GitHub release
fman install IdreesInc/Monocraft

# Install from repository tree when no releases exist
fman install epk/SF-Mono-Nerd-Font
```

---

### 2. Direct URLs and Release Archives

Install directly from any web URL pointing to a `.zip`, `.ttf`, or `.otf` file:

```powershell
# Install from release archive URL
fman install "https://github.com/the-moonwitch/Cozette/releases/download/v.1.30.0/CozetteFonts-v-1-30-0.zip"

# Install from raw font file URL
fman install "https://example.com/fonts/CustomFont.ttf"
```

---

### 3. Local Files and Directories

Install fonts from your local disk:

```powershell
# Install single TTF or OTF file
fman install "C:\Downloads\CustomFont.ttf"

# Install all fonts inside a ZIP file
fman install "C:\Downloads\FontPack.zip"

# Install all fonts inside a folder
fman install "C:\Downloads\ExtractedFonts"
```

---

### 4. Listing Installed Fonts

#### Compact View (Default)
Groups all variant files cleanly by font family name:

```powershell
fman list
# or shorthand
fman l
```

*Example Output:*
```text
=== INSTALLED USER FONTS (16 Families, 123 Files) ===

[ Pixel & Bitmap Fonts ]
  - Cozette (8 variants)
  - Fixedsys (2 variants)
  - GohuFont (8 variants)
  - Monocraft (13 variants)
  - PixelCode (1 variants)

[ Monospace & Coding Fonts ]
  - Agave (4 variants)
  - AporeticSansMono (4 variants)
  - AporeticSerifMono (4 variants)
  - ComicMono (1 variants)
  - DaddyTimeMono (2 variants)
  - FantasqueSansMono (6 variants)
  - Hermit (6 variants)
  - IntelOneMono (3 variants)
  - Iosevka (54 variants)
  - PsudoFontLigaMono (4 variants)
  - VictorMono (3 variants)
```

#### Detailed View (`-full`)
Displays every individual font file under its family:

```powershell
fman list -full
# or shorthand
fman lf
```

*Example Output:*
```text
=== INSTALLED USER FONTS (16 Families, 123 Files) ===

[ Pixel & Bitmap Fonts ]
  - Fixedsys (2 variants)
       -> FSEX302-alt.ttf
       -> FSEX302.ttf
  - Monocraft (13 variants)
       -> Monocraft-Bold.otf
       -> Monocraft-Italic.otf
       ...
```

---

### 5. Removing Fonts

Uninstalls all matching font files from disk and removes their Windows registry entries:

```powershell
fman remove fixedsys
# or shorthand
fman rm Cozette
```

---

### 6. Help and Version

```powershell
# View help
fman help
# or
fman -h

# View version
fman version
# or
fman -v
```

---

## How It Works

1. **Asset Discovery**: When given `owner/repo`, `fman` checks the GitHub Releases API for zip archives and font files. If no release exists, it queries the GitHub Git Tree API to discover font files recursively throughout the repository.
2. **Parallel Fetching**: Assets are downloaded concurrently using `curl -4 --parallel` to ensure maximum throughput and bypass IPv6 DNS lookup delays.
3. **Per-User Installation**: Font files are copied to `%LOCALAPPDATA%\Microsoft\Windows\Fonts`, requiring no administrator privileges.
4. **Registry Registration**: Per-user font entries are written to `HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts`.
5. **Live System Notification**: `fman` calls the Win32 `SendNotifyMessage(HWND_BROADCAST, WM_FONTCHANGE, 0, 0)` API, notifying active applications (such as Windows Terminal, VS Code, and editors) without blocking the terminal session.

---

## Command Reference

| Command | Shorthand | Arguments | Description |
| :--- | :--- | :--- | :--- |
| `install` | `i` | `<repo \| url \| path>` | Install font from GitHub repo, URL, or local file |
| `remove` | `rm`, `r` | `<font_name>` | Uninstall font files and remove registry entries |
| `list` | `ls`, `l` | `[-full]` | List installed font families (or all files with `-full`) |
| `add` | `add` | `<font_name>` | Add a font name to the local tracking manifest |
| `help` | `h`, `-h`, `--help` | - | Display help and usage instructions |
| `version` | `v`, `-v`, `--version` | - | Display current version |

---

## License

MIT (c) [kmanisk](https://github.com/kmanisk)
