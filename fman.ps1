<#
.SYNOPSIS
    fman - Lightning-fast PowerShell Font Manager for Windows.
.DESCRIPTION
    Install, remove, list, and manage Windows fonts with zero dependencies.
    Supports Neovim-style GitHub repo shorthand (e.g. 'owner/repo'), direct release URLs,
    local .ttf/.otf files, and .zip archives.
.EXAMPLE
    fman install the-moonwitch/Cozette
    fman install IdreesInc/Monocraft
    fman install "https://example.com/font.zip"
    fman install "C:\Downloads\MyFont.ttf"
    fman list
    fman list -full
    fman remove Cozette
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $false)]
    [ValidateSet("install", "i", "remove", "rm", "r", "add", "list", "ls", "l", "lf", "version", "v", "help", "h")]
    [string]$Action = "list",

    [Parameter(Position = 1, Mandatory = $false, ValueFromRemainingArguments = $true)]
    [string[]]$Targets
)

$VERSION = "1.0.0"
$userFonts = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
$regKey    = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"
$manifest  = "$env:LOCALAPPDATA\fman\fonts.json"

if (-not (Test-Path $userFonts)) {
    New-Item -ItemType Directory -Path $userFonts -Force | Out-Null
}

$manifestDir = [System.IO.Path]::GetDirectoryName($manifest)
if (-not (Test-Path $manifestDir)) {
    New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
}

# Helper: Update local tracked manifest
function Update-Manifest {
    param([string]$FontName, [bool]$Add)
    try {
        $data = if (Test-Path $manifest) { Get-Content $manifest -Raw | ConvertFrom-Json -AsHashtable } else { @{ "fonts" = @() } }
        $list = [System.Collections.Generic.List[object]]::new(@($data["fonts"]))
        if ($Add) {
            if ($list -notcontains $FontName) {
                $list.Add($FontName)
                $data["fonts"] = $list
                $data | ConvertTo-Json -Depth 5 | Set-Content $manifest -Encoding UTF8
            }
        } else {
            if ($list -contains $FontName) {
                [void]$list.Remove($FontName)
                $data["fonts"] = $list
                $data | ConvertTo-Json -Depth 5 | Set-Content $manifest -Encoding UTF8
            }
        }
    } catch {}
}

# Helper: Notify Windows of Font Change
function Send-FontNotification {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WinFontNotifier {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern int SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);
}
"@ -ErrorAction SilentlyContinue
    try {
        [WinFontNotifier]::SendMessage(0xffff, 0x001D, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
    } catch {}
}

switch ($Action) {
    { $_ -in "version", "v" } {
        Write-Host "fman v$VERSION - PowerShell Font Manager for Windows" -ForegroundColor Cyan
        return
    }

    { $_ -in "help", "h" } {
        Write-Host @"
fman v$VERSION - Lightning-fast PowerShell Font Manager for Windows

USAGE:
    fman install <repo | url | path>    Install font from GitHub repo, URL, or local file
    fman remove <font_name>             Uninstall a font and remove registry entries
    fman list                           List all installed font families
    fman list -full                     List all individual .ttf / .otf variant files
    fman add <font_name>                Track a font name in local manifest

EXAMPLES:
    fman install the-moonwitch/Cozette
    fman install IdreesInc/Monocraft
    fman install "https://github.com/.../release.zip"
    fman install "C:\Downloads\CustomFont.ttf"
    fman remove Cozette
    fman list
    fman list -full
"@ -ForegroundColor Cyan
        return
    }

    { $_ -in "list", "ls", "l", "lf" } {
        $isFull = ($Action -eq "lf") -or ($Targets -contains "full") -or ($Targets -contains "-full") -or ($Targets -contains "-f")

        $installed = Get-ChildItem -Path $userFonts -Include *.ttf, *.otf -Recurse -ErrorAction SilentlyContinue

        if (-not $installed -or $installed.Count -eq 0) {
            Write-Host "No user fonts installed in $userFonts." -ForegroundColor Yellow
            return
        }

        # Group files into font families
        $groups = [System.Collections.Generic.SortedDictionary[string, System.Collections.Generic.List[string]]]::new([System.StringComparer]::OrdinalIgnoreCase)

        foreach ($f in $installed) {
            $clean = $f.BaseName -replace '(-Bold|-Regular|-Italic|-BoldItalic|-ExtraBold|-SemiBold|-Light|-Medium|-Thin|-Heavy|-Oblique|-Normal|BoldItalic|BoldUpright|RegularItalic|RegularUpright|_bold|_italic|_regular)+$', ''
            $clean = $clean -replace '[-_]+$', ''
            if (-not $groups.ContainsKey($clean)) {
                $groups[$clean] = [System.Collections.Generic.List[string]]::new()
            }
            $groups[$clean].Add($f.Name)
        }

        Write-Host "`n=== INSTALLED USER FONTS ($($groups.Count) Families, $($installed.Count) Files) ===" -ForegroundColor Cyan
        foreach ($fam in $groups.Keys) {
            Write-Host "  [OK] $fam ($($groups[$fam].Count) variant file(s))" -ForegroundColor Green
            if ($isFull) {
                foreach ($file in $groups[$fam]) {
                    Write-Host "       -> $file" -ForegroundColor DarkGray
                }
            }
        }

        if (-not $isFull) {
            Write-Host "`n Tip: Run 'fman list -full' (or 'fman lf') to view all individual .ttf/.otf variant files." -ForegroundColor DarkCyan
        }
    }

    { $_ -in "add" } {
        if (-not $Targets) {
            Write-Error "Please specify a font name to track."
            return
        }
        foreach ($t in $Targets) {
            Update-Manifest $t $true
            Write-Host "Tracked font '$t' in manifest." -ForegroundColor Green
        }
    }

    { $_ -in "install", "i" } {
        if (-not $Targets) {
            Write-Error "Please specify a GitHub repo (owner/repo), URL, or local font path."
            return
        }

        foreach ($target in $Targets) {
            $tempDir = $null
            $filesToInstall = @()
            $inferredName = $target

            # 1. GitHub repo shorthand (e.g. 'the-moonwitch/Cozette', 'IdreesInc/Monocraft')
            if ($target -match '^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$' -and -not (Test-Path $target)) {
                Write-Host "Resolving latest GitHub release for $target..." -ForegroundColor Cyan
                try {
                    $api = "https://api.github.com/repos/$target/releases/latest"
                    $headers = @{ "User-Agent" = "Mozilla/5.0" }
                    if ($env:GITHUB_TOKEN) { $headers["Authorization"] = "token $env:GITHUB_TOKEN" }
                    $res = Invoke-RestMethod -Uri $api -Headers $headers -ErrorAction Stop

                    $zipAssets = @($res.assets | Where-Object { $_.name -match "\.zip$" })
                    $downloadUrls = @()
                    if ($zipAssets.Count -gt 0) {
                        $best = ($zipAssets | Where-Object { $_.name -match "(font|vector|bundle|release|all)" } | Select-Object -First 1)
                        if (-not $best) { $best = $zipAssets[0] }
                        $downloadUrls = @($best.browser_download_url)
                    } else {
                        $fontAssets = @($res.assets | Where-Object { $_.name -match "\.(ttf|otf)$" })
                        if ($fontAssets.Count -gt 0) {
                            $downloadUrls = @($fontAssets | Select-Object -ExpandProperty browser_download_url)
                        }
                    }

                    if ($downloadUrls.Count -gt 0) {
                        $tempDir = Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString())
                        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
                        foreach ($dUrl in $downloadUrls) {
                            $fName = ($dUrl -split '/')[-1]
                            $dlFile = Join-Path $tempDir $fName
                            curl.exe -fL -A "Mozilla/5.0" -s -o $dlFile $dUrl
                            if ($fName -match '\.zip$') {
                                Expand-Archive -Path $dlFile -DestinationPath $tempDir -Force
                            }
                        }
                        $filesToInstall = Get-ChildItem -Path $tempDir -Include *.ttf, *.otf -Recurse
                        $inferredName = ($target -split '/')[-1]
                    } else {
                        Write-Warning "No font files (.ttf/.otf/.zip) found in latest release of $target."
                    }
                } catch {
                    Write-Warning "GitHub release query failed for $target : $_"
                }
            }
            # 2. URL Download (Direct Link or Release Asset)
            elseif ($target -match '^https?://') {
                Write-Host "Downloading font from $target..." -ForegroundColor Cyan
                $tempDir = Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString())
                New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
                $fileName = ($target -split '/')[-1]
                $dlPath = Join-Path $tempDir $fileName
                if (Get-Command 'curl.exe' -ErrorAction SilentlyContinue) {
                    curl.exe -fL -A "Mozilla/5.0" -s -o $dlPath $target
                } else {
                    Invoke-WebRequest -Uri $target -OutFile $dlPath -Headers @{ 'User-Agent' = 'Mozilla/5.0' } -MaximumRedirection 10
                }

                if ($fileName -match '\.zip$') {
                    Expand-Archive -Path $dlPath -DestinationPath $tempDir -Force
                    $filesToInstall = Get-ChildItem -Path $tempDir -Include *.ttf, *.otf -Recurse
                } elseif ($fileName -match '\.(ttf|otf)$') {
                    $filesToInstall = @(Get-Item $dlPath)
                }
                $inferredName = ($fileName -replace '\.(zip|ttf|otf)$', '')
            }
            # 3. Local File / Folder / ZIP
            elseif (Test-Path $target) {
                $item = Get-Item $target
                if ($item.PSIsContainer) {
                    $filesToInstall = Get-ChildItem -Path $item.FullName -Include *.ttf, *.otf -Recurse
                    $inferredName = $item.Name
                } elseif ($item.Extension -ieq ".zip") {
                    $tempDir = Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString())
                    Expand-Archive -Path $item.FullName -DestinationPath $tempDir -Force
                    $filesToInstall = Get-ChildItem -Path $tempDir -Include *.ttf, *.otf -Recurse
                    $inferredName = [System.IO.Path]::GetFileNameWithoutExtension($item.Name)
                } elseif ($item.Extension -in @(".ttf", ".otf")) {
                    $filesToInstall = @($item)
                    $inferredName = [System.IO.Path]::GetFileNameWithoutExtension($item.Name)
                }
            }
            # 4. Fallback Font Name (Track in manifest)
            else {
                Update-Manifest $target $true
                continue
            }

            # Install font files to User Fonts directory
            foreach ($f in $filesToInstall) {
                $dest = Join-Path $userFonts $f.Name
                try {
                    if (-not (Test-Path $dest)) {
                        Copy-Item $f.FullName $dest -Force -ErrorAction Stop
                    }
                    $fontRegName = "$([System.IO.Path]::GetFileNameWithoutExtension($f.Name)) (TrueType)"
                    Set-ItemProperty -Path $regKey -Name $fontRegName -Value $dest -Force
                    Write-Host "Installed: $($f.Name)" -ForegroundColor Green
                } catch {
                    Write-Host "Skipped (in use/already present): $($f.Name)" -ForegroundColor DarkGray
                }
            }

            if ($filesToInstall.Count -gt 0) {
                Send-FontNotification
                Update-Manifest $inferredName $true
                Write-Host "Font '$inferredName' successfully installed and registered!" -ForegroundColor Green
            }

            if ($tempDir -and (Test-Path $tempDir)) {
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    { $_ -in "remove", "rm", "r" } {
        if (-not $Targets) {
            Write-Error "Please specify a font name to remove."
            return
        }

        foreach ($target in $Targets) {
            $pattern = "*$target*"
            $foundFiles = Get-ChildItem -Path $userFonts -Filter $pattern -Include *.ttf, *.otf -Recurse -ErrorAction SilentlyContinue
            if ($foundFiles) {
                foreach ($f in $foundFiles) {
                    Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue
                    Write-Host "Deleted font file: $($f.Name)" -ForegroundColor Yellow
                }
            }

            # Remove registry entries
            $regEntries = Get-ItemProperty -Path $regKey -ErrorAction SilentlyContinue
            if ($regEntries) {
                $props = $regEntries.PSObject.Properties | Where-Object { $_.Name -like "*$target*" -or $_.Value -like "*$target*" }
                foreach ($prop in $props) {
                    Remove-ItemProperty -Path $regKey -Name $prop.Name -ErrorAction SilentlyContinue
                    Write-Host "Removed registry font: $($prop.Name)" -ForegroundColor Yellow
                }
            }

            Send-FontNotification
            Update-Manifest $target $false
            Write-Host "Font '$target' uninstalled." -ForegroundColor Green
        }
    }
}
