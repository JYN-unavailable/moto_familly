"""
MotoFamily — Serveur d'appairage RPi hôte
==========================================
- API REST : gestion des demandes d'appairage des satellites
- WebSocket : notifications temps réel vers l'app Flutter de l'hôte
- Contrôle Mumble : autorise/bloque les connexions via tokens
"""

import asyncio
import json
import uuid
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Set

import uvicorn
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

# ── Configuration ─────────────────────────────────────────────────────────────

DEVICES_FILE = Path("/etc/motofamily/devices.json")
DEVICES_FILE.parent.mkdir(parents=True, exist_ok=True)

API_PORT = 8080
MAX_DEVICES = 5  # 5 satellites max (+ 1 hôte = 6 total)

# ── Application ───────────────────────────────────────────────────────────────

app = FastAPI(title="MotoFamily Pairing Server", version="1.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Persistance des appareils ─────────────────────────────────────────────────

class DeviceStore:
    """Stocke les appareils connus et leur statut d'appairage."""

    def __init__(self):
        self._data: Dict[str, dict] = {}
        self._load()

    def _load(self):
        if DEVICES_FILE.exists():
            try:
                self._data = json.loads(DEVICES_FILE.read_text())
            except json.JSONDecodeError:
                self._data = {}

    def _save(self):
        DEVICES_FILE.write_text(json.dumps(self._data, indent=2, ensure_ascii=False))

    def status(self, device_id: str) -> str | None:
        return self._data.get(device_id, {}).get("status")

    def token(self, device_id: str) -> str | None:
        return self._data.get(device_id, {}).get("token")

    def add_pending(self, device_id: str, name: str):
        if device_id not in self._data:
            self._data[device_id] = {
                "id": device_id,
                "name": name,
                "status": "pending",
                "token": None,
                "first_seen": datetime.now().isoformat(),
                "last_seen": datetime.now().isoformat(),
            }
            self._save()
        else:
            self._data[device_id]["last_seen"] = datetime.now().isoformat()
            self._save()

    def approve(self, device_id: str) -> str:
        if device_id not in self._data:
            raise KeyError(device_id)
        token = str(uuid.uuid4())
        self._data[device_id].update(
            status="approved",
            token=token,
            approved_at=datetime.now().isoformat(),
        )
        self._save()
        return token

    def reject(self, device_id: str):
        if device_id in self._data:
            self._data[device_id]["status"] = "rejected"
            self._save()

    def set_connected(self, device_id: str, connected: bool):
        if device_id in self._data:
            self._data[device_id]["online"] = connected
            self._save()

    def all(self) -> List[dict]:
        return list(self._data.values())


store = DeviceStore()
ws_clients: Set[WebSocket] = set()

# ── Helpers ───────────────────────────────────────────────────────────────────

async def broadcast(event: dict):
    """Envoie un événement à toutes les connexions WebSocket Flutter actives."""
    dead: Set[WebSocket] = set()
    for ws in ws_clients:
        try:
            await ws.send_json(event)
        except Exception:
            dead.add(ws)
    ws_clients.difference_update(dead)


def _mumble_token_file() -> Path:
    return Path("/etc/motofamily/mumble_tokens.txt")

def _refresh_mumble_tokens():
    """Recrée la liste des tokens Mumble autorisés depuis les appareils approuvés."""
    tokens = [
        d["token"]
        for d in store.all()
        if d.get("status") == "approved" and d.get("token")
    ]
    _mumble_token_file().write_text("\n".join(tokens) + "\n")

# ── Modèles Pydantic ──────────────────────────────────────────────────────────

class PairRequest(BaseModel):
    device_id: str
    name: str

# ── Endpoints REST ────────────────────────────────────────────────────────────

@app.post("/pair")
async def request_pairing(req: PairRequest):
    """
    Appelé par un satellite au démarrage.
    - Appareil inconnu  → statut 'pending', notification Flutter
    - Appareil approuvé → retourne le token Mumble
    - Appareil rejeté   → retourne 'rejected'
    - Appareil pending  → retourne 'pending' (satellite doit réessayer)
    """
    current = store.status(req.device_id)

    if current == "approved":
        store.set_connected(req.device_id, True)
        await broadcast({"type": "device_connected", "device_id": req.device_id})
        return {"status": "approved", "token": store.token(req.device_id)}

    if current == "rejected":
        return {"status": "rejected"}

    if current == "pending":
        return {"status": "pending"}

    # Nouvel appareil inconnu
    approved_count = sum(1 for d in store.all() if d.get("status") == "approved")
    if approved_count >= MAX_DEVICES:
        return {"status": "rejected", "reason": "session_full"}

    store.add_pending(req.device_id, req.name)
    await broadcast({
        "type": "pair_request",
        "device": {"id": req.device_id, "name": req.name},
    })
    return {"status": "pending"}


@app.post("/approve/{device_id}")
async def approve(device_id: str):
    """Approuve un satellite (appelé par l'app Flutter de l'hôte)."""
    try:
        token = store.approve(device_id)
        _refresh_mumble_tokens()
        await broadcast({"type": "device_approved", "device_id": device_id})
        return {"status": "approved", "token": token}
    except KeyError:
        raise HTTPException(status_code=404, detail="Appareil non trouvé")


@app.post("/reject/{device_id}")
async def reject(device_id: str):
    """Rejette un satellite."""
    store.reject(device_id)
    await broadcast({"type": "device_rejected", "device_id": device_id})
    return {"status": "rejected"}


@app.post("/disconnect/{device_id}")
async def notify_disconnect(device_id: str):
    """Appelé par un satellite qui se déconnecte proprement."""
    store.set_connected(device_id, False)
    await broadcast({"type": "device_disconnected", "device_id": device_id})
    return {"ok": True}


@app.get("/devices")
async def list_devices():
    """Liste tous les appareils connus."""
    return store.all()


@app.get("/health")
async def health():
    return {"status": "ok", "devices": len(store.all())}


# ── WebSocket (app Flutter hôte) ──────────────────────────────────────────────

@app.websocket("/ws")
async def websocket_endpoint(ws: WebSocket):
    """
    Connexion WebSocket persistante depuis l'app Flutter.
    Reçoit tous les événements en temps réel (pair_request, device_connected…).
    """
    await ws.accept()
    ws_clients.add(ws)

    # État initial complet à la connexion
    await ws.send_json({
        "type": "initial_state",
        "devices": store.all(),
    })

    try:
        while True:
            # Maintien de la connexion — le client peut envoyer des pings
            data = await ws.receive_text()
            if data == "ping":
                await ws.send_text("pong")
    except WebSocketDisconnect:
        ws_clients.discard(ws)


# ── Démarrage ─────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    uvicorn.run(
        "server:app",
        host="0.0.0.0",
        port=API_PORT,
        log_level="info",
        reload=False,
    )
