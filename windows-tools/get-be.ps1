# Qubes builder - preparing Windows build environment for Qubes
#
# Bootstrap: downloads 7zip, msys, mingw64; prepares msys/mingw environment; fetches qubes-builder off the repository; starts msys shell.
# Build environment is contained in 'msys' directory created in current directory.
# qubes-builder is created directly inside msys directory.
# This is intended as a base/clean environment. Component-specific scripts may copy it and modify according to their requirements.

Param(
    $builder,            # [optional] If specified, path to existing qubes-builder.
    $GIT_SUBDIR = "omeg" # [optional] Same as in builder.conf
)

Function DownloadFile($url, $fileName)
{
    $uri = [System.Uri] $url
    if ($fileName -eq $null)  { $fileName = $uri.Segments[$uri.Segments.Count-1] } # get file name from URL 
    $fullPath = Join-Path $tmpDir $fileName
    Write-Host "[*] Downloading $pkgName from $url..."
    
    try
    {
	    $client = New-Object System.Net.WebClient
	    $client.DownloadFile($url, $fullPath)
    }
    catch [Exception]
    {
        Write-Host "[!] Failed to download ${url}:" $_.Exception.Message
        Exit 1
    }
    
    Write-Host "[=] Downloaded: $fullPath"
    return $fullPath
}

Function UnpackZip($filePath, $destination)
{
    Write-Host "[*] Unpacking $filePath..."
    $shell = New-Object -com Shell.Application
    $zip = $shell.Namespace($filePath)
    foreach($item in $zip.Items())
    {
        $shell.Namespace($destination).CopyHere($item)
    }
}

Function Unpack7z($filePath, $destinationDir)
{
    Write-Host "[*] Unpacking $filePath..."
    $arg = "x", "-y", "-o$destinationDir", $filePath
    & $7zip $arg | Out-Null
}

Function PathToUnix($path)
{
    # converts windows path to msys/mingw path
    $path = $path.Replace('\', '/')
    $path = $path -replace '^([a-zA-Z]):', '/$1'
    return $path
}

### start

$scriptDir = Split-Path -parent $MyInvocation.MyCommand.Definition
Set-Location $scriptDir

# log everything from this script
$Host.UI.RawUI.BufferSize.Width = 500
Start-Transcript -Path win-prepare-be.log


if ($builder)
{
    # use pased value for already existing qubes-builder directory
    $builderDir = $builder
    Write-Host "[*] Using '$builderDir' as qubes-builder directory."
}
else # check if we're invoked from existing qubes-builder
{
    $curDir = Split-Path $scriptDir -Leaf
    $upDir = Split-Path (Join-Path $scriptDir ".." -Resolve) -Leaf
    if (($curDir -eq "windows-tools") -and ($upDir -eq "qubes-builder"))
    {
        Write-Host "[*] Running from existing qubes-builder."
        $builder = $true # don't clone builder later
        $builderDir = Join-Path $scriptDir ".." -Resolve
    }
    else
    {
        Write-Host "[*] Running from clean state, need to clone qubes-builder."
    }
}

if ($builder -and (Test-Path (Join-Path $builderDir "windows-prereqs\msys")))
{
    Write-Host "[=] BE seems already prepared, delete windows-prereqs if you want to rerun this script."
    Exit 0
}

$tmpDir = Join-Path $scriptDir "tmp"
# delete previous tmp is exists
Remove-Item -Recurse -Force $tmpDir -ErrorAction Ignore | Out-Null
New-Item $tmpDir -ItemType Directory | Out-Null
Write-Host "[*] Tmp dir: $tmpDir"

$pkgName = "7zip"
$url = "http://downloads.sourceforge.net/sevenzip/7za920.zip"
$file = DownloadFile $url
UnpackZip $file $tmpDir
$7zip = Join-Path $tmpDir "7za.exe"

$pkgName = "msys"
$url = "http://downloads.sourceforge.net/project/mingwbuilds/external-binary-packages/msys%2B7za%2Bwget%2Bsvn%2Bgit%2Bmercurial%2Bcvs-rev13.7z"
$file = DownloadFile $url
Unpack7z $file $tmpDir
$msysDir = (Join-Path $tmpDir "msys")

$pkgName = "mingw64"
$url = "http://sourceforge.net/projects/mingwbuilds/files/host-windows/releases/4.8.1/64-bit/threads-win32/seh/x64-4.8.1-release-win32-seh-rev5.7z"
$file = DownloadFile $url
$mingwArchive = $file
Unpack7z $file $msysDir

Move-Item (Join-Path $msysDir "mingw64") (Join-Path $msysDir "mingw")

if (! $builder)
{
    # fetch qubes-builder off the repo
    $repo = "git://git.qubes-os.org/$GIT_SUBDIR/qubes-builder.git"
    $builderDir = Join-Path $scriptDir "qubes-builder"
    Write-Host "[*] Cloning qubes-builder to $builderDir"
    & (Join-Path $msysDir "bin\git.exe") "clone", $repo, $builderDir | Out-Host
}

$prereqsDir = (Join-Path $builderDir "windows-prereqs")
Write-Host "[*] Moving msys to $prereqsDir..."
New-Item -ItemType Directory $prereqsDir -ErrorAction Ignore | Out-Null
# move msys/mingw to qubes-builder/windows-prereqs, this will be the default "clean" environment
Move-Item $msysDir $prereqsDir
Move-Item $7zip $prereqsDir
$msysDir = (Join-Path $prereqsDir "msys") # update

# set msys to start in qubes-builder directory
$builderUnix = PathToUnix $builderDir
$cmd = "cd $builderUnix"
Add-Content (Join-Path $msysDir "etc\profile") "`n$cmd"
# mingw/bin is in default msys' PATH

# cleanup
Write-Host "[*] Cleanup"
Remove-Item $tmpDir -Recurse -Force | Out-Null

Write-Host "[=] Done"
# start msys shell as administrator
Start-Process -FilePath (Join-Path $msysDir "msys.bat")
