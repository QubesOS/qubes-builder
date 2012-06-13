Name:	    qubes-core-dom0-pvdrivers
Version:	0.3
Release:	1
Summary:	PV Drivers for Windows VMs
Group:		Qubes
License:    GPL
Provides:   qubes-core-dom0-pvdrivers

%define _builddir %(pwd)

%description
PV Drivers for Windows VMs. Bundled for XP, Vista, 2003, 7, both 32bit and 64bit.

%install
mkdir -p $RPM_BUILD_ROOT/usr/lib/qubes/
cp pvdrivers-windows.iso $RPM_BUILD_ROOT/usr/lib/qubes/

%files
/usr/lib/qubes/pvdrivers-windows.iso



%changelog

