from sqlalchemy import create_engine, Column, Integer, String, DateTime, func, Float, Boolean, TypeDecorator
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
import os
from cryptography.fernet import Fernet
from dotenv import load_dotenv

load_dotenv()

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(os.path.dirname(BASE_DIR), "database.db")

# Clé de chiffrement depuis .env
DB_KEY = os.getenv("DB_ENCRYPTION_KEY")
if not DB_KEY:
    raise ValueError("DB_ENCRYPTION_KEY manquant dans .env")

cipher = Fernet(DB_KEY.encode())

# ============================================================================
# TYPE CHIFFRE POUR SQLALCHEMY
# ============================================================================

class EncryptedString(TypeDecorator):
    """Type SQLAlchemy qui chiffre/déchiffre automatiquement"""
    impl = String
    
    def process_bind_param(self, value, dialect):
        if value is None:
            return None
        return cipher.encrypt(value.encode()).decode()
    
    def process_result_value(self, value, dialect):
        if value is None:
            return None
        return cipher.decrypt(value.encode()).decode()


# ============================================================================
# DATABASE
# ============================================================================

engine = create_engine(f"sqlite:///{DB_PATH}", connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


class Admin(Base):
    __tablename__ = "admins"
    id = Column(Integer, primary_key=True, index=True)
    mail = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)
    fullname = Column(EncryptedString, nullable=False)  # ← Chiffré
    created_at = Column(DateTime, server_default=func.now())
    reset_password_token = Column(String, nullable=True)
    reset_password_expire = Column(DateTime, nullable=True)


class Employee(Base):
    __tablename__ = "employees"
    id_bracelet = Column(Integer, primary_key=True, index=True)
    firstName = Column(EncryptedString, nullable=False)  # ← Chiffré
    lastName = Column(EncryptedString, nullable=False)   # ← Chiffré
    role = Column(EncryptedString, nullable=False)       # ← Chiffré
    created_at = Column(DateTime, server_default=func.now())
    last_seen = Column(DateTime, nullable=True, default=None)


class Data(Base):
    __tablename__ = "data"
    id = Column(Integer, primary_key=True, index=True)
    timestamp = Column(DateTime, nullable=False)
    state = Column(Integer, nullable=False)
    id_bracelet = Column(Integer, nullable=False)
    confidence = Column(Float, nullable=False)
    confidence_vision = Column(Float, nullable=False, default=0.0)
    vision_timestamp = Column(DateTime, nullable=True)


def init_db():
    Base.metadata.create_all(bind=engine)