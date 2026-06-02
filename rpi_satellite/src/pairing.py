"""
MotoFamily — Satellite : module d'appairage
============================================
Gère la première connexion au RPi hôte :
  - Envoi de la demande d'appairage
  - Attente de l'approbation par l'hôte
  - Sauvegarde du token Mumble obtenu
"""

import json
import logging
import time
from pathlib import Path

import requests

logger = logging.getLogger(__name__)

CONFIG_FILE = Path("/etc/motofamily/satellite.json")
HOST_API = "http://192.168.50.1:8080"
POLL_INTERVAL = 5   # secondes entre chaque tentative
MAX_WAIT = 600      # 10 minutes maximum d'attente

# ── Config locale ─────────────────────────────────────────────────────────────

def load_config() -> dict:
    if CONFIG_FILE.exists():
        return json.loads(CONFIG_FILE.read_text())
    return {}

def save_config(data: dict):
    CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
    CONFIG_FILE.write_text(json.dumps(data, indent=2))

def get_device_id() -> str:
    """Utilise l'adresse MAC de wlan0 comme identifiant unique."""
    try:
        mac = Path("/sys/class/net/wlan0/address").read_text().strip()
        return mac.replace(":", "")
    except Exception:
        import uuid
        return str(uuid.uuid4()).replace("-", "")[:12]

def get_device_name() -> str:
    config = load_config()
    return config.get("name", "Satellite")

# ── Appairage ─────────────────────────────────────────────────────────────────

def get_mumble_token() -> str | None:
    """
    Retourne le token Mumble si l'appareil est déjà approuvé,
    sinon None (besoin de faire le handshake).
    """
    config = load_config()
    return config.get("mumble_token")

def request_pairing() -> str | None:
    """
    Handshake complet avec le RPi hôte.
    Bloque jusqu'à approbation, rejet, ou timeout.
    Retourne le token Mumble si approuvé, None sinon.
    """
    device_id = get_device_id()
    name = get_device_name()

    logger.info(f"Demande d'appairage — device_id={device_id}, name={name}")

    elapsed = 0
    while elapsed < MAX_WAIT:
        try:
            resp = requests.post(
                f"{HOST_API}/pair",
                json={"device_id": device_id, "name": name},
                timeout=10,
            )
            data = resp.json()
            status = data.get("status")

            if status == "approved":
                token = data["token"]
                logger.info("Appairage approuvé — token reçu")
                # Sauvegarder le token pour les prochaines connexions
                config = load_config()
                config["mumble_token"] = token
                config["device_id"] = device_id
                save_config(config)
                return token

            elif status == "rejected":
                logger.warning("Appairage rejeté par l'hôte")
                return None

            elif status == "pending":
                if elapsed == 0:
                    logger.info("En attente d'approbation par l'hôte...")
                # Continuer à attendre

        except requests.ConnectionError:
            logger.warning("RPi hôte injoignable, nouvelle tentative...")
        except Exception as e:
            logger.error(f"Erreur appairage : {e}")

        time.sleep(POLL_INTERVAL)
        elapsed += POLL_INTERVAL

    logger.error("Timeout : appairage non résolu en 10 minutes")
    return None


def notify_disconnect(device_id: str):
    """Signale au RPi hôte que ce satellite se déconnecte."""
    try:
        requests.post(
            f"{HOST_API}/disconnect/{device_id}",
            timeout=5,
        )
    except Exception:
        pass
