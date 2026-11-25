#!/bin/bash
#######################################################################
# Copyright (c) 2026 ENEO Tecnología S.L.
# This file is part of redBorder.
# redBorder is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# redBorder is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License License for more details.
# You should have received a copy of the GNU Affero General Public License License
# along with redBorder. If not, see <http://www.gnu.org/licenses/>.
#######################################################################
#
# Migrates a node from the Progress Chef binaries to Cinc:
#   - Managers running Chef Server: redborder-chef-server (chef-server-core 15.7)
#     -> redborder-cinc-server (cinc-server-core 15.10). Keeps the same external
#     PostgreSQL, S3 cookbook storage, keys, secrets and nginx certificate.
#   - Every node: redborder-chef-client + chef-workstation
#     -> redborder-cinc-client (cinc-workstation 26.4).
#
# It must run outside chef-client (it stops chef-client and erchef).
# In a cluster, migrate first every manager with the chef-server service,
# then the rest of managers and finally the sensors.
# /etc/opscode and /var/opt/opscode are kept untouched for rollback.
#
# Only the first manager (the one that bootstrapped Chef Server) has the real server
# configuration in chef-server.rb (external PostgreSQL, S3). The other managers with
# chef-server were installed with a default chef-server.rb and their sys.config edited by
# cookbook-chef-server, so they take the configuration of the first one:
#   manager 1:  rb_migrate_to_cinc.sh                      (migrate it first)
#               rb_migrate_to_cinc.sh --export-server-config /root/cinc-server-config.tgz
#   manager N:  copy that file, then
#               rb_migrate_to_cinc.sh --server-config /root/cinc-server-config.tgz

set -euo pipefail

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
SCRIPT=$(basename "$0")
BACKUP_DIR="/var/backups/rb_migrate_to_cinc-${TIMESTAMP}"
LOG_FILE="/root/.rb_migrate_to_cinc.log"
ASSUME_YES=false
EXPORT_CONFIG=""
SERVER_CONFIG=""

# Configuration shared by every Cinc Server of a cluster (same database, same keys)
SHARED_CONFIG_FILES=(
  etc/cinc-project/cinc-server.rb
  etc/cinc-project/private-cinc-secrets.json
  etc/cinc-project/pivotal.pem
  etc/cinc-project/webui_priv.pem
  etc/cinc-project/webui_pub.pem
  var/opt/cinc-project/bootstrapped
)
SHARED_CONFIG_OPTIONAL_FILES=(
  etc/cinc-project/pivotal.rb
  var/opt/cinc-project/upgrades/migration-level
)

OLD_ETC=/etc/opscode
NEW_ETC=/etc/cinc-project
OLD_VAR=/var/opt/opscode
NEW_VAR=/var/opt/cinc-project

# ======================
# GENERAL FUNCTIONS
# ======================

log() {
  local level="$1"
  local msg="$2"
  echo "[$level] $(date '+%Y-%m-%d %H:%M:%S') - $msg" | tee -a "$LOG_FILE"
}

die() {
  log "ERROR" "$1"
  exit 1
}

usage() {
  echo "Migrate this node from Chef to Cinc"
  echo ""
  echo "Usage:"
  echo "  $SCRIPT [-y] [--server-config <file>]"
  echo "  $SCRIPT --export-server-config [<file>]"
  echo ""
  echo "Options:"
  echo "  -y, --yes                      Do not ask for confirmation"
  echo "  --server-config <file>         Use the Cinc Server configuration exported from the first"
  echo "                                 manager (needed on the other managers with chef-server)"
  echo "  --export-server-config [file]  On a manager already migrated to Cinc Server, export its"
  echo "                                 configuration (default /root/cinc-server-config.tgz)"
  echo "  -h, --help                     Show this help"
}

# chef-server.rb points to the external PostgreSQL only on the manager that bootstrapped it
has_real_server_config() {
  grep -qE "^postgresql\[['\"]external['\"]\] *= *true" "$OLD_ETC/chef-server.rb" 2>/dev/null
}

export_server_config() {
  local file="$1" f
  is_installed redborder-cinc-server || die "Cinc Server is not installed on this node: migrate it first"
  for f in "${SHARED_CONFIG_FILES[@]}"; do
    [ -f "/$f" ] || die "/$f not found: is Cinc Server configured on this node?"
  done
  grep -qE "^postgresql\[['\"]external['\"]\] *= *true" "$NEW_ETC/cinc-server.rb" ||
    die "$NEW_ETC/cinc-server.rb does not use the external PostgreSQL: export it from the first manager"
  local files=("${SHARED_CONFIG_FILES[@]}")
  for f in "${SHARED_CONFIG_OPTIONAL_FILES[@]}"; do
    [ -f "/$f" ] && files+=("$f")
  done
  (umask 077 && tar -czf "$file" -C / "${files[@]}")
  chmod 0600 "$file"
  echo "Cinc Server configuration exported to $file (it contains keys and secrets: copy it only to the"
  echo "other managers, run '$SCRIPT --server-config $file' there and delete it afterwards)"
}

# Server ctl commands run on the embedded Ruby: hide the RVM environment from them
server_ctl() {
  local ctl="$1"
  shift
  env -u GEM_HOME -u GEM_PATH -u GEM_ROOT -u RUBYOPT -u RUBYLIB -u BUNDLE_GEMFILE "$ctl" "$@"
}

is_installed() {
  rpm -q "$1" &>/dev/null
}

# redborder role package installed on this node (redborder-manager, redborder-ips...)
role_package() {
  local p
  for p in redborder-manager redborder-ips redborder-intrusion redborder-proxy redborder-mailgateway; do
    if is_installed "$p"; then
      echo "$p"
      return 0
    fi
  done
  return 1
}

# Packages dnf must never remove during the migration: if a solution needs it, dnf fails instead
protected_packages() {
  local list="dnf,redborder-common,redborder-rubyrvm,redborder-cinc-client,redborder-cinc-server,cinc-workstation,cinc-server-core"
  [ -n "$ROLE_PKG" ] && list="$list,$ROLE_PKG"
  echo "$list"
}

# Runs a dnf transaction only if it removes nothing outside the allowed packages.
#   safe_dnf <allowed removals, regex> <dnf command and args...>
# It first simulates it (--assumeno) and reads the "Removing" sections of the plan,
# so a dependency problem can never erase the rest of the node in cascade.
safe_dnf() {
  local allowed="$1"
  shift
  local opts=(--setopt=protected_packages="$(protected_packages)" --setopt=clean_requirements_on_remove=False)
  local plan removals pkg

  # Wide output so dnf does not wrap package lines in the plan
  plan=$(LANG=C COLUMNS=250 dnf --assumeno "${opts[@]}" "$@" 2>&1 || true)
  echo "$plan" >> "$LOG_FILE"
  if echo "$plan" | grep -qE '^(Error|Problem)'; then
    die "dnf cannot resolve 'dnf $*' (details in $LOG_FILE)"
  fi

  removals=$(echo "$plan" | awk '/^Removing/ {f=1; next} /^[^ ]/ {f=0} f && NF >= 4 {print $1}')
  for pkg in $removals; do
    [[ "$pkg" =~ ^($allowed)$ ]] || die "'dnf $*' would also remove $pkg. Aborted, nothing changed (plan in $LOG_FILE)"
  done
  log "INFO" "dnf $* (removes: ${removals:-nothing})"

  LANG=C dnf -y "${opts[@]}" "$@" 2>&1 | tee -a "$LOG_FILE"
}

# ======================
# STEPS
# ======================

stop_chef_server() {
  log "INFO" "Stopping Chef Server services"
  local units
  units=$(systemctl list-unit-files --no-legend 'opscode-*.service' | awk '{print $1}')
  for unit in $units; do
    systemctl stop "$unit" || true
  done
  if [ -x /opt/opscode/bin/chef-server-ctl ]; then
    server_ctl /opt/opscode/bin/chef-server-ctl graceful-kill &>/dev/null || true
    server_ctl /opt/opscode/bin/chef-server-ctl stop &>/dev/null || true
  fi
  # Cinc Server reuses this unit name: reconfigure only rewrites its ExecStart and "starts" it,
  # so if the Chef runsvdir (/opt/opscode/service) is still running it is never replaced and
  # reconfigure waits forever for the Cinc services. Stop it now.
  systemctl stop private_chef-runsvdir-start.service 2>/dev/null || true
  pkill -f 'runsvdir -P /opt/opscode/service' 2>/dev/null || true
}

backup_chef_server() {
  log "INFO" "Backing up $OLD_ETC and $OLD_VAR/nginx to $BACKUP_DIR"
  mkdir -p "$BACKUP_DIR"
  tar -czf "$BACKUP_DIR/etc-opscode.tar.gz" -C / "${OLD_ETC#/}"
  [ -d "$OLD_VAR/nginx" ] && tar -czf "$BACKUP_DIR/var-opt-opscode-nginx.tar.gz" -C / "${OLD_VAR#/}/nginx"
  chmod -R go-rwx "$BACKUP_DIR"
}

copy_chef_server_config() {
  log "INFO" "Copying Chef Server configuration, keys and secrets to $NEW_ETC"
  mkdir -p "$NEW_ETC"

  [ -f "$OLD_ETC/chef-server.rb" ] || die "$OLD_ETC/chef-server.rb not found"
  sed -e "s#$OLD_ETC#$NEW_ETC#g" -e "s#$OLD_VAR#$NEW_VAR#g" "$OLD_ETC/chef-server.rb" > "$NEW_ETC/cinc-server.rb"

  # Same passwords: the external PostgreSQL users and the S3 keys already use them
  [ -f "$OLD_ETC/private-chef-secrets.json" ] || die "$OLD_ETC/private-chef-secrets.json not found"
  cp -a "$OLD_ETC/private-chef-secrets.json" "$NEW_ETC/private-cinc-secrets.json"
  chmod 0600 "$NEW_ETC/private-cinc-secrets.json"

  # pivotal (superuser), webui keys, admin and validator keys
  cp -a "$OLD_ETC"/*.pem "$NEW_ETC"/
  [ -f "$OLD_ETC/pivotal.rb" ] && sed "s#$OLD_ETC#$NEW_ETC#g" "$OLD_ETC/pivotal.rb" > "$NEW_ETC/pivotal.rb"

  # Keep the same nginx certificate (clients have it in trusted_certs)
  if [ -d "$OLD_VAR/nginx/ca" ]; then
    mkdir -p "$NEW_VAR/nginx/ca"
    cp -a "$OLD_VAR/nginx/ca/." "$NEW_VAR/nginx/ca/"
  fi

  # Other managers: the shared server configuration (cinc-server.rb, secrets, pivotal and webui
  # keys, bootstrapped, migration-level) comes from the first manager and replaces the local one
  if [ -n "$SERVER_CONFIG" ]; then
    import_server_config
    return 0
  fi

  # This server is already bootstrapped and its database is at the Chef Server migration level.
  # Without the sentinel, reconfigure treats it as a new server: it tries to start a local
  # PostgreSQL (fails with an external one) and would bootstrap the data again (pivotal user...).
  # Without migration-level, partybus would not know which upgrades are already applied.
  [ -f "$OLD_VAR/bootstrapped" ] || die "$OLD_VAR/bootstrapped not found: this Chef Server was never bootstrapped"
  cp -a "$OLD_VAR/bootstrapped" "$NEW_VAR/bootstrapped"
  if [ -f "$OLD_VAR/upgrades/migration-level" ]; then
    mkdir -p "$NEW_VAR/upgrades"
    cp -a "$OLD_VAR/upgrades/migration-level" "$NEW_VAR/upgrades/migration-level"
  fi
}

import_server_config() {
  log "INFO" "Using the Cinc Server configuration of the first manager ($SERVER_CONFIG)"
  local tmp f
  tmp=$(mktemp -d)
  tar -xzf "$SERVER_CONFIG" -C "$tmp"
  for f in "${SHARED_CONFIG_FILES[@]}"; do
    [ -f "$tmp/$f" ] || { rm -rf "$tmp"; die "$SERVER_CONFIG does not contain $f"; }
  done
  grep -qE "^postgresql\[['\"]external['\"]\] *= *true" "$tmp/etc/cinc-project/cinc-server.rb" ||
    { rm -rf "$tmp"; die "$SERVER_CONFIG: cinc-server.rb does not use the external PostgreSQL"; }
  for f in "${SHARED_CONFIG_FILES[@]}" "${SHARED_CONFIG_OPTIONAL_FILES[@]}"; do
    if [ -f "$tmp/$f" ]; then
      mkdir -p "$(dirname "/$f")"
      cp -a "$tmp/$f" "/$f"
    fi
  done
  chmod 0600 "$NEW_ETC/private-cinc-secrets.json"
  rm -rf "$tmp"
}

install_cinc_server() {
  # Re-running the script on a half migrated node: the package switch is already done
  if is_installed redborder-cinc-server; then
    log "INFO" "redborder-cinc-server already installed"
  else
    log "INFO" "Switching redborder-chef-server to redborder-cinc-server"
    # Nothing else requires redborder-chef-server: no --allowerasing needed
    safe_dnf 'redborder-chef-server' swap redborder-chef-server redborder-cinc-server
  fi
  is_installed cinc-server-core || die "cinc-server-core was not installed"
}

# Value of a postgresql['key'] setting in cinc-server.rb (external PostgreSQL)
pg_setting() {
  grep -E "^postgresql\[['\"]$1['\"]\]" "$NEW_ETC/cinc-server.rb" | tail -1 | sed -E "s/^[^=]*= *['\"]?([^'\"]*)['\"]?.*/\1/"
}

# reconfigure only deploys the sqitch schemas when it creates the databases. On an existing
# database the schema stays at the Chef Server 15.7 level (opscode_chef lacks telemetry and kvpair)
# and erchef 15.10 fails its SQL health check. Deploy the pending changes, as pg_sqitch does.
deploy_cinc_schemas() {
  local host port user
  host=$(pg_setting vip)
  port=$(pg_setting port)
  user=$(pg_setting db_superuser)
  [ -n "$host" ] && [ -n "$user" ] || die "postgresql vip/db_superuser not found in $NEW_ETC/cinc-server.rb"
  [ -n "$port" ] || port=5432

  local schema db
  for schema in opscode-erchef/schema/baseline:opscode_chef opscode-erchef/schema:opscode_chef oc_bifrost/db:bifrost; do
    db=${schema#*:}
    schema=/opt/cinc-project/embedded/service/${schema%%:*}
    log "INFO" "Deploying the $schema schema on $db"
    PGPASSWORD="$(pg_setting db_superuser_password)" PGSSLMODE=disable \
      PERL5LIB=/opt/cinc-project/embedded/lib LD_LIBRARY_PATH=/opt/cinc-project/embedded/lib \
      /opt/cinc-project/embedded/bin/sqitch --quiet --chdir "$schema" \
      deploy "db:pg://${user}@${host}:${port}/${db}" --verify 2>&1 | tee -a "$LOG_FILE"
  done
}

configure_cinc_server() {
  log "INFO" "Running cinc-server-ctl reconfigure"
  server_ctl /usr/bin/cinc-server-ctl reconfigure 2>&1 | tee -a /root/.install-cinc-server.log
  chown cinc: "$NEW_ETC/private-cinc-secrets.json"

  deploy_cinc_schemas

  # Replace the runit services started by reconfigure with the redborder systemd units
  log "INFO" "Moving Cinc Server services from runit to systemd"
  server_ctl /usr/bin/cinc-server-ctl graceful-kill &>/dev/null || true
  server_ctl /usr/bin/cinc-server-ctl stop &>/dev/null || true
  systemctl daemon-reload
  if [ -d /opt/cinc-project/service ]; then
    for i in $(ls /opt/cinc-project/service/ | sed 's/opscode-//g'); do
      rm -rf "/opt/cinc-project/service/$i" "/opt/cinc-project/service/opscode-$i"
      if [ "$i" != "postgresql" ]; then
        systemctl enable "opscode-$i" &>/dev/null || true
        systemctl restart "opscode-$i"
      fi
    done
  fi

  log "INFO" "Waiting for erchef"
  local i
  for i in $(seq 1 60); do
    curl -ksf https://localhost:4443/_status &>/dev/null && break
    sleep 5
  done
  curl -ksf https://localhost:4443/_status &>/dev/null || die "erchef does not answer on https://localhost:4443/_status"

  # OpenSearch starts empty in /var/opt/cinc-project: rebuild the search index
  log "INFO" "Rebuilding the search index"
  server_ctl /usr/bin/cinc-server-ctl reindex --all-orgs 2>&1 | tee -a "$LOG_FILE"
}

remove_chef_server_core() {
  log "INFO" "Removing chef-server-core ($OLD_ETC and $OLD_VAR are kept for rollback)"
  # rpm -e fails if any package still requires it, instead of removing it in cascade
  rpm -e chef-server-core 2>&1 | tee -a "$LOG_FILE"
}

install_cinc_client() {
  if is_installed redborder-cinc-client && ! is_installed chef-workstation; then
    log "INFO" "redborder-cinc-client already installed"
  else
    # The installed role package still requires chef-workstation. Upgrading it to the version
    # that requires redborder-cinc-client does the whole switch in one transaction: it installs
    # redborder-cinc-client + cinc-workstation and, through their Conflicts, removes only
    # chef-workstation and redborder-chef-client. --allowerasing is needed for those two, and
    # safe_dnf aborts if the plan removes anything else.
    # redborder-rubyrvm goes in the same transaction: it and cinc-workstation ship the same
    # precompiled nokogiri .so files, so older redborder-rubyrvm packages own the same
    # /usr/lib/.build-id links and the transaction test fails. The new one ships no build-id links.
    log "INFO" "Upgrading $ROLE_PKG and redborder-rubyrvm: redborder-chef-client + chef-workstation -> redborder-cinc-client"
    safe_dnf 'chef-workstation|redborder-chef-client' --allowerasing upgrade "$ROLE_PKG" redborder-rubyrvm
  fi
  is_installed cinc-workstation || die "cinc-workstation was not installed"
  is_installed chef-workstation && die "chef-workstation is still installed"

  # Normally done by the package %posttrans; repeated in case of a partial transaction
  /usr/lib/redborder/bin/rb_cinc_compat_links.sh
  systemctl daemon-reload
}

upload_cinc_server_cookbook() {
  # A fresh install of cookbook-cinc-server does not upload it, and the new rb-manager cookbook
  # depends on it: it must be on erchef before cookbook-rb-manager is upgraded and uploaded
  if ! is_installed cookbook-cinc-server; then
    log "INFO" "Installing cookbook-cinc-server"
    safe_dnf '' install cookbook-cinc-server
  fi
  log "INFO" "Uploading the cinc-server cookbook"
  su - -s /bin/bash -c 'source /etc/profile && rvm gemset use default && env knife cookbook upload cinc-server' 2>&1 | tee -a "$LOG_FILE"
}

# ======================
# MAIN
# ======================

while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes) ASSUME_YES=true ;;
    --server-config)
      [ $# -ge 2 ] || { usage; exit 1; }
      SERVER_CONFIG="$2"
      shift
      ;;
    --export-server-config)
      EXPORT_CONFIG="/root/cinc-server-config.tgz"
      if [ $# -ge 2 ] && [[ "$2" != -* ]]; then
        EXPORT_CONFIG="$2"
        shift
      fi
      ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
  shift
done

[ "$(id -u)" -eq 0 ] || die "This script must be run as root"

if [ -n "$EXPORT_CONFIG" ]; then
  export_server_config "$EXPORT_CONFIG"
  exit 0
fi

if [ -n "$SERVER_CONFIG" ]; then
  [ -f "$SERVER_CONFIG" ] || die "$SERVER_CONFIG not found"
  SERVER_CONFIG=$(readlink -f "$SERVER_CONFIG")
fi

HAS_SERVER=false
is_installed chef-server-core && HAS_SERVER=true
ROLE_PKG=$(role_package) || die "No redborder role package (redborder-manager, -ips, -intrusion, -proxy, -mailgateway) installed"

# Checked before changing anything: a manager that did not bootstrap Chef Server has a default
# chef-server.rb (local PostgreSQL). Converting it would make Cinc configure a local database.
if $HAS_SERVER && [ -z "$SERVER_CONFIG" ] && ! has_real_server_config; then
  die "$OLD_ETC/chef-server.rb does not use the external PostgreSQL: this is not the manager that bootstrapped Chef Server. Migrate that manager first, run '$SCRIPT --export-server-config' there, copy the file here and run '$SCRIPT --server-config <file>'"
fi

if ! $HAS_SERVER && is_installed redborder-cinc-client && ! is_installed chef-workstation; then
  log "INFO" "This node is already on Cinc. Nothing to do"
  exit 0
fi

echo "This node will be migrated from Chef to Cinc:"
$HAS_SERVER && echo "  - Chef Server 15.7 -> Cinc Server (erchef will be stopped)"
echo "  - redborder-chef-client + chef-workstation -> redborder-cinc-client"
if ! $ASSUME_YES; then
  read -r -p "Continue? [y/N] " answer
  [[ "$answer" =~ ^[yY]$ ]] || { echo "Aborted"; exit 1; }
fi

log "INFO" "Starting migration to Cinc on $(hostname -s)"
systemctl stop chef-client || true

if $HAS_SERVER; then
  stop_chef_server
  backup_chef_server
  copy_chef_server_config
  install_cinc_server
  configure_cinc_server
  remove_chef_server_core
fi

install_cinc_client

is_installed redborder-cinc-server && upload_cinc_server_cookbook

log "INFO" "$(/opt/cinc-workstation/bin/cinc-client --version)"
systemctl start chef-client
log "INFO" "Migration finished. Check the next chef-client run: journalctl -fu chef-client"
$HAS_SERVER && log "INFO" "When everything works, $OLD_ETC and $OLD_VAR can be removed (backup in $BACKUP_DIR)"
exit 0
