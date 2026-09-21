<#
.SYNOPSIS
    Apply an MST transform to an MSI installer, producing a standalone patched MSI.

.DESCRIPTION
    Bakes the FULL MST transform into an MSI (Property, Registry, CustomAction, etc.)
    so it can be deployed without the /TRANSFORMS flag. Uses Windows Installer COM API.

.PARAMETER Msi
    Path to the source MSI file.

.PARAMETER Mst
    Path to the MST transform file.

.PARAMETER Output
    Output MSI path. Defaults to <source>_transformed.msi in the same folder.

.PARAMETER DryRun
    Show what would change without writing any files.

.PARAMETER Verbose
    Print all property values being applied.

.EXAMPLE
    .\msi_transform.ps1 Agent_Install.msi Agent_Install.mst
    .\msi_transform.ps1 Agent_Install.msi Agent_Install.mst -Output CustomAgent.msi
    .\msi_transform.ps1 Agent_Install.msi Agent_Install.mst -DryRun
    .\msi_transform.ps1 Agent_Install.msi Agent_Install.mst -Verbose
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory, Position=0)]
    [string]$Msi,

    [Parameter(Mandatory, Position=1)]
    [string]$Mst,

    [Parameter(Position=2)]
    [string]$Output,

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------

$MsiPath = (Resolve-Path $Msi).Path
$MstPath = (Resolve-Path $Mst).Path

if (-not $Output) {
    $stem   = [System.IO.Path]::GetFileNameWithoutExtension($MsiPath)
    $dir    = [System.IO.Path]::GetDirectoryName($MsiPath)
    $Output = Join-Path $dir ($stem + "_transformed.msi")
}
$OutputPath = $Output

$msiSize = "{0:N1} MB" -f ((Get-Item $MsiPath).Length / 1MB)
$mstSize = "{0:N0} KB" -f ((Get-Item $MstPath).Length / 1KB)

Write-Host "  MSI:    $([System.IO.Path]::GetFileName($MsiPath))  ($msiSize)"
Write-Host "  MST:    $([System.IO.Path]::GetFileName($MstPath))  ($mstSize)"
if (-not $DryRun) {
    Write-Host "  Output: $OutputPath"
}
Write-Host ""

$msiOpenDatabaseModeReadOnly = 0
$msiOpenDatabaseModeTransact = 1

# ---------------------------------------------------------------------------
# Step 1: Read original properties (for dry-run diff display)
# ---------------------------------------------------------------------------

Write-Host "[1/4] Reading MSI property table..."

$installer = New-Object -ComObject WindowsInstaller.Installer
$msiDb = $installer.OpenDatabase($MsiPath, $msiOpenDatabaseModeReadOnly)
$view = $msiDb.OpenView("SELECT Property, Value FROM Property")
$view.Execute()

$currentProps = @{}
while ($true) {
    $record = $view.Fetch()
    if ($null -eq $record) { break }
    $currentProps[$record.StringData(1)] = $record.StringData(2)
}
$view.Close()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($msiDb) | Out-Null

Write-Host "       $($currentProps.Count) properties in source MSI"

# ---------------------------------------------------------------------------
# Step 2: Apply transform (to temp for dry-run, to output for real run)
# ---------------------------------------------------------------------------

Write-Host "[2/4] Applying MST transform..."

$workMsi = if ($DryRun) {
    $t = [System.IO.Path]::GetTempFileName() + ".msi"
    Copy-Item $MsiPath $t -Force
    $t
} else {
    Copy-Item $MsiPath $OutputPath -Force
    $OutputPath
}

try {
    $workDb = $installer.OpenDatabase($workMsi, $msiOpenDatabaseModeTransact)
    $workDb.ApplyTransform($MstPath, 0)

    $tview = $workDb.OpenView("SELECT Property, Value FROM Property")
    $tview.Execute()

    $patchedProps = @{}
    while ($true) {
        $rec = $tview.Fetch()
        if ($null -eq $rec) { break }
        $patchedProps[$rec.StringData(1)] = $rec.StringData(2)
    }
    $tview.Close()

    # Diff for display
    $mstChanges = @{}
    foreach ($key in $patchedProps.Keys) {
        $newVal = $patchedProps[$key]
        $oldVal = $currentProps[$key]
        if ($newVal -ne $oldVal) { $mstChanges[$key] = $newVal }
    }
    foreach ($key in $patchedProps.Keys) {
        if (-not $currentProps.ContainsKey($key)) {
            $mstChanges[$key] = $patchedProps[$key]
        }
    }

    if ($mstChanges.Count -eq 0) {
        Write-Host "       No property changes in MST (other tables may still change)"
    } else {
        $keyList = ($mstChanges.Keys | Sort-Object) -join ", "
        Write-Host "       $($mstChanges.Count) property changes: $keyList"
    }

    # ---------------------------------------------------------------------------
    # Dry run: show diff, discard temp, exit
    # ---------------------------------------------------------------------------

    if ($DryRun) {
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($workDb) | Out-Null  # Don't commit
        Write-Host ""
        if ($mstChanges.Count -gt 0) {
            Write-Host "Property changes that would be applied:"
            foreach ($k in ($mstChanges.Keys | Sort-Object)) {
                $newVal = $mstChanges[$k]
                $oldVal = if ($currentProps.ContainsKey($k)) { $currentProps[$k] } else { "<not present>" }
                $action = if ($currentProps.ContainsKey($k)) { "UPDATE" } else { "ADD" }
                $oldD = if ($oldVal.Length -gt 58) { $oldVal.Substring(0,55) + "..." } else { $oldVal }
                $newD = if ($newVal.Length -gt 58) { $newVal.Substring(0,55) + "..." } else { $newVal }
                Write-Host "  [$action] $k"
                Write-Host "          was: $oldD"
                Write-Host "          now: $newD"
            }
        }
        Write-Host ""
        Write-Host "[DRY RUN] Full MST (Property + Registry + CustomAction + etc.) would be applied."
        Write-Host "          No files written. Remove -DryRun to apply."
        Remove-Item $workMsi -Force -ErrorAction SilentlyContinue
        exit 0
    }

    # ---------------------------------------------------------------------------
    # Step 3 & 4: Commit the full transform
    # ---------------------------------------------------------------------------

    Write-Host "[3/4] Committing full transform (Property, Registry, CustomAction, etc.)..."
    $workDb.Commit()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($workDb) | Out-Null
}
catch {
    if ($DryRun -and $workMsi -and (Test-Path $workMsi)) {
        Remove-Item $workMsi -Force -ErrorAction SilentlyContinue
    }
    throw
}

Write-Host "[4/4] Done."
$outSize = "{0:N1} MB" -f ((Get-Item $OutputPath).Length / 1MB)
$outName = [System.IO.Path]::GetFileName($OutputPath)
Write-Host ""
Write-Host "[OK]  $outName  ($outSize)"
Write-Host "      Deploy: msiexec /i `"$outName`" /qn"
