Name:	    qubes-core-dom0-pvdrivers-win7	
Version:	0.2
Release:	1
Summary:	PV Drivers for Vista and Windows 7 VMs
Group:		Qubes
License:    GPL
Provides:   qubes-core-dom0-pvdrivers

%define _builddir %(pwd)

%description
PV Drivers for Vista and Windows 7 VMs.

%install
mkdir -p $RPM_BUILD_ROOT/usr/lib/qubes/
cp pvdrivers-win7.iso $RPM_BUILD_ROOT/usr/lib/qubes/

%files
/usr/lib/qubes/pvdrivers-win7.iso



%changelog

