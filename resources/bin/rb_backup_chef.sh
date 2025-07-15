#!/bin/bash

set -euo pipefail

# Default variables
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
DEFAULT_BACKUP_DIR="/var/chef"
BACKUP_DIR="$DEFAULT_BACKUP_DIR"
IMPORT_FILE=""
MODE=""
NODES_ONLY=false
ROLES_ONLY=false
INCLUDE_ENVIRONMENTS=false
FILENAME=""
SCRIPT=$(basename "$0")

# Function for printing logs with timestamp and level (INFO, ERROR, ...)
log() {
  local level="$1"
  local msg="$2"
  echo "[$level] $(date '+%Y-%m-%d %H:%M:%S') - $msg"
}

# Displays help and examples of useClick to apply
usage() {
  echo "Chef Backup"
  echo ""
  echo "Usage:"
  echo "  $SCRIPT -e [options]"
  echo "  $SCRIPT -i <file> [options]"
  echo ""
  echo "Options:"
  echo "  -e, --export              Export Chef data"
  echo "  -i, --import <file>       Import data from JSON file"
  echo "  -d, --directory <dir>     Backup output/input directory (default: $DEFAULT_BACKUP_DIR)"
  echo "  -f, --file <name>         Name of the file to backup (timestamp will be appended)"
  echo "  -n, --nodes-only          Only export/import nodes"
  echo "  -r, --roles-only          Only export/import roles"
  echo "  -E, --environments        Include environments (Chef environments)"
  echo "  -h, --help                Show this help"
  echo ""
  echo "Examples:"
  echo "  $SCRIPT -e                          # Export all data (nodes, roles)"
  echo "  $SCRIPT -e -n                       # Export only nodes"
  echo "  $SCRIPT -e -r                       # Export only roles"
  echo "  $SCRIPT -e -n -E                    # Export only nodes and include environments"
  echo "  $SCRIPT -e -d /backup/chef          # Export to specific directory"
  echo "  $SCRIPT -e -f backup                # Export using filename 'backup_<timestamp>.json'"
  echo "  $SCRIPT -i backup_20250715.json     # Import all data from the given backup file"
  echo "  $SCRIPT -i backup.json -r           # Import only roles from backup.json"
  echo "  $SCRIPT -i backup.json -n           # Import only nodes from backup.json"
  echo "  $SCRIPT -i backup.json -E           # Include environments in the import"
  exit 1
}

# Verify that required dependencies are available (knife and jq)
check_dependencies() {
  if ! command -v knife >/dev/null 2>&1; then
    log "ERROR" "knife not found in PATH. Install Chef Workstation."
    exit 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    log "ERROR" "jq not found. Please install jq for JSON handling."
    exit 1
  fi
}

# Processes command-line arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -e|--export) MODE="export"; shift ;;
      -i|--import) MODE="import"; IMPORT_FILE="$2"; shift 2 ;;
      -d|--directory) BACKUP_DIR="$2"; shift 2 ;;
      -n|--nodes-only) NODES_ONLY=true; shift ;;
      -r|--roles-only) ROLES_ONLY=true; shift ;;
      -E|--environments) INCLUDE_ENVIRONMENTS=true; shift ;;
      -f|--file) FILENAME="$2"; shift 2 ;;
      -h|--help) usage ;;
      *) echo "Unknown option: $1"; usage ;;
    esac
  done

  if [[ -z "$MODE" ]]; then
    log "ERROR" "Specify --export (-e) or --import (-i <file>)"
    usage
  fi
}

# Function to export Chef data to a JSON file
export_data() {
  mkdir -p "$BACKUP_DIR"

  if [[ -n "$FILENAME" ]]; then
    BACKUP_FILE="$BACKUP_DIR/${FILENAME}_$TIMESTAMP.json"
  else
    BACKUP_FILE="$BACKUP_DIR/backup_chef_$TIMESTAMP.json"
  fi

  log "INFO" "Exporting Chef data to $BACKUP_FILE"

 # Generate backup metadata
  metadata=$(jq -n \
    --arg timestamp "$TIMESTAMP" \
    --arg created_at "$(date -Iseconds)" \
    --arg hostname "$(hostname)" \
    --arg user "$USER" \
    '{timestamp: $timestamp, created_at: $created_at, hostname: $hostname, user: $user}'
  )

  # Write JSON header and metadata
  echo '{' > "$BACKUP_FILE"
  echo "  \"metadata\": $metadata," >> "$BACKUP_FILE"

  # Export nodes if --roles-only is not activated
  if [[ "$ROLES_ONLY" = false ]]; then
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

  # Export roles if --nodes-only is not enabled
  if [[ "$NODES_ONLY" = false ]]; then
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

  # Exports environments if --environments is activated
  if [[ "$INCLUDE_ENVIRONMENTS" = true ]]; then
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
    sed -i '$ s/,$//' "$BACKUP_FILE"
  fi

  echo "}" >> "$BACKUP_FILE"
  log "INFO" "Backup complete."
}

# Function to import data from a JSON file to Chef
import_data() {
  if [[ ! -f "$IMPORT_FILE" ]]; then
    log "ERROR" "File not found: $IMPORT_FILE"
    exit 1
  fi

  echo -n "Confirm import? This may overwrite existing Chef data (yes/no): "
  read -r confirm
  [[ "$confirm" =~ ^(yes|y)$ ]] || { echo "Aborted."; exit 0; }

  tmp_dir=$(mktemp -d)

  # Import nodes
  if [[ "$ROLES_ONLY" = false ]]; then
    log "INFO" "Importing nodes..."
    jq -r '.nodes | to_entries[] | "\(.key)\n\(.value|tojson)"' "$IMPORT_FILE" | while read -r name && read -r json; do
      file="$tmp_dir/node_$name.json"
      echo "$json" > "$file"
      knife node from file "$file"
    done
  fi

  # Import roles
  if [[ "$NODES_ONLY" = false ]]; then
    log "INFO" "Importing roles..."
    jq -r '.roles | to_entries[] | "\(.key)\n\(.value|tojson)"' "$IMPORT_FILE" | while read -r name && read -r json; do
      file="$tmp_dir/role_$name.json"
      echo "$json" > "$file"
      knife role from file "$file"
    done
  fi

  # Import environments
  if [[ "$INCLUDE_ENVIRONMENTS" = true ]]; then
    log "INFO" "Importing environments..."
    jq -r '.environments | to_entries[] | "\(.key)\n\(.value|tojson)"' "$IMPORT_FILE" | while read -r name && read -r json; do
      file="$tmp_dir/env_$name.json"
      echo "$json" > "$file"
      knife environment from file "$file"
    done
  fi

  rm -rf "$tmp_dir"
  log "INFO" "Import complete."
}

### Main
parse_args "$@"
check_dependencies

if [[ "$MODE" == "export" ]]; then
  export_data
elif [[ "$MODE" == "import" ]]; then
  import_data
fi
