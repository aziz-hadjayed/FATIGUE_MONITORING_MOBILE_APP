"""
Module de vision par ordinateur pour la détection de fatigue
Utilise TensorFlow Lite pour la détection de visage et la classification fatigue
"""

import cv2
import numpy as np
import os
import logging
from typing import Dict, List, Tuple
import threading
import json
import time
from datetime import datetime

try:
    from tflite_runtime.interpreter import Interpreter
    TFLITE_RUNTIME_NAME = "tflite-runtime"
except ImportError:
    from tensorflow.lite.python.interpreter import Interpreter
    TFLITE_RUNTIME_NAME = "tensorflow"

logger = logging.getLogger(__name__)

# ============================================
# CONFIGURATION
# ============================================

# Chemins des modèles (absolus depuis backend/)
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) # backend/app/image
BACKEND_DIR = os.path.dirname(BASE_DIR) # backend/
DETECTION_MODEL_PATH = os.path.join(BACKEND_DIR, "yolov8n_detect_int8.tflite") # backend/yolov8n_detect_int8.tflite
CLASSIFICATION_MODEL_PATH = os.path.join(BACKEND_DIR, "yolov8n_classify_int8.tflite") # backend/yolov8n_classify_int8.tflite
VISION_DEBUG_LOG = os.path.join(BACKEND_DIR, "vision_debug.jsonl") # backend/vision_debug.jsonl

# Paramètres vision
CONF_THRESHOLD = 0.25
IOU_THRESHOLD = 0.45
IMG_SIZE_DET = 640
IMG_SIZE_CLS = 224
DEBUG_TOP_CANDIDATES = 5

_cap = None
# Couleurs pour affichage
COLOR_FATIGUE = (0, 0, 255)      # Rouge
COLOR_NON_FATIGUE = (0, 255, 0)  # Vert

# Mapping classes détection (à ajuster selon votre dataset)
# {0: 'ayoub_BA', 1: 'aziz_HA', 2: 'koukou', 3: 'mema_sousou'}
CLASS_MAPPING = {
    0: 'ayoub_BA',
    1: 'aziz_HA', 
    2: 'koukou',
    3: 'mema_sousou'
}

# Mapping inverse: nom -> id
INVERSE_CLASS_MAPPING = {v: k for k, v in CLASS_MAPPING.items()}

# ============================================
# CHARGEMENT DES MODÈLES (lazy loading)
# ============================================

_det_model = None
_cls_model = None
_det_input = None
_det_output = None
_cls_input = None
_cls_output = None
_det_lock = threading.Lock()
_cls_lock = threading.Lock()
_camera_lock = threading.Lock()
_last_detection_debug = {}
_last_detection_inference_time_ms = 0.0
_last_classification_inference_time_ms = 0.0


def write_vision_debug(event: Dict):
    """Écrit un événement debug lisible par Codex et par le terminal."""
    try:
        event = {
            'timestamp': datetime.now().isoformat(timespec='seconds'),
            **event
        }
        with open(VISION_DEBUG_LOG, "a", encoding="utf-8") as f:
            f.write(json.dumps(event, ensure_ascii=False) + "\n")
    except Exception as exc:
        logger.warning(f"Impossible d'écrire le debug vision: {exc}")

def load_models():
    """Charge les modèles TensorFlow Lite (lazy loading)."""
    global _det_model, _cls_model, _det_input, _det_output, _cls_input, _cls_output
    
    if _det_model is None:
        logger.info(f" Chargement modèle détection: {DETECTION_MODEL_PATH}")
        if not os.path.exists(DETECTION_MODEL_PATH):
            logger.error(f" Fichier non trouvé: {DETECTION_MODEL_PATH}")
            return False
        
        _det_model = Interpreter(model_path=DETECTION_MODEL_PATH)
        _det_model.allocate_tensors()
        _det_input = _det_model.get_input_details()[0]
        _det_output = _det_model.get_output_details()[0]
        logger.info(
            f" Détection TFLite chargée avec {TFLITE_RUNTIME_NAME}: "
            f"input={_det_input['shape']} output={_det_output['shape']}"
        )
    
    if _cls_model is None:
        logger.info(f" Chargement modèle classification: {CLASSIFICATION_MODEL_PATH}")
        if not os.path.exists(CLASSIFICATION_MODEL_PATH):
            logger.error(f"Fichier non trouvé: {CLASSIFICATION_MODEL_PATH}")
            return False
        
        _cls_model = Interpreter(model_path=CLASSIFICATION_MODEL_PATH)
        _cls_model.allocate_tensors()
        _cls_input = _cls_model.get_input_details()[0]
        _cls_output = _cls_model.get_output_details()[0]
        logger.info(
            f"Classification TFLite chargée avec {TFLITE_RUNTIME_NAME}: "
            f"input={_cls_input['shape']} output={_cls_output['shape']}"
        )
    
    return True

def get_detection_model():
    """Retourne le modèle de détection"""
    if _det_model is None:
        load_models()
    return _det_model

def get_classification_model():
    """Retourne le modèle de classification"""
    if _cls_model is None:
        load_models()
    return _cls_model

# ============================================
# TRAITEMENT DES IMAGES
# ============================================

def preprocess_face_for_classification(face_roi, target_size=224):
    """
    Prétraite le ROI visage pour le modèle de classification
    """
    if face_roi is None or face_roi.size == 0:
        return None
    
    face_letterboxed, _, _, _ = letterbox_image(face_roi, target_size)
    face_rgb = cv2.cvtColor(face_letterboxed, cv2.COLOR_BGR2RGB)
    
    return face_rgb


def letterbox_image(image, target_size, color=(114, 114, 114)):
    """Redimensionne avec padding et retourne les infos pour remettre les boxes à l'échelle."""
    h, w = image.shape[:2]
    ratio = min(target_size / w, target_size / h)
    new_w, new_h = int(round(w * ratio)), int(round(h * ratio))
    resized = cv2.resize(image, (new_w, new_h), interpolation=cv2.INTER_LINEAR)

    pad_w = target_size - new_w
    pad_h = target_size - new_h
    left = int(round(pad_w / 2 - 0.1))
    right = int(round(pad_w / 2 + 0.1))
    top = int(round(pad_h / 2 - 0.1))
    bottom = int(round(pad_h / 2 + 0.1))

    padded = cv2.copyMakeBorder(resized, top, bottom, left, right, cv2.BORDER_CONSTANT, value=color)
    return padded, ratio, left, top


def prepare_tflite_input(image_rgb, input_detail):
    """Prépare une image RGB selon le dtype et le layout du modèle TFLite."""
    dtype = input_detail["dtype"]
    tensor = image_rgb.astype(dtype)
    if np.issubdtype(dtype, np.floating):
        tensor = tensor / 255.0

    tensor = np.expand_dims(tensor, axis=0)
    shape = input_detail["shape"]
    if len(shape) == 4 and shape[1] == 3:
        tensor = tensor.transpose(0, 3, 1, 2)
    return tensor


def run_tflite(interpreter, input_detail, output_detail, input_tensor, lock):
    """Exécute une inférence TFLite; les interpreters ne sont pas thread-safe."""
    with lock:
        interpreter.set_tensor(input_detail["index"], input_tensor)
        interpreter.invoke()
        return interpreter.get_tensor(output_detail["index"])


def xywh_to_xyxy(boxes):
    xyxy = np.empty_like(boxes)
    xyxy[:, 0] = boxes[:, 0] - boxes[:, 2] / 2
    xyxy[:, 1] = boxes[:, 1] - boxes[:, 3] / 2
    xyxy[:, 2] = boxes[:, 0] + boxes[:, 2] / 2
    xyxy[:, 3] = boxes[:, 1] + boxes[:, 3] / 2
    return xyxy


def nms_boxes(boxes, scores, iou_threshold):
    if len(boxes) == 0:
        return []

    x1, y1, x2, y2 = boxes.T
    areas = np.maximum(0, x2 - x1) * np.maximum(0, y2 - y1)
    order = scores.argsort()[::-1]
    keep = []

    while order.size > 0:
        i = order[0]
        keep.append(i)

        xx1 = np.maximum(x1[i], x1[order[1:]])
        yy1 = np.maximum(y1[i], y1[order[1:]])
        xx2 = np.minimum(x2[i], x2[order[1:]])
        yy2 = np.minimum(y2[i], y2[order[1:]])

        inter_w = np.maximum(0, xx2 - xx1)
        inter_h = np.maximum(0, yy2 - yy1)
        inter = inter_w * inter_h
        union = areas[i] + areas[order[1:]] - inter
        iou = inter / np.maximum(union, 1e-6)

        order = order[1:][iou <= iou_threshold]

    return keep


def classify_fatigue(face_roi) -> Tuple[str, float, bool]:
    """
    Classifie un visage en Fatigue / Non-Fatigue
    
    该函数用于对人脸图像进行疲劳分类判断
    Args:
        face_roi: 人脸区域图像，将用于疲劳分类
    Returns:
        tuple: (label, confidence, is_fatigue)
    """
    # 加载分类模型
    cls_model = get_classification_model()
    # 检查模型是否加载成功
    if cls_model is None:
        return "Erreur", 0.0, False
    
    # 检查预处理是否成功
    face_processed = preprocess_face_for_classification(face_roi, IMG_SIZE_CLS)
    
    if face_processed is None:
    # 使用全局变量记录上一次分类推理时间
        return "Erreur", 0.0, False
    
    # 准备TensorFlow Lite输入张量
    global _last_classification_inference_time_ms
    # 记录推理开始时间

    # 运行TensorFlow Lite模型进行推理
    input_tensor = prepare_tflite_input(face_processed, _cls_input)
    # 计算并更新推理耗时
    start = time.perf_counter()
    # 压缩输出并获取概率值
    output = run_tflite(cls_model, _cls_input, _cls_output, input_tensor, _cls_lock)
    _last_classification_inference_time_ms = round((time.perf_counter() - start) * 1000, 2)
    probs = np.squeeze(output)
    pred = int(np.argmax(probs))
    confidence = float(probs[pred])

    # 根据预测结果返回相应的标签和状态
    if pred == 0:
        return "FATIGUE", confidence, True
    if pred == 1:
        return "NON-FATIGUE", confidence, False
    
    # 如果预测结果不是0或1，返回未知状态
    return "INCONNU", 0.0, False


def detect_faces(frame) -> List[Dict]:
    """
    Détecte les visages dans une image
    
    Returns:
        List de dict avec {bbox, confidence, class_id, class_name}
    """
    det_model = get_detection_model()
    if det_model is None:
        return []
    
    height, width = frame.shape[:2]
    frame_letterboxed, ratio, pad_left, pad_top = letterbox_image(frame, IMG_SIZE_DET)
    frame_rgb = cv2.cvtColor(frame_letterboxed, cv2.COLOR_BGR2RGB)
    input_tensor = prepare_tflite_input(frame_rgb, _det_input)
    global _last_detection_debug, _last_detection_inference_time_ms

    start = time.perf_counter()
    output = run_tflite(det_model, _det_input, _det_output, input_tensor, _det_lock)
    _last_detection_inference_time_ms = round((time.perf_counter() - start) * 1000, 2)

    predictions = np.squeeze(output)
    if predictions.ndim == 2 and predictions.shape[0] < predictions.shape[1]:
        predictions = predictions.T

    boxes_xywh = predictions[:, :4]
    class_scores = predictions[:, 4:]
    class_ids = np.argmax(class_scores, axis=1)
    scores = np.max(class_scores, axis=1)
    top_order = scores.argsort()[::-1][:DEBUG_TOP_CANDIDATES]
    top_candidates = [
        {
            'class_id': int(class_ids[i]),
            'class_name': CLASS_MAPPING.get(int(class_ids[i]), f"Classe_{int(class_ids[i])}"),
            'confidence': float(scores[i]),
            'box_xywh': tuple(float(v) for v in boxes_xywh[i])
        }
        for i in top_order
    ]
    _last_detection_debug = {
        'threshold': CONF_THRESHOLD,
        'detection_inference_time_ms': _last_detection_inference_time_ms,
        'raw_output_shape': tuple(int(v) for v in np.shape(output)),
        'top_candidates': top_candidates
    }
    valid = scores >= CONF_THRESHOLD

    boxes_xywh = boxes_xywh[valid].copy()
    if len(boxes_xywh) > 0 and float(np.max(boxes_xywh)) <= 2.0:
        boxes_xywh[:, [0, 2]] *= IMG_SIZE_DET
        boxes_xywh[:, [1, 3]] *= IMG_SIZE_DET

    boxes = xywh_to_xyxy(boxes_xywh)
    scores = scores[valid]
    class_ids = class_ids[valid]

    if len(boxes) > 0:
        boxes[:, [0, 2]] = (boxes[:, [0, 2]] - pad_left) / ratio
        boxes[:, [1, 3]] = (boxes[:, [1, 3]] - pad_top) / ratio
        boxes[:, [0, 2]] = np.clip(boxes[:, [0, 2]], 0, width)
        boxes[:, [1, 3]] = np.clip(boxes[:, [1, 3]], 0, height)

    keep = nms_boxes(boxes, scores, IOU_THRESHOLD)

    faces = []
    for idx in keep:
        x1, y1, x2, y2 = boxes[idx].astype(int)
        cls_id = int(class_ids[idx])
        class_name = CLASS_MAPPING.get(cls_id, f"Classe_{cls_id}")

        faces.append({
            'bbox': (int(x1), int(y1), int(x2), int(y2)),
            'confidence': float(scores[idx]),
            'class_id': cls_id,
            'class_name': class_name
        })

    if faces:
        detected = ", ".join(
            f"{face['class_name']}#{face['class_id']} ({face['confidence']:.2f})"
            for face in faces
        )
        logger.info(f"Visages détectés: {detected}")
    else:
        logger.warning(f"Aucun visage après seuil {CONF_THRESHOLD}. Top candidats: {top_candidates}")
    
    return faces


def process_image_for_bracelet(frame, bracelet_id: int) -> Tuple[bool, float, Dict]:
    """
    Traite une image pour un bracelet spécifique
    
    IMPORTANT: La fatigue n'est confirmée QUE SI la personne correspondante 
    est détectée dans l'image.
    """
    # 1. Détection des visages
    total_start = time.perf_counter()
    faces = detect_faces(frame)
    
    if not faces:
        total_vision_time_ms = round((time.perf_counter() - total_start) * 1000, 2)
        logger.warning(f"Aucun visage détecté pour bracelet {bracelet_id}")
        return False, 0.0, {
            'error': 'No face detected',
            'person_found': False,
            'target_class_id': bracelet_id,
            'target_person': CLASS_MAPPING.get(bracelet_id, f"Bracelet_{bracelet_id}"),
            'detection_inference_time_ms': _last_detection_inference_time_ms,
            'classification_inference_time_ms': 0.0,
            'total_vision_time_ms': total_vision_time_ms,
            'debug': _last_detection_debug
        }
    
    # 2. Chercher UNIQUEMENT la personne correspondant au bracelet_id
    target_face = None
    for face in faces:
        if face['class_id'] == bracelet_id:
            target_face = face
            break
    
    # 3. SI la personne n'est PAS trouvée → PAS de confirmation
    if target_face is None:
        total_vision_time_ms = round((time.perf_counter() - total_start) * 1000, 2)
        detected = ", ".join(
            f"{face['class_name']}#{face['class_id']} ({face['confidence']:.2f})"
            for face in faces
        )
        logger.warning(f"Personne avec ID {bracelet_id} NON trouvée dans l'image")
        return False, 0.0, {
            'error': f'Person with ID {bracelet_id} not found in image',
            'person_found': False,
            'target_class_id': bracelet_id,
            'target_person': CLASS_MAPPING.get(bracelet_id, f"Bracelet_{bracelet_id}"),
            'faces_detected': [f['class_name'] for f in faces],
            'faces_detected_details': detected,
            'detection_inference_time_ms': _last_detection_inference_time_ms,
            'classification_inference_time_ms': 0.0,
            'total_vision_time_ms': total_vision_time_ms,
            'debug': _last_detection_debug
        }
    
    # 4. La personne est trouvée → Classification fatigue
    x1, y1, x2, y2 = target_face['bbox']
    face_roi = frame[y1:y2, x1:x2]
    
    if face_roi.size == 0:
        total_vision_time_ms = round((time.perf_counter() - total_start) * 1000, 2)
        return False, 0.0, {
            'error': 'Empty ROI',
            'person_found': True,
            'target_class_id': bracelet_id,
            'target_person': CLASS_MAPPING.get(bracelet_id, f"Bracelet_{bracelet_id}"),
            'bbox': target_face['bbox'],
            'frame_shape': tuple(int(v) for v in frame.shape),
            'detection_inference_time_ms': _last_detection_inference_time_ms,
            'classification_inference_time_ms': 0.0,
            'total_vision_time_ms': total_vision_time_ms,
            'debug': _last_detection_debug
        }
    
    # 5. Classification fatigue
    label, confidence, is_fatigue = classify_fatigue(face_roi)
    total_vision_time_ms = round((time.perf_counter() - total_start) * 1000, 2)
    
    detection_info = {
        'face_detected': True,
        'person_name': target_face['class_name'],
        'class_id': target_face['class_id'],
        'detection_confidence': target_face['confidence'],
        'fatigue_label': label,
        'fatigue_confidence': confidence,
        'bbox': target_face['bbox'],
        'person_found': True,
        'detection_inference_time_ms': _last_detection_inference_time_ms,
        'classification_inference_time_ms': _last_classification_inference_time_ms,
        'total_vision_time_ms': total_vision_time_ms
    }
    
    logger.info(
        f"Bracelet {bracelet_id} ({target_face['class_name']}): {label} ({confidence:.1%}) | "
        f"detect={_last_detection_inference_time_ms:.2f}ms "
        f"classify={_last_classification_inference_time_ms:.2f}ms "
        f"total={total_vision_time_ms:.2f}ms"
    )
    
    return is_fatigue, confidence, detection_info
def simulate_frame_for_bracelet(bracelet_id: int) -> Tuple[bool, float, Dict]:
    """
    Simule une image pour un bracelet (quand pas de caméra)
    Utilisé pour le développement sans caméra
    """
    # Simuler une image avec OpenCV
    import numpy as np
    
    # Créer une image synthétique
    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    
    # Dessiner un visage simulé
    center_x, center_y = 320, 240
    
    # Cercle pour le visage
    cv2.circle(frame, (center_x, center_y), 100, (200, 200, 200), -1)
    
    # Yeux
    cv2.circle(frame, (center_x - 40, center_y - 30), 20, (255, 255, 255), -1)
    cv2.circle(frame, (center_x + 40, center_y - 30), 20, (255, 255, 255), -1)
    cv2.circle(frame, (center_x - 40, center_y - 30), 10, (0, 0, 0), -1)
    cv2.circle(frame, (center_x + 40, center_y - 30), 10, (0, 0, 0), -1)
    
    # Bouche
    if bracelet_id % 2 == 0:  # Simulation fatigue
        cv2.ellipse(frame, (center_x, center_y + 40), (30, 15), 0, 0, 360, (0, 0, 255), -1)
        is_fatigue = True
        confidence = 0.92
    else:
        cv2.ellipse(frame, (center_x, center_y + 40), (30, 15), 0, 0, 180, (0, 255, 0), 2)
        is_fatigue = False
        confidence = 0.85
    
    detection_info = {
        'face_detected': True,
        'person_name': CLASS_MAPPING.get(bracelet_id, f"Personne_{bracelet_id}"),
        'class_id': bracelet_id,
        'detection_confidence': 0.95,
        'fatigue_label': "FATIGUE" if is_fatigue else "NON-FATIGUE",
        'fatigue_confidence': confidence,
        'bbox': (center_x-100, center_y-120, center_x+100, center_y+100)
    }
    
    return is_fatigue, confidence, detection_info


# ============================================
# FONCTION PRINCIPALE POUR LE BRACELET
# ============================================
def get_camera():
    """Ouvre la caméra une seule fois et la garde active."""
    global _cap
    if _cap is None or not _cap.isOpened():
        _cap = cv2.VideoCapture(0)
    return _cap
def detect_fatigue_from_camera_for_bracelet(bracelet_id: int, use_simulation: bool = True) -> Tuple[bool, float, Dict]:
    """
    Détecte la fatigue pour un bracelet donné
    
    Args:
        bracelet_id: ID du bracelet
        use_simulation: Si True, utilise la simulation (pas de caméra)
    
    Returns:
        tuple: (is_fatigue, confidence_vision, detection_info)
    """
    if use_simulation:
        # Mode simulation (pour développement)
        return simulate_frame_for_bracelet(bracelet_id)
    
    # Mode réel (avec caméra). Un seul thread doit ouvrir la caméra à la fois.
    with _camera_lock:
        try:
            logger.info(...)
            cap = get_camera()
            if not cap.isOpened():
                logger.warning("Impossible d'ouvrir la caméra, utilisation de la simulation")
                return simulate_frame_for_bracelet(bracelet_id)

            ret, frame = cap.read()  # une seule lecture, caméra déjà "chaude"
            if not ret or frame is None:
                logger.warning("Erreur lecture caméra, utilisation de la simulation")
                return simulate_frame_for_bracelet(bracelet_id)

            return process_image_for_bracelet(frame, bracelet_id)

        except Exception as e:
            logger.error(f" Erreur caméra: {e}")
            return simulate_frame_for_bracelet(bracelet_id)
    # plus de cap.release() ici -- on la garde ouverte pour le prochain appel



def init_vision():
    """Initialise les modèles TensorFlow Lite."""
    return load_models()
