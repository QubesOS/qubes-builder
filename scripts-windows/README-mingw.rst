Preparing Windows build environment
===================================

PV Drivers and tools for Qubes R2
---------------------------------
Check windows-tools/README.windows in qubes-builder.

Odyssey framework, especially Windows control domain
----------------------------------------------------
To build core components (especially libvirt) a lot of libraries and tools needs to be installed. As Windows doesn't have package manager, you need to do it manually (perhaps in the future there will be some script for this...).
You need to choose some directories to store installed components:
1. msys (Minimalist GNU for Windows) - I suggest c:\msys
2. python - I suggest c:\python27
Additional libraries will be installed in msys directory, as it is default for /usr (so /usr/lib, /usr/include etc).

Note: most of those packages are unsigned (neither sources nor binaries)...

I assume 64bit target binaries. If you wish build 32bit one, choose appropriate versions of packages: mingw32 instead of mingw32-w64 and all libraries in 32bit.
If you're planning to build both versions, use separate msys, mingw and python directories (and switch PATH accordingly before build).

Components required to build Windows code (download list):
1. 7z tool: http://www.7-zip.org/
#. MSYS: version bundled with some useful tools: http://sourceforge.net/projects/mingwbuilds/files/external-binary-packages/
   You can of course build your own version from sources, or install separately those components
#. git - bundled in the above package
#. mingw-w64: http://sourceforge.net/apps/trac/mingw-w64/wiki/GeneralUsageInstructions, specific link: http://sourceforge.net/projects/mingw-w64/files/Toolchains%20targetting%20Win64/Personal%20Builds/rubenvb/gcc-4.7-release/x86_64-w64-mingw32-gcc-4.7.4-release-win64_rubenvb.7z/download
#. libxml2: homepage http://www.xmlsoft.org/, windows binaries provided by: http://www.zlatkovic.com/libxml.en.html, specific link: ftp://ftp.zlatkovic.com/libxml/64bit/libxml-2.9.1-win32-x86_64.7z
#. Portable XDR: http://people.redhat.com/~rjones/portablexdr/files/ (no windows binaries available)
#. zlib: http://zlib.net, http://zlib.net/zlib-1.2.8.tar.gz, windows binaries: http://sourceforge.net/projects/mingw-w64/files/External%20binary%20packages%20%28Win64%20hosted%29/Binaries%20%2864-bit%29/zlib-1.2.5-bin-x64.zip/download
#. iconv: https://www.gnu.org/software/libiconv/, windows binaries: http://sourceforge.net/projects/mingw-w64/files/External%20binary%20packages%20%28Win64%20hosted%29/libiconv/libiconv-1.13.1-win64-20100707.zip/download
#. Python 2.7: http://python.org/, http://python.org/ftp/python/2.7.5/python-2.7.5.amd64.msi
#. python-psutils binaries: http://code.google.com/p/psutil/downloads/detail?name=psutil-1.0.1.win-amd64-py2.7.exe&can=2&q=
#. python-setuptools: https://pypi.python.org/pypi/setuptools

Installation instruction:
1. Install 7z tool (installer).
#. Unpack msys archive content into choosen msys directory (c:\msys).
#. (if you choose to install git separately) install git package (installer), choose to place "git" binary in PATH.
#. Unpack ming32-w64 archive content into choosen msys directory (c:\msys).
#. Install python (installer).
#. Add msys and python to system PATH (Start->Computer properties->Advanced system settings->Advanced tab->Environment Variables), append '';c:\msys\bin;c:\python27'' there.
#. Unpack zlib into msys directory. Copy ''zlib1.dll'' into ''windows\system32'' directory.
#. Compile and install Portable XDR:
   1. Unpack archive somewhere
   1. Goto that directory in msys shell
   1. Apply patch from ''qubes-builder/windows-build-files/portablexdr-4.9.1-64bit.patch''.
   1. Execute: ::
   ./configure -C --prefix=/usr --build=x86_64-w64-mingw32
   make
   make install
   cp /usr/bin/portable-rpcgen.exe /usr/bin/rpcgen.exe

#. Unpack iconv into msys directory. Fix paths in ''c:\msys\lib\libiconv.la''.
#. Unpack libxml2 into msys directory. Fix paths in ''c:\msys\lib\libxml2.la'', ''c:\msys\bin\xml2-config'' and ''c:\msys\lib\pkgconfig\libxml-2.0.pc''.
#. Copy python include directory (c:\python27\include) to msys as c:\msys\include\python2.7 (so c:\msys\include\python2.7\python.h exists).
#. Prepare python devel files: ::
   cd c:/python27
   gendef c:\windows\system32\python27.dll
   dlltool -d python27.def -l libpython27.dll.a

#. Install python modules:
   1) setuptools (manually); copy python27/scripts/easy_install.py to level up (to be in $PATH)
   2) Apply patch from qubes-builder/windows-build-files/python-mingw32.patch
   3) lxml (easy_install lxml)
   4) lockfile
   5) psutil (binaries from code.google.com. Sources fail to compile with mingw)
#. 
   

