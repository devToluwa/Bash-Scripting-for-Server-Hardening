#!/bin/bash


set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# 1. Update the system
echo "[1/9] Updating system packages..."
apt update && apt upgrade -y


# 2. Disable Unnecessary services 
echo "[2/9] Disabling unnecessary services..."
systemctl disable --now bluetooth avahi-daemon cups 2>/dev/null || true


# 3. Harden SSH
echo "[3/9] Hardening SSH configuration..."
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl restart sshd


# 4. Configure Firewall with UFW
echo "[4/9] Configuring UFW firewall..."
ufw allow 22/tcp
ufw allow 80/tcp
ufw --force enable

# 5. Setup fail2ban
echo "[5/9] Installing and configuring Fail2Ban.."
apt install -y fail2ban
cat > /etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
port = 22
maxretry = 5
bantime = 3600
findtime = 600
EOF
systemctl enable fail2ban
systemctl restart fail2ban


# 6. Setup kernel parameters
echo "[6/9] Setting kernel parameteres..."
cat >> /etc/sysctl.conf <<EOF
net.ipv4.ip_forward = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
EOF
sysctl -p


# 7. Configure auditd
echo "[7/9] Configuring auditd..."
apt install -y auditd
cat >> /etc/audit/rules.d/audit.rules <<EOF
-w /etc/sudoers -p wa -k sudo_changes
-a always,exit -F arch=b64 -S execve -F euid=0 -k root_commands
-w /etc/passwd -p wa -k passwd_changes
-w /etc/group -p wa -k group_changes
EOF
systemctl enable auditd
systemctl restart auditd


# 8. Configure the password policy
echo "[8/9] Setting password policy..."
apt install -y libpam-pwquality

sed -i 's/^password.*pam_pwquality.so.*/password requisite pam_pwquality.so retry=3 minlen=12 ucredit=-1 lcredit=-1 dcredit=-1 ocredit=-1/' /etc/pam.d/common-password
if ! grep -q "pam_pwquality.so" /etc/pam.d/common-password; then
  sed -i '/pam_unix.so/i password requisite pam_pwquality.so retry=3 minlen=12 ucredit=-1 lcredit=-1 dcredit=-1 ocredit=-1' /etc/pam.d/common-password
fi


# 9. Configure cronjob rkhunter rootkitscan
echo "[9/9] Setting up daily rkhunter scan..."
echo "postfix postfix/main_mailer_type select Local only" | debconf-set-selections
echo "postfix postfix/mailname string $(hostname)" | debconf-set-selections
apt install -y rkhunter mailutils
rkhunter --propupd
cat > /etc/cron.d/rkhunter-scan <<EOF
0 3 * * * root /usr/bin/rkhunter --check --skip-keypress --report-warnings-only | mail -s "Daily rkhunter scan -\$(hostname)" root
EOF