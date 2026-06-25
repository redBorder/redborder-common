%global debug_package %{nil}
%define _build_id_links none

Name:           govc
Version:        %{__version}
Release:        1%{?dist}
Summary:        vSphere CLI built on top of govmomi

License:        MIT
URL:            https://github.com/vmware/govmomi
Source0:        govc-%{version}_Linux_x86_64.tar.gz

%description
govc is a vSphere CLI built on top of govmomi.

%prep
%setup -c -q -T
tar -xzf %{SOURCE0}

%build
# Pre-built binary, no build step needed

%install
mkdir -p %{buildroot}%{_bindir}
install -p -m 0755 govc %{buildroot}%{_bindir}/govc

%files
%{_bindir}/govc

%changelog
* Wed Jun 24 2026 Nils <nverschaeve@redborder.com> - 0.54.1-1
- Initial package release for govc
