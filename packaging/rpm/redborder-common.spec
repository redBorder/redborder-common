Name: redborder-common
Version: %{__version}
Release: %{__release}%{?dist}
BuildArch: noarch
Summary: Package for redborder containing common functions and scripts.

License: AGPL 3.0
URL: https://github.com/redBorder/redborder-common
Source0: %{name}-%{version}.tar.gz

Requires: bash figlet util-linux

%description
%{summary}

%prep
%setup -qn %{name}-%{version}

%build

%install
mkdir -p %{buildroot}/etc/profile.d
mkdir -p %{buildroot}/usr/lib/redborder/bin
install -D -m 0644 resources/redborder-common.sh %{buildroot}/etc/profile.d
cp resources/bin/* %{buildroot}/usr/lib/redborder/bin
chmod 0755 %{buildroot}/usr/lib/redborder/bin/*

%pre
getent group redborder >/dev/null || groupadd -r redborder
getent passwd redborder >/dev/null || \
    useradd -r -g redborder -d /home/redborder -s /bin/bash \
    -c "User of redborder framework" redborder -m
exit 0

%files
%defattr(0755,root,root)
/usr/lib/redborder/bin
%defattr(0644,root,root)
/etc/profile.d/redborder-common.sh

%doc

%changelog
* Wed Oct 26 2016 Juan J. Prieto <jjprieto@redborder.com> - 1.0.0-1
- Added wrapper to ruby scripts

* Thu Sep 08 2016 Carlos J. Mateos <cjmateos@redborder.com> - 1.0.0-1
- Remove unused scripts

* Thu Jul 07 2016 Carlos J. Mateos <cjmateos@redborder.com> - 1.0.0-1
- Added various rb scripts

* Thu Jun 23 2016 Juan J. Prieto <jjprieto@redborder.com> - 1.0.0-1
- first spec version
