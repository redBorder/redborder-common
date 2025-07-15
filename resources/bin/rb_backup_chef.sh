#!/bin/bash

set -euo pipefail

# ======================
# INITIAL CONFIGURATION
# ======================

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
DEFAULT_BACKUP_DIR="/var/chef"
BACKUP_DIR="$DEFAULT_BACKUP_DIR"
FILENAME=""
SCRIPT=$(basename "$0")

# Export flags
EXPORT_NODES=false
EXPORT_ROLES=false
EXPORT_ENVS=false

# ======================
# GENERAL FUNCTIONS
# ======================

log() {
  local level="$1"
  local msg="$2"
  echo "[$level] $(date '+%Y-%m-%d %H:%M:%S') - $msg"
}

usage() {
  echo "Chef Backup"
  echo ""
  echo "Usage:"
  echo "  $SCRIPT -e [options]"
  echo ""
  echo "Options:"
  echo "  -e, --export              Export Chef data"
  echo "  -d, --directory <dir>     Backup directory (default: $DEFAULT_BACKUP_DIR)"
  echo "  -f, --file <name>         Backup filename (timestamp will be appended)"
  echo "  -n, --nodes-only          Export nodes only"
  echo "  -r, --roles-only          Export roles only"
  echo "  -E, --environments        Export environments only"
  echo "  -h, --help                Show help"
  echo ""
  echo "Examples:"
  echo "  $SCRIPT -e                        # Export everything (nodes, roles, environments)"
  echo "  $SCRIPT -e -n                     # Export nodes only"
  echo "  $SCRIPT -e -r                     # Export roles only"
  echo "  $SCRIPT -e -E                     # Export environments only"
  echo "  $SCRIPT -e -d /backup/path        # Export to specific directory"
  echo "  $SCRIPT -e -f backupname          # Use filename backupname_<timestamp>.json"
  exit 1
}

check_dependencies() {
  if ! command -v knife >/dev/null 2>&1; then
    log "ERROR" "knife not found in PATH. Please install Chef Workstation."
    exit 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    log "ERROR" "jq not found. Please install jq for JSON handling."
    exit 1
  fi
}

# ========================
# ARGUMENT PARSER
# ========================

parse_args() {
  local MODE_SET=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -e|--export) MODE_SET=true; shift ;;
      -d|--directory) BACKUP_DIR="$2"; shift 2 ;;
      -n|--nodes-only) EXPORT_NODES=true; shift ;;
      -r|--roles-only) EXPORT_ROLES=true; shift ;;
      -E|--environments) EXPORT_ENVS=true; shift ;;
      -f|--file) FILENAME="$2"; shift 2 ;;
      -h|--help) usage ;;
      *) echo "Unknown option: $1"; usage ;;
    esac
  done

  if [[ "$MODE_SET" = false ]]; then
    log "ERROR" "You must specify --export (-e)"
    usage
  fi

  # If no filter specified, export all
  if [[ "$EXPORT_NODES" = false && "$EXPORT_ROLES" = false && "$EXPORT_ENVS" = false ]]; then
    EXPORT_NODES=true
    EXPORT_ROLES=true
    EXPORT_ENVS=true
  fi
}

# ===================
# EXPORT FUNCTIONS
# ===================

export_data() {
  mkdir -p "$BACKUP_DIR"

  if [[ -n "$FILENAME" ]]; then
    BACKUP_FILE="$BACKUP_DIR/${FILENAME}_$TIMESTAMP.json"
  else
    BACKUP_FILE="$BACKUP_DIR/backup_chef_$TIMESTAMP.json"
  fi

  log "INFO" "Exporting Chef data to $BACKUP_FILE"

  metadata=$(jq -n \
    --arg timestamp "$TIMESTAMP" \
    --arg created_at "$(date -Iseconds)" \
    --arg hostname "$(hostname)" \
    --arg user "$USER" \
    '{timestamp: $timestamp, created_at: $created_at, hostname: $hostname, user: $user}'
  )

  echo '{' > "$BACKUP_FILE"
  echo "  \"metadata\": $metadata," >> "$BACKUP_FILE"

  # ---- Export NODES ----
  if [[ "$EXPORT_NODES" = true ]]; then
    log "INFO" "Exporting nodes..."
    echo "  \"nodes\": {" >> "$BACKUP_FILE"
    first=true
    for node in $(knife node list 2>/dev/null | grep -vE '^(INFO|WARN|ERROR):'); do
      json=$(knife node show "$node" -F json 2>/dev/null | grep -vE '^(INFO|WARN|ERROR):')
      $first || echo "," >> "$BACKUP_FILE"
      echo -n "    \"$node\": $json" >> "$BACKUP_FILE"
      first=false
    done
    echo "" >> "$BACKUP_FILE"
    echo "  }," >> "$BACKUP_FILE"
  fi

  # ---- Export ROLES ----
  if [[ "$EXPORT_ROLES" = true ]]; then
    log "INFO" "Exporting roles..."
    echo "  \"roles\": {" >> "$BACKUP_FILE"
    first=true
    for role in $(knife role list 2>/dev/null | grep -vE '^(INFO|WARN|ERROR):'); do
      json=$(knife role show "$role" -F json 2>/dev/null | grep -vE '^(INFO|WARN|ERROR):')
      $first || echo "," >> "$BACKUP_FILE"
      echo -n "    \"$role\": $json" >> "$BACKUP_FILE"
      first=false
    done
    echo "" >> "$BACKUP_FILE"
    echo "  }," >> "$BACKUP_FILE"
  fi

  # ---- Export ENVIRONMENTS ----
  if [[ "$EXPORT_ENVS" = true ]]; then
    log "INFO" "Exporting environments..."
    echo "  \"environments\": {" >> "$BACKUP_FILE"
    first=true
    for env in $(knife environment list 2>/dev/null | grep -vE '^(INFO|WARN|ERROR):'); do
      json=$(knife environment show "$env" -F json 2>/dev/null | grep -vE '^(INFO|WARN|ERROR):')
      $first || echo "," >> "$BACKUP_FILE"
      echo -n "    \"$env\": $json" >> "$BACKUP_FILE"
      first=false
    done
    echo "" >> "$BACKUP_FILE"
    echo "  }" >> "$BACKUP_FILE"
  else
    # Remove trailing comma if no environments
    sed -i '$ s/,$//' "$BACKUP_FILE"
  fi

  echo "}" >> "$BACKUP_FILE"
  log "INFO" "Backup completed successfully."
}

# ==========
# MAIN
# ==========

parse_args "$@"
check_dependencies
export_data
