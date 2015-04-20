1) Create an IMG file with the sources:

make windows-image

The resulting windows-image.img file can be passed to a Windows-based HVM and build there.

2) Create an ISO containing built drivers and installer:

make windows-image-extract installer-qubes-os-windows-tools

The resulting qubes-windows.iso can be attached to a Windows HVM in order to install
the Qubes PV drivers.

Windows Build Machine Preparation
-----------------------------------
1) WDK 7600 (edit makedist.bat for exact path to the DDK)
2) WIX >= 3.6 RC (http://wix.codeplex.com/releases/view/88566)
3) Run scripts-windows/get-be.ps1

