#Requires -Version 5.1
<#
.SYNOPSIS
    Download Pale Moon Portable, keep a desktop shortcut, and launch it.

.DESCRIPTION
    For an admin PC. Paste the one-liner into ScreenConnect Backstage or a
    local PowerShell window. It does not target a remote session.

    The package is the official 64-bit portable self-extractor. The script
    reads the SHA256 from the Pale Moon download page and checks the file
    before unpacking. Files go under %LOCALAPPDATA%\PaleMoonPortable.
    A later run with a newer published build replaces the program files and
    copies the existing User folder onto the new copy.

    The shortcut is Pale Moon Portable.lnk on the current user's desktop.
    Launch uses Palemoon-Portable.exe so the profile stays inside that folder.
#>
[CmdletBinding()]
param(
    [switch]$NoExit,
    [switch]$Exit,
    [switch]$NoLaunch,
    [string]$Destination,
    [string]$ShortcutFolder
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Complete-PaleMoon {
    param([Parameter(Mandatory = $true)][int]$Code)
    $global:LASTEXITCODE = $Code
    if ($Exit) { exit $Code }
    if ($NoExit) { return }
    if ($PSCommandPath) { exit $Code }
}

function Enable-PaleMoonTls {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
    } catch {
        Write-Verbose $_.Exception.Message
    }
}

function Get-PaleMoonPublished {
    $page = Invoke-WebRequest -Uri 'https://www.palemoon.org/download.shtml' -UseBasicParsing
    $flat = [regex]::Replace($page.Content, '\s+', ' ')
    $match = [regex]::Match($flat, 'Palemoon-Portable-(\d+(?:\.\d+)+)\.win64\.exe\s+([a-fA-F0-9]{64})')
    if (-not $match.Success) {
        throw 'Pale Moon download page did not list a win64 portable build and SHA256.'
    }
    return [pscustomobject]@{
        Version = $match.Groups[1].Value
        Sha256  = $match.Groups[2].Value.ToUpperInvariant()
    }
}

function Get-PaleMoonInstalledVersion {
    param([Parameter(Mandatory = $true)][string]$Root)
    $browser = Join-Path $Root 'Bin\Palemoon\palemoon.exe'
    $launcher = Join-Path $Root 'Palemoon-Portable.exe'
    if (-not (Test-Path -LiteralPath $browser) -or -not (Test-Path -LiteralPath $launcher)) {
        return $null
    }
    return (Get-Item -LiteralPath $browser).VersionInfo.ProductVersion
}

function Test-PaleMoonRunning {
    param([Parameter(Mandatory = $true)][string]$Root)
    $prefix = $Root.TrimEnd('\') + '\'
    $procs = @(Get-CimInstance -ClassName Win32_Process -ErrorAction SilentlyContinue | Where-Object {
            $_.ExecutablePath -and $_.ExecutablePath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
        })
    return ($procs.Count -gt 0)
}

function Save-PaleMoonPackage {
    param(
        [Parameter(Mandatory = $true)][string]$Version,
        [Parameter(Mandatory = $true)][string]$Sha256,
        [Parameter(Mandatory = $true)][string]$OutFile
    )
    $mirrors = @(
        'https://www.palemoon.org/download.php?mirror=us&bits=64&type=portable',
        'https://www.palemoon.org/download.php?mirror=eu&bits=64&type=portable'
    )
    $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
    if (-not (Test-Path -LiteralPath $curl)) {
        throw 'curl.exe was not found in System32.'
    }
    $lastError = $null
    foreach ($mirror in $mirrors) {
        if (Test-Path -LiteralPath $OutFile) {
            Remove-Item -LiteralPath $OutFile -Force
        }
        Write-Output ("Downloading Pale Moon Portable {0}" -f $Version)
        $lines = @(& $curl -fsSL -o $OutFile -w '%{url_effective}' $mirror)
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $OutFile)) {
            $lastError = "Download failed from $mirror (curl $LASTEXITCODE)."
            continue
        }
        $effective = [string]$lines[-1]
        $uri = $null
        try { $uri = [Uri]$effective } catch { $uri = $null }
        $nameOk = $uri -and ($uri.AbsolutePath -match [regex]::Escape("/Palemoon-Portable-$Version.win64.exe"))
        $hostOk = $uri -and ($uri.Host -match '(?i)(^|\.)palemoon\.org$')
        if (-not $nameOk -or -not $hostOk) {
            $lastError = "Mirror did not return Palemoon-Portable-$Version.win64.exe ($effective)."
            continue
        }
        $actual = (Get-FileHash -LiteralPath $OutFile -Algorithm SHA256).Hash
        if ($actual -ne $Sha256) {
            $lastError = "SHA256 mismatch. Expected $Sha256 got $actual."
            continue
        }
        Write-Output ("SHA256 matches the Pale Moon download page ({0})" -f $Sha256)
        return
    }
    throw $lastError
}

function Expand-PaleMoonPackage {
    param(
        [Parameter(Mandatory = $true)][string]$Package,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    New-Item -ItemType Directory -Path $Destination | Out-Null
    # Official portable build is a 7-Zip self-extractor. -o sets the folder, -y skips the prompt.
    $proc = Start-Process -FilePath $Package -ArgumentList @("-o$Destination", '-y') -Wait -PassThru -WindowStyle Hidden
    $launcher = Join-Path $Destination 'Palemoon-Portable.exe'
    if ($proc.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $launcher)) {
        throw ("Pale Moon portable extract failed (exit {0})." -f $proc.ExitCode)
    }
}

function Copy-PaleMoonUserFolder {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$DestRoot
    )
    $source = Join-Path $SourceRoot 'User'
    $dest = Join-Path $DestRoot 'User'
    if (-not (Test-Path -LiteralPath $source)) { return }
    Write-Output 'Copying the existing Pale Moon User folder onto the new build.'
    Copy-Item -Path (Join-Path $source '*') -Destination $dest -Recurse -Force
}

function Set-PaleMoonShortcut {
    param(
        [Parameter(Mandatory = $true)][string]$Launcher,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string]$Folder
    )
    if (-not (Test-Path -LiteralPath $Folder)) {
        New-Item -ItemType Directory -Path $Folder -Force | Out-Null
    }
    $path = Join-Path $Folder 'Pale Moon Portable.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($path)
    $link.TargetPath = $Launcher
    $link.WorkingDirectory = $WorkingDirectory
    $link.Description = 'Pale Moon Portable'
    $link.Save()
    Write-Output ("Shortcut: {0}" -f $path)
}

try {
    Enable-PaleMoonTls
    if (-not $Destination) {
        $Destination = Join-Path $env:LOCALAPPDATA 'PaleMoonPortable'
    }
    if (-not $ShortcutFolder) {
        $ShortcutFolder = [Environment]::GetFolderPath('Desktop')
    }
    $published = Get-PaleMoonPublished
    $installed = Get-PaleMoonInstalledVersion -Root $Destination
    $running = $false
    if (Test-Path -LiteralPath $Destination) {
        $running = Test-PaleMoonRunning -Root $Destination
    }

    if ($installed -eq $published.Version) {
        Write-Output ("Pale Moon Portable {0} is already in {1}" -f $installed, $Destination)
    } elseif ($running) {
        Write-Output ("Pale Moon is running from {0}. Close it, then run this again to install {1}." -f $Destination, $published.Version)
    } else {
        $sfx = Join-Path $env:TEMP ("Palemoon-Portable-{0}.win64.exe" -f $published.Version)
        $stage = Join-Path $env:TEMP ("PaleMoonPortable-{0}" -f [guid]::NewGuid().ToString('n'))
        try {
            Save-PaleMoonPackage -Version $published.Version -Sha256 $published.Sha256 -OutFile $sfx
            Expand-PaleMoonPackage -Package $sfx -Destination $stage
            if ($installed) {
                Copy-PaleMoonUserFolder -SourceRoot $Destination -DestRoot $stage
            }
            if (Test-Path -LiteralPath $Destination) {
                $backup = "$Destination.bak"
                if (Test-Path -LiteralPath $backup) {
                    Remove-Item -LiteralPath $backup -Recurse -Force
                }
                Move-Item -LiteralPath $Destination -Destination $backup
                try {
                    Move-Item -LiteralPath $stage -Destination $Destination
                    $stage = $null
                } catch {
                    if ((Test-Path -LiteralPath $backup) -and -not (Test-Path -LiteralPath $Destination)) {
                        Move-Item -LiteralPath $backup -Destination $Destination
                    }
                    throw
                }
                Remove-Item -LiteralPath $backup -Recurse -Force
            } else {
                $parent = Split-Path -Parent $Destination
                if (-not (Test-Path -LiteralPath $parent)) {
                    New-Item -ItemType Directory -Path $parent | Out-Null
                }
                Move-Item -LiteralPath $stage -Destination $Destination
                $stage = $null
            }
            Write-Output ("Installed Pale Moon Portable {0} in {1}" -f $published.Version, $Destination)
        } finally {
            if ($stage -and (Test-Path -LiteralPath $stage)) {
                Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path -LiteralPath $sfx) {
                Remove-Item -LiteralPath $sfx -Force -ErrorAction SilentlyContinue
            }
        }
    }

    $launcher = Join-Path $Destination 'Palemoon-Portable.exe'
    if (-not (Test-Path -LiteralPath $launcher)) {
        throw "Palemoon-Portable.exe was not found in $Destination"
    }
    Set-PaleMoonShortcut -Launcher $launcher -WorkingDirectory $Destination -Folder $ShortcutFolder

    if ($NoLaunch) {
        Write-Output 'Launch skipped.'
    } elseif (Test-PaleMoonRunning -Root $Destination) {
        Write-Output 'Pale Moon is already running.'
    } else {
        Start-Process -FilePath $launcher -WorkingDirectory $Destination | Out-Null
        Write-Output 'Started Palemoon-Portable.exe'
    }
    Complete-PaleMoon -Code 0
} catch {
    Write-Output ("Pale Moon portable setup failed: {0}" -f $_.Exception.Message)
    Complete-PaleMoon -Code 1
}
