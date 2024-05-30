%undefine __brp_mangle_shebangs

Name: redborder-common
Version: %{__version}
Release: %{__release}%{?dist}
BuildArch: noarch
Summary: Package for redborder containing common functions and scripts.

License: AGPL 3.0
URL: https://github.com/redBorder/redborder-common
Source0: %{name}-%{version}.tar.gz

Requires: bash figlet util-linux vim mlocate tree htop tmux screen net-tools tcpdump wget btop

%description
%{summary}

%prep
%setup -qn %{name}-%{version}

%build

%install
mkdir -p %{buildroot}/etc/profile.d
mkdir -p %{buildroot}/usr/lib/redborder/bin
mkdir -p %{buildroot}/usr/lib/redborder/scripts
install -D -m 0644 resources/redborder-common.sh %{buildroot}/etc/profile.d
cp resources/bin/* %{buildroot}/usr/lib/redborder/bin
cp -r resources/etc/* %{buildroot}/etc
cp resources/scripts/* %{buildroot}/usr/lib/redborder/scripts
chmod 0755 %{buildroot}/usr/lib/redborder/bin/*
chmod 0755 %{buildroot}/usr/lib/redborder/scripts/*

%pre
getent group redborder >/dev/null || groupadd -r redborder
getent passwd redborder >/dev/null || \
    useradd -r -g redborder -d /home/redborder -s /bin/bash \
    -c "User of redborder framework" redborder -m
exit 0

%files
%defattr(0755,root,root)
/usr/lib/redborder/bin
/usr/lib/redborder/scripts
%defattr(0644,root,root)
/etc/profile.d/redborder-common.sh
/etc/objects/mac_vendors

%doc

%changelog
* Thu May 30 2024 Miguel Negrón <manegron@redborder.com>
- Add btop

* Thu May 23 2024 Miguel Negrón <manegron@redborder.com>
- Add wget

* Fri May 17 2024 Miguel Negrón <manegron@redborder.com>
- Add tree htop tmux screen net-tools tcpdump 

* Mon May 13 2024 Miguel Negrón <manegron@redborder.com>
- Add vim and mlocate as require 

* Wed Nov 15 2023 Miguel Álvarez <malvarez@redborder.com> - 1.0.2-1
- Added mac vendors file

* Fri Apr 21 2023 Vicente Mesa <vimesa@redborder.com> - 1.0.1-1
- Added scripts folder

* Wed Oct 26 2016 Juan J. Prieto <jjprieto@redborder.com> - 1.0.0-1
- Added wrapper to ruby scripts

* Thu Sep 08 2016 Carlos J. Mateos <cjmateos@redborder.com> - 1.0.0-1
- Remove unused scripts

* Thu Jul 07 2016 Carlos J. Mateos <cjmateos@redborder.com> - 1.0.0-1
- Added various rb scripts

* Thu Jun 23 2016 Juan J. Prieto <jjprieto@redborder.com> - 1.0.0-1
- first spec version
