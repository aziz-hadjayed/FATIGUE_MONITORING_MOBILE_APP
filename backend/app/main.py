# backend/app/main.py
from contextlib import asynccontextmanager
import threading

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from .routers import auth, employees, ws
from app.middleware.rate_limit import RateLimitMiddleware
from app.middleware.logging import LoggingMiddleware
from app.LoRa.realDATA import run_reception
import logging
from logging.handlers import RotatingFileHandler

from .database import init_db
import os




# Créer le dossier logs si besoin
os.makedirs("/var/log", exist_ok=True)

# Configurer le logger
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        RotatingFileHandler(
            "/var/log/fastapi.log",      # ← ← FICHIER LOG
            maxBytes=10*1024*1024,       # 10 MB max par fichier
            backupCount=5                  # Garde 5 fichiers de backup
        ),
        logging.StreamHandler()           # Console aussi
    ]
)

logger = logging.getLogger("fastapi")


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    print("Base de données initialisée")

    lora_stop_event = threading.Event()
    lora_thread = threading.Thread(
        target=run_reception,
        args=(lora_stop_event,),
        name="LoRaReception",
        daemon=True
    )

    # Garde-fou déploiement: la réception LoRa lit un port série physique.
    # Le service FastAPI DOIT tourner avec un seul worker (uvicorn sans --workers
    # ou --workers 1), sinon plusieurs processus liront le même /dev/ttyAMA0.
    app.state.lora_stop_event = lora_stop_event
    app.state.lora_thread = lora_thread
    lora_thread.start()

    try:
        yield
    finally:
        lora_stop_event.set()
        lora_thread.join(timeout=10)


app = FastAPI(title="Fatigue Detection API", version="1.0", lifespan=lifespan)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://conduit-heavily-kudos.ngrok-free.dev",],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["*"],
)

# Rate limiting
# 60 requêtes max par fenêtre de 60 secondes (1 minute)
app.add_middleware(RateLimitMiddleware, requests_per_minute=60, window=60)


# LOGGING pour Fail2Ban
# Doit être APRES le RateLimitMiddleware
app.add_middleware(LoggingMiddleware)

# ============================================================
# ROUTERS API
# ============================================================
app.include_router(auth.router)
app.include_router(employees.router)
app.include_router(ws.router, prefix="/ws", tags=["websocket"])

# ============================================================
# SERVE THE FLUTTER FRONTEND (BUILD/WEB)
# ============================================================
frontend_path = os.path.join(os.path.dirname(__file__), "../../frontend/build/web")

if os.path.exists(frontend_path):
    print(f"Frontend found: {frontend_path}")
    
    # Servir les assets statiques
    app.mount("/assets", StaticFiles(directory=os.path.join(frontend_path, "assets")), name="assets")
    
    @app.get("/")
    async def serve_root():
        return FileResponse(os.path.join(frontend_path, "index.html"))
    
    @app.get("/{path:path}")
    async def serve_frontend(path: str):
        # Ignorer les routes API (elles sont gérées par les routers)
        if path.startswith("auth/") or path.startswith("employees/") or path.startswith("data/") or path.startswith("ws"):
            return FileResponse(os.path.join(frontend_path, "index.html"))
        
        # Servir les fichiers statiques (CSS, JS, etc.)
        file_path = os.path.join(frontend_path, path)
        if os.path.exists(file_path) and os.path.isfile(file_path):
            return FileResponse(file_path)
        
        # Retourner index.html pour les routes SPA (Flutter)
        return FileResponse(os.path.join(frontend_path, "index.html"))
else:
    print(f" Frontend non trouvé: {frontend_path}")
    print("   Pour générer le frontend:")
    print("   cd frontend && flutter build web --release")


