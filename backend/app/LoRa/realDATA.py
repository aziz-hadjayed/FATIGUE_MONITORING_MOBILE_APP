# ═══════════════════════════════════════════════════════════════════════
# backend/app/LoRa/realDATA.py
# Réception temps réel LoRa UART : bracelets -> table Data
# AVEC DÉTECTION VISAGE TFLITE
# ═══════════════════════════════════════════════════════════════════════

# ─── CONFIGURATION (variables modifiables en haut) ────────────────────
SERIAL_PORT = "/dev/ttyAMA0"
BAUDRATE = 9600
SERIAL_RECONNECT_SEC = 3.0
SERIAL_TIMEOUT_SEC = 1.0
MAX_LINE_BYTES = 256
QUEUE_MAXSIZE = 200
MAX_WORKERS = 4
MIN_FRAME_INTERVAL_SEC = 0.5
USE_SIMULATION_LORA = True
USE_SIMULATION = False      # True = simulation sans caméra, False = avec caméra réelle
# ─────────────────────────────────────────────────────────────────────

import sys
import os
import threading
import time
import random
import datetime
import json
import queue
from concurrent.futures import ThreadPoolExecutor
from json import JSONDecodeError

from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator

try:
    import serial
except ImportError:
    serial = None

# Ajouter le parent de LoRa (app/) au path pour les imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from database import Employee, Data, engine, SessionLocal
from schemas import DataCreate
from image.camera import CLASS_MAPPING, detect_fatigue_from_camera_for_bracelet, init_vision


class LoRaFrameIn(BaseModel):
    """Schéma strict des trames JSON reçues par LoRa."""

    model_config = ConfigDict(extra="forbid", strict=True)

    id: int = Field(ge=0)
    state: int = Field(alias="class")
    confidence: float = Field(ge=0.0, le=1.0)

    @field_validator("state")
    def validate_state(cls, v):
        if v not in [0, 1, 2, 3]:
            raise ValueError("state must be 0, 1, 2, or 3")
        return v


# ─── Fonctions utilitaires ────────────────────────────────────────────
def sanitize_for_log(value, max_len=120):
    """Supprime les caractères de contrôle et tronque avant affichage."""
    text = str(value)
    safe = "".join(ch if ch.isprintable() and ch not in "\x1b\r\n\t" else "?" for ch in text)
    if len(safe) > max_len:
        return safe[:max_len] + "..."
    return safe


def get_existing_bracelets():
    """Récupère tous les id_bracelet existants dans Employee."""
    db = SessionLocal()
    try:
        employees = db.query(Employee).all()
        return [emp.id_bracelet for emp in employees]
    finally:
        db.close()


def parse_lora_line(raw_line):
    """Valide strictement une ligne UART et retourne une LoRaFrameIn ou None."""
    if len(raw_line) > MAX_LINE_BYTES:
        print(f" Trame LoRa trop longue ({len(raw_line)} octets), ignorée")
        return None

    try:
        line = raw_line.decode("utf-8").strip()
    except UnicodeDecodeError as exc:
        print(f" Trame LoRa non UTF-8, ignorée: {sanitize_for_log(exc)}")
        return None

    if not line:
        return None

    try:
        payload = json.loads(line)
    except JSONDecodeError as exc:
        print(f" JSON LoRa invalide, ignoré: {sanitize_for_log(exc)}")
        return None

    try:
        return LoRaFrameIn.model_validate(payload)
    except ValidationError as exc:
        print(f" Schéma LoRa invalide, trame ignorée: {sanitize_for_log(exc)}")
        return None


def generate_data_point(id_bracelet, state, confidence):
    """
    Génère un point de données avec détection vision

    La détection vision est déclenchée UNIQUEMENT si state == 3 (fatigue)
    """
    # 1. Les valeurs viennent de la trame LoRa validée
    confidence = round(float(confidence), 3)

    # 2. Variables par défaut
    confidence_vision = 0.0
    vision_timestamp = None
    detection_info = {}

    # 3. SI state == 3 (fatigue) → déclencher la vision
    if state == 3:
        target_person = CLASS_MAPPING.get(id_bracelet, f"Bracelet_{id_bracelet}")
        print(f"🔍 [Bracelet #{id_bracelet} / {target_person}] State=3 (FATIGUE) → Détection vision...")

        # Appel des modèles TFLite pour détecter la fatigue
        is_fatigue_vision, conf_vision, info = detect_fatigue_from_camera_for_bracelet(
            bracelet_id=id_bracelet,
            use_simulation=USE_SIMULATION
        )
        if info:
            print(f"    Détails vision: {info}")
            if "detection_inference_time_ms" in info:
                print(
                    "   ⏱ Temps vision: "
                    f"détection={info.get('detection_inference_time_ms', 0.0):.2f}ms | "
                    f"classification={info.get('classification_inference_time_ms', 0.0):.2f}ms | "
                    f"total={info.get('total_vision_time_ms', 0.0):.2f}ms"
                )

        # 4. Vérifier si la vision confirme la fatigue
        if is_fatigue_vision:
            confidence_vision = 1.0
            vision_timestamp = datetime.datetime.now()
            print(f"    Vision CONFIRME fatigue (Conf: {conf_vision:.1%})")
        else:
            confidence_vision = 0.0
            vision_timestamp = datetime.datetime.now()
            print(f"    Vision INFIRME fatigue (Conf: {conf_vision:.1%})")

        detection_info = info
    else:
        # Pas de détection vision si state != 3
        print(f"   [Bracelet #{id_bracelet}] State={state} → Pas de vision")

    # 5. Créer l'objet DataCreate avec les nouvelles colonnes
    return DataCreate(
        timestamp=datetime.datetime.now(),
        state=state,
        id_bracelet=id_bracelet,
        confidence=confidence,
        confidence_vision=confidence_vision,
        vision_timestamp=vision_timestamp
    ), detection_info


def insert_data(db, data_create, detection_info=None, flush_last_seen=False):
    """
    Insère dans la table Data après validation Pydantic.
    Inclut confidence_vision et vision_timestamp.
    """
    db_item = Data(
        timestamp=data_create.timestamp,
        state=data_create.state,
        id_bracelet=data_create.id_bracelet,
        confidence=data_create.confidence,
        confidence_vision=data_create.confidence_vision,
        vision_timestamp=data_create.vision_timestamp
    )
    db.add(db_item)
    if flush_last_seen:
        employee = db.query(Employee).filter(Employee.id_bracelet == data_create.id_bracelet).first()
        if employee:
            employee.last_seen = data_create.timestamp

    db.commit()

    # Affichage formaté
    vision_str = f"Vision: {data_create.confidence_vision}" if data_create.confidence_vision is not None else "Vision: N/A"
    print(f"[{data_create.timestamp.strftime('%H:%M:%S.%f')[:-3]}] "
          f"Thread={threading.current_thread().name} | "
          f"Bracelet #{data_create.id_bracelet} | State={data_create.state} | "
          f"Conf={data_create.confidence} | {vision_str}")


class LoRaSerialReader(threading.Thread):
    """Lit les trames LoRa UART et pousse les payloads validés dans une queue."""

    def __init__(self, frame_queue, stop_event):
        super().__init__(name="LoRaSerialReader", daemon=True)
        self.frame_queue = frame_queue
        self.stop_event = stop_event

    def run(self):
        if USE_SIMULATION_LORA:
            self._run_simulation()
            return

        if serial is None:
            print("pyserial n'est pas installé, exécutez: pip install pyserial")
            self.stop_event.set()
            return

        while not self.stop_event.is_set():
            try:
                print(f"📡 Ouverture LoRa UART: {SERIAL_PORT} @ {BAUDRATE} bauds")
                with serial.Serial(SERIAL_PORT, BAUDRATE, timeout=SERIAL_TIMEOUT_SEC) as ser:
                    print("📡 LoRa UART connecté")
                    while not self.stop_event.is_set():
                        raw_line = ser.readline()
                        if not raw_line:
                            continue
                        self._handle_raw_line(raw_line)
            except OSError as exc:
                print(f" Erreur port LoRa ({sanitize_for_log(exc)}), reconnexion dans {SERIAL_RECONNECT_SEC}s")
                self.stop_event.wait(SERIAL_RECONNECT_SEC)
            except Exception as exc:
                print(f" Erreur LoRa inattendue ({sanitize_for_log(exc)}), reprise dans {SERIAL_RECONNECT_SEC}s")
                self.stop_event.wait(SERIAL_RECONNECT_SEC)

    def _run_simulation(self):
        print("📡 Mode LoRa simulé activé")
        bracelet_ids = get_existing_bracelets() or [1]
        while not self.stop_event.is_set():
            payload = {
                "id": random.choice(bracelet_ids),
                "class": random.choice([0, 1, 2, 3]),
                "confidence": round(random.uniform(0.0, 1.0), 3),
            }
            raw_line = (json.dumps(payload) + "\n").encode("utf-8")
            self._handle_raw_line(raw_line)
            self.stop_event.wait(2.0)

    def _handle_raw_line(self, raw_line):
        frame = parse_lora_line(raw_line)
        if frame is None:
            return

        try:
            self.frame_queue.put(frame, timeout=0.2)
        except queue.Full:
            print(" Queue LoRa pleine, trame ignorée")


def process_frame(frame, flush_last_seen=False):
    """Traite une trame avec sa propre session SQLAlchemy."""
    db = SessionLocal()
    try:
        employee = db.query(Employee).filter(Employee.id_bracelet == frame.id).first()
        if not employee:
            print(f" Bracelet inconnu #{frame.id}, trame ignorée")
            return

        data_create, detection_info = generate_data_point(
            id_bracelet=frame.id,
            state=frame.state,
            confidence=frame.confidence
        )
        insert_data(db, data_create, detection_info, flush_last_seen=flush_last_seen)
    except Exception as exc:
        db.rollback()
        print(f" Erreur traitement trame LoRa: {sanitize_for_log(exc)}")
    finally:
        db.close()


# ─── Orchestrateur principal ─────────────────────────────────────────
def run_reception(stop_event=None):
    """Lance la réception LoRa et le traitement asynchrone des trames."""
    print(f"\n{'='*60}")
    print("  RÉCEPTION LoRa - Table Data AVEC VISION")
    print(f"{'='*60}")
    print(f"  Port série          : {SERIAL_PORT}")
    print(f"  Baudrate            : {BAUDRATE}")
    print(f"  Mode LoRa           : {'SIMULATION' if USE_SIMULATION_LORA else 'UART RÉEL'}")
    print(f"  Mode vision         : {'SIMULATION' if USE_SIMULATION else 'CAMÉRA RÉELLE'}")
    print(f"{'='*60}\n")

    # Initialiser les modèles TFLite
    print("🔧 Initialisation des modèles TFLite...")
    if init_vision():
        print(" Modèles TFLite chargés avec succès")
    else:
        print(" Erreur chargement modèles TFLite, la vision ne fonctionnera pas")

    bracelet_ids = get_existing_bracelets()

    if not bracelet_ids:
        print(" AVERTISSEMENT : Aucun bracelet dans Employee au démarrage !")
        print(" La réception LoRa démarre quand même; les bracelets seront vérifiés à chaque trame.\n")
    else:
        print(f" Bracelets trouvés : {len(bracelet_ids)}")
        print(f" Bracelets actifs  : {bracelet_ids}\n")

    print(" Réception en cours...")
    print(" La détection vision est activée UNIQUEMENT quand state == 3 (FATIGUE)\n")

    if stop_event is None:
        stop_event = threading.Event()

    frame_queue = queue.Queue(maxsize=QUEUE_MAXSIZE)
    reader = LoRaSerialReader(frame_queue, stop_event)

    insert_counters = {}
    last_processed_at = {}
    counters_lock = threading.Lock()

    reader.start()

    try:
        with ThreadPoolExecutor(max_workers=MAX_WORKERS, thread_name_prefix="LoRaWorker") as executor:
            while not stop_event.is_set():
                try:
                    frame = frame_queue.get(timeout=0.5)
                except queue.Empty:
                    continue

                now = time.monotonic()
                with counters_lock:
                    previous = last_processed_at.get(frame.id)
                    if previous is not None and now - previous < MIN_FRAME_INTERVAL_SEC:
                        print(f" Débit trop élevé Bracelet #{frame.id}, trame ignorée")
                        frame_queue.task_done()
                        continue

                    last_processed_at[frame.id] = now
                    insert_counters[frame.id] = insert_counters.get(frame.id, 0) + 1
                    flush = (insert_counters[frame.id] % 5 == 0)

                future = executor.submit(process_frame, frame, flush)
                future.add_done_callback(lambda _future: frame_queue.task_done())
    except KeyboardInterrupt:
        print("\n Arrêt demandé...")
    finally:
        stop_event.set()
        reader.join(timeout=SERIAL_RECONNECT_SEC + 1.0)
        print(f"\n{'='*60}")
        print("   RÉCEPTION LoRa TERMINÉE")
        print(f"{'='*60}")


# ─── Point d'entrée ───────────────────────────────────────────────────
if __name__ == "__main__":
    run_reception()
