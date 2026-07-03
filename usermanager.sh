#!/bin/bash

# Ensure the script is run with root/sudo privileges
if [ "$EUID" -ne 0 ]; then
    echo "[-] Error: This script must be run as root (sudo)." >&2
    exit 1
fi

# Print instructions if the user doesn't pass a file flag
log_usage() {
    echo "Usage: $0 --file <path_to_csv>"
    exit 1
}

# Parse command line flags (--file)
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -f|--file) CSV_FILE="$2"; shift ;;
        *) echo "Unknown parameter: $1"; log_usage ;;
    esac
    shift
done

# Stop the script if no valid CSV file was provided
if [ -z "$CSV_FILE" ] || [ ! -f "$CSV_FILE" ]; then
    echo "[-] Error: Valid CSV file path is required."
    log_usage
fi

# FUNCTION: How to onboard a user
onboard_user() {
    local username=$1
    local dept=$2
    local default_password="TempPassword123!"

    echo "[*] Processing ONBOARDING for user: $username ($dept)"

    # 1. Create the department group if it doesn't exist
    if ! getent group "$dept" > /dev/null 2>&1; then
        groupadd "$dept"
        echo "  + Created new department group: $dept"
    fi

    # 2. Skip user creation if they already exist
    if id "$username" > /dev/null 2>&1; then
        echo "  [!] User $username already exists. Skipping creation."
        return
    fi

    # 3. Create the user with a home directory, bash shell, and department group
    useradd -m -s /bin/bash -G "$dept" "$username"
    
    # 4. Set temporary password and force change on their very first login
    echo "$username:$default_password" | chpasswd
    chage -d 0 "$username"

    # 5. Copy our custom welcome message to their home folder
    if [ -f "./skeleton/.welcome_msg" ]; then
        cp ./skeleton/.welcome_msg "/home/$username/"
        echo "cat ~/ .welcome_msg" >> "/home/$username/.bashrc"
        chown "$username:$username" "/home/$username/.welcome_msg"
    fi

    echo "[+] Successfully onboarded $username."
}

# FUNCTION: How to offboard a user
offboard_user() {
    local username=$1
    local backup_dir="/var/user_backups"

    echo "[*] Processing OFFBOARDING for user: $username"

    # Skip if the user doesn't exist to begin with
    if ! id "$username" > /dev/null 2>&1; then
        echo "  [!] User $username does not exist. Skipping removal."
        return
    fi

    # 1. Instantly kick the user offline and kill their active sessions
    echo "  - Terminating active user processes..."
    pkill -u "$username" 2>/dev/null
    sleep 1

    # 2. Compress and archive their home folder data safely into /var/user_backups
    mkdir -p "$backup_dir"
    if [ -d "/home/$username" ]; then
        echo "  - Archiving home directory to $backup_dir..."
        tar -czf "$backup_dir/${username}_backup_$(date +%F).tar.gz" -C /home "$username" 2>/dev/null
    fi

    # 3. Securely lock the account and disable login access
    usermod -s /usr/sbin/nologin -L "$username"
    
    echo "[+] Successfully offboarded and locked $username."
}

# ==============================================================================
# Main execution: Read the CSV line-by-line
# ==============================================================================
tail -n +2 "$CSV_FILE" | while IFS=, read -r username department action || [ -n "$username" ]; do
    # Remove hidden invisible spacing characters from Windows/macOS line endings
    username=$(echo "$username" | tr -d '\r\n ' )
    department=$(echo "$department" | tr -d '\r\n ' )
    action=$(echo "$action" | tr -d '\r\n ' )

    if [ -z "$username" ]; then continue; fi

    # Direct the script flow based on the 'action' column
    if [ "$action" == "onboard" ]; then
        onboard_user "$username" "$department"
    elif [ "$action" == "offboard" ]; then
        offboard_user "$username"
    else
        echo "[-] Unknown action '$action' for user $username. Skipping."
    fi
    echo "------------------------------------------------"
done

