# backend/app/routers/ws.py
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from sqlalchemy.orm import Session
from datetime import datetime, timedelta
import asyncio
import json
from .employees import get_cached_status   

from app.database import SessionLocal, Data, Employee

router = APIRouter()

class ConnectionManager:
    """Gère les connexions WebSocket actives."""
    def __init__(self):
        self.active_connections: dict[int, WebSocket] = {}

    async def connect(self, employee_id: int, websocket: WebSocket):
        await websocket.accept()
        self.active_connections[employee_id] = websocket

    def disconnect(self, employee_id: int):
        self.active_connections.pop(employee_id, None)

manager = ConnectionManager()


@router.websocket("/{employee_id}")
async def employee_websocket(websocket: WebSocket, employee_id: int):
    """
    WebSocket par employé.
    - get_history : envoie TOUT l'historique
    - get_history_range:YYYY-MM-DD : envoie l'historique par date
    - Temps réel : toutes les 5 secondes
    """
    # Vérifier que l'employé existe
    db: Session = SessionLocal()
    try:
        employee = db.query(Employee).filter(Employee.id_bracelet == employee_id).first()
        if not employee:
            await websocket.close(code=4004, reason="Employee not found")
            return
    finally:
        db.close()

    await manager.connect(employee_id, websocket)
    print(f"🔌 WebSocket connecté : bracelet #{employee_id}")

    # ─── Initialiser le dernier timestamp ───
    db = SessionLocal()
    last_timestamp = None
    try:
        latest = (
            db.query(Data)
            .filter(Data.id_bracelet == employee_id)
            .order_by(Data.timestamp.desc())
            .first()
        )
        if latest:
            last_timestamp = latest.timestamp
            print(f" Dernier timestamp: {last_timestamp}")
    finally:
        db.close()

    # ─── Boucle WebSocket ──────────────────────────────────────────
    try:
        while True:
            try:
                # Attendre un message du client (timeout 5 secondes)
                data = await asyncio.wait_for(websocket.receive_text(), timeout=5.0)
                
                # ─── Gérer les commandes ──────────────────────────
                if data == "get_history":
                    #  Envoyer TOUT l'historique
                    await send_history(websocket, employee_id)
                
                elif data.startswith("get_history_range:"):
                    #  Envoyer l'historique par date
                    date_str = data.split(":")[1]
                    await send_history_range(websocket, employee_id, date_str)
                
                elif data == "ping":
                    await websocket.send_json({"pong": "ok"})
                else:
                    await websocket.send_json({"error": f"Commande inconnue: {data}"})
                    
            except asyncio.TimeoutError:
                # ─── TOUTES LES 5 SECONDES : VÉRIFIER LES NOUVELLES DONNÉES ───
                if last_timestamp is not None:
                    db = SessionLocal()
                    try:
                        new_data = (
                            db.query(Data)
                            .filter(Data.id_bracelet == employee_id)
                            .filter(Data.timestamp > last_timestamp)
                            .order_by(Data.timestamp.asc())
                            .all()
                        )
                        
                        if new_data:
                            for record in new_data:
                                await websocket.send_json(_record_payload(record))
                                await asyncio.sleep(0.005)
                            
                            last_timestamp = new_data[-1].timestamp
                            print(f"{len(new_data)} nouvelles données temps réel pour bracelet #{employee_id}")
                    finally:
                        db.close()
                continue

    except WebSocketDisconnect as e:
        print(
            f"🔌 WebSocket déconnecté : bracelet #{employee_id} "
            f"(code={getattr(e, 'code', 'unknown')})"
        )
    except Exception as e:
        print(f" Erreur WebSocket bracelet #{employee_id}: {type(e).__name__}: {e}")
    finally:
        manager.disconnect(employee_id)

@router.websocket("/{employee_id}")
async def employee_websocket(websocket: WebSocket, employee_id: int):
    """
    WebSocket par employé.
    - get_history : envoie TOUT l'historique
    - get_history_range:YYYY-MM-DD : envoie l'historique par date
    - Temps réel : toutes les 5 secondes
    """
    # Vérifier que l'employé existe
    db: Session = SessionLocal()
    try:
        employee = db.query(Employee).filter(Employee.id_bracelet == employee_id).first()
        if not employee:
            await websocket.close(code=4004, reason="Employee not found")
            return
    finally:
        db.close()

    await manager.connect(employee_id, websocket)
    print(f" WebSocket connecté : bracelet #{employee_id}")

    # ─── Initialiser le dernier timestamp ───
    db = SessionLocal()
    last_timestamp = None
    try:
        latest = (
            db.query(Data)
            .filter(Data.id_bracelet == employee_id)
            .order_by(Data.timestamp.desc())
            .first()
        )
        if latest:
            last_timestamp = latest.timestamp
            print(f" Dernier timestamp: {last_timestamp}")
    finally:
        db.close()

    # ─── Boucle WebSocket ──────────────────────────────────────────
    try:
        while True:
            try:
                # Attendre un message du client (timeout 5 secondes)
                data = await asyncio.wait_for(websocket.receive_text(), timeout=5.0)
                
                # ─── Gérer les commandes ──────────────────────────
                if data == "get_history":
                    #  Envoyer TOUT l'historique
                    await send_history(websocket, employee_id)
                
                elif data.startswith("get_history_range:"):
                    #  Envoyer l'historique par date
                    date_str = data.split(":")[1]
                    await send_history_range(websocket, employee_id, date_str)
                
                elif data == "ping":
                    await websocket.send_json({"pong": "ok"})
                else:
                    await websocket.send_json({"error": f"Commande inconnue: {data}"})
                    
            except asyncio.TimeoutError:
                # ─── TOUTES LES 5 SECONDES : VÉRIFIER LES NOUVELLES DONNÉES ───
                if last_timestamp is not None:
                    db = SessionLocal()
                    try:
                        new_data = (
                            db.query(Data)
                            .filter(Data.id_bracelet == employee_id)
                            .filter(Data.timestamp > last_timestamp)
                            .order_by(Data.timestamp.asc())
                            .all()
                        )
                        
                        if new_data:
                            # ← AJOUT : Calculer le statut UNE FOIS pour tout le batch (Pi4 optimisé)
                            status = get_cached_status(employee.last_seen) if employee else "offline"
                            # ← FIN AJOUT
                            
                            for record in new_data:
                                # ← MODIFIER : passer le statut pré-calculé
                                await websocket.send_json(_record_payload(record, status))
                                # ← FIN MODIFIER
                                await asyncio.sleep(0.005)
                            
                            last_timestamp = new_data[-1].timestamp
                            print(f" {len(new_data)} nouvelles données temps réel pour bracelet #{employee_id}")
                    finally:
                        db.close()
                continue

    except WebSocketDisconnect as e:
        print(
            f" WebSocket déconnecté : bracelet #{employee_id} "
            f"(code={getattr(e, 'code', 'unknown')})"
        )
    except Exception as e:
        print(f" Erreur WebSocket bracelet #{employee_id}: {type(e).__name__}: {e}")
    finally:
        manager.disconnect(employee_id)
# ─── Fonctions auxiliaires ──────────────────────────────────────────

async def send_history(websocket: WebSocket, employee_id: int):
    """Envoyer TOUT l'historique (toutes les données)."""
    batch_size = 500
    db = SessionLocal()
    try:
        history = (
            db.query(Data)
            .filter(Data.id_bracelet == employee_id)
            .order_by(Data.timestamp.asc())
            .all()
        )
        
        if history:
            for index in range(0, len(history), batch_size):
                batch = history[index:index + batch_size]
                await websocket.send_json({
                    "type": "history_batch",
                    "items": [_record_payload(record) for record in batch],
                })
                await asyncio.sleep(0.02)
            
            print(f" Historique complet envoyé: {len(history)} données pour bracelet #{employee_id}")
        else:
            await websocket.send_json({"error": "Aucune donnée historique"})
    finally:
        db.close()


async def send_history_range(websocket: WebSocket, employee_id: int, date_str: str):
    """Envoyer l'historique pour une date spécifique."""
    batch_size = 500
    try:
        target_date = datetime.strptime(date_str, "%Y-%m-%d")
        start_date = target_date.replace(hour=0, minute=0, second=0)
        end_date = target_date.replace(hour=23, minute=59, second=59)
        
        db = SessionLocal()
        try:
            history = (
                db.query(Data)
                .filter(Data.id_bracelet == employee_id)
                .filter(Data.timestamp >= start_date)
                .filter(Data.timestamp <= end_date)
                .order_by(Data.timestamp.asc())
                .all()
            )
            
            if history:
                for index in range(0, len(history), batch_size):
                    batch = history[index:index + batch_size]
                    await websocket.send_json({
                        "type": "history_batch",
                        "items": [_record_payload(record) for record in batch],
                    })
                    await asyncio.sleep(0.02)
                
                print(f" Historique envoyé pour {date_str}: {len(history)} données")
            else:
                await websocket.send_json({"error": f"Aucune donnée pour {date_str}"})
        finally:
            db.close()
    except Exception as e:
        await websocket.send_json({"error": f"Date invalide: {e}"})


def _record_payload(record: Data, status: str = "offline", last_seen=None):
    return {
        "id_bracelet": str(record.id_bracelet),
        "timestamp": record.timestamp.isoformat(),
        "state": str(record.state),
        "confidence_vision": record.confidence_vision,
        "status": status,
        "last_seen": last_seen.isoformat() if last_seen else None
    }
