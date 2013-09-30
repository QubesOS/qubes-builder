# Qubes builder - preparing Windows build environment

# This script is called from Makefile.windows dist-prepare-chroot target.
# Administrator rights shouldn't be required as long as installed MSIs support that (python msi does).

# TODO: Most of this is only needed for libvirt. This script should be modularized and be component-specific.

$chrootDir = $env:CHROOT_DIR
$component = $env:COMPONENT
Write-Host "`n[*] >>> Preparing windows build environment for $component..."

# check if it's already done
$markerPath = "$chrootDir\.be-prepared"
if (Test-Path $markerPath)
{
    Write-Host "[*] BE already prepared"
    Exit 0
}

$verbose = $env:VERBOSE -ne 0

$builderDir = Join-Path $chrootDir ".." -Resolve # normalize path
$depsDir = [System.IO.Path]::GetFullPath("$chrootDir\build-deps")

$scriptDir = "$builderDir\scripts-windows"
$prereqsDir = "$builderDir\windows-prereqs"  # place for downloaded installers/packages, they'll get copied/installed to proper chroots during the build process
$logDir = "$builderDir\build-logs"
$msiToolsDir = "$scriptDir\msi-tools"
$installedMsisFile = "$scriptDir\installed-msis" # guids/names of installed MSIs so we can easily uninstall them later (clean-be.ps1)

$global:pkgConf = @{}

# log everything from this script
$Host.UI.RawUI.BufferSize.Width = 500
Start-Transcript -Path "$logDir\win-prepare-be.log"
<#
# check if we have administrative rights
$wid = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$prp = New-Object System.Security.Principal.WindowsPrincipal($wid)
$adm = [System.Security.Principal.WindowsBuiltInRole]::Administrator
$isAdmin = $prp.IsInRole($adm)
if (!($isAdmin))
{
    Write-Host "[!] We have no administrative rights -- make sure to run msys shell `as administrator'."
    Exit 1
}
#>
# create dirs
if (-not (Test-Path $logDir)) { New-Item $logDir -ItemType Directory | Out-Null }
if (-not (Test-Path $prereqsDir)) { New-Item $prereqsDir -ItemType Directory | Out-Null }
if (-not (Test-Path $depsDir)) { New-Item $depsDir -ItemType Directory | Out-Null }

Write-Host "[*] Downloaded prerequisites dir: $prereqsDir"
Write-Host "[*] Prerequisites dir in chroot: $depsDir"
Write-Host "[*] Log dir: $logDir"

Function FatalExit()
{
    Exit 1
}

Filter OutVerbose()
{
    if ($verbose) { $_ | Out-Host }
}

# downloads to $prereqsDir (installers, zipped packages etc)
Function DownloadFile($url, $fileName)
{
    $uri = [System.Uri] $url
    if ($fileName -eq $null)  { $fileName = $uri.Segments[$uri.Segments.Count-1] } # get file name from URL 
    $fullPath = "$prereqsDir\$fileName"
    Write-Host "[*] Downloading $pkgName..."

    if (Test-Path $fullPath)
    {
        Write-Host "[=] Already downloaded"
        return $fullPath
    }
    
    try
    {
	    $client = New-Object System.Net.WebClient
	    $client.DownloadFile($url, $fullPath)
    }
    catch [Exception]
    {
        Write-Host "[!] Failed to download ${url}:" $_.Exception.Message
        FatalExit
    }
    
    Write-Host "[=] Downloaded: $fullPath"
    return $fullPath
}

Function InstallMsi($msiPath, $targetDirProperty, $targetDir)
{
    Write-Host "[*] Installing $pkgName from $msiPath to $targetDir..."

    # patch the .msi with a temporary product/package GUID so it can be installed even if there is another copy in the system
    $tmpMsiGuid = "{$([guid]::NewGuid().Guid)}"

    # change product name (so it's easier to see in 'add/remove programs' what was installed by us)
    $productName = "qubes-dep " + $pkgName + "/" + $component + " " + (Get-Date)

    & $msiToolsDir\msi-patch.exe "$msiPath" "$tmpMsiGuid" "$productName"

    $log = "$logDir\install-$pkgName-$tmpMsiGuid.log"
    #Write-Host "[*] Install log: $log"

    # install patched msi
    $arg = @(
        "/qn",
        "/log `"$log`"",
        "/i `"$msiPath`"",
        "$targetDirProperty=`"$targetDir`""
        )

    $ret = (Start-Process -FilePath "msiexec" -ArgumentList $arg -Wait -PassThru).ExitCode
    
    if ($ret -ne 0)
    {
        Write-Host "[!] Install failed! Check the log at $log"
        FatalExit
    }
    else # success - store info for later uninstallation on cleanup
    {
        Add-Content $installedMsisFile "$tmpMsiGuid $pkgName"
        Write-Host "[=] Install successful."
    }
}

Function Unpack7z($archivePath, $log, $targetDir)
{
    $arg = "x", "-y", "-o$targetDir", $archivePath
    & $7zip $arg | Out-File $log
}

Function UnpackTgz($archivePath, $log, $targetDir)
{
    $srcDir = [System.IO.Path]::GetDirectoryName($archivePath)
    $arg = "x", "-y", "-o$srcDir", $archivePath # extract .tar to where .tar.gz is
    & $7zip $arg | Out-File $log
    $archivePath = $archivePath.Substring(0, $archivePath.Length-3) # strip .gz
    $arg = "x", "-y", "-o$targetDir", $archivePath # extract the rest
    & $7zip $arg | Out-File $log -Append
}

Function UnpackZip($archivePath, $targetDir)
{
    Write-Host "[*] Extracting $archivePath to $targetDir..."
    $shell = New-Object -com Shell.Application
    $zip = $shell.Namespace($archivePath)
    foreach($item in $zip.Items())
    {
        $shell.Namespace($targetDir).CopyHere($item)
    }
}

Function Unpack($archivePath, $targetDir)
{
    $log = "$logDir\extract-$pkgName.log"
    Write-Host "[*] Extracting $pkgName to $targetDir"

    switch ((Get-Item $archivePath).Extension)
    {
        ".gz" 
        {
            # check if it's .tar.gz
            if (($archivePath.Length -gt 7) -and ($archivePath.Substring($archivePath.Length-7) -eq ".tar.gz"))
            {
                UnpackTgz $archivePath $log $targetDir
            }
            else
            {
                Write-Host "[!] Unknown archive type: $archivePath"
                FatalExit
            }

        }
        default { Unpack7z $archivePath $log $targetDir } # .7z or .zip are fine
    }
}

Function PathToUnix($path)
{
    # converts windows path to msys/mingw path
    $path = $path.Replace('\', '/')
    $path = $path -replace '^([a-zA-Z]):', '/$1'
    return $path
}

Function ReadPackages($confPath)
{
    $conf = Get-Content $confPath
    Write-Host "[*] Reading dependency list from $confPath..."
    foreach ($line in $conf)
    {
        if ($line.Trim().StartsWith("#")) { continue }
        $line = $line.Trim()
        if ([string]::IsNullOrEmpty($line)) { continue }
        $tokens = $line.Split(',')
        $key = $tokens[0].Trim()
        $url = $tokens[1].Trim()
        $fileName = $null
        if ($tokens.Count -eq 3) # there is a file name
        {
            $fileName = $tokens[2].Trim()
        }
        # store entry in the dictionary
        $global:pkgConf[$key] = @($url, $fileName) # second field is local file name, set when downloading
    }
    $count = $global:pkgConf.Count
    Write-Host "[*] $count entries"
}

Function DownloadAll()
{
    Write-Host "[*] Downloading windows dependencies to $depsDir..."
    $keys = $global:pkgConf.Clone().Keys # making a copy because we're changing the collection inside the loop
    foreach ($pkgName in $keys)
    {
        $val = $global:pkgConf[$pkgName] # array
        $url = $val[0]
        $path = $val[1] # may be null
        $path = DownloadFile $url $path
        $val[1] = $path
        $global:pkgConf[$pkgName] = $val # update entry with local file path
    }
}

# compile msi tools
if (!(Test-Path "$msiToolsDir\msi-patch.exe") -or !(Test-Path "$msiToolsDir\msi-interop.dll"))
{
    Write-Host "[*] Compiling msi tools..."
    $netDir = "$env:SystemRoot\Microsoft.NET\Framework\v2.0.50727"

    if (!(Test-Path $netDir))
    {
        Write-Host "[!] .NET Framework v2 not found!"
        Exit 1
    }

    $csc = "$netDir\csc.exe"

    Push-Location
    Set-Location $msiToolsDir
    & $csc /t:exe /out:tlb-convert.exe tlb-convert.cs | Out-Null
    & $msiToolsDir\tlb-convert.exe msi.dll msi-interop.dll WindowsInstaller | Out-Null
    & $csc /t:exe /out:msi-patch.exe /r:msi-interop.dll msi-patch.cs | Out-Null
    Pop-Location
    
    Write-Host "[=] Done."
}

# download all dependencies
ReadPackages "$scriptDir\win-be-deps.conf"
DownloadAll

# delete existing stuff
Write-Host "[*] Clearing $depsDir..."
Remove-Item $depsDir\* -Recurse -Force -Exclude ("include", "libs")

Write-Host "`n[*] Processing dependencies..."

# 7zip should be prepared by get-be script
$7zip = "$prereqsDir\7za.exe"

$pkgName = "msys"
$file = $global:pkgConf[$pkgName][1]
Unpack $file $depsDir
$msysBin = "$depsDir\msys\bin"

$pkgName = "mingw64"
$file = $global:pkgConf[$pkgName][1]
Unpack $file $depsDir
$mingw = "$depsDir\mingw64"
$mingwUnix = PathToUnix $mingw

# some packages look for cc instead of gcc
# need admin for mklink so just copy instead
Copy-Item "$mingw\bin\gcc.exe" "$mingw\bin\cc.exe"

$pkgName = "libiconv"
$file = $global:pkgConf[$pkgName][1]
Unpack $file $depsDir # unpacks to mingw64

# fix path in libiconv.la
$file = "$mingw\lib\libiconv.la"
Get-Content $file | Foreach-Object {$_ -replace "libdir='/mingw64/lib'", "libdir='$mingwUnix/lib'"} | Set-Content "$file.new"
Move-Item -Force "$file.new" $file

$pkgName = "libxml"
$file = $global:pkgConf[$pkgName][1]
Unpack $file $depsDir
# move contents to mingw64 dir
$src = "$depsDir\$pkgName"
Copy-Item -Path "$src\*" -Destination $mingw -Recurse -Force
Remove-Item $src -Recurse
# fix path in libxml2.la
$file = "$mingw\lib\libxml2.la"
Get-Content $file | Foreach-Object {$_ -replace "libdir='/usr/local/lib'", "libdir='$mingwUnix/lib'"} | Foreach-Object {$_ -replace "dependency_libs=' -L/usr/local/lib -lz /usr/local/lib/libiconv.la -lws2_32'", "dependency_libs=' -L$mingwUnix/bin -lzlib1 $mingwUnix/lib/libiconv.la -lws2_32'"} | Set-Content "$file.new"
Move-Item -Force "$file.new" $file
# fix path in libxml-2.0.pc
$file = "$mingw\lib\pkgconfig\libxml-2.0.pc"
Get-Content $file | Foreach-Object {$_ -replace 'prefix=/usr/local', "prefix=$mingwUnix" -replace 'Cflags: -I\${includedir}/libxml2 -I/usr/local/include', "Cflags: -I$mingwUnix/include/libxml2"} | Set-Content "$file.new"
Move-Item -Force "$file.new" $file
# copy from mingw to msys so pkg-config will read it
New-Item -ItemType Directory "$depsDir\msys\lib\pkgconfig" | Out-Null
Copy-Item $file "$depsDir\msys\lib\pkgconfig"

$pkgName = "zlib"
$file = $global:pkgConf[$pkgName][1]
Unpack $file $depsDir
# move contents to mingw64 dir
$src = "$depsDir\$pkgName"
Copy-Item -Path "$src\*" -Destination $mingw -Recurse -Force
Remove-Item $src -Recurse
Copy-Item "$mingw\bin\zlib1.dll" "$mingw\bin\libzlib1.dll"

$pkgName = "python27"
$file = $global:pkgConf[$pkgName][1]
$pythonDir = "$depsDir\python27"
InstallMsi $file "TARGETDIR" "$pythonDir"
$python = "$pythonDir\python.exe"

# add binaries to PATH
$env:Path = "$msysBin;$mingw\bin;$pythonDir;$depsDir\wix;$env:Path"

$pkgName = "portablexdr"
$file = $global:pkgConf[$pkgName][1]
Unpack $file $depsDir

# apply 64bit xdr patch
Copy-Item "$builderDir\windows-build-files\portablexdr-4.9.1-64bit.patch" "$depsDir\portablexdr-4.9.1"
Push-Location
Set-Location "$depsDir\portablexdr-4.9.1"
& patch.exe "-i", "portablexdr-4.9.1-64bit.patch" | OutVerbose
Pop-Location

Write-Host "[*] Building $pkgName..."
Push-Location
Set-Location "$depsDir\portablexdr-4.9.1"
& sh.exe "configure", "-C", "--prefix=$mingwUnix", "--build=x86_64-w64-mingw32" | Tee-Object -File "$logDir\build-configure-$pkgName.log" | OutVerbose
& make.exe | Tee-Object -File "$logDir\build-make-$pkgName.log" | OutVerbose
& make.exe "install" | Tee-Object -File "$logDir\build-install-$pkgName.log" | OutVerbose
Copy-Item config.h "$mingw\include\rpc\"
Pop-Location
Copy-Item "$mingw\bin\portable-rpcgen.exe" "$mingw\bin\rpcgen.exe"

Push-Location
Set-Location $depsDir
# setuptools install downloads archive to current dir, don't leave garbage outside of chroot
$pkgName = "setuptools"
Write-Host "[*] Installing $pkgName..."
$file = $global:pkgConf[$pkgName][1]
& $python $file | OutVerbose
Pop-Location

# prepare python dev files
Write-Host "[*] Preparing python dev files..."
Push-Location
Set-Location $pythonDir
& gendef.exe "python27.dll" | OutVerbose
& dlltool.exe "-d", "python27.def", "-l", "libpython27.dll.a" | OutVerbose
# apply patch
$patchPath = PathToUnix ([System.IO.Path]::GetFullPath("$builderDir\windows-build-files\python-mingw32.patch"))
& patch.exe "-p0", "-i", "$patchPath" | OutVerbose
Pop-Location

# copy python includes to mingw64
New-Item -ItemType Directory "$depsDir\mingw64\include\python2.7" | Out-Null
Copy-Item "$pythonDir\include\*" "$depsDir\mingw64\include\python2.7\" -Recurse

$pkgName = "psutil"
$file = $global:pkgConf[$pkgName][1]
# to install automatically we need a trick
# sources don't build with mingw
# this is an .exe installer that doesn't support silent installation 
# but it's a self-extracting archive so we use 7zip to extract it and copy files ourselves
Unpack $file $depsDir # extracted dir is PLATLIB

# similar thing with pywin32
$pkgName = "pywin32"
$file = $global:pkgConf[$pkgName][1]
Unpack $file $depsDir

Copy-Item -Recurse "$depsDir\PLATLIB\*" "$pythonDir\Lib\site-packages"

# run pywin32's post-install script
Write-Host "[*] Running pywin32 postinstall script..."
& $python "$depsDir\SCRIPTS\pywin32_postinstall.py", "-install" | OutVerbose

# install lxml, lockfile
Write-Host "[*] Installing lxml..."
& "$pythonDir\Scripts\easy_install.exe" lxml | OutVerbose
Write-Host "[*] Installing lockfile..."
& "$pythonDir\Scripts\easy_install.exe" lockfile | OutVerbose

# copy python-config. it uses PYTHON_DIR variable to determine python install location
Copy-Item "$builderDir\windows-build-files\python-config" $pythonDir

# check if wix is installed
$wixIntalled = (Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -eq "WiX Toolset v3.7 Native 2012 SDK"}) -ne $null

if ($wixIntalled)
{
    Write-Host "[*] WiX Toolset already installed"
}
else
{
    Write-Host "[*] Installing WiX Toolset..."
    $pkgName = "wix"
    $file = $global:pkgConf[$pkgName][1]
    $log = "$logDir\wix-install.log"
    # install
    $ret = (Start-Process -FilePath $file -ArgumentList @("-q", "-l $log", "InstallFolder=$depsDir\wix") -Wait -PassThru).ExitCode

    if ($ret -ne 0)
    {
        Write-Host "[!] Install failed! Check the log at $log"
        FatalExit
    }
    else
    {
        Write-Host "[=] Install successful."
    }
}

# write PATH to be passed back to make
# convert to unix form
$pathDirs = $env:Path.Split(';')
$unixPath = ""
foreach ($dir in $pathDirs)
{
    $dir = $dir.Replace("%SystemRoot%", $env:windir)
    if ($unixPath -eq "") { $unixPath = (PathToUnix $dir) }
    else { $unixPath = $unixPath + ":" + (PathToUnix $dir) }
}

# mark chroot as prepared to not repeat everything on next build
# save mingw path, python path and modified search path
$pythonUnix = PathToUnix $pythonDir
Set-Content -Path $markerPath "$mingwUnix`n$pythonUnix`n$unixPath"

Write-Host "[=] Windows build environment prepared`n"
