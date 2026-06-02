#!/bin/bash
# =============================================================================
# MotoFamily — Installation automatique RPi Satellite (Zero 2W)
# Compatible : Raspberry Pi Zero 2W — Raspberry Pi OS Lite (Bookworm)
# Usage : sudo ./install.sh "Moto 2"
#         (le nom entre guillemets identifie cette moto dans la session)
# =============================================================================
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

[ "$EUID" -ne 0 ] && err "Lancez ce script en root : sudo ./install.sh \"Nom Moto\""

DEVICE_NAME="${1:-Satellite}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  MotoFamily — Installation Satellite      ║"
echo "╚══════════════════════════════════════════╝"
echo ""
log "Nom de cet appareil : $DEVICE_NAME"

# ── 1. Système ────────────────────────────────────────────────────────────────
log "Mise à jour du système..."
apt-get update -y -q
apt-get install -y -q \
    bluez bluez-tools ofono \
    pulseaudio pulseaudio-module-bluetooth \
    python3 python3-pip python3-venv \
    python3-dbus \
    portaudio19-dev \
    wpasupplicant \
    git curl

# ── 2. Connexion Wi-Fi MotoFamily ─────────────────────────────────────────────
log "Configuration Wi-Fi (réseau MotoFamily)..."

cp "$SCRIPT_DIR/config/wpa_supplicant.conf" /etc/wpa_supplicant/wpa_supplicant.conf
chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf

# Activer wpa_supplicant sur wlan0
systemctl enable wpa_supplicant
systemctl restart wpa_supplicant || true

# ── 3. Bluetooth + oFono (HFP Audio Gateway) ──────────────────────────────────
log "Configuration Bluetooth HFP..."

# Activer le plugin HFP dans BlueZ
sed -i 's/^#*ExecStart=\/usr\/lib\/bluetooth\/bluetoothd/ExecStart=\/usr\/lib\/bluetooth\/bluetoothd --plugin=a2dp,avrcp,hfp/' \
    /lib/systemd/system/bluetooth.service 2>/dev/null || \
    sed -i 's/^#*ExecStart=\/usr\/libexec\/bluetooth\/bluetoothd/ExecStart=\/usr\/libexec\/bluetooth\/bluetoothd --plugin=a2dp,avrcp,hfp/' \
    /lib/systemd/system/bluetooth.service

# Configurer PulseAudio pour Bluetooth HFP (mode system)
mkdir -p /etc/pulse
cat > /etc/pulse/system.pa << 'EOF'
.ifexists module-udev-detect.so
load-module module-udev-detect
.endif

load-module module-bluetooth-policy
load-module module-bluetooth-discover headset=ofono
load-module module-native-protocol-unix auth-anonymous=1
EOF

# PulseAudio en mode système (nécessaire pour démarrage automatique)
cat > /etc/systemd/system/pulseaudio.service << 'EOF'
[Unit]
Description=PulseAudio System-Wide Daemon
After=bluetooth.service

[Service]
Type=simple
ExecStart=/usr/bin/pulseaudio --system --realtime --disallow-exit --no-cpu-limit
Restart=always
User=pulse
Group=pulse

[Install]
WantedBy=multi-user.target
EOF

usermod -aG bluetooth pulse
usermod -aG audio pulse

systemctl daemon-reload
systemctl enable bluetooth
systemctl enable ofono
systemctl enable pulseaudio

# ── 4. Application Python ─────────────────────────────────────────────────────
log "Installation de l'application satellite..."

mkdir -p /opt/motofamily /etc/motofamily

python3 -m venv /opt/motofamily/venv
/opt/motofamily/venv/bin/pip install -q -r "$SCRIPT_DIR/src/requirements.txt"

cp "$SCRIPT_DIR/src/"*.py /opt/motofamily/

# Config de l'appareil (nom affiché dans la session)
cat > /etc/motofamily/satellite.json << EOF
{
  "name": "$DEVICE_NAME"
}
EOF

# Service systemd
cat > /etc/systemd/system/motofamily-satellite.service << 'EOF'
[Unit]
Description=MotoFamily Satellite
After=network.target bluetooth.service pulseaudio.service

[Service]
Type=simple
ExecStart=/opt/motofamily/venv/bin/python /opt/motofamily/main.py
Restart=always
RestartSec=10
WorkingDirectory=/opt/motofamily

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable motofamily-satellite

# ── 5. Démarrage ──────────────────────────────────────────────────────────────
log "Démarrage des services..."
systemctl start bluetooth
systemctl start ofono
systemctl start pulseaudio || true

# ── Résumé ────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║          Installation terminée ✓                 ║"
echo "╠══════════════════════════════════════════════════╣"
printf "║  Nom de la moto    : %-28s ║\n" "$DEVICE_NAME"
echo "║  Réseau cible      : MotoFamily                  ║"
echo "║  Démarrage auto    : activé                      ║"
echo "╠══════════════════════════════════════════════════╣"
echo "║  Première utilisation :                          ║"
echo "║  1. Allumez le RPi hôte                          ║"
echo "║  2. Allumez ce satellite                         ║"
echo "║  3. L'hôte voit la demande → approuve            ║"
echo "║  4. Coupler le casque BT depuis l'intercom       ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
warn "Redémarrez le RPi pour finaliser : sudo reboot"
