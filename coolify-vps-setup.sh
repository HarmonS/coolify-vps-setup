#!/bin/bash
# coolify-vps-setup.sh - Modular, Interactive & Secured

set -euo pipefail

# --- 0. ROOT CHECK ---
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root."
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
    if confirm "Do you want to configure Firewall & Fail2ban?"; then
        echo "--- Configuring UFW, ufw-docker & Fail2ban ---"
        sudo apt update && sudo apt install -y ufw wget fail2ban
        
        # 1. Set Policies & Enable UFW FIRST (Required for ufw-docker)
        sudo ufw default deny incoming
        sudo ufw default allow outgoing
        sudo ufw allow 22/tcp
        sudo ufw allow 80/tcp
        sudo ufw allow 443/tcp
        sudo ufw allow 8000/tcp
        sudo ufw allow 6001/tcp
        sudo ufw allow 6002/tcp
        sudo ufw --force enable

        # 2. Now install ufw-docker patch
        sudo wget -O /usr/local/bin/ufw-docker https://github.com/chaifeng/ufw-docker/raw/master/ufw-docker
        sudo chmod +x /usr/local/bin/ufw-docker
        sudo ufw-docker install
        
        # 3. Configure Fail2ban
        sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
        sudo sed -i 's/^bantime  = 10m/bantime  = 24h/' /etc/fail2ban/jail.local
        sudo sed -i 's/^maxretry = 5/maxretry = 3/' /etc/fail2ban/jail.local
        sudo systemctl restart fail2ban

        echo "✅ Firewall and Fail2ban secured."
    fi
}

# --- 3. MAINTENANCE & OPTIMIZED CLAMAV ---
setup_maintenance_cron() {
    echo "--- Configuring Maintenance & Cron Jobs ---"
    local clam_cmd=""

    if confirm "Do you want to install ClamAV for malware scanning?"; then
        sudo apt install -y clamav clamav-daemon
        echo "   -> Updating ClamAV signatures..."
        sudo systemctl stop clamav-freshclam || true
        sudo freshclam
        sudo systemctl start clamav-freshclam
        sudo systemctl enable clamav-daemon
        sudo systemctl start clamav-daemon

        local freq_choice=$(get_input "ClamAV Frequency? 1) Daily 2) Weekly" "1")
        local clam_cron="0 3 * * *"
        [[ "$freq_choice" == "2" ]] && clam_cron="0 3 * * 1"
        
        clam_cmd="$clam_cron /usr/bin/clamdscan --fdpass -r / --exclude-dir='^/sys|^/proc|^/dev|^/var/lib/docker' -i --log=/var/log/clamav/daily_scan.log"
        echo "✅ ClamAV scheduled."
    fi

    # Unattended Upgrades
    sudo apt install -y unattended-upgrades update-notifier-common
    sudo dpkg-reconfigure -f noninteractive unattended-upgrades

    # CRON MARKER LOGIC
    CRON_MARKER="# EXPERT-VPS-SETUP"
    tmpfile=$(mktemp)
    crontab -l 2>/dev/null | grep -v "$CRON_MARKER" > "$tmpfile" || true
    {
        echo "$CRON_MARKER"
        [ -n "$clam_cmd" ] && echo "$clam_cmd"
        echo "0 3 * * 1 sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y && sudo apt clean"
        echo "0 4 * * 1 sudo bash -c '[ -f /var/run/reboot-required ] && reboot'"
    } >> "$tmpfile"
    crontab "$tmpfile"
    rm -f "$tmpfile"
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
