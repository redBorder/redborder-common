%undefine __brp_mangle_shebangs

Name: redborder-common
Version: %{__version}
Release: %{__release}%{?dist}
BuildArch: noarch
Summary: Package for redborder containing common functions and scripts.

License: AGPL 3.0
URL: https://github.com/redBorder/redborder-common
Source0: %{name}-%{version}.tar.gz

Requires: bash figlet util-linux vim mlocate tree htop tmux screen net-tools tcpdump wget bwm-ng btop xmlstarlet iotop

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

%posttrans

# Define target versions
TARGET_VERSION="25.2"
TARGET_GEM_VERSION="2.0.6"

# Get the installed version of Chef Workstation
CHEF_VERSION=$(rpm -q --queryformat '%{VERSION}' chef-workstation 2>/dev/null || true)

# If the version cannot be determined, print an error message and exit
if [[ -z "$CHEF_VERSION" ]]; then
    echo "Unable to determine Chef Workstation version. Exiting..."
    exit 1
fi

# Function to compare versions (returns 0 if $1 >= $2, 1 otherwise)
version_ge() {
    [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" != "$2" ]
}

# Define working paths
GEM_PATH="/opt/chef-workstation/embedded/lib/ruby/gems/3.1.0/specifications"
GEM_NAME="openssl-3.0.1.gemspec"
BACKUP_DIR="$GEM_PATH/backup"
NEW_GEM="$GEM_PATH/openssl-3.2.0.gemspec"

# Check if the installed Chef Workstation version is greater than or equal to the target version
if version_ge "$CHEF_VERSION" "$TARGET_VERSION"; then
    echo "Detected Chef Workstation version $CHEF_VERSION (>= $TARGET_VERSION), modifying OpenSSL gem..."

    # Create backup directory and move the old gemspec if it exists
    if [[ -f "$GEM_PATH/default/$GEM_NAME" ]]; then
        install -D "$GEM_PATH/default/$GEM_NAME" "$BACKUP_DIR/$GEM_NAME"
        rm -f "$GEM_PATH/default/$GEM_NAME"
        echo "Moved $GEM_NAME to $BACKUP_DIR"
    fi

    # Replace the old OpenSSL gemspec with the new one if available
    if [[ -f "$NEW_GEM" ]]; then
        cp "$NEW_GEM" "$GEM_PATH/default/"
        echo "Replaced with openssl-3.2.0.gemspec"
    else
        echo "Warning: openssl-3.2.0.gemspec not found, cannot replace."
    fi

    # Install the specific version of the netaddr gem
    echo "Installing netaddr gem version $TARGET_GEM_VERSION..."
    /opt/chef-workstation/embedded/bin/gem install netaddr -v "$TARGET_GEM_VERSION"

else
    # If the installed Chef Workstation version is lower than the required version, do nothing
    echo "ℹChef Workstation version $CHEF_VERSION is lower than $TARGET_VERSION, no changes made."
fi

%doc

%changelog
* Thu Feb 20 2025 Vicente Mesa <vimesa@redborder.com> - 1.2.0-1
- Update chef-workstation

* Mon Sep 16 2024 Miguel Negrón <manegron@redborder.com>
- Add xmlstarlet and iotop

* Mon Jun 03 2024 Miguel Negrón <manegron@redborder.com>
- Add bwm-ng and btop

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
