#!/bin/bash
# =============================================================
# Surface Pro 5 Kamera Fix - Installer
# Kernel 6.19 kompatibel
# Fixes: dw9719 i2c_device_id, int3472 avdd quirk, v4l2loopback
# =============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[!!]${NC} $1"; }
err()  { echo -e "${RED}[FEHLER]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KERNEL=$(uname -r)

echo "=================================================="
echo " Surface Pro 5 Kamera Fix Installer"
echo " Kernel: $KERNEL"
echo "=================================================="
echo ""

# Root Check
if [[ $EUID -eq 0 ]]; then
    err "Nicht als root ausführen! Sudo wird intern genutzt."
fi

# Kernel Check
if [[ "$KERNEL" != *"surface"* ]]; then
    warn "Kein Surface Kernel erkannt ($KERNEL)"
    read -p "Trotzdem fortfahren? [j/N] " yn
    [[ "$yn" =~ ^[jJ]$ ]] || exit 0
fi

# Abhängigkeiten prüfen
log "Prüfe Abhängigkeiten..."
for pkg in gcc make gstreamer1.0-tools gstreamer1.0-plugins-good \
           gstreamer1.0-plugins-bad libcamera-tools v4l-utils zenity \
           python3-gi; do
    if ! dpkg -l "$pkg" &>/dev/null; then
        warn "$pkg fehlt – installiere..."
        sudo apt install -y "$pkg" || err "Konnte $pkg nicht installieren"
    fi
done

# ---- 1. dw9719 Fix ----
log "Baue dw9719 Fix..."
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
    # i2c_device_id Tabelle hinzufügen
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
print("dw9719.c gepatcht")
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
log "dw9719.ko installiert"

# ---- 2. v4l2loopback ----
log "Baue v4l2loopback..."
if [[ ! -d "/tmp/v4l2loopback" ]]; then
    git clone --depth=1 https://github.com/umlaeute/v4l2loopback.git /tmp/v4l2loopback
fi
cd /tmp/v4l2loopback
make -C /lib/modules/$KERNEL/build M="$(pwd)" modules 2>&1 | tail -3
sudo cp v4l2loopback.ko \
    /lib/modules/$KERNEL/kernel/drivers/media/v4l2-core/
sudo depmod -a
cd "$SCRIPT_DIR"
log "v4l2loopback.ko installiert"

# ---- 3. Daemon bauen ----
log "Baue surface-kamera-daemon..."
if [[ ! -f "surface-kamera-daemon-v9.c" ]]; then
    err "surface-kamera-daemon-v9.c nicht gefunden!"
fi
gcc -O2 -Wall -o surface-kamera-daemon surface-kamera-daemon-v9.c
sudo cp surface-kamera-daemon /usr/local/bin/
sudo chmod +x /usr/local/bin/surface-kamera-daemon
log "Daemon installiert"

# ---- 4. Switcher installieren ----
log "Installiere Switcher..."
if [[ ! -f "surface-kamera-switcher.py" ]]; then
    err "surface-kamera-switcher.py nicht gefunden!"
fi
mkdir -p ~/.local/bin
cp surface-kamera-switcher.py ~/.local/bin/
chmod +x ~/.local/bin/surface-kamera-switcher.py
log "Switcher installiert"

# ---- 5. Konfiguration ----
log "Konfiguriere System..."

# modprobe.d
sudo tee /etc/modprobe.d/surface-kamera.conf > /dev/null << 'EOF'
options v4l2loopback video_nr=20 card_label="Surface Kamera" max_buffers=8
EOF

# modules-load.d
sudo tee /etc/modules-load.d/surface-kamera.conf > /dev/null << 'EOF'
dw9719
v4l2loopback
EOF

# known-apps.conf
sudo mkdir -p /etc/surface-kamera
if [[ ! -f /etc/surface-kamera/known-apps.conf ]]; then
    sudo tee /etc/surface-kamera/known-apps.conf > /dev/null << 'EOF'
obs
firefox
firefox-bin
chromium
zoom
teams
EOF
    log "known-apps.conf erstellt"
fi

# ---- 6. systemd Service ----
log "Installiere systemd Service..."
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/surface-kamera-daemon.service << 'EOF'
[Unit]
Description=Surface Pro 5 Kamera On-Demand Daemon
After=pipewire.service graphical-session.target

[Service]
ExecStart=/usr/local/bin/surface-kamera-daemon
Restart=on-failure
RestartSec=3
Environment=DISPLAY=:0

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload
systemctl --user enable surface-kamera-daemon
log "Service aktiviert"

# ---- 7. Module laden ----
log "Lade Module..."
sudo modprobe dw9719 2>/dev/null || true
sudo rmmod v4l2loopback 2>/dev/null || true
sudo modprobe v4l2loopback 2>/dev/null
log "Module geladen"

# ---- 8. Service starten ----
systemctl --user start surface-kamera-daemon
sleep 2
if systemctl --user is-active --quiet surface-kamera-daemon; then
    log "Daemon läuft!"
else
    warn "Daemon konnte nicht gestartet werden"
fi

# ---- Zusammenfassung ----
echo ""
echo "=================================================="
echo " Installation abgeschlossen!"
echo "=================================================="
echo ""
echo " Kamera Device:  /dev/video20 (Surface Kamera)"
echo " Daemon:         /usr/local/bin/surface-kamera-daemon"
echo " Switcher:       ~/.local/bin/surface-kamera-switcher.py"
echo " Bekannte Apps:  /etc/surface-kamera/known-apps.conf"
echo ""
echo " Test: cam --list"
echo "=================================================="
