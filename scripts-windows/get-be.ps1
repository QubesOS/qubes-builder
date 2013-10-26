# Qubes builder - preparing Windows build environment for Qubes
#
# If launched outside of existing qubes-builder, clones it to current directory.
# Existing qubes-builder location may be specified via `-builder <path>' option.
# Build environment is contained in 'msys' directory created in qubes-builder/windows-prereqs. It also contains mingw64.
# This is intended as a base/clean environment. Component-specific scripts may copy it and modify according to their requirements.

Param(
    $builder,            # [optional] If specified, path to existing qubes-builder.
    [switch] $verify,    # [optional] Verify qubes-builder tags.
    $GIT_SUBDIR = "omeg" # [optional] Same as in builder.conf
)

Function IsAdministrator()
{
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

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
        $client.Dispose()
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
        $shell.Namespace($destination).CopyHere($item, 4+16) # flags: 4=no ui, 16=yes to all
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

$sha1 = [System.Security.Cryptography.SHA1]::Create()
Function GetHash($filePath)
{
    $fs = New-Object System.IO.FileStream $filePath, "Open"
    $hash = [BitConverter]::ToString($sha1.ComputeHash($fs)).Replace("-", "")
    $fs.Close()
    return $hash.ToLowerInvariant()
}

Function VerifyFile($filePath, $hash)
{
    $fileHash = GetHash $filePath
    if ($fileHash -ne $hash)
    {
        Write-Host "[!] Failed to verify SHA-1 checksum of $filePath!"
        Write-Host "[!] Expected: $hash, actual: $fileHash"
        Exit 1
    }
    else
    {
        Write-Host "[=] File successfully verified."
    }
}

Function CreateShortcuts($linkName, $targetPath)
{
    $desktop = [Environment]::GetFolderPath("Desktop")
    $startMenu = [Environment]::GetFolderPath("StartMenu")
    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $wsh.CreateShortcut("$desktop\$linkName")
    $shortcut.TargetPath = $targetPath
    $shortcut.Save()
    $shortcut = $wsh.CreateShortcut("$startMenu\Programs\$linkName")
    $shortcut.TargetPath = $targetPath
    $shortcut.Save()
}

### start

# relaunch elevated if not running as administrator
if (! (IsAdministrator))
{
    [string[]]$argList = @("-ExecutionPolicy", "bypass", "-NoProfile", "-NoExit", "-File", $MyInvocation.MyCommand.Path)
    if ($builder) { $argList += "-builder $builder" }
    if ($verify) { $argList += "-verify" }
    if ($GIT_SUBDIR) { $argList += "-GIT_SUBDIR $GIT_SUBDIR" }
    Start-Process PowerShell.exe -Verb RunAs -WorkingDirectory $pwd -ArgumentList $argList
    return
}

$scriptDir = Split-Path -parent $MyInvocation.MyCommand.Definition
Set-Location $scriptDir

# log everything from this script
$Host.UI.RawUI.BufferSize.Width = 500

if ($builder)
{
    # use pased value for already existing qubes-builder directory
    $builderDir = $builder

    $logFilePath = Join-Path (Join-Path $builderDir "build-logs") "win-initialize-be.log"
    Start-Transcript -Path $logFilePath

    Write-Host "[*] Using '$builderDir' as qubes-builder directory."
}
else # check if we're invoked from existing qubes-builder
{
    $curDir = Split-Path $scriptDir -Leaf
    $makefilePath = Join-Path (Join-Path $scriptDir "..") "Makefile.windows" -Resolve -ErrorAction SilentlyContinue
    if (($curDir -eq "scripts-windows") -and (Test-Path -Path $makefilePath))
    {
        $builder = $true # don't clone builder later
        $builderDir = Join-Path $scriptDir ".." -Resolve

        $logFilePath = Join-Path (Join-Path $builderDir "build-logs") "win-initialize-be.log"
        Start-Transcript -Path $logFilePath

        Write-Host "[*] Running from existing qubes-builder ($builderDir)."
    }
    else
    {
        Start-Transcript -Path "win-initialize-be.log"
        Write-Host "[*] Running from clean state, need to clone qubes-builder."
    }
}

if ($builder -and (Test-Path (Join-Path $builderDir "windows-prereqs\msys")))
{
    Write-Host "[=] BE seems already initialized, delete windows-prereqs\msys if you want to rerun this script."
    Exit 0
}

$tmpDir = Join-Path $scriptDir "tmp"
# delete previous tmp is exists
Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue | Out-Null
New-Item $tmpDir -ItemType Directory | Out-Null
Write-Host "[*] Tmp dir: $tmpDir"

# verification hashes are embedded here to keep the script self-contained
$pkgName = "7zip"
$url = "http://downloads.sourceforge.net/sevenzip/7za920.zip"
$file = DownloadFile $url
VerifyFile $file "9ce9ce89ebc070fea5d679936f21f9dde25faae0"
UnpackZip $file $tmpDir
$7zip = Join-Path $tmpDir "7za.exe"

$pkgName = "msys"
$url = "http://downloads.sourceforge.net/project/mingwbuilds/external-binary-packages/msys%2B7za%2Bwget%2Bsvn%2Bgit%2Bmercurial%2Bcvs-rev13.7z"
$file = DownloadFile $url
VerifyFile $file "ed6f1ec0131530122d00eed096fbae7eb76f8ec9"
Unpack7z $file $tmpDir
$msysDir = (Join-Path $tmpDir "msys")

$pkgName = "mingw64"
$url = "http://sourceforge.net/projects/mingwbuilds/files/host-windows/releases/4.8.1/64-bit/threads-win32/seh/x64-4.8.1-release-win32-seh-rev5.7z"
$file = DownloadFile $url
VerifyFile $file "53886dd1646aded889e6b9b507cf5877259342f2"
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

$prereqsDir = Join-Path $builderDir "windows-prereqs"
Write-Host "[*] Moving msys to $prereqsDir..."
New-Item -ItemType Directory $prereqsDir -ErrorAction SilentlyContinue | Out-Null
# move msys/mingw to qubes-builder/windows-prereqs, this will be the default "clean" environment
Move-Item $msysDir $prereqsDir
Move-Item $7zip $prereqsDir -Force
$msysDir = Join-Path $prereqsDir "msys" # update

if ($verify)
{
	# install gpg if needed
	$gpgRegistryPath = "HKLM:SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\GPG4Win"
	$gpgInstalled = Test-Path $gpgRegistryPath
	if ($gpgInstalled)
	{
		$gpgDir = (Get-ItemProperty $gpgRegistryPath).InstallLocation
		# additional sanity check
		if (!(Test-Path "$gpgDir\pub\gpg.exe"))
		{
			$gpgInstalled = $false
		}
	}

	if ($gpgInstalled)
	{
		Write-Host "[*] GnuPG is already installed."
	}
	else
	{
		$pkgName = "GnuPG"
		$url = "http://files.gpg4win.org/gpg4win-2.2.1.exe"
		$file = DownloadFile $url
		VerifyFile $file "6fe64e06950561f2183caace409f42be0a45abdf"

		Write-Host "[*] Installing GnuPG..."
		$gpgDir = Join-Path $prereqsDir "gpg"
		Start-Process -FilePath $file -Wait -PassThru -ArgumentList @("/S", "/D=$gpgDir") | Out-Null
	}
	$gpg = Join-Path $gpgDir "pub\gpg.exe"

	Set-Location $builderDir

	Write-Host "[*] Importing Qubes OS signing keys..."
	# import master qubes signing key
	& $gpg --keyserver hkp://keys.gnupg.net --recv-keys 0x36879494

	# import other dev keys
	$pkgName = "qubes dev keys"
	$url = "http://keys.qubes-os.org/keys/qubes-developers-keys.asc"
	$file = DownloadFile $url
	VerifyFile $file "bfaa2864605218a2737f0dc39d4dfe08720d436a"

	& $gpg --import $file

	# add gpg and msys to PATH
	$env:Path = "$env:Path;$msysDir\bin;$gpgDir\pub"

	# verify qubes-builder tags
	$tag = & git tag --points-at=HEAD | head -n 1
	$ret = & git tag -v $tag
	if ($?)
	{
		Write-Host "[*] qubes-builder successfully verified."
	}
	else
	{
		Write-Host "[!] Failed to verify qubes-builder! Output:`n$ret"
		Exit 1
	}
}
# set msys to start in qubes-builder directory
$builderUnix = PathToUnix $builderDir
$cmd = "cd $builderUnix"
Add-Content (Join-Path $msysDir "etc\profile") "`n$cmd"
# mingw/bin is in default msys' PATH

# add msys shortcuts to desktop/start menu
Write-Host "[*] Adding shortcuts to msys..."
CreateShortcuts "qubes-msys.lnk" "$msysDir\msys.bat"

# cleanup
Write-Host "[*] Cleanup"
Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue | Out-Null

Write-Host "[=] Done"
# start msys shell
Start-Process -FilePath (Join-Path $msysDir "msys.bat")

Stop-Transcript
