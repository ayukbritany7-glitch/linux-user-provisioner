# Linux User Provisioning and Offboarding Automation Engine

A robust, production-ready Bash automation tool designed for system administrators to securely streamline employee onboarding and offboarding lifecycle events using structured data (`.csv`).

## 🚀 Key Features
- **Bulk Ingestion:** Efficiently parses CSV arrays to handle hundreds of concurrent user requests.
- **Role-Based Access Control (RBAC):** Dynamically provisions local Linux groups mapped to internal department assignments.
- **Secure Onboarding defaults:** Automates temporary password generation and enforces immediate credential rotation on first user authentication (`chage -d 0`).
- **Graceful Offboarding:** Instantly terminates all active, orphan system processes owned by a departed user before modifying permissions.
- **Data Lifecycle Management:** Bundles and archives user home profiles into compressed standard backups (`.tar.gz`) stored securely in `/var/user_backups/`.
- **System Hardening:** Mitigates access risk by replacing the login shell of offboarded accounts with `/usr/sbin/nologin` and locking the password matrix rather than direct, volatile system deletions.

## 📁 Repository Structure
```text
linux-user-provisioner/
├── README.md           # Technical documentation
├── usermanager.sh      # Core automation engine (Bash executable)
├── employees.csv       # Sample testing configuration file
└── skeleton/           # Custom system assets
    └── .welcome_msg    # Interactive environment banner for new hires
```

## 🛠️ Installation & Setup

1. Clone this repository down to your staging environment:
   ```bash
   git clone https://github.com
   cd linux-user-provisioner
   ```

2. Grant execute permissions to the core automation engine:
   ```bash
   chmod +x usermanager.sh
   ```

## 💻 Usage & Verification

Execute the engine with root privileges by supplying the targeted configuration path flag:
```bash
sudo ./usermanager.sh --file employees.csv
```

### Verification Checks

Confirm account creations and group assignments:
```bash
id jdoe
```

Confirm targeted user session terminations and secure isolation:
```bash
getent passwd rjones
ls -l /var/user_backups/
```

