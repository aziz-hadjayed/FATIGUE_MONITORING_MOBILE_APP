from cryptography.fernet import Fernet
import os

# Clé depuis variable d'environnement
KEY = os.getenv("DB_ENCRYPTION_KEY").encode()
cipher = Fernet(KEY)

def encrypt(value: str) -> str:
    return cipher.encrypt(value.encode()).decode()

def decrypt(encrypted: str) -> str:
    return cipher.decrypt(encrypted.encode()).decode()