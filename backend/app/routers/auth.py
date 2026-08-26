# backend/app/routers/auth.py
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPBearer
from sqlalchemy.orm import Session
from typing import List
from datetime import datetime, timedelta
import os
import socket
import subprocess
import re
from dotenv import load_dotenv

from ..database import SessionLocal, Admin, Employee, Data
from ..schemas import (
    AdminCreate, AdminLogin, AdminOut, Token,
    EmployeeCreate, EmployeeOut, DataCreate, DataOut,
    ForgotPasswordRequest, ResetPasswordRequest, UpdateProfileRequest
)
from ..auth import (
    get_password_hash, authenticate_admin, create_access_token,
    get_current_admin, generate_reset_token, hash_token
)
from ..services.email_service import email_service

load_dotenv()

router = APIRouter(prefix="/auth", tags=["auth"])
security = HTTPBearer()

# ─── Configuration ────────────────────────────────────────────────────
FRONTEND_URL = os.getenv("FRONTEND_URL")
RESET_PATH = os.getenv("RESET_PASSWORD_PATH", "/#/reset-password")
ENVIRONMENT = os.getenv("ENVIRONMENT", "development")
FLUTTER_PORT = os.getenv("FLUTTER_PORT", "3000")

# ─── Helper Functions ────────────────────────────────────────────────
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def get_local_ip() -> str:
    """
    Récupère l'IP locale du réseau de manière robuste
    """
    # Méthode 1: Socket
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        if ip and ip != "127.0.0.1":
            return ip
    except:
        pass
    
    # Méthode 2: hostname -I (Linux/Mac)
    try:
        result = subprocess.run(
            ["hostname", "-I"],
            capture_output=True,
            text=True,
            timeout=1
        )
        ips = result.stdout.strip().split()
        for ip in ips:
            if ip and not ip.startswith("127.") and "." in ip:
                return ip
    except:
        pass
    
    # Méthode 3: ifconfig (Linux/Mac)
    try:
        result = subprocess.run(
            ["ifconfig"],
            capture_output=True,
            text=True,
            timeout=1
        )
        # Chercher les adresses IPv4
        ip_pattern = r'inet\s+(\d+\.\d+\.\d+\.\d+)'
        ips = re.findall(ip_pattern, result.stdout)
        for ip in ips:
            if ip and not ip.startswith("127."):
                return ip
    except:
        pass
    
    # Méthode 4: ipconfig (Windows)
    try:
        result = subprocess.run(
            ["ipconfig"],
            capture_output=True,
            text=True,
            timeout=1
        )
        ip_pattern = r'IPv4 Address[.\s]+:\s+(\d+\.\d+\.\d+\.\d+)'
        ips = re.findall(ip_pattern, result.stdout)
        for ip in ips:
            if ip and not ip.startswith("127."):
                return ip
    except:
        pass
    
    # Fallback
    return "192.168.1.100"  # IP par défaut


def get_all_ips() -> List[str]:
    """
    Récupère toutes les IPs locales disponibles
    """
    ips = []
    
    # Méthode 1: hostname -I
    try:
        result = subprocess.run(
            ["hostname", "-I"],
            capture_output=True,
            text=True,
            timeout=1
        )
        for ip in result.stdout.strip().split():
            if ip and not ip.startswith("127.") and "." in ip:
                ips.append(ip)
    except:
        pass
    
    # Méthode 2: ifconfig
    try:
        result = subprocess.run(
            ["ifconfig"],
            capture_output=True,
            text=True,
            timeout=1
        )
        ip_pattern = r'inet\s+(\d+\.\d+\.\d+\.\d+)'
        for ip in re.findall(ip_pattern, result.stdout):
            if ip and not ip.startswith("127.") and ip not in ips:
                ips.append(ip)
    except:
        pass
    
    # Méthode 3: socket
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        if ip and not ip.startswith("127.") and ip not in ips:
            ips.append(ip)
    except:
        pass
    
    # Si aucune IP trouvée, ajouter une IP par défaut
    if not ips:
        ips = ["192.168.1.100"]
    
    return ips


def build_reset_url(token: str) -> str:
    """
    Construit l'URL de reset avec IP automatique
    """
    reset_path = os.getenv("RESET_PASSWORD_PATH", "/#/reset-password")
    flutter_port = os.getenv("FLUTTER_PORT", "3000")
    environment = os.getenv("ENVIRONMENT", "development")
    
    # 1. Si FRONTEND_URL est défini dans .env, l'utiliser
    frontend_url = os.getenv("FRONTEND_URL")
    if frontend_url:
        return f"{frontend_url}{reset_path}?token={token}"
    
    # 2. Si c'est la production, utiliser le domaine
    if environment == "production":
        domain = os.getenv("DOMAIN", "fatigue-monitoring.com")
        return f"https://{domain}{reset_path}?token={token}"
    
    # 3. Développement: utiliser l'IP automatique
    local_ip = get_local_ip()
    
    # URLs possibles
    urls = [
        f"https://{local_ip}:{flutter_port}{reset_path}?token={token}",
        f"https://10.0.2.2:{flutter_port}{reset_path}?token={token}",  # Émulateur Android
        f"https://localhost:{flutter_port}{reset_path}?token={token}",  # Localhost
    ]
    
    # Ajouter les autres IPs trouvées
    all_ips = get_all_ips()
    for ip in all_ips:
        if ip != local_ip:
            urls.append(f"https://{ip}:{flutter_port}{reset_path}?token={token}")
    
    # Logger toutes les URLs disponibles
    print("\n" + "=" * 70)
    print(" RESET URLs disponibles:")
    for i, url in enumerate(urls, 1):
        print(f"  {i}. {url}")
    print("=" * 70 + "\n")
    
    # Retourner la première URL comme principale
    return urls[0]


def get_flutter_web_url() -> str:
    """
    Récupère l'URL complète de l'application Flutter Web
    """
    frontend_url = os.getenv("FRONTEND_URL")
    if frontend_url:
        return frontend_url
    
    local_ip = get_local_ip()
    flutter_port = os.getenv("FLUTTER_PORT", "3000")
    
    # Essayer plusieurs URLs
    urls = [
        f"https://{local_ip}:{flutter_port}",
        f"https://10.0.2.2:{flutter_port}",
        f"https://localhost:{flutter_port}",
    ]
    
    # Afficher toutes les URLs
    print("\n Application Flutter disponible sur:")
    for url in urls:
        print(f"  • {url}")
    print()
    
    return urls[0]

# ==================== AUTHENTICATION ====================

@router.post("/signup", response_model=Token)
def signup(admin: AdminCreate, db: Session = Depends(get_db)):
    """
    Inscription d'un nouvel administrateur
    """
    # Vérifier si l'email existe déjà
    existing = db.query(Admin).filter(Admin.mail == admin.mail).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email already registered"
        )
    
    # Hasher le mot de passe
    hashed = get_password_hash(admin.password)
    
    # Créer l'admin
    db_admin = Admin(
        mail=admin.mail,
        hashed_password=hashed,
        fullname=admin.fullname
    )
    db.add(db_admin)
    db.commit()
    db.refresh(db_admin)
    
    # Générer le token
    access_token = create_access_token(data={"sub": admin.mail})
    
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "id": db_admin.id,
        "mail": db_admin.mail,
        "fullname": db_admin.fullname
    }


@router.post("/login", response_model=Token)
def login(admin: AdminLogin, db: Session = Depends(get_db)):
    """
    Connexion d'un administrateur avec protection anti-brute force par compte
    """
    try:
        # Authentifier (vérifie aussi le verrouillage)
        authenticated = authenticate_admin(db, admin.mail, admin.password)
    except HTTPException as e:
        # Propager l'erreur (401 ou 403)
        raise e
    
    # Récupérer l'admin
    db_admin = db.query(Admin).filter(Admin.mail == admin.mail).first()
    
    # Générer le token
    access_token = create_access_token(data={"sub": admin.mail})
    
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "id": db_admin.id,
        "mail": db_admin.mail,
        "fullname": db_admin.fullname
    }

@router.post("/logout")
def logout(current_admin: Admin = Depends(get_current_admin)):
    """
    Déconnexion - côté client uniquement
    """
    return {
        "success": True,
        "message": "Logged out successfully"
    }


@router.get("/profile", response_model=AdminOut)
def get_profile(current_admin: Admin = Depends(get_current_admin)):
    """
    Récupérer le profil de l'admin connecté
    """
    return current_admin


@router.put("/profile", response_model=Token)
def update_profile(
    update_data: UpdateProfileRequest,
    current_admin: Admin = Depends(get_current_admin),
    db: Session = Depends(get_db)
):
    """
    Mettre à jour le profil de l'admin connecté
    """
    #  Récupérer l'admin depuis la base avec la session actuelle
    admin = db.query(Admin).filter(Admin.id == current_admin.id).first()
    
    if not admin:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Admin not found"
        )
    
    # Mettre à jour le nom
    if update_data.fullname:
        admin.fullname = update_data.fullname
    
    # Mettre à jour l'email
    if update_data.mail:
        # Vérifier si l'email est déjà pris
        existing = db.query(Admin).filter(
            Admin.mail == update_data.mail,
            Admin.id != admin.id
        ).first()
        if existing:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Email already in use"
            )
        admin.mail = update_data.mail
    
    db.commit()
    db.refresh(admin)
    
    # Générer un nouveau token
    access_token = create_access_token(data={"sub": admin.mail})
    
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "id": admin.id,
        "mail": admin.mail,
        "fullname": admin.fullname
    }

# ==================== FORGOT / RESET PASSWORD ====================

@router.post("/forgot-password")
def forgot_password(
    request: ForgotPasswordRequest,
    db: Session = Depends(get_db)
):
    """
    Envoie un email avec un lien de réinitialisation
    """
    # Vérifier si l'admin existe
    admin = db.query(Admin).filter(Admin.mail == request.mail).first()
    
    #  Pour des raisons de sécurité, on ne révèle pas si l'email existe
    if not admin:
        return {
            "message": "If your email is registered, you will receive a reset link"
        }
    
    # Générer un token
    reset_token = generate_reset_token()
    hashed_token = hash_token(reset_token)
    
    # Sauvegarder le token hashé dans la BDD
    admin.reset_password_token = hashed_token
    admin.reset_password_expire = datetime.utcnow() + timedelta(minutes=10)
    db.commit()
    
    #  Construire l'URL de reset avec IP automatique
    reset_url = build_reset_url(reset_token)
    
    #  Afficher l'URL d'accès à l'application
    app_url = get_flutter_web_url()
    print(f"\n Accéder à l'application sur: {app_url}")
    
    #  Envoyer l'email
    email_sent = email_service.send_reset_password_email(
        to_email=admin.mail,
        reset_url=reset_url,
        token=reset_token
    )
    
    # Log pour debug
    print("=" * 70)
    print(f" RESET PASSWORD EMAIL")
    print(f"To: {admin.mail}")
    print(f" Reset Link: {reset_url}")
    print(f" Token: {reset_token}")
    print(f" Email sent: {email_sent}")
    print("=" * 70 + "\n")
    
    return {
        "message": "If your email is registered, you will receive a reset link"
    }


@router.post("/reset-password")
def reset_password(
    request: ResetPasswordRequest,
    db: Session = Depends(get_db)
):
    """
    Réinitialise le mot de passe avec le token reçu par email
    """
    # Hasher le token reçu
    hashed_token = hash_token(request.token)
    
    # Chercher l'admin avec le token valide et non expiré
    admin = db.query(Admin).filter(
        Admin.reset_password_token == hashed_token,
        Admin.reset_password_expire > datetime.utcnow()
    ).first()
    
    if not admin:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired token"
        )
    
    # Mettre à jour le mot de passe
    admin.hashed_password = get_password_hash(request.new_password)
    
    # Effacer le token (usage unique)
    admin.reset_password_token = None
    admin.reset_password_expire = None
    
    db.commit()
    
    return {
        "success": True,
        "message": "Password reset successfully"
    }

# ==================== EMPLOYEE MANAGEMENT ====================

@router.post("/employees", response_model=EmployeeOut)
def create_employee(
    employee: EmployeeCreate,
    db: Session = Depends(get_db),
    current_admin: Admin = Depends(get_current_admin)
):
    """
    Créer un nouvel employé (admin uniquement)
    """
    # Vérifier si l'employé existe déjà
    existing = db.query(Employee).filter(
        Employee.id_bracelet == employee.id_bracelet
    ).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Employee with this bracelet ID already exists"
        )
    
    db_employee = Employee(
        id_bracelet=employee.id_bracelet,
        firstName=employee.firstName,
        lastName=employee.lastName,
        role=employee.role
    )
    db.add(db_employee)
    db.commit()
    db.refresh(db_employee)
    return db_employee


@router.get("/employees", response_model=List[EmployeeOut])
def get_employees(
    db: Session = Depends(get_db),
    current_admin: Admin = Depends(get_current_admin)
):
    """
    Récupérer tous les employés (admin uniquement)
    """
    return db.query(Employee).all()


@router.get("/employees/{id_bracelet}", response_model=EmployeeOut)
def get_employee(
    id_bracelet: int,
    db: Session = Depends(get_db),
    current_admin: Admin = Depends(get_current_admin)
):
    """
    Récupérer un employé par son ID de bracelet (admin uniquement)
    """
    employee = db.query(Employee).filter(
        Employee.id_bracelet == id_bracelet
    ).first()
    if not employee:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Employee not found"
        )
    return employee


@router.put("/employees/{id_bracelet}", response_model=EmployeeOut)
def update_employee(
    id_bracelet: int,
    employee_update: EmployeeCreate,
    db: Session = Depends(get_db),
    current_admin: Admin = Depends(get_current_admin)
):
    """
    Mettre à jour un employé (admin uniquement)
    """
    employee = db.query(Employee).filter(
        Employee.id_bracelet == id_bracelet
    ).first()
    if not employee:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Employee not found"
        )
    
    employee.firstName = employee_update.firstName
    employee.lastName = employee_update.lastName
    employee.role = employee_update.role
    
    db.commit()
    db.refresh(employee)
    return employee


@router.delete("/employees/{id_bracelet}")
def delete_employee(
    id_bracelet: int,
    db: Session = Depends(get_db),
    current_admin: Admin = Depends(get_current_admin)
):
    """
    Supprimer un employé (admin uniquement)
    """
    employee = db.query(Employee).filter(
        Employee.id_bracelet == id_bracelet
    ).first()
    if not employee:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Employee not found"
        )
    
    db.delete(employee)
    db.commit()
    return {
        "success": True,
        "message": f"Employee {id_bracelet} deleted successfully"
    }


# ==================== DATA MANAGEMENT ====================

@router.post("/data", response_model=DataOut)
def create_data(
    data: DataCreate,
    db: Session = Depends(get_db),
    current_admin: Admin = Depends(get_current_admin)
):
    """
    Ajouter des données de fatigue pour un employé (admin uniquement)
    """
    # Vérifier que l'employé existe
    employee = db.query(Employee).filter(
        Employee.id_bracelet == data.id_bracelet
    ).first()
    if not employee:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Employee not found"
        )
    
    db_data = Data(
        timestamp=data.timestamp,
        state=data.state,
        id_bracelet=data.id_bracelet,
        confidence=data.confidence
    )
    db.add(db_data)
    db.commit()
    db.refresh(db_data)
    return db_data


@router.get("/data/{id_bracelet}", response_model=List[DataOut])
def get_employee_data(
    id_bracelet: int,
    limit: int = 100,
    db: Session = Depends(get_db),
    current_admin: Admin = Depends(get_current_admin)
):
    """
    Récupérer les données de fatigue d'un employé (admin uniquement)
    """
    # Vérifier que l'employé existe
    employee = db.query(Employee).filter(
        Employee.id_bracelet == id_bracelet
    ).first()
    if not employee:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Employee not found"
        )
    
    return db.query(Data).filter(
        Data.id_bracelet == id_bracelet
    ).order_by(Data.timestamp.desc()).limit(limit).all()


@router.get("/data/{id_bracelet}/latest", response_model=DataOut)
def get_latest_data(
    id_bracelet: int,
    db: Session = Depends(get_db),
    current_admin: Admin = Depends(get_current_admin)
):
    """
    Récupérer la dernière donnée de fatigue d'un employé (admin uniquement)
    """
    # Vérifier que l'employé existe
    employee = db.query(Employee).filter(
        Employee.id_bracelet == id_bracelet
    ).first()
    if not employee:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Employee not found"
        )
    
    data = db.query(Data).filter(
        Data.id_bracelet == id_bracelet
    ).order_by(Data.timestamp.desc()).first()
    
    if not data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No data found for this employee"
        )
    return data
