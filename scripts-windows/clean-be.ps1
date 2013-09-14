# This script uninstalls all MSIs that were installed by prepare-be.
# It should be called from 'clean' target during make process, before deleting chroot.

$scriptDir = Split-Path -parent $MyInvocation.MyCommand.Definition
$builderDir = Join-Path $scriptDir ".." -Resolve
$logDir = "$builderDir\build-logs"
$installedMsisFile = "$builderDir\scripts-windows\installed-msis" # guids/names of installed MSIs

Function UninstallMsi($guid, $name)
{
    Write-Host "[*] Uninstalling $name ($guid)..."
    $log = "$logDir\uninstall-$name-$guid.log"
    $arg = @(
        "/qn",
        "/log `"$log`"",
        "/x `"$guid`""
        )

    $ret = (Start-Process -FilePath "msiexec" -ArgumentList $arg -Wait -PassThru).ExitCode
    if ($ret -ne 0)
    {
        Write-Host "[!] Uninstall failed! Check the log at $log"
    }
    else
    {
        Write-Host "[=] $name ($guid) successfully uninstalled."
    }
}

### start

Write-Host "[*] Cleanup: uninstalling dependencies..."

if (Test-Path $installedMsisFile)
{
    $file = Get-Content $installedMsisFile
    foreach ($line in $file)
    {
        if ($line.Trim().StartsWith("#")) { continue }
        $line = $line.Trim()
        if ([string]::IsNullOrEmpty($line)) { continue }
        $tokens = $line.Split(' ')
        $guid = $tokens[0].Trim()
        $name = $tokens[1].Trim()
        UninstallMsi $guid $name
    }

    Move-Item $installedMsisFile "$installedMsisFile.old" -Force
}
else
{
    Write-Host "[*] Nothing to clean."
}

Write-Host "[=] Done uninstalling."
