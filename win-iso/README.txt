I. Prerequisites for installing Xen PV drivers on Windows
-----------------------------------------------------------

In order to install the PV drivers on x64 Vista nd Windows 7, one needs to
disable driver signature checking policy, as the current drivers are only self
signed. In order to disable driver signing requirement do the following (in
Windows VM):

1) Start command prompt as Administrator Mode, i.e. right click on the Command
Prompt icon and choose "Run as administrator",

2) In the command prompt type:
bcdedit /set testsigning on

3) Reboot your Windows VM

II. Installing the PV drivers
-------------------------------

Run the .msi file from the virtual CDROM, specific for your Windows version:
either x86 or x64.


