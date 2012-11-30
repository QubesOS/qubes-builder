%define iso_build_timestamp %(cat iso_build_timestamp)

Name:	    qubes-windows-tools
Version:	1
Release:	%{iso_build_timestamp}
Summary:	PV Drivers for Windows VMs
Group:		Qubes
License:    GPL/Proprietary
Obsoletes:  qubes-core-dom0-pvdrivers

%define _builddir %(pwd)

%description
PV Drivers (GPL) and Qubes Windows agent code (proprietary) Windows AppVMs. Bundled for XP, Vista, 2003, 7, both 32bit and 64bit.

%install
mkdir -p $RPM_BUILD_ROOT/usr/lib/qubes/
cp qubes-windows-tools-%{iso_build_timestamp}.iso $RPM_BUILD_ROOT/usr/lib/qubes/

%files
/usr/lib/qubes/qubes-windows-tools-%{iso_build_timestamp}.iso

%changelog

