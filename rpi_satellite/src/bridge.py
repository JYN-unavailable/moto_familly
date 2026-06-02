"""
MotoFamily — Satellite : pont audio BT HFP ↔ Mumble
=====================================================
Architecture audio :

  Casque intercom (BT HFP HFU)
        ↕  Bluetooth HFP
  RPi Zero 2W  (agit comme un téléphone — HFP AG)
        ↕  PulseAudio virtual device
  pymumble client
        ↕  réseau Wi-Fi
  RPi hôte  (Mumble server)

Flux :
  mic intercom  → PulseAudio BT source → pymumble → réseau → autres motos
  réseau        → pymumble → PulseAudio BT sink   → hp intercom
"""

import audioop
import logging
import subprocess
import threading
import time

import pyaudio
import pymumble_py3 as pymumble

logger = logging.getLogger(__name__)

# ── Paramètres audio ──────────────────────────────────────────────────────────

MUMBLE_HOST   = "192.168.50.1"
MUMBLE_PORT   = 64738
SAMPLE_RATE   = 48000   # Hz — standard Mumble/Opus
CHANNELS      = 1       # Mono — intercom HFP
CHUNK_FRAMES  = 960     # 20ms @ 48kHz — taille de trame Opus optimale
PYAUDIO_FORMAT = pyaudio.paInt16

# ── Gestion Bluetooth ─────────────────────────────────────────────────────────

def _get_bt_device_names() -> tuple[str | None, str | None]:
    """
    Retrouve les noms de périphériques PulseAudio pour le casque BT connecté.
    Retourne (source_name, sink_name) ou (None, None) si aucun casque connecté.
    """
    try:
        out = subprocess.check_output(
            ["pactl", "list", "short", "sources"], text=True
        )
        source = next(
            (line.split()[1] for line in out.splitlines()
             if "bluez_source" in line and "handsfree" in line),
            None,
        )
        out = subprocess.check_output(
            ["pactl", "list", "short", "sinks"], text=True
        )
        sink = next(
            (line.split()[1] for line in out.splitlines()
             if "bluez_sink" in line and "handsfree" in line),
            None,
        )
        return source, sink
    except Exception as e:
        logger.error(f"Erreur lecture périphériques PulseAudio : {e}")
        return None, None


def wait_for_bt_headset(timeout: int = 120) -> tuple[str, str]:
    """
    Attend qu'un casque BT HFP soit connecté et visible dans PulseAudio.
    Retourne (source_name, sink_name) dès que disponible.
    """
    logger.info("Attente de la connexion du casque Bluetooth...")
    elapsed = 0
    while elapsed < timeout:
        source, sink = _get_bt_device_names()
        if source and sink:
            logger.info(f"Casque BT connecté — source={source}")
            return source, sink
        time.sleep(2)
        elapsed += 2
    raise TimeoutError("Aucun casque BT HFP détecté dans le délai imparti")


def make_bt_discoverable():
    """Rend le RPi visible pour un couplage BT depuis le casque."""
    try:
        subprocess.run(["bluetoothctl", "discoverable", "on"], check=True, capture_output=True)
        subprocess.run(["bluetoothctl", "pairable", "on"],     check=True, capture_output=True)
        logger.info("RPi visible en Bluetooth (couplage possible depuis le casque)")
    except Exception as e:
        logger.warning(f"Impossible d'activer la visibilité BT : {e}")

# ── Bridge audio ──────────────────────────────────────────────────────────────

class AudioBridge:
    """
    Pont bidirectionnel audio entre le casque BT (PulseAudio) et Mumble.
    """

    def __init__(self, mumble_token: str, device_name: str):
        self._token       = mumble_token
        self._device_name = device_name
        self._running     = False
        self._mumble: pymumble.Mumble | None = None
        self._pa          = pyaudio.PyAudio()
        self._bt_source   = None
        self._bt_sink     = None

    # ── Connexion Mumble ──────────────────────────────────────────────────────

    def _connect_mumble(self):
        self._mumble = pymumble.Mumble(
            host=MUMBLE_HOST,
            port=MUMBLE_PORT,
            user=self._device_name,
            password=self._token,
            reconnect=True,
        )
        self._mumble.callbacks.set_callback(
            pymumble.constants.PYMUMBLE_CLBK_SOUNDRECEIVED,
            self._on_mumble_audio,
        )
        self._mumble.set_receive_sound(True)
        self._mumble.start()
        self._mumble.is_ready()
        logger.info("Connecté au serveur Mumble")

    # ── Réception audio Mumble → casque BT ───────────────────────────────────

    def _on_mumble_audio(self, user, soundchunk):
        """Appelé par pymumble à chaque trame audio reçue des autres riders."""
        if self._stream_out and self._running:
            try:
                # Mumble envoie du PCM 16-bit — on le transmet directement
                self._stream_out.write(soundchunk.pcm)
            except Exception:
                pass

    # ── Envoi audio micro BT → Mumble ────────────────────────────────────────

    def _mic_loop(self):
        """Lit en continu le micro BT et envoie à Mumble."""
        pa_source_index = self._get_pa_device_index(self._bt_source, is_input=True)

        stream_in = self._pa.open(
            format=PYAUDIO_FORMAT,
            channels=CHANNELS,
            rate=SAMPLE_RATE,
            input=True,
            input_device_index=pa_source_index,
            frames_per_buffer=CHUNK_FRAMES,
        )

        logger.info("Capture micro BT démarrée")
        try:
            while self._running:
                try:
                    pcm = stream_in.read(CHUNK_FRAMES, exception_on_overflow=False)
                    # Vérification silence (ne pas envoyer si muet)
                    rms = audioop.rms(pcm, 2)
                    if rms > 200 and self._mumble and self._mumble.is_alive():
                        self._mumble.sound_output.add_sound(pcm)
                except Exception as e:
                    logger.debug(f"Mic loop : {e}")
        finally:
            stream_in.stop_stream()
            stream_in.close()

    def _get_pa_device_index(self, pa_name: str, is_input: bool) -> int | None:
        """Retrouve l'index PyAudio d'un périphérique PulseAudio par son nom."""
        count = self._pa.get_device_count()
        for i in range(count):
            info = self._pa.get_device_info_by_index(i)
            if pa_name in info.get("name", ""):
                if is_input and info["maxInputChannels"] > 0:
                    return i
                if not is_input and info["maxOutputChannels"] > 0:
                    return i
        return None

    # ── Démarrage / arrêt ─────────────────────────────────────────────────────

    def start(self, bt_source: str, bt_sink: str):
        self._bt_source = bt_source
        self._bt_sink   = bt_sink
        self._running   = True

        # Flux de sortie vers le casque (audio reçu de Mumble)
        pa_sink_index = self._get_pa_device_index(bt_sink, is_input=False)
        self._stream_out = self._pa.open(
            format=PYAUDIO_FORMAT,
            channels=CHANNELS,
            rate=SAMPLE_RATE,
            output=True,
            output_device_index=pa_sink_index,
            frames_per_buffer=CHUNK_FRAMES,
        )

        self._connect_mumble()

        # Thread dédié à la capture micro
        self._mic_thread = threading.Thread(target=self._mic_loop, daemon=True)
        self._mic_thread.start()

        logger.info("Bridge audio BT ↔ Mumble actif")

    def stop(self):
        self._running = False
        if self._mumble:
            self._mumble.stop()
        if hasattr(self, "_stream_out") and self._stream_out:
            self._stream_out.stop_stream()
            self._stream_out.close()
        self._pa.terminate()
        logger.info("Bridge audio arrêté")
