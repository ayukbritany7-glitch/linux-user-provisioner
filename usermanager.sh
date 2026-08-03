#!/usr/bin/env bash

# Linux User Provisioner - hardened and professionalized
# - strict mode
# - safe CSV parsing
# - dry-run and confirmation flags
# - secure temporary password generation (written to restricted file)
# - idempotent operations

set -euo pipefail
IFS=$'\n\t'

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CSV_FILE=""
DRY_RUN=0
ASSUME_YES=0
REMOVE_ON_DELETE=0
BACKUP_DIR="/var/user_backups"
CREDENTIALS_LOG="${BACKUP_DIR}/new_user_credentials_$(date +%F_%H%M%S).txt"
WELCOME_SRC="$REPO_ROOT/skeleton/.welcome_msg"

log() { printf "[+] %s\n" "$*"; }
err() { printf "[-] %s\n" "$*" >&2; }
die() { err "$*"; exit 1; }

usage() {
    cat <<EOF
Usage: $0 --file <path_to_csv> [--dry-run] [--yes] [--remove]

Options:
  -f, --file <file>     Path to CSV file (header: username,department,action)
      --dry-run         Show what would be done without making changes
      --yes              Run non-interactively (assume yes for destructive actions)
      --remove           When offboarding, remove account after backup (must be explicit)
      --help             Show this help and exit

Examples:
  sudo $0 --file employees.csv
  sudo $0 --file employees.csv --dry-run
  sudo $0 --file employees.csv --yes --remove
EOF
    exit 1
}

# Simple argument parser for long options
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--file)
            CSV_FILE="$2"; shift 2 ;;
        --dry-run)
            DRY_RUN=1; shift ;;
        --yes)
            ASSUME_YES=1; shift ;;
        --remove)
            REMOVE_ON_DELETE=1; shift ;;
        --help)
            usage; shift ;;
        *)
            err "Unknown option: $1"; usage ;;
    esac
done

# Must run as root
if [[ $(id -u) -ne 0 ]]; then
    die "This script must be run as root (sudo)."
fi

if [[ -z "$CSV_FILE" || ! -f "$CSV_FILE" ]]; then
    err "Valid CSV file path is required."
    usage
fi

# Ensure backup directory exists (or simulate in dry-run)
if [[ $DRY_RUN -eq 0 ]]; then
    mkdir -p -- "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR" || true
fi

# Create credentials log header (only in non-dry-run)
if [[ $DRY_RUN -eq 0 ]]; then
    printf "New user credentials generated on %s\n\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$CREDENTIALS_LOG"
    chmod 600 "$CREDENTIALS_LOG" || true
fi

# Generate a secure password (openssl or /dev/urandom fallback)
generate_password() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 18
    else
        tr -dc 'A-Za-z0-9!@#$%&*()-_=+' < /dev/urandom | head -c 20 || echo 'TempPass123!'
    fi
}

# Onboard user: create group, create user, set password, copy welcome message
onboard_user() {
    local username=$1
    local dept=$2

    log "Processing ONBOARDING for user: $username (dept: $dept)"

    # Create department group if absent
    if ! getent group "$dept" >/dev/null 2>&1; then
        if [[ $DRY_RUN -eq 1 ]]; then
            log "[dry-run] Would create group: $dept"
        else
            groupadd -- "$dept"
            log "Created group: $dept"
        fi
    fi

    # If user exists, skip creation
    if id "$username" >/dev/null 2>&1; then
        log "User $username already exists. Ensuring group membership and skipping creation."
        if [[ $DRY_RUN -eq 0 ]]; then
            usermod -a -G "$dept" "$username" || true
        fi
        return
    fi

    # Create the user
    if [[ $DRY_RUN -eq 1 ]]; then
        log "[dry-run] Would create user: $username (home: /home/$username, shell: /bin/bash)"
    else
        useradd -m -s /bin/bash -G "$dept" -- "$username"
        log "Created user: $username"
    fi

    # Generate and set a secure temporary password
    local password
    password=$(generate_password)

    if [[ $DRY_RUN -eq 1 ]]; then
        log "[dry-run] Would set temporary password for $username"
    else
        echo "$username:$password" | chpasswd
        chage -d 0 "$username" || true

        # Save credential in restricted log
        printf "Username: %s\nPassword: %s\n---\n" "$username" "$password" >> "$CREDENTIALS_LOG"
        chmod 600 "$CREDENTIALS_LOG" || true
        log "Wrote temporary credential for $username to $CREDENTIALS_LOG"
    fi

    # Copy welcome message (if present)
    if [[ -f "$WELCOME_SRC" ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            log "[dry-run] Would copy welcome message to /home/$username/.welcome_msg and append display to .bashrc"
        else
            cp -- "$WELCOME_SRC" "/home/$username/.welcome_msg"
            chown "$username:$(id -gn "$username")" "/home/$username/.welcome_msg"
            chmod 644 "/home/$username/.welcome_msg"
            # Append display command safely if not already present
            if ! grep -qxF "cat ~/.welcome_msg" "/home/$username/.bashrc" 2>/dev/null; then
                echo "cat ~/.welcome_msg" >> "/home/$username/.bashrc"
                chown "$username:$(id -gn "$username")" "/home/$username/.bashrc"
            fi
            log "Copied welcome message for $username"
        fi
    fi

    log "Completed onboarding for $username"
}

# Offboard user: kill processes, archive home, lock or remove account
offboard_user() {
    local username=$1

    log "Processing OFFBOARDING for user: $username"

    if ! id "$username" >/dev/null 2>&1; then
        log "User $username does not exist. Skipping."
        return
    fi

    if [[ $ASSUME_YES -ne 1 ]]; then
        printf "Confirm offboard user '%s'? [y/N]: " "$username"
        read -r reply || true
        case "$reply" in
            [Yy]* ) ;;
            * ) log "Skipping $username"; return ;;
        esac
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log "[dry-run] Would terminate processes for $username"
    else
        pkill -u -- "$username" 2>/dev/null || true
        sleep 1
        log "Terminated processes for $username"
    fi

    # Archive home directory if present
    if [[ -d "/home/$username" ]]; then
        local archive_name="${username}_backup_$(date +%F_%H%M%S).tar.gz"
        if [[ $DRY_RUN -eq 1 ]]; then
            log "[dry-run] Would archive /home/$username to $BACKUP_DIR/$archive_name"
        else
            tar -czf "$BACKUP_DIR/$archive_name" -C /home "$username" >/dev/null 2>&1 || true
            chmod 600 "$BACKUP_DIR/$archive_name" || true
            log "Archived /home/$username to $BACKUP_DIR/$archive_name"
        fi
    fi

    # Lock account and set nologin shell
    if [[ $DRY_RUN -eq 1 ]]; then
        log "[dry-run] Would lock account and set nologin shell for $username"
    else
        usermod -s /usr/sbin/nologin -L -- "$username" || true
        log "Locked account and set shell to /usr/sbin/nologin for $username"
    fi

    # Optionally remove account entirely
    if [[ $REMOVE_ON_DELETE -eq 1 ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            log "[dry-run] Would remove user account $username and delete home"
        else
            userdel -r -- "$username" || true
            log "Removed user account $username and home directory"
        fi
    fi

    log "Completed offboarding for $username"
}

# Process CSV: skip header, read username,department,action
# Use awk to safely handle different line endings and preserve commas inside quoted fields is outside scope

tail -n +2 -- "$CSV_FILE" | while IFS=, read -r username department action || [[ -n "$username" ]]; do
    # Trim whitespace
    username=$(echo "$username" | tr -d '\r\n ')
    department=$(echo "$department" | tr -d '\r\n ')
    action=$(echo "$action" | tr -d '\r\n ')

    [[ -z "$username" ]] && continue

    case "$action" in
        onboard)
            onboard_user "$username" "$department" ;;
        offboard)
            offboard_user "$username" ;;
        *)
            err "Unknown action '$action' for user $username. Skipping." ;;
    esac
    printf "------------------------------------------------\n"
done

log "Run completed."
