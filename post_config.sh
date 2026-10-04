#!/bin/bash
# post_config.sh - configure OpenStick after first boot
set -e

echo "=== JZ01-45-@ / JZ0145_V33 Post-Install Configuration ==="
echo ""

if ! grep -q "Debian" /etc/os-release; then
    echo "[ERROR] This doesn't look like Debian. Aborting."
    exit 1
fi
echo "[OK] Debian detected"

echo ""
echo "Set root password:"
passwd root

echo ""
echo "Setting hostname to 'openstick'..."
hostnamectl set-hostname openstick

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

echo ""
echo "Fixing apt sources (bullseye is EOL)..."
rm -f /etc/apt/sources.list.d/*.list 2>/dev/null || true

cat > /etc/apt/sources.list <<'EOF'
deb http://archive.debian.org/debian bullseye main contrib non-free
deb http://archive.debian.org/debian-security bullseye-security main contrib non-free
EOF

echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid-until
apt update
echo "[OK] APT sources fixed"

echo ""
echo "Installing useful packages..."
apt install -y \
    htop tmux nano curl git python3 python3-pip \
    iproute2 iw wireless-tools wpasupplicant \
    dnsmasq evtest rfkill

echo "[OK] Packages installed"

echo ""
echo "Enabling SSH root login..."
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl restart ssh
echo "[OK] SSH configured"

echo ""
echo "Configuring LEDs (JZ0145_V33 pins 6/7/8)..."
cat > /usr/local/bin/led-config.sh <<'EOF'
#!/bin/bash
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

# JZ0145_V33: blue=GPIO7, green=GPIO6, red=GPIO8
set_led blue:wifi     phy0tx        # blink on WiFi TX
set_led green:internet usb-gadget   # on when USB gadget active
set_led red:os        heartbeat     # slow pulse — always visible
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

echo ""
echo "Setting up reset button (KEY_F1 code 59 -> graceful shutdown)..."
cat > /usr/local/bin/reset-button-listener.py <<'PYEOF'
#!/usr/bin/env python3
# JZ0145_V33 reset button: KEY_F1 (code 59), GPIO 37
import glob, os, select, struct, subprocess, sys, time

KEY_F1 = 59          # per jz01-512mb.dts: linux,code = <0x3b>
EV_KEY = 1

def find_device():
    for path in sorted(glob.glob("/dev/input/event*")):
        base = os.path.basename(path)
        namefile = f"/sys/class/input/{base}/device/name"
        try:
            with open(namefile) as f:
                name = f.read().strip()
            if any(k in name for k in ("gpio-keys", "keys", "pwrkey")):
                return path, name
        except OSError:
            continue
    return "/dev/input/event0", "fallback"

def main():
    dev, name = find_device()
    print(f"Listening on {dev} ({name})", flush=True)
    while True:
        try:
            with open(dev, "rb") as f:
                while True:
                    r, _, _ = select.select([f], [], [], 5)
                    if not r:
                        continue
                    data = f.read(24)
                    if len(data) < 24:
                        break
                    _, _, ev_type, ev_code, ev_val = struct.unpack("llHHI", data)
                    if ev_type == EV_KEY and ev_code == KEY_F1 and ev_val == 1:
                        subprocess.run(["/usr/bin/logger", "Reset button pressed"])
                        subprocess.Popen(["/sbin/shutdown", "-h", "now"])
        except OSError as e:
            print(f"input error: {e}; retrying", file=sys.stderr)
            time.sleep(2)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
PYEOF
chmod +x /usr/local/bin/reset-button-listener.py

cat > /etc/systemd/system/reset-listener.service <<'EOF'
[Unit]
Description=Reset button listener
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/local/bin/reset-button-listener.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now reset-listener.service
echo "[OK] Reset button configured"

echo ""
echo "=== Configuration Complete ==="
echo ""
echo "IP addresses:"
ip addr show | grep -E "inet " | grep -v "127.0.0.1" || true
echo ""
echo "SSH:  ssh root@<ip>"
echo ""
echo "Verify LEDs:"
echo "  od -A x -t x1z /proc/device-tree/leds/wifi/gpios"
echo "  (should show GPIO 7)"
echo ""
echo "Test reset button:"
echo "  systemctl status reset-listener"
echo "  # press the physical reset button — device should shut down"
echo ""#!/bin/bash
# post_config.sh - configure OpenStick after first boot
set -e

echo "=== JZ01-45-@ OpenStick Post-Install Configuration ==="
echo ""

if ! grep -q "Debian" /etc/os-release; then
    echo "[ERROR] This doesn't look like Debian. Aborting."
    exit 1
fi
echo "[OK] Debian detected"

echo ""
echo "Set root password:"
passwd root

echo ""
echo "Setting hostname to 'openstick'..."
hostnamectl set-hostname openstick

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

echo ""
echo "Fixing apt sources (bullseye is EOL)..."
rm -f /etc/apt/sources.list.d/*.list 2>/dev/null || true

cat > /etc/apt/sources.list <<'EOF'
deb http://archive.debian.org/debian bullseye main contrib non-free
deb http://archive.debian.org/debian-security bullseye-security main contrib non-free
EOF

echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid-until
apt update
echo "[OK] APT sources fixed"

echo ""
echo "Installing useful packages..."
apt install -y \
    htop tmux nano curl git python3 python3-pip \
    iproute2 iw wireless-tools wpasupplicant \
    dnsmasq evtest rfkill

echo "[OK] Packages installed"

echo ""
echo "Enabling SSH root login..."
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl restart ssh
echo "[OK] SSH configured"

echo ""
echo "Configuring LEDs..."
cat > /usr/local/bin/led-config.sh <<'EOF'
#!/bin/bash
set_led() {
    local led="$1" trig="$2"
    if [ -e "/sys/class/leds/$led/trigger" ]; then
        echo "$trig" > "/sys/class/leds/$led/trigger" && echo "  set $led -> $trig"
    else
        echo "  [skip] /sys/class/leds/$led not found"
    fi
}
set_led blue:wifi     phy1tx
set_led green:internet usb-gadget
set_led red:os        heartbeat
EOF
chmod +x /usr/local/bin/led-config.sh

cat > /etc/systemd/system/led-config.service <<'EOF'
[Unit]
Description=Configure status LEDs
After=multi-user.target

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

echo ""
echo "Setting up reset button (KEY_RESTART -> shutdown)..."
cat > /usr/local/bin/reset-button-listener.py <<'PYEOF'
#!/usr/bin/env python3
import glob, os, select, struct, subprocess, sys, time

KEY_RESTART = 408
EV_KEY = 1

def find_device():
    for path in sorted(glob.glob("/dev/input/event*")):
        base = os.path.basename(path)
        namefile = f"/sys/class/input/{base}/device/name"
        try:
            with open(namefile) as f:
                name = f.read().strip()
            if any(k in name for k in ("gpio-keys", "pwrkey", "keys")):
                return path, name
        except OSError:
            continue
    return "/dev/input/event0", "fallback"

def main():
    dev, name = find_device()
    print(f"Listening on {dev} ({name})", flush=True)
    while True:
        try:
            with open(dev, "rb") as f:
                while True:
                    r, _, _ = select.select([f], [], [], 5)
                    if not r:
                        continue
                    data = f.read(24)
                    if len(data) < 24:
                        break
                    _, _, ev_type, ev_code, ev_val = struct.unpack("llHHI", data)
                    if ev_type == EV_KEY and ev_code == KEY_RESTART and ev_val == 1:
                        subprocess.run(["/usr/bin/logger", "Reset button pressed"])
                        subprocess.Popen(["/sbin/shutdown", "-h", "now"])
        except OSError as e:
            print(f"input error: {e}; retrying", flush=True)
            time.sleep(2)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
PYEOF
chmod +x /usr/local/bin/reset-button-listener.py

cat > /etc/systemd/system/reset-listener.service <<'EOF'
[Unit]
Description=Reset button listener
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/local/bin/reset-button-listener.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now reset-listener.service
echo "[OK] Reset button configured"

echo ""
echo "=== Configuration Complete ==="
echo ""
echo "IP addresses:"
ip addr show | grep -E "inet " | grep -v "127.0.0.1" || true
echo ""
echo "SSH:  ssh root@<ip>"
echo "Useful:"
echo "  systemctl status led-config"
echo "  systemctl status reset-listener"
echo "  ls /sys/class/leds/"
echo ""
