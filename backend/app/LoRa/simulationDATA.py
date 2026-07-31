# ═══════════════════════════════════════════════════════════════════════
# backend/app/LoRa/simulationDATA.py
# Génération temps réel : 1 thread par bracelet existant dans Employee
# AVEC DÉTECTION VISAGE TFLITE
# ═══════════════════════════════════════════════════════════════════════

# ─── CONFIGURATION (variables modifiables en haut) ────────────────────
PERIOD_SEC = 2.0           # Période entre données i et i+1 (secondes)
SIMULATION_MIN = 480        # Durée totale de simulation (minutes)
USE_SIMULATION = False      # True = simulation sans caméra, False = avec caméra réelle
# ─────────────────────────────────────────────────────────────────────

import sys
import os
import threading
import time
import random
import datetime

# Ajouter le parent de LoRa (app/) au path pour les imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from database import Employee, Data, engine, SessionLocal
from schemas import DataCreate
from image.camera import CLASS_MAPPING, detect_fatigue_from_camera_for_bracelet, init_vision

# ─── Fonctions utilitaires ────────────────────────────────────────────
def get_existing_bracelets():
    """Récupère tous les id_bracelet existants dans Employee."""
    db = SessionLocal()
    try:
        employees = db.query(Employee).all()
        return [emp.id_bracelet for emp in employees]
    finally:
        db.close()

def generate_data_point(id_bracelet):
    """
    Génère un point de données avec détection vision
    
    La détection vision est déclenchée UNIQUEMENT si state == 3 (fatigue)
    """
    # 1. Générer le state aléatoire (0,1,2,3)
    state = random.choice([0, 1, 2, 3])
    confidence = round(random.uniform(0.0, 1.0), 3)
    
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

def insert_data(db, data_create, detection_info=None,flush_last_seen=False):
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

# ─── Worker Thread (1 par bracelet) ───────────────────────────────────
def bracelet_worker(id_bracelet, period_sec, stop_event):
    """
    Boucle de génération optimisée : last_seen flushé toutes les 5 insertions.
    """
    db = SessionLocal()
    insert_counter = 0
    try:
        while not stop_event.is_set():
            data_create, detection_info = generate_data_point(id_bracelet)
            
            # Flush last_seen toutes les 5 insertions (pas à chaque fois)
            insert_counter += 1
            flush = (insert_counter % 5 == 0)
            
            insert_data(db, data_create, detection_info, flush_last_seen=flush)
            
            time.sleep(period_sec)
    finally:
        db.close()

# ─── Orchestrateur principal ─────────────────────────────────────────
def run_simulation():
    """Lance 1 thread par bracelet existant."""
    print(f"\n{'='*60}")
    print("  SIMULATION DE DONNÉES - Table Data AVEC VISION")
    print(f"{'='*60}")
    print(f"  Période             : {PERIOD_SEC} sec")
    print(f"  Durée simulation    : {SIMULATION_MIN} min")
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
        print(" ERREUR : Aucun bracelet dans Employee !")
        return

    nb_threads = len(bracelet_ids)
    print(f" Bracelets trouvés : {nb_threads}")
    print(f" Bracelets actifs  : {bracelet_ids}\n")

    stop_event = threading.Event()
    threads = []

    for b_id in bracelet_ids:
        t = threading.Thread(
            target=bracelet_worker,
            args=(b_id, PERIOD_SEC, stop_event),
            name=f"Bracelet-{b_id}"
        )
        t.start()
        threads.append(t)

    # Attendre la durée configurée
    simulation_sec = SIMULATION_MIN * 60
    print(f" Simulation en cours ({simulation_sec}s) avec {nb_threads} threads...")
    print(" La détection vision est activée UNIQUEMENT quand state == 3 (FATIGUE)\n")
    time.sleep(simulation_sec)

    # Arrêt propre de tous les threads
    print("\n Arrêt demandé...")
    stop_event.set()
    for t in threads:
        t.join()

    print(f"\n{'='*60}")
    print("   SIMULATION TERMINÉE")
    print(f"{'='*60}")

# ─── Point d'entrée ───────────────────────────────────────────────────
if __name__ == "__main__":
    run_simulation()
