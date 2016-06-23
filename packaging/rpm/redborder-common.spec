Name: redborder-common
Version: %{__version}
Release: %{__release}%{?dist}
Summary: Package for redborder containing common functions and scripts.

License: AGPL 3.0
URL: https://github.com/redBorder/redborder-common
Source0: %{name}-%{version}.tar.gz

Requires: bash dialog

%description
%{summary}

%prep
%setup -qn %{name}-%{version}

%build

%install
mkdir -p %{buildroot}/usr/lib/redborder/bin
install -D -m 0644 rb_functions.sh %{buildroot}/usr/lib/redborder/bin

%files
/usr/lib/redborder/bin
%doc



%changelog
* Thu Jun 23 2016 Juan J. Prieto <jjprieto@redborder.com> - 1.0.0-1
- first spec version
