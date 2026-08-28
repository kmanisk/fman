# ⚡ fman — PowerShell Font Manager for Windows

> **A lightning-fast, zero-dependency PowerShell font manager for Windows with Neovim-style GitHub repo shorthand support.**

`fman` makes managing fonts on Windows as effortless as installing packages with Scoop or plugins with Lazy.nvim.

---

## ✨ Features

- 🚀 **GitHub Repo Shorthand**: Install fonts directly with `owner/repo` (e.g. `the-moonwitch/Cozette`, `IdreesInc/Monocraft`).
- ⚡ **Zero Dependencies**: Pure PowerShell, no admin rights required (installs per-user to `%LOCALAPPDATA%\Microsoft\Windows\Fonts`).
- 🔄 **Instant Live Registration**: Automatically registers fonts in the Windows Registry and broadcasts `WM_FONTCHANGE` so applications pick up fonts immediately without rebooting.
- 📦 **Multi-Format Support**: Direct `.ttf`, `.otf`, `.zip` release archives, or local directories.
- 📋 **Clean Grouped Listing**: Groups hundreds of variants cleanly by font family name, with a `-full` flag to inspect individual files.
- 🗑️ **Clean Uninstall**: Removes font files and unregisters registry keys automatically.

---

## 📥 Quick Start / Installation

### Option 1: Run Directly via PowerShell
```powershell
# Clone the repository
git clone https://github.com/kmanisk/fman.git ~/fman

# Add to your PowerShell profile ($PROFILE)
Add-Content $PROFILE 'Set-Alias fman "$HOME\fman\fman.ps1"'
```

### Option 2: One-Liner Profile Function
Add this to your PowerShell `$PROFILE`:
```powershell
function fman { & "$HOME\fman\fman.ps1" @args }
```

---

## 📖 Usage

### 1. Install Fonts via GitHub Shorthand *(Neovim-Style)*
```powershell
# Install latest Cozette font release from GitHub
fman install the-moonwitch/Cozette

# Install Monocraft font from GitHub
fman install IdreesInc/Monocraft
```

### 2. Install from URL / Release Archive
```powershell
fman install "https://github.com/the-moonwitch/Cozette/releases/download/v.1.30.0/CozetteFonts-v-1-30-0.zip"
```

### 3. Install from Local File or Directory
```powershell
# Install single TTF or OTF
fman install "C:\Downloads\MyFont.ttf"

# Install all fonts inside a ZIP or folder
fman install "C:\Downloads\FontBundle.zip"
fman install "C:\Downloads\FontsFolder"
```

### 4. List Installed Fonts
```powershell
# Concise list grouped by font family
fman list
# or shorthand:
fman l

# Full list showing every individual .ttf / .otf file
fman list -full
# or shorthand:
fman lf
```

### 5. Remove / Uninstall a Font
```powershell
fman remove Cozette
# or shorthand:
fman rm Monocraft
```

---

## 🛠️ CLI Cheat Sheet

| Command | Shorthand | Description |
| :--- | :--- | :--- |
| `fman install <target>` | `fman i <target>` | Install from GitHub `owner/repo`, URL, or file |
| `fman remove <font>` | `fman rm <font>` | Uninstall font files and remove registry entries |
| `fman list` | `fman l` | List installed font families |
| `fman list -full` | `fman lf` | List all individual `.ttf`/`.otf` variant files |
| `fman add <font>` | `fman add <font>` | Track a font name in the local manifest |
| `fman version` | `fman v` | Print `fman` version |
| `fman help` | `fman h` | Show help and usage examples |

---

## 📄 License

MIT © [kmanisk](https://github.com/kmanisk)
