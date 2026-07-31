from datetime import datetime, timedelta
from typing import Optional
from jose import JWTError, jwt
from passlib.context import CryptContext
from fastapi import HTTPException, status, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session
from .database import SessionLocal, Admin
from .schemas import TokenData
import os
import secrets
import string
import hashlib
from collections import defaultdict
from dotenv import load_dotenv

load_dotenv()

# Changer bcrypt → argon2 (pas de limite 72 bytes)
pwd_context = CryptContext(schemes=["argon2"], deprecated="auto")
security = HTTPBearer()

SECRET_KEY = os.getenv("SECRET_KEY")
ALGORITHM = os.getenv("ALGORITHM")
ACCESS_TOKEN_EXPIRE_MINUTES = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES"))

# Stockage des tentatives échouées par compte
# Structure: {mail: [timestamp1, timestamp2, ...]}
failed_attempts = defaultdict(list)
MAX_FAILED_ATTEMPTS = 3
LOCKOUT_DURATION_MINUTES = 15


def verify_password(plain_password, hashed_password):
    return pwd_context.verify(plain_password, hashed_password)


def get_password_hash(password):
    return pwd_context.hash(password)


def is_account_locked(mail: str) -> bool:
    """Vérifie si le compte est verrouillé après trop d'échecs"""
    now = datetime.utcnow()
    
    # Nettoyer les anciennes tentatives (> 15 min)
    failed_attempts[mail] = [
        t for t in failed_attempts[mail]
        if now - t < timedelta(minutes=LOCKOUT_DURATION_MINUTES)
    ]
    
    # Vérifier si le compte est verrouillé
    if len(failed_attempts[mail]) >= MAX_FAILED_ATTEMPTS:
        # Calculer le temps restant
        last_attempt = failed_attempts[mail][-1]
        unlock_time = last_attempt + timedelta(minutes=LOCKOUT_DURATION_MINUTES)
        minutes_left = int((unlock_time - now).total_seconds() / 60)
        
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Compte temporairement verrouillé. Réessayez dans {minutes_left} minutes."
        )
    
    return False


def record_failed_attempt(mail: str):
    """Enregistre une tentative échouée"""
    failed_attempts[mail].append(datetime.utcnow())


def reset_failed_attempts(mail: str):
    """Réinitialise les tentatives échouées après succès"""
    failed_attempts[mail] = []


def authenticate_admin(db: Session, mail: str, password: str):
    # Vérifier si le compte est verrouillé
    try:
        is_account_locked(mail)
    except HTTPException:
        raise
    
    admin = db.query(Admin).filter(Admin.mail == mail).first()
    
    if not admin or not verify_password(password, admin.hashed_password):
        # Enregistrer l'échec
        record_failed_attempt(mail)
        
        # Vérifier si le compte vient d'être verrouillé
        remaining_attempts = MAX_FAILED_ATTEMPTS - len(failed_attempts[mail])
        
        if remaining_attempts <= 0:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Compte verrouillé pendant {LOCKOUT_DURATION_MINUTES} minutes suite à {MAX_FAILED_ATTEMPTS} tentatives échouées."
            )
        else:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail=f"Mot de passe incorrect. {remaining_attempts} tentative(s) restante(s) avant verrouillage."
            )
    
    # Réinitialiser les échecs après succès
    reset_failed_attempts(mail)
    return admin


def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    to_encode = data.copy()
    expire = datetime.utcnow() + (expires_delta or timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES))
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


def get_current_admin(token: HTTPAuthorizationCredentials = Depends(security)) -> Admin:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token.credentials, SECRET_KEY, algorithms=[ALGORITHM])
        mail = payload.get("sub")
        if mail is None:
            raise credentials_exception
        token_data = TokenData(mail=mail)
    except JWTError:
        raise credentials_exception
    
    db = SessionLocal()
    admin = db.query(Admin).filter(Admin.mail == token_data.mail).first()
    db.close()
    
    if admin is None:
        raise credentials_exception
    return admin


def generate_reset_token() -> str:
    """Génère un token aléatoire de 32 caractères"""
    alphabet = string.ascii_letters + string.digits
    return ''.join(secrets.choice(alphabet) for _ in range(32))


def hash_token(token: str) -> str:
    """Hash le token pour le stockage en base de données"""
    return hashlib.sha256(token.encode()).hexdigest()