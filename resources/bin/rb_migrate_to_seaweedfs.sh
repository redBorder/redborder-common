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
# Migrates the S3 service of a manager cluster from MinIO to SeaweedFS.
#
# The consumers (erchef cookbooks, Druid, WebUI, Logstash, Airflow) move to SeaweedFS when
# chef-client runs with the new cookbooks, so the data must be in SeaweedFS before that:
#
#   1. Every manager with the s3 service, the first one first:
#        rb_migrate_to_seaweedfs.sh --prepare
#      Stops chef-client, installs SeaweedFS and starts the cluster next to MinIO
#      (MinIO keeps serving everything).
#   2. Every manager: dnf update (new cookbooks; chef-client stays stopped)
#   3. One manager with the s3 service:
#        rb_migrate_to_seaweedfs.sh --copy
#      Copies every bucket from MinIO to SeaweedFS and deletes from SeaweedFS what is no
#      longer in MinIO. It can run again: it only copies what is missing or has a different size.
#   4. Every manager: systemctl start chef-client (the consumers move to SeaweedFS)
#   5. Every manager with the s3 service:
#        rb_migrate_to_seaweedfs.sh --finish
#      Copies what was written to MinIO since step 3, then stops and removes MinIO.
#
# Until step 4 MinIO is untouched: to roll back, stop SeaweedFS and start chef-client.

set -euo pipefail

SCRIPT=$(basename "$0")
LOG_FILE="/root/.rb_migrate_to_seaweedfs.log"
WORKDIR="/var/lib/rb_migrate_to_seaweedfs"
ASSUME_YES=false
ACTION=""

S3_PORT=8333
MINIO_ENDPOINT="http://127.0.0.1:9000"
WEED_PORTS=(8333 18333 9333 19333 9340 19340 9350 19350)

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
  echo "Migrate the S3 service of this manager from MinIO to SeaweedFS"
  echo ""
  echo "Usage:"
  echo "  $SCRIPT [-y] --prepare | --copy | --finish"
  echo ""
  echo "Steps (see the header of this script):"
  echo "  1. --prepare  every manager with s3 (first one first): install and start SeaweedFS"
  echo "  2. dnf update in every manager"
  echo "  3. --copy     one manager with s3: copy the buckets from MinIO to SeaweedFS"
  echo "  4. systemctl start chef-client in every manager"
  echo "  5. --finish   every manager with s3: copy the last changes, stop and remove MinIO"
  echo ""
  echo "Options:"
  echo "  -y, --yes     Do not ask for confirmation"
  echo "  -h, --help    Show this help"
}

confirm() {
  $ASSUME_YES && return 0
  read -r -p "$1 [y/N] " answer
  [[ "$answer" =~ ^[yY]$ ]] || { echo "Aborted"; exit 1; }
}

is_installed() {
  rpm -q "$1" &>/dev/null
}

knife_cmd() {
  /opt/cinc-workstation/bin/knife "$@" 2>/dev/null
}

# Cinc node name of this manager
node_name() {
  local name
  name=$(awk '/^node_name/ {gsub(/["'\'']/, "", $2); print $2}' /etc/chef/client.rb 2>/dev/null)
  [ -n "$name" ] && echo "$name" || hostname -s
}

# Managers with the s3 service, in the order of redborder.managers_per_services.s3
s3_managers() {
  knife_cmd node show "$NODE" -a redborder.managers_per_services.s3 -F json |
    python3 -c 'import json,sys; d=json.load(sys.stdin); print("\n".join(list(d.values())[0]["redborder.managers_per_services.s3"] or []))'
}

sync_ip() {
  knife_cmd node show "$1" -a ipaddress_sync -F json |
    python3 -c 'import json,sys; d=json.load(sys.stdin); print(list(d.values())[0]["ipaddress_sync"] or "")'
}

# Writes $WORKDIR/creds.json (mode 600) with the S3 credentials of the data bags
write_creds() {
  local s3 malware
  s3=$(knife_cmd data bag show passwords s3 -F json --secret-file /etc/chef/encrypted_data_bag_secret) ||
    die "Cannot read the data bag passwords/s3"
  malware=$(knife_cmd data bag show rBglobal malware-bucket -F json) || malware='{}'
  (umask 077; python3 -c '
import json,sys
s3=json.loads(sys.argv[1]); mw=json.loads(sys.argv[2])
json.dump({"access_key": s3["s3_access_key_id"], "secret_key": s3["s3_secret_key_id"],
           "malware_access_key": mw.get("s3_malware_access_key_id"),
           "malware_secret_key": mw.get("s3_malware_secret_key_id")}, open(sys.argv[3], "w"))
' "$s3" "$malware" "$WORKDIR/creds.json")
}

masters_option() {
  # The masters are the first managers with s3 (1 with 1-2 managers, 3 with more)
  local count=1 ips=() m
  [ "${#MANAGERS[@]}" -ge 3 ] && count=3
  for m in "${MANAGERS[@]:0:$count}"; do ips+=("$(sync_ip "$m"):9333"); done
  (IFS=,; echo "${ips[*]}")
}

weed_shell() {
  printf '%s\n' "$@" | /usr/bin/weed shell -master="$(masters_option)" 2>&1
}

# Runtime and permanent: the dnf update of step 2 can reload firewalld. chef-client (the old
# cookbook-rb-firewall removes unknown ports) is stopped until step 4, and the new
# cookbook-rb-firewall keeps these ports
open_ports() {
  local p
  for p in "${WEED_PORTS[@]}"; do
    firewall-cmd -q --zone=home --add-port="$p/tcp" || true
    firewall-cmd -q --permanent --zone=home --add-port="$p/tcp" || true
  done
}

# ======================
# STEPS
# ======================

# Step 1: SeaweedFS in this manager with the cookbook seaweedfs, run by cinc-solo
prepare() {
  local ip json m

  echo "SeaweedFS will be installed and started in $NODE next to MinIO (MinIO keeps serving)."
  echo "chef-client is stopped until step 4 (systemctl start chef-client)."
  confirm "Continue?"

  log "INFO" "Preparing SeaweedFS on $NODE (S3 managers: ${MANAGERS[*]})"
  systemctl stop chef-client || true

  # Only new packages: nothing is removed
  LANG=C dnf -y install redborder-seaweedfs cookbook-seaweedfs 2>&1 | tee -a "$LOG_FILE"
  [ -d /var/chef/cookbooks/seaweedfs ] || die "/var/chef/cookbooks/seaweedfs not found"

  # The current cookbook-rb-firewall does not know the SeaweedFS ports
  open_ports

  mkdir -p "$WORKDIR/cookbooks/rb_migrate_seaweedfs/recipes"
  chmod 700 "$WORKDIR"
  write_creds

  cat > "$WORKDIR/cookbooks/rb_migrate_seaweedfs/metadata.rb" <<'EOF'
name 'rb_migrate_seaweedfs'
version '1.0.0'
depends 'seaweedfs'
EOF
  cat > "$WORKDIR/cookbooks/rb_migrate_seaweedfs/recipes/default.rb" <<'EOF'
require 'json'
creds = JSON.parse(File.read('/var/lib/rb_migrate_to_seaweedfs/creds.json'))
attrs = node['rb_migrate_seaweedfs']

seaweedfs_config 'Configure S3 (seaweedfs)' do
  ipaddress attrs['ipaddress']
  managers_with_s3 attrs['managers']
  cluster_info attrs['cluster_info'].to_hash
  access_key_id creds['access_key']
  secret_key_id creds['secret_key']
  malware_access_key_id creds['malware_access_key'] if creds['malware_access_key']
  malware_secret_key_id creds['malware_secret_key'] if creds['malware_secret_key']
  action :add
end
EOF
  cat > "$WORKDIR/solo.rb" <<EOF
cookbook_path ['/var/chef/cookbooks', '$WORKDIR/cookbooks']
file_cache_path '$WORKDIR/cache'
node_path '$WORKDIR/nodes'
log_level :info
log_location STDOUT
EOF

  json="{\"rb_migrate_seaweedfs\": {\"ipaddress\": \"$IP\", \"managers\": ["
  for m in "${MANAGERS[@]}"; do json="$json\"$m\","; done
  json="${json%,}], \"cluster_info\": {"
  for m in "${MANAGERS[@]}"; do
    ip=$(sync_ip "$m")
    [ -n "$ip" ] || die "Cannot get the ipaddress_sync of $m"
    json="$json\"$m\": {\"ipaddress_sync\": \"$ip\"},"
  done
  json="${json%,}}}, \"run_list\": [\"recipe[rb_migrate_seaweedfs]\"]}"
  echo "$json" > "$WORKDIR/attributes.json"

  log "INFO" "Configuring SeaweedFS with cinc-solo (output in $LOG_FILE)"
  if ! /opt/cinc-workstation/bin/cinc-solo -c "$WORKDIR/solo.rb" -j "$WORKDIR/attributes.json" --no-color >> "$LOG_FILE" 2>&1; then
    die "cinc-solo failed (details in $LOG_FILE)"
  fi

  wait_s3 "$IP"
  log "INFO" "SeaweedFS is running on $NODE. Next: --prepare in the other S3 managers, then step 2"
}

wait_s3() {
  local count=0 code
  while [ $count -lt 60 ]; do
    code=$(curl -s -o /dev/null -w '%{http_code}' "http://$1:$S3_PORT/" || true)
    [ "$code" != "000" ] && return 0
    count=$((count + 1))
    sleep 2
  done
  die "The SeaweedFS S3 gateway is not answering in $1:$S3_PORT"
}

# Every S3 manager must have its volume server in the cluster before copying: with more
# than one, every object is written in two of them
wait_volume_servers() {
  local count=0 servers
  while [ $count -lt 30 ]; do
    servers=$(weed_shell volume.list | grep -cE '^\s+DataNode .*hdd' || true)
    [ "$servers" -ge "${#MANAGERS[@]}" ] && return 0
    count=$((count + 1))
    sleep 5
  done
  die "Only $servers of ${#MANAGERS[@]} SeaweedFS volume servers are in the cluster: run --prepare in every S3 manager (it also opens the SeaweedFS ports in the firewall)"
}

# Copies every bucket from the local MinIO to SeaweedFS (objects missing or with a different
# size). Prints the objects and bytes of each bucket in both.
#   copy_buckets mirror : also deletes from SeaweedFS the objects that are not in MinIO (only
#                         before the consumers use SeaweedFS, step 3)
#   copy_buckets missing: only copies the objects that are not in SeaweedFS, it never overwrites
#                         one (after step 4 the consumers write in SeaweedFS)
copy_buckets() {
  local mode="${1:-copy}"
  systemctl is-active --quiet minio || die "MinIO is not running in $NODE"
  [ -f "$WORKDIR/creds.json" ] || write_creds
  wait_s3 "$IP"
  wait_volume_servers

  cat > "$WORKDIR/s3_copy.rb" <<'EOF'
require 'aws-sdk-s3'
require 'json'
require 'tempfile'

src_endpoint, dst_endpoint, creds_file, mode = ARGV
creds = JSON.parse(File.read(creds_file))
opts = { region: 'us-east-1', force_path_style: true,
         access_key_id: creds['access_key'], secret_access_key: creds['secret_key'] }
src = Aws::S3::Client.new(**opts, endpoint: src_endpoint)
dst = Aws::S3::Client.new(**opts, endpoint: dst_endpoint)
# TransferManager replaces Aws::S3::Object#upload_file in the newer aws-sdk-s3 (multipart > 100MB)
transfer = defined?(Aws::S3::TransferManager) ? Aws::S3::TransferManager.new(client: dst) : nil

def objects(client, bucket)
  list = {}
  client.list_objects_v2(bucket: bucket).each { |page| page.contents.each { |o| list[o.key] = o.size } }
  list
end

failed = 0
src.list_buckets.buckets.each do |b|
  begin
    dst.head_bucket(bucket: b.name)
  rescue Aws::S3::Errors::NotFound, Aws::S3::Errors::NoSuchBucket
    dst.create_bucket(bucket: b.name)
  end
  existing = objects(dst, b.name)
  source = objects(src, b.name)
  copied = deleted = 0
  # Deleted from MinIO since the last copy (old cookbook checksums, cleaned Druid segments...)
  if mode == 'mirror'
    (existing.keys - source.keys).each_slice(1000) do |keys|
      dst.delete_objects(bucket: b.name, delete: { objects: keys.map { |k| { key: k } } })
      deleted += keys.size
    end
  end
  source.each do |key, size|
    next if existing[key] == size
    next if mode == 'missing' && existing.key?(key)

    Tempfile.create('s3copy', '/var/tmp') do |tmp|
      resp = src.get_object(bucket: b.name, key: key, response_target: tmp.path)
      upload = { content_type: resp.content_type }.compact
      if transfer
        transfer.upload_file(tmp.path, bucket: b.name, key: key, **upload)
      else
        Aws::S3::Object.new(b.name, key, client: dst).upload_file(tmp.path, **upload)
      end
    end
    copied += 1
  rescue StandardError => e
    failed += 1
    warn "FAILED #{b.name}/#{key}: #{e.message}"
  end
  s = objects(src, b.name)
  d = objects(dst, b.name)
  missing = mode == 'missing' ? s.count { |k, _| !d.key?(k) } : s.count { |k, v| d[k] != v }
  puts format('%-12s copied %6d deleted %6d | MinIO %7d objects %14d bytes | SeaweedFS %7d objects %14d bytes | missing %d',
              b.name, copied, deleted, s.size, s.values.sum, d.size, d.values.sum, missing)
  failed += missing
end
exit(failed.zero? ? 0 : 1)
EOF

  log "INFO" "Copying the buckets from MinIO ($MINIO_ENDPOINT) to SeaweedFS (http://$IP:$S3_PORT)"
  set +e
  bash -c "source /etc/profile.d/rvm.sh; rvm gemset use web &>/dev/null; ruby '$WORKDIR/s3_copy.rb' '$MINIO_ENDPOINT' 'http://$IP:$S3_PORT' '$WORKDIR/creds.json' '$mode'" 2>&1 | tee -a "$LOG_FILE"
  local ret=${PIPESTATUS[0]}
  set -e
  [ "$ret" -eq 0 ] || die "Some objects were not copied (details above and in $LOG_FILE). Run $SCRIPT --copy again"
  log "INFO" "Every object of MinIO is in SeaweedFS"
}

copy() {
  echo "Every bucket of MinIO in $NODE will be copied to SeaweedFS (MinIO is not changed)."
  confirm "Continue?"
  copy_buckets mirror
  log "INFO" "Next: systemctl start chef-client in every manager (step 4), then --finish"
}

# Step 5: last copy, then MinIO is stopped and removed from this manager
finish() {
  local ret

  if ! systemctl is-active --quiet chef-client; then
    die "chef-client is not running: start it in every manager first (step 4)"
  fi
  if [ -f /etc/nginx/conf.d/s3.conf ] && grep -qE ':9000;|:9000 ' /etc/nginx/conf.d/s3.conf; then
    die "nginx still sends S3 to MinIO (:9000). Wait for chef-client with the new cookbooks (step 4)"
  fi

  echo "The last changes of MinIO will be copied to SeaweedFS, then MinIO is stopped and removed from $NODE."
  confirm "Continue?"

  if systemctl is-active --quiet minio; then
    copy_buckets missing
    systemctl stop minio
  fi
  systemctl disable minio &>/dev/null || true

  # Only these packages: dnf fails instead of removing anything else
  local pkgs=() p
  for p in minio mcli cookbook-minio; do is_installed "$p" && pkgs+=("$p"); done
  if [ "${#pkgs[@]}" -gt 0 ]; then
    set +e
    LANG=C dnf -y --setopt=protected_packages=dnf,redborder-manager,redborder-common,redborder-cookbooks,redborder-seaweedfs \
      --setopt=clean_requirements_on_remove=False remove "${pkgs[@]}" 2>&1 | tee -a "$LOG_FILE"
    ret=${PIPESTATUS[0]}
    set -e
    [ "$ret" -eq 0 ] || log "WARN" "dnf remove ${pkgs[*]} failed (details in $LOG_FILE)"
  fi

  # The minio package created the user minio with a login shell: dnf remove does not delete it
  if getent passwd minio &>/dev/null; then
    userdel minio && log "INFO" "User minio removed" || log "WARN" "The user minio could not be removed"
  fi

  rm -f "$WORKDIR/creds.json" /root/.mcli/config.json
  log "INFO" "MinIO removed from $NODE. Its data is kept in /var/minio/data: remove it when everything works"
}

# ======================
# MAIN
# ======================

while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes) ASSUME_YES=true ;;
    --prepare) ACTION=prepare ;;
    --copy) ACTION=copy ;;
    --finish) ACTION=finish ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
  shift
done

[ -n "$ACTION" ] || { usage; exit 1; }
[ "$(id -u)" -eq 0 ] || die "This script must be run as root"
is_installed redborder-manager || die "This script only runs in managers"

NODE=$(node_name)
mapfile -t MANAGERS < <(s3_managers)
[ "${#MANAGERS[@]}" -gt 0 ] || die "Cannot get redborder.managers_per_services.s3 of $NODE with knife"
[[ " ${MANAGERS[*]} " == *" $NODE "* ]] || die "$NODE does not have the s3 service (S3 managers: ${MANAGERS[*]})"
IP=$(sync_ip "$NODE")
[ -n "$IP" ] || die "Cannot get the ipaddress_sync of $NODE"

"$ACTION"
exit 0
