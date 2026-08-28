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
    [ValidateSet("install", "i", "remove", "rm", "r", "add", "list", "ls", "l", "lf", "version", "v", "-v", "--version", "help", "h", "-h", "--help", "-help", "/?")]
    [string]$Action = "help",

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

# Helper: Notify Windows of Font Change (non-blocking)
function Send-FontNotification {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WinFontNotifier {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SendNotifyMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);
}
"@ -ErrorAction SilentlyContinue
    try {
        [WinFontNotifier]::SendNotifyMessage(0xffff, 0x001D, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
    } catch {}
}

switch ($Action) {
    { $_ -in "version", "v", "-v", "--version" } {
        Write-Host "fman v$VERSION - PowerShell Font Manager for Windows" -ForegroundColor Cyan
        return
    }

    { $_ -in "help", "h", "-h", "--help", "-help", "/?" } {
        Write-Host @"
fman v$VERSION - Lightning-fast PowerShell Font Manager for Windows

USAGE:
    fman install <repo | url | path>    Install font from GitHub repo, URL, or local file
    fman remove <font_name>             Uninstall a font and remove registry entries
    fman list                           List all installed font families
    fman list -full                     List all individual .ttf / .otf variant files
    fman add <font_name>                Track a font name in local manifest
    fman help                           Show this help message

EXAMPLES:
    fman install the-moonwitch/Cozette
    fman install kika/fixedsys
    fman install IdreesInc/Monocraft
    fman install "https://github.com/.../release.zip"
    fman install "C:\Downloads\CustomFont.ttf"
    fman remove fixedsys
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

        # Group files into clean font families
        $families = @{}
        foreach ($f in $installed) {
            $clean = $f.BaseName -replace '(-Bold|-Regular|-Italic|-BoldItalic|-ExtraBold|-SemiBold|-Light|-Medium|-Thin|-Heavy|-Black|-ExtraLight|-ExtraBlack|-Oblique|-Normal|BoldItalic|BoldUpright|RegularItalic|RegularUpright|_bold|_italic|_regular)+$', ''
            $clean = $clean -replace '[-_]+$', ''
            if ($clean -match '^(FSEX\d+|Fixedsys)') { $clean = "Fixedsys" }
            elseif ($clean -match '^Cozette') { $clean = "Cozette" }
            elseif ($clean -match '^GohuFont') { $clean = "GohuFont" }
            elseif ($clean -match '^Monocraft') { $clean = "Monocraft" }
            elseif ($clean -match '^Iosevka') { $clean = "Iosevka" }
            elseif ($clean -match '^Agave') { $clean = "Agave" }
            elseif ($clean -match '^JetBrainsMono') { $clean = "JetBrainsMono" }
            elseif ($clean -match '^(Intone|IntelOne)') { $clean = "IntelOneMono" }
            elseif ($clean -match '^(Hurmit|Hermit)') { $clean = "Hermit" }
            elseif ($clean -match '^Fantasque') { $clean = "FantasqueSansMono" }
            elseif ($clean -match '^DaddyTime') { $clean = "DaddyTimeMono" }
            elseif ($clean -match '^Victor') { $clean = "VictorMono" }
            elseif ($clean -match '^(psudo|Pseudo)') { $clean = "PsudoFontLigaMono" }
            elseif ($clean -match '^aporetic-sans') { $clean = "AporeticSansMono" }
            elseif ($clean -match '^aporetic-serif') { $clean = "AporeticSerifMono" }

            if (-not $families.ContainsKey($clean)) {
                $families[$clean] = [System.Collections.Generic.List[string]]::new()
            }
            $families[$clean].Add($f.Name)
        }

        $FontCategoryMap = @{
            # Retro / Pixel
            "DepartureMono"      = "Retro / Pixel"
            "PixelCode"          = "Retro / Pixel"
            "Monocraft"          = "Retro / Pixel"
            "Cozette"            = "Retro / Pixel"
            "Fixedsys"           = "Retro / Pixel"
            "GohuFont"           = "Retro / Pixel"
            "Terminus"           = "Retro / Pixel"
            "Spleen"             = "Retro / Pixel"
            "Scientifica"        = "Retro / Pixel"

            # Coding / Terminal
            "Iosevka"            = "Coding / Terminal"
            "Agave"              = "Coding / Terminal"
            "IntelOneMono"       = "Coding / Terminal"
            "Hermit"             = "Coding / Terminal"
            "FantasqueSansMono"  = "Coding / Terminal"
            "DaddyTimeMono"      = "Coding / Terminal"
            "VictorMono"         = "Coding / Terminal"
            "ComicMono"          = "Coding / Terminal"
            "PsudoFontLigaMono"  = "Coding / Terminal"
            "AporeticSansMono"   = "Coding / Terminal"
            "AporeticSerifMono"  = "Coding / Terminal"
            "JetBrainsMono"      = "Coding / Terminal"
            "FiraCode"           = "Coding / Terminal"
            "CascadiaCode"       = "Coding / Terminal"
            "Hack"               = "Coding / Terminal"

            # System / UI
            "Inter"              = "System / UI"
            "SegoeUI"            = "System / UI"
            "SFPro"              = "System / UI"
            "Roboto"             = "System / UI"
            "Aptos"              = "System / UI"
            "Cantarell"          = "System / UI"
        }

        $buckets = [ordered]@{
            "Coding / Terminal"    = [System.Collections.Generic.SortedDictionary[string, System.Collections.Generic.List[string]]]::new([System.StringComparer]::OrdinalIgnoreCase)
            "Retro / Pixel"        = [System.Collections.Generic.SortedDictionary[string, System.Collections.Generic.List[string]]]::new([System.StringComparer]::OrdinalIgnoreCase)
            "System / UI"          = [System.Collections.Generic.SortedDictionary[string, System.Collections.Generic.List[string]]]::new([System.StringComparer]::OrdinalIgnoreCase)
            "Display / Decorative" = [System.Collections.Generic.SortedDictionary[string, System.Collections.Generic.List[string]]]::new([System.StringComparer]::OrdinalIgnoreCase)
        }

        foreach ($k in $families.Keys) {
            $targetBucket = $null
            if ($FontCategoryMap.ContainsKey($k)) {
                $targetBucket = $FontCategoryMap[$k]
            } else {
                $lower = $k.ToLower()
                if ($lower -match "(pixel|bitmap|craft|cozette|gohu|fixedsys|terminus|spleen|scientifica|creep|tamzen|unscii|dina)") {
                    $targetBucket = "Retro / Pixel"
                } elseif ($lower -match "(mono|code|nerd|terminal|console|type|iosevka|cascadia|fira|jetbrains|hack)") {
                    $targetBucket = "Coding / Terminal"
                } elseif ($lower -match "(ui|system|sans|serif|text|pro|aptos|segoe)") {
                    $targetBucket = "System / UI"
                } else {
                    $targetBucket = "Display / Decorative"
                }
            }

            if (-not $buckets.Contains($targetBucket)) {
                $buckets[$targetBucket] = [System.Collections.Generic.SortedDictionary[string, System.Collections.Generic.List[string]]]::new([System.StringComparer]::OrdinalIgnoreCase)
            }
            $buckets[$targetBucket][$k] = $families[$k]
        }

        Write-Host "`n=== INSTALLED USER FONTS ($($families.Count) Families, $($installed.Count) Files) ===" -ForegroundColor Cyan

        foreach ($bName in $buckets.Keys) {
            if ($buckets[$bName].Count -gt 0) {
                Write-Host "`n[ $bName ]" -ForegroundColor Yellow
                foreach ($fam in $buckets[$bName].Keys) {
                    Write-Host "  - $fam ($($buckets[$bName][$fam].Count) variants)" -ForegroundColor White
                    if ($isFull) {
                        foreach ($file in $buckets[$bName][$fam]) {
                            Write-Host "       -> $file" -ForegroundColor DarkGray
                        }
                    }
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

            # 1. GitHub repo shorthand (e.g. 'the-moonwitch/Cozette', 'kika/fixedsys', 'epk/SF-Mono-Nerd-Font')
            if ($target -match '^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$' -and -not (Test-Path $target)) {
                Write-Host "Resolving GitHub font files for $target..." -ForegroundColor Cyan
                $headers = @{ "User-Agent" = "Mozilla/5.0" }
                if ($env:GITHUB_TOKEN) { $headers["Authorization"] = "token $env:GITHUB_TOKEN" }
                $downloadUrls = [System.Collections.Generic.List[string]]::new()
                $isZipList = [System.Collections.Generic.List[bool]]::new()

                # A. Try GitHub Releases first
                try {
                    $api = "https://api.github.com/repos/$target/releases/latest"
                    $res = Invoke-RestMethod -Uri $api -Headers $headers -ErrorAction Stop

                    $zipAssets = @($res.assets | Where-Object { $_.name -match "\.zip$" })
                    if ($zipAssets.Count -gt 0) {
                        $best = ($zipAssets | Where-Object { $_.name -match "(font|vector|bundle|release|all)" } | Select-Object -First 1)
                        if (-not $best) { $best = $zipAssets[0] }
                        $downloadUrls.Add($best.browser_download_url)
                        $isZipList.Add($true)
                        Write-Host "Found release font bundle: $($best.name) (Release $($res.tag_name))" -ForegroundColor Green
                    } else {
                        $fontAssets = @($res.assets | Where-Object { $_.name -match "\.(ttf|otf)$" })
                        if ($fontAssets.Count -gt 0) {
                            foreach ($fa in $fontAssets) {
                                $downloadUrls.Add($fa.browser_download_url)
                                $isZipList.Add($false)
                            }
                            Write-Host "Found $($fontAssets.Count) font file(s) in Release $($res.tag_name)" -ForegroundColor Green
                        }
                    }
                } catch {
                    Write-Host "No release found for $target. Searching repository tree..." -ForegroundColor DarkGray
                }

                # B. Fallback: Search Repository Tree recursively if no release assets found
                if ($downloadUrls.Count -eq 0) {
                    try {
                        $treeApi = "https://api.github.com/repos/$target/git/trees/HEAD?recursive=1"
                        $treeRes = Invoke-RestMethod -Uri $treeApi -Headers $headers -ErrorAction Stop
                        $fontBlobs = @($treeRes.tree | Where-Object { $_.type -eq "blob" -and $_.path -match "\.(ttf|otf)$" })

                        if ($fontBlobs.Count -gt 0) {
                            Write-Host "Found $($fontBlobs.Count) font file(s) across $target repository tree." -ForegroundColor Green
                            foreach ($blob in $fontBlobs) {
                                $rawUrl = "https://raw.githubusercontent.com/$target/HEAD/$($blob.path)"
                                $downloadUrls.Add($rawUrl)
                                $isZipList.Add($false)
                            }
                        }
                    } catch {
                        Write-Warning "Tree search failed for $target : $_"
                    }
                }

                # Download all resolved assets
                if ($downloadUrls.Count -gt 0) {
                    $tempDir = Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString())
                    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

                    Write-Host "  -> Fetching $($downloadUrls.Count) font file(s) in parallel..." -ForegroundColor Cyan
                    $curlArgs = @("-4", "-fL", "-A", "Mozilla/5.0", "--parallel", "--parallel-immediate", "--retry", "2", "--connect-timeout", "5", "--max-time", "30", "-s")
                    for ($i = 0; $i -lt $downloadUrls.Count; $i++) {
                        $dUrl = $downloadUrls[$i]
                        $fName = [System.IO.Path]::GetFileName(($dUrl -split '\?')[0])
                        $dlFile = Join-Path $tempDir $fName
                        $curlArgs += @("-o", $dlFile, $dUrl)
                    }

                    & curl.exe @curlArgs

                    # Extract any downloaded zip archives
                    Get-ChildItem -Path $tempDir -Filter *.zip -ErrorAction SilentlyContinue | ForEach-Object {
                        Expand-Archive -Path $_.FullName -DestinationPath $tempDir -Force
                    }

                    $filesToInstall = Get-ChildItem -Path $tempDir -Include *.ttf, *.otf -Recurse
                    $inferredName = ($target -split '/')[-1]
                } else {
                    Write-Warning "No font files (.ttf/.otf/.zip) found in releases or repository tree for $target."
                }
            }
            # 2. URL Download (Direct Link or Release Asset)
            elseif ($target -match '^https?://') {
                $tempDir = Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString())
                New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
                $fileName = ($target -split '/')[-1]
                $dlPath = Join-Path $tempDir $fileName
                Write-Host "  -> Fetching $fileName..." -ForegroundColor Cyan
                if (Get-Command 'curl.exe' -ErrorAction SilentlyContinue) {
                    curl.exe -4 -fL --retry 2 --connect-timeout 5 --max-time 30 -A "Mozilla/5.0" -s -o $dlPath $target
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
