#!/bin/bash
# =============================================================
# Surface Pro 5 Camera Fix - Installer
# Kernel 6.19 compatible
# Fixes: dw9719 i2c_device_id, int3472 avdd quirk, v4l2loopback
# =============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[!!]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KERNEL=$(uname -r)

echo "=================================================="
echo " Surface Pro 5 Camera Fix Installer"
echo " Kernel: $KERNEL"
echo "=================================================="
echo ""

# Root Check
if [[ $EUID -eq 0 ]]; then
    err "Do not run as root! Sudo is used internally."
fi

# Kernel Check
if [[ "$KERNEL" != *"surface"* ]]; then
    warn "No Surface kernel was found ($KERNEL)"
    read -p "Continue anyway? [y/N] " yn
    [[ "$yn" =~ ^[yY]$ ]] || exit 0
fi

# Check dependencies
log "Checking dependencies…"
for pkg in gcc make gstreamer1.0-tools gstreamer1.0-plugins-good \
           gstreamer1.0-plugins-bad libcamera-tools v4l-utils zenity \
           python3-gi; do
    if ! dpkg -l "$pkg" &>/dev/null; then
        warn "$pkg is missing – Installing…"
        sudo apt install -y "$pkg" || err "Could not install $pkg, please install manually"
    fi
done

# ---- 1. dw9719 Fix ----
log "Building the dw9719 fix…"
cd "$SCRIPT_DIR"
if [[ ! -f "dw9719.c" ]]; then
    if [[ ! -d "/tmp/lsk-dw9719" ]]; then
        git clone --depth=1 --filter=blob:none --sparse \
            -b v6.19-surface \
            https://github.com/linux-surface/kernel.git /tmp/lsk-dw9719
        cd /tmp/lsk-dw9719
        git sparse-checkout set drivers/media/i2c/
        cd "$SCRIPT_DIR"
    fi
    cp /tmp/lsk-dw9719/drivers/media/i2c/dw9719.c .
    # Add the i2c_device_id table
    python3 << 'PYEOF'
with open('dw9719.c', 'r') as f:
    content = f.read()
old = 'static struct i2c_driver dw9719_i2c_driver = {'
new = '''static const struct i2c_device_id dw9719_id_table[] = {
\t{ "dw9719", DW9719 },
\t{ }
};
MODULE_DEVICE_TABLE(i2c, dw9719_id_table);

static struct i2c_driver dw9719_i2c_driver = {'''
content = content.replace(old, new)
content = content.replace(
    '\t.probe = dw9719_probe,\n\t.remove = dw9719_remove,\n};',
    '\t.probe = dw9719_probe,\n\t.remove = dw9719_remove,\n\t.id_table = dw9719_id_table,\n};'
)
with open('dw9719.c', 'w') as f:
    f.write(content)
print("dw9719.c patched")
PYEOF
fi

cat > Kbuild << 'EOF'
obj-m := dw9719.o
EOF
make -C /lib/modules/$KERNEL/build M="$SCRIPT_DIR/drivers/media/i2c" \
    modules 2>/dev/null || {
    mkdir -p drivers/media/i2c
    cp dw9719.c drivers/media/i2c/
    make -C /lib/modules/$KERNEL/build M="$SCRIPT_DIR/drivers/media/i2c" \
        modules 2>&1 | tail -3
}
sudo cp drivers/media/i2c/dw9719.ko \
    /lib/modules/$KERNEL/kernel/drivers/media/i2c/
sudo depmod -a
log "dw9719.ko installed"

# ---- 2. v4l2loopback ----
log "Building v4l2loopback…"
if [[ ! -d "/tmp/v4l2loopback" ]]; then
    git clone --depth=1 https://github.com/umlaeute/v4l2loopback.git /tmp/v4l2loopback
fi
cd /tmp/v4l2loopback
make -C /lib/modules/$KERNEL/build M="$(pwd)" modules 2>&1 | tail -3
sudo cp v4l2loopback.ko \
    /lib/modules/$KERNEL/kernel/drivers/media/v4l2-core/
sudo depmod -a
cd "$SCRIPT_DIR"
log "v4l2loopback.ko installed"

# ---- 3. Build the daemon ----
log "Building surface-camera-daemon..."
if [[ ! -f "surface-camera-daemon.c" ]]; then
    err "surface-camera-daemon.c not found!"
fi
gcc -O2 -Wall -o surface-camera-daemon surface-camera-daemon.c
sudo cp surface-camera-daemon /usr/local/bin/
sudo chmod +x /usr/local/bin/surface-camera-daemon
log "Daemon installed"

# ---- 4. Install the switcher ----
log "Installing the switcher…"
if [[ ! -f "surface-camera-switcher.py" ]]; then
    err "surface-camera-switcher.py not found!"
fi
mkdir -p ~/.local/bin
cp surface-camera-switcher.py ~/.local/bin/
chmod +x ~/.local/bin/surface-camera-switcher.py
log "Switcher installed"

# ---- 5. Configuration ----
log "Configuring the system…"

# modprobe.d
sudo tee /etc/modprobe.d/surface-camera.conf > /dev/null << 'EOF'
options v4l2loopback video_nr=20 card_label="Surface Camera" max_buffers=8
EOF

# modules-load.d
sudo tee /etc/modules-load.d/surface-camera.conf > /dev/null << 'EOF'
dw9719
v4l2loopback
EOF

# known-apps.conf
sudo mkdir -p /etc/surface-camera
if [[ ! -f /etc/surface-camera/known-apps.conf ]]; then
    sudo tee /etc/surface-camera/known-apps.conf > /dev/null << 'EOF'
obs
firefox
firefox-bin
chromium
zoom
teams
EOF
    log "known-apps.conf created"
fi

# ---- 6. systemd service ----
log "Installing systemd service…"
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/surface-camera-daemon.service << 'EOF'
[Unit]
Description=Surface Pro 5 Camera on-demand daemon
After=pipewire.service graphical-session.target

[Service]
ExecStart=/usr/local/bin/surface-camera-daemon
Restart=on-failure
RestartSec=3
Environment=DISPLAY=:0

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload
systemctl --user enable surface-camera-daemon
log "Service enabled"

# ---- 7. Module loading ----
log "Loading module..."
sudo modprobe dw9719 2>/dev/null || true
sudo rmmod v4l2loopback 2>/dev/null || true
sudo modprobe v4l2loopback 2>/dev/null
log "Module loaded"

# ---- 8. Starting the service ----
systemctl --user start surface-camera-daemon
sleep 2
if systemctl --user is-active --quiet surface-camera-daemon; then
    log "The Surface camera daemon is running!"
else
    warn "The Surface camera daemon could not be started"
fi

# ---- Recap ----
echo ""
echo "=================================================="
echo " Installation complete!"
echo "=================================================="
echo ""
echo " Camera Device:  /dev/video20 (Surface Camera)"
echo " Daemon:         /usr/local/bin/surface-camera-daemon"
echo " Switcher:       ~/.local/bin/surface-camera-switcher.py"
echo " Known apps:  /etc/surface-camera/known-apps.conf"
echo ""
echo " Test: cam --list"
echo "=================================================="
