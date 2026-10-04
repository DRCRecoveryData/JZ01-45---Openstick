#!/bin/bash
# ============================================================
#  post_config.sh — JZ01-45-@ / JZ0145_V33 OpenStick post-install
#  Run on the device:  bash post_config.sh
# ============================================================

set -e

echo "=== JZ01-45-@ / JZ0145_V33 Post-Install Configuration ==="
echo ""

# --- OS check ---
if ! grep -q "Debian" /etc/os-release; then
    echo "[ERROR] This doesn't look like Debian. Aborting."
    exit 1
fi
echo "[OK] Debian detected ($(. /etc/os-release && echo $VERSION))"

# --- Root password ---
echo ""
echo "Set root password:"
passwd root

# --- Hostname ---
echo ""
echo "Setting hostname to 'openstick'..."
hostnamectl set-hostname openstick

# --- WiFi ---
echo ""
echo "Preparing WiFi..."
rfkill unblock wifi 2>/dev/null || true
systemctl enable --now NetworkManager
sleep 3
nmcli radio wifi on 2>/dev/null || true
sleep 2

read -p "Enter your WiFi SSID: " WIFI_SSID
read -sp "Enter your WiFi password: " WIFI_PASS
echo ""

CONNECTED=0
for attempt in 1 2 3; do
    echo "  [attempt $attempt/3] connecting to '$WIFI_SSID'..."
    if nmcli device wifi connect "$WIFI_SSID" password "$WIFI_PASS"; then
        sleep 3
        if ping -c 2 8.8.8.8 >/dev/null 2>&1; then
            CONNECTED=1
            break
        fi
    fi
    sleep 2
done

if [ "$CONNECTED" = "1" ]; then
    echo "[OK] WiFi connected"
else
    echo "[WARN] WiFi did not come up. Retry manually:"
    echo "  nmcli device wifi list"
    echo "  nmcli device wifi connect \"SSID\" password \"PASS\""
fi

# --- APT sources (bullseye/trixie) ---
echo ""
echo "Fixing apt sources..."
rm -f /etc/apt/sources.list.d/*.list 2>/dev/null || true

# Detect Debian version
. /etc/os-release
CODENAME="${VERSION_CODENAME:-bookworm}"

if [ "$CODENAME" = "bullseye" ]; then
    cat > /etc/apt/sources.list <<'EOF'
deb http://archive.debian.org/debian bullseye main contrib non-free
deb http://archive.debian.org/debian-security bullseye-security main contrib non-free
EOF
    echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid-until
else
    cat > /etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian $CODENAME main contrib non-free
deb http://deb.debian.org/debian $CODENAME-updates main contrib non-free
deb http://security.debian.org/debian-security $CODENAME-security main contrib non-free
EOF
fi

apt update
echo "[OK] APT sources fixed for $CODENAME"

# --- Useful packages ---
echo ""
echo "Installing useful packages..."
apt install -y \
    htop tmux nano curl git python3 python3-pip \
    iproute2 iw wireless-tools wpasupplicant \
    dnsmasq evtest rfkill gpiod

echo "[OK] Packages installed"

# --- SSH ---
echo ""
echo "Enabling SSH root login..."
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl restart ssh
echo "[OK] SSH configured"

# --- LEDs (JZ0145_V33: blue=GPIO7, green=GPIO6, red=GPIO8) ---
echo ""
echo "Configuring LEDs (GPIO 6/7/8)..."

cat > /usr/local/bin/led-config.sh <<'EOF'
#!/bin/bash
# JZ0145_V33 LED configuration
# The DTB is already patched so blue=GPIO7, green=GPIO6, red=GPIO8
set_led() {
    local led="$1" trig="$2"
    if [ -e "/sys/class/leds/$led/trigger" ]; then
        if echo "$trig" > "/sys/class/leds/$led/trigger" 2>/dev/null; then
            echo "  set $led -> $trig"
        else
            echo "  [FAIL] $led cannot use '$trig'"
            echo "         available: $(cat /sys/class/leds/$led/trigger)"
        fi
    else
        echo "  [skip] /sys/class/leds/$led not found"
    fi
}

set_led blue:wifi      phy0tx        # blink on WiFi TX activity
set_led green:internet usb-gadget    # on when USB gadget active
set_led red:os         heartbeat     # slow 1 Hz pulse — always visible
EOF
chmod +x /usr/local/bin/led-config.sh

cat > /etc/systemd/system/led-config.service <<'EOF'
[Unit]
Description=Configure status LEDs
After=multi-user.target network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/led-config.sh

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now led-config.service
echo "[OK] LEDs configured"

# --- Reset button (hardware-only RESIN_N) ---
echo ""
echo "[INFO] Reset button is wired to the PM8916 PMIC's RESIN_N pin."
echo "       It is a hardware reset — the kernel never sees it."
echo "       - Hold at power-on  -> enters EDL mode"
echo "       - Press at runtime  -> immediate hard power-cycle"
echo "       No software listener installed (not interceptable)."

# Remove any leftover listener from earlier installs
if [ -f /etc/systemd/system/reset-listener.service ]; then
    systemctl disable --now reset-listener.service 2>/dev/null || true
    rm -f /etc/systemd/system/reset-listener.service
    rm -f /usr/local/bin/reset-button-listener.py
    systemctl daemon-reload
    echo "[OK] Removed old reset-listener service"
fi

# --- zram (keep systemd-zram-generator, drop zram-tools) ---
echo ""
echo "Configuring zram swap..."
# Prefer systemd-zram-generator (modern, no conflict)
if dpkg -l 2>/dev/null | grep -q "^ii  systemd-zram-generator"; then
    apt-mark manual systemd-zram-generator 2>/dev/null || true
fi
# zram-tools conflicts with systemd-zram-generator — let it go if it isn't needed
if dpkg -l 2>/dev/null | grep -q "^ii  zram-tools"; then
    # Only remove if systemd-zram-generator is present to take over
    if dpkg -l 2>/dev/null | grep -q "^ii  systemd-zram-generator"; then
        systemctl disable --now zramswap.service 2>/dev/null || true
        apt-mark auto zram-tools 2>/dev/null || true
        echo "[OK] Disabled legacy zram-tools (systemd-zram-generator handles zram)"
    fi
fi

# --- Pin the custom kernel ---
echo ""
echo "Pinning custom kernel..."
if dpkg -l 2>/dev/null | grep -q "^ii  linux-image-5.15.0-handsomekernel+"; then
    apt-mark hold linux-image-5.15.0-handsomekernel+ 2>/dev/null || true
    echo "[OK] linux-image-5.15.0-handsomekernel+ is now held"
else
    echo "[INFO] handsomekernel not found — pin skipped"
fi

# --- Summary ---
echo ""
echo "=== Configuration Complete ==="
echo ""
echo "IP addresses:"
ip addr show | grep -E "inet " | grep -v "127.0.0.1" || true
echo ""
echo "SSH:  ssh root@<ip>"
echo ""
echo "Verify hardware:"
echo "  # LEDs (should show GPIO 7, 6, 8):"
echo "  for c in wifi internet os; do"
echo "      echo -n \"\$c: \"; od -A x -t x1z /proc/device-tree/leds/\$c/gpios | head -1"
echo "  done"
echo ""
echo "  # LED triggers:"
echo "  for led in blue:wifi green:internet red:os; do"
echo "      echo -n \"\$led: \""
echo "      cat /sys/class/leds/\$led/trigger | tr ' ' '\\n' | grep '\\[' | tr -d '[]'"
echo "  done"
echo ""
echo "  # zram swap:"
echo "  zramctl"
echo ""
echo "  # Kernel:"
echo "  uname -r"
echo ""
echo "  # Held packages:"
echo "  apt-mark showhold | grep handsome"
echo ""
echo "To upgrade to Debian 13 (trixie):"
echo "  1. sudo apt-mark hold linux-image-* linux-headers-*"
echo "  2. sudo sed -i 's/bookworm/trixie/g' /etc/apt/sources.list"
echo "  3. sudo apt update --allow-releaseinfo-change"
echo "  4. sudo apt upgrade --without-new-pkgs && sudo apt full-upgrade"
echo "  5. sudo reboot"
echo ""
