#!/bin/bash
# coolify-vps-setup.sh - Modular, Interactive & Secured (Optimized with clamdscan)

set -euo pipefail

# --- 0. ROOT CHECK ---
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root. Try: sudo ./coolify-vps-setup.sh"
   exit 1
fi

# --- HELPER FUNCTIONS ---
get_input() {
    local prompt=$1
    local default=$2
    read -p "$prompt [$default]: " val
    echo "${val:-$default}"
}

confirm() {
    local prompt=$1
    read -p "$prompt (y/n): " res
    [[ "$res" == "y" ]]
}

# --- 1. SWAP CONFIGURATION ---
setup_swap() {
    if confirm "Do you want to configure a Swap file?"; then
        local swap_size=$(get_input "How much Swap? (e.g., 2G, 4G)" "2G")
        if [ -f /swapfile ]; then
            echo "✅ Swapfile already exists. Skipping."
        else
            echo "--- Creating $swap_size Swap File ---"
            sudo fallocate -l "$swap_size" /swapfile
            sudo chmod 600 /swapfile
            sudo mkswap /swapfile
            sudo swapon /swapfile
            echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
            sudo sysctl vm.swappiness=10
            echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
            echo "✅ $swap_size Swap enabled."
        fi
    fi
}

# --- 2. FIREWALL & BRUTE-FORCE SECURITY ---
setup_ufw_docker() {
    echo "--- Configuring UFW, ufw-docker & Fail2ban ---"
    sudo apt update && sudo apt install -y ufw wget fail2ban
    
    # Install ufw-docker patch
    sudo wget -O /usr/local/bin/ufw-docker https://github.com/chaifeng/ufw-docker/raw/master/ufw-docker
    sudo chmod +x /usr/local/bin/ufw-docker
    sudo ufw-docker install
    
    # Configure Fail2ban for SSH (Bantime: 24h, Retries: 3)
    sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
    sudo sed -i 's/^bantime  = 10m/bantime  = 24h/' /etc/fail2ban/jail.local
    sudo sed -i 's/^maxretry = 5/maxretry = 3/' /etc/fail2ban/jail.local
    sudo systemctl restart fail2ban

    # Strict Default Policies
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    
    # Allow Essential Ports
    sudo ufw allow 22/tcp      # SSH
    sudo ufw allow 80/tcp      # HTTP
    sudo ufw allow 443/tcp     # HTTPS
    sudo ufw allow 8000/tcp    # Coolify UI
    sudo ufw allow 6001/tcp    # Coolify Real-time
    sudo ufw allow 6002/tcp    # Coolify Terminal
    
    sudo ufw --force enable
    echo "✅ Firewall and Fail2ban secured."
}

# --- 3. MAINTENANCE & OPTIMIZED CLAMAV ---
setup_maintenance_cron() {
    echo "--- Configuring Maintenance & Cron Jobs ---"
    
    local clam_cmd=""

    if confirm "Do you want to install ClamAV for malware scanning?"; then
        sudo apt install -y clamav clamav-daemon
        
        # Proper ClamAV Initialization (Standard Fix for locked databases)
        echo "   -> Updating ClamAV signatures..."
        sudo systemctl stop clamav-freshclam || true
        sudo freshclam
        sudo systemctl start clamav-freshclam
        
        # Ensure the daemon is enabled and running for clamdscan to work
        sudo systemctl enable clamav-daemon
        sudo systemctl start clamav-daemon

        local freq_choice=$(get_input "ClamAV Frequency? 1) Daily 2) Weekly" "1")
        local clam_cron="0 3 * * *"
        [[ "$freq_choice" == "2" ]] && clam_cron="0 3 * * 1"
        
        # OPTIMIZED: Using clamdscan for better performance via the daemon
        clam_cmd="$clam_cron /usr/bin/clamdscan --fdpass -r / --exclude-dir='^/sys|^/proc|^/dev|^/var/lib/docker' -i --log=/var/log/clamav/daily_scan.log"
        echo "✅ ClamAV scheduled with clamdscan optimization."
    fi

    # Unattended Upgrades for Security Kernel Patches
    echo "--- Configuring Unattended Upgrades ---"
    sudo apt install -y unattended-upgrades update-notifier-common
    sudo dpkg-reconfigure -f noninteractive unattended-upgrades
    sudo sed -i 's#//Unattended-Upgrade::Automatic-Reboot "false";#Unattended-Upgrade::Automatic-Reboot "true";#' /etc/apt/apt.conf.d/50unattended-upgrades
    sudo sed -i 's#//Unattended-Upgrade::Automatic-Reboot-Time "02:00";#Unattended-Upgrade::Automatic-Reboot-Time "05:00";#' /etc/apt/apt.conf.d/50unattended-upgrades

    # CRON MARKER LOGIC (Duplicate Protection)
    CRON_MARKER="# EXPERT-VPS-SETUP"
    tmpfile=$(mktemp)
    crontab -l 2>/dev/null | grep -v "$CRON_MARKER" > "$tmpfile" || true

    {
        echo "$CRON_MARKER"
        [ -n "$clam_cmd" ] && echo "$clam_cmd"
        # Weekly Full Upgrade/Cleanup (Monday 03:00 AM)
        echo "0 3 * * 1 sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y && sudo apt clean"
        # Weekly Conditional Reboot (Monday 04:00 AM)
        echo "0 4 * * 1 sudo bash -c '[ -f /var/run/reboot-required ] && reboot'"
    } >> "$tmpfile"

    crontab "$tmpfile"
    rm -f "$tmpfile"
    echo "✅ Maintenance cron jobs applied."
}

# --- MAIN EXECUTION ---
echo "--- Welcome to the Coolify VPS Wizard ---"
setup_swap
setup_ufw_docker
setup_maintenance_cron

if confirm "Install Coolify now?"; then
    curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash
fi

echo "--- Setup Finished! Rebooting in 10 seconds ---"
sleep 10
sudo reboot
