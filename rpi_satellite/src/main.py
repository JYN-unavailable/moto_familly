"""
MotoFamily — Satellite : orchestrateur principal
=================================================
Séquence au démarrage :

  1. Attend la connexion Wi-Fi au réseau MotoFamily
  2. Vérifie si l'appareil est déjà approuvé (token sauvegardé)
     → Non : demande l'appairage, attend l'approbation de l'hôte
     → Oui : connexion directe
  3. Active la visibilité Bluetooth
  4. Attend le couplage du casque intercom
  5. Lance le pont audio BT HFP ↔ Mumble
  6. Gère la reconnexion automatique en cas de perte de signal
"""

import logging
import signal
import socket
import sys
import time

from pairing import (
    get_device_id,
    get_device_name,
    get_mumble_token,
    notify_disconnect,
    request_pairing,
)
from bridge import AudioBridge, make_bt_discoverable, wait_for_bt_headset

# ── Logging ───────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s — %(message)s",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler("/var/log/motofamily-satellite.log"),
    ],
)
logger = logging.getLogger("main")

# ── Réseau ────────────────────────────────────────────────────────────────────

HOST_IP = "192.168.50.1"
HOST_API_PORT = 8080


def wait_for_wifi(timeout: int = 120) -> bool:
    """Attend que la connexion Wi-Fi au RPi hôte soit établie."""
    logger.info("Attente de la connexion au réseau MotoFamily...")
    elapsed = 0
    while elapsed < timeout:
        try:
            sock = socket.create_connection((HOST_IP, HOST_API_PORT), timeout=3)
            sock.close()
            logger.info("Réseau MotoFamily accessible")
            return True
        except (socket.timeout, ConnectionRefusedError, OSError):
            time.sleep(3)
            elapsed += 3
    logger.error("Réseau MotoFamily non accessible après %ds", timeout)
    return False


# ── Boucle principale ─────────────────────────────────────────────────────────

bridge: AudioBridge | None = None


def shutdown(signum, frame):
    """Arrêt propre sur SIGTERM / SIGINT."""
    logger.info("Arrêt du satellite...")
    if bridge:
        bridge.stop()
    notify_disconnect(get_device_id())
    sys.exit(0)


signal.signal(signal.SIGTERM, shutdown)
signal.signal(signal.SIGINT, shutdown)


def run():
    global bridge
    device_name = get_device_name()
    logger.info(f"=== MotoFamily Satellite — {device_name} ===")

    while True:
        # ── Étape 1 : Wi-Fi ───────────────────────────────────────────────────
        if not wait_for_wifi():
            logger.warning("Nouvelle tentative dans 30s...")
            time.sleep(30)
            continue

        # ── Étape 2 : Appairage ───────────────────────────────────────────────
        token = get_mumble_token()

        if not token:
            logger.info("Premier démarrage — demande d'appairage à l'hôte")
            token = request_pairing()
            if not token:
                logger.error("Appairage échoué ou rejeté. Nouvelle tentative dans 60s.")
                time.sleep(60)
                continue

        logger.info("Appareil approuvé — token Mumble disponible")

        # ── Étape 3 : Bluetooth ───────────────────────────────────────────────
        make_bt_discoverable()

        try:
            bt_source, bt_sink = wait_for_bt_headset(timeout=300)
        except TimeoutError:
            logger.warning("Casque BT non détecté. Nouvelle tentative...")
            continue

        # ── Étape 4 : Bridge audio ────────────────────────────────────────────
        bridge = AudioBridge(
            mumble_token=token,
            device_name=device_name,
        )

        try:
            bridge.start(bt_source, bt_sink)

            # Maintenir le bridge actif
            while True:
                time.sleep(5)
                # Vérifier que le casque BT est toujours connecté
                from bridge import _get_bt_device_names
                src, snk = _get_bt_device_names()
                if not src or not snk:
                    logger.warning("Casque BT déconnecté — attente reconnexion")
                    break

        except Exception as e:
            logger.error(f"Erreur bridge audio : {e}")
        finally:
            bridge.stop()
            bridge = None

        logger.info("Redémarrage du cycle dans 5s...")
        time.sleep(5)


if __name__ == "__main__":
    run()
