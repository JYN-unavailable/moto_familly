#!/bin/bash
# =============================================================================
# MotoFamily — Installation automatique RPi Hôte
# Compatible : Raspberry Pi 3B+, 4, 5 — Raspberry Pi OS Lite (Bookworm)
# Usage : sudo ./install.sh
# =============================================================================
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

[ "$EUID" -ne 0 ] && err "Lancez ce script en root : sudo ./install.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOTSPOT_IFACE="wlan0"
HOST_IP="192.168.50.1"
SSID="MotoFamily"
WIFI_PASS="MotoFamily2024"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║   MotoFamily — Installation Hôte     ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── 1. Système ────────────────────────────────────────────────────────────────
log "Mise à jour du système..."
apt-get update -y -q
apt-get install -y -q \
    hostapd dnsmasq mumble-server \
    python3 python3-pip python3-venv \
    iptables iptables-persistent \
    rfkill git curl

# Activer le Wi-Fi si bloqué (Raspberry Pi)
rfkill unblock wifi || true

# ── 2. Interface réseau statique ──────────────────────────────────────────────
log "Configuration de l'interface Wi-Fi ($HOTSPOT_IFACE → $HOST_IP)..."

# Désactiver wpa_supplicant sur wlan0 (on prend le contrôle)
systemctl stop wpa_supplicant 2>/dev/null || true
systemctl disable wpa_supplicant 2>/dev/null || true

# IP statique via dhcpcd
if ! grep -q "interface $HOTSPOT_IFACE" /etc/dhcpcd.conf 2>/dev/null; then
    cat >> /etc/dhcpcd.conf << EOF

# MotoFamily hotspot
interface $HOTSPOT_IFACE
    static ip_address=$HOST_IP/24
    nohook wpa_supplicant
EOF
fi

# ── 3. Hotspot Wi-Fi (hostapd) ────────────────────────────────────────────────
log "Configuration du hotspot Wi-Fi (SSID: $SSID)..."

cp "$SCRIPT_DIR/config/hostapd.conf" /etc/hostapd/hostapd.conf
sed -i "s/^ssid=.*/ssid=$SSID/" /etc/hostapd/hostapd.conf
sed -i "s/^wpa_passphrase=.*/wpa_passphrase=$WIFI_PASS/" /etc/hostapd/hostapd.conf

echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' > /etc/default/hostapd

systemctl unmask hostapd
systemctl enable hostapd

# ── 4. DHCP (dnsmasq) ─────────────────────────────────────────────────────────
log "Configuration du serveur DHCP..."

# Sauvegarder la config existante
[ -f /etc/dnsmasq.conf ] && mv /etc/dnsmasq.conf /etc/dnsmasq.conf.bak

cp "$SCRIPT_DIR/config/dnsmasq.conf" /etc/dnsmasq.conf
sed -i "s/192.168.50.1/$HOST_IP/g" /etc/dnsmasq.conf

systemctl enable dnsmasq

# ── 5. Serveur Mumble ─────────────────────────────────────────────────────────
log "Configuration du serveur Mumble (basse latence)..."

cp "$SCRIPT_DIR/config/mumble-server.ini" /etc/mumble-server.ini
systemctl enable mumble-server

# ── 6. API d'appairage (Python/FastAPI) ───────────────────────────────────────
log "Installation de l'API d'appairage..."

mkdir -p /opt/motofamily /etc/motofamily

python3 -m venv /opt/motofamily/venv
/opt/motofamily/venv/bin/pip install -q -r "$SCRIPT_DIR/src/requirements.txt"
cp "$SCRIPT_DIR/src/server.py" /opt/motofamily/

# Service systemd
cat > /etc/systemd/system/motofamily-api.service << EOF
[Unit]
Description=MotoFamily Pairing API
After=network.target hostapd.service

[Service]
Type=simple
ExecStart=/opt/motofamily/venv/bin/python /opt/motofamily/server.py
Restart=always
RestartSec=5
User=root
WorkingDirectory=/opt/motofamily

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable motofamily-api

# ── 7. IP forwarding + firewall ───────────────────────────────────────────────
log "Configuration du pare-feu..."

# Autoriser le forwarding IP (si connexion internet sur eth0)
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p /etc/sysctl.conf >/dev/null

# Autoriser les ports nécessaires depuis wlan0
iptables -A INPUT -i "$HOTSPOT_IFACE" -p tcp --dport 8080 -j ACCEPT   # API
iptables -A INPUT -i "$HOTSPOT_IFACE" -p tcp --dport 64738 -j ACCEPT  # Mumble TCP
iptables -A INPUT -i "$HOTSPOT_IFACE" -p udp --dport 64738 -j ACCEPT  # Mumble UDP
iptables-save > /etc/iptables/rules.v4

# ── 8. Démarrage de tous les services ─────────────────────────────────────────
log "Démarrage des services..."

systemctl restart dhcpcd || true
sleep 2
systemctl start hostapd
systemctl start dnsmasq
systemctl start mumble-server
systemctl start motofamily-api

# ── Résumé ────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║          Installation terminée ✓                 ║"
echo "╠══════════════════════════════════════════════════╣"
printf "║  Wi-Fi SSID    : %-31s ║\n" "$SSID"
printf "║  Mot de passe  : %-31s ║\n" "$WIFI_PASS"
printf "║  IP hôte       : %-31s ║\n" "$HOST_IP"
echo "║  API appairage : http://192.168.50.1:8080        ║"
echo "║  WebSocket     : ws://192.168.50.1:8080/ws       ║"
echo "║  Mumble        : 192.168.50.1:64738              ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
warn "Redémarrez le RPi pour finaliser : sudo reboot"
