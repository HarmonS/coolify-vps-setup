# coolify-vps-setup
Interactive, modular Ubuntu VPS hardening script optimized for Coolify, featuring UFW-Docker, ClamAV, and automated maintenance.

# 🚀 Coolify VPS Setup

An interactive, modular shell script to harden and prepare a fresh Ubuntu VPS for [Coolify](https://coolify.io). This script automates security best practices that Coolify doesn't handle by default, such as deep system hardening and automated malware scanning.

## ✨ Features
- **Modular Design:** Run specific tasks (Swap, Firewall, Maintenance) or a full setup.
- **Firewall Hardening:** Integrates `ufw-docker` to prevent Docker from bypassing your UFW rules.
- **Automated Security:** Configures `unattended-upgrades` for critical security patches.
- **Malware Protection:** Nightly ClamAV scans optimized to skip heavy Docker directories.
- **Customizable Swap:** Interactive prompt to set swap size based on your VPS RAM.
- **Maintenance:** Weekly cleanup (Monday 3 AM) and conditional reboots for kernel updates.

## 🛠️ Quick Start
1. **Connect to your fresh VPS as root:**
   ```bash
   ssh root@your-server-ip

⚙️ Configuration Options
During the interactive wizard, you can configure:
Swap Size: Recommended 2G for most 1-2GB RAM VPS instances.
ClamAV Frequency: Choose between Daily or Weekly scans.
Coolify Installation: Option to trigger the official Coolify installer at the end.

⚠️ Important Note on Permissions
This script does not automatically manage application folder permissions. After uploading your files via SFTP, remember to run: sudo chown -R 1000:1000 /path/to/your/app

📄 License
This project is licensed under the MIT License - see the LICENSE file for details.
