# app/routers/employees.py
# from backend.app.database import Data
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from typing import List
from ..database import SessionLocal, Employee, Data
from ..schemas import EmployeeCreate, EmployeeOut, DataOut
from ..auth import get_current_admin
from ..database import Admin
from datetime import datetime, timedelta
from sqlalchemy import case, func

router = APIRouter(prefix="/employees", tags=["employees"])

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# Cache simple en mémoire (pas de Redis, pas de dépendance externe)
_status_cache = {}
CACHE_TTL_SEC = 10

def get_cached_status(last_seen):
    """Retourne le statut sans recalculer si déjà en cache et récent."""
    if last_seen is None:
        return "offline"
    
    now = datetime.now()
    cache_key = last_seen.isoformat()
    
    cached = _status_cache.get(cache_key)
    if cached:
        status, cached_time = cached
        if (now - cached_time).seconds < CACHE_TTL_SEC:
            return status
    
    # Calcul
    delta = now - last_seen
    if delta < timedelta(minutes=2):
        status = "online"
    elif delta < timedelta(minutes=15):
        status = "away"
    else:
        status = "offline"
    
    # Nettoyer le cache si trop grand (>100 entrées)
    if len(_status_cache) > 100:
        _status_cache.clear()
    
    _status_cache[cache_key] = (status, now)
    return status





# ========== GET tous les employés ==========
@router.get("/", response_model=List[EmployeeOut])
def get_all_employees(
    db: Session = Depends(get_db),
    current_admin: Admin = Depends(get_current_admin)
):
    """
    Récupère tous les employés avec statut calculé en SQL (pas de boucle Python).
    """
    now = datetime.now()
    two_min_ago = now - timedelta(minutes=2)
    fifteen_min_ago = now - timedelta(minutes=15)
    
    employees = db.query(Employee).all()
    
    # Calcul du statut avec cache (évite datetime.now() N fois)
    for emp in employees:
        emp.status = get_cached_status(emp.last_seen)
    
    return employees






# ========== GET un employé par ID ==========
@router.get("/{id_bracelet}", response_model=EmployeeOut)
def get_employee(
    id_bracelet: str,
    db: Session = Depends(get_db),
    current_admin: Admin = Depends(get_current_admin)
):
    employee = db.query(Employee).filter(Employee.id_bracelet == id_bracelet).first()
    if not employee:
        raise HTTPException(status_code=404, detail="Employee not found")
    
    employee.status = get_cached_status(employee.last_seen)
    
    return employee
    
# ========== POST créer un employé ==========
@router.post("/", response_model=EmployeeOut, status_code=status.HTTP_201_CREATED)
def create_employee(
    employee: EmployeeCreate,
    db: Session = Depends(get_db),
    current_admin: Admin = Depends(get_current_admin)
):
    """Créer un nouvel employé"""
    # Vérifier si l'employé existe déjà
    existing = db.query(Employee).filter(Employee.id_bracelet == employee.id_bracelet).first()
    if existing:
        raise HTTPException(status_code=400, detail="Bracelet ID already exists")
    
    # Créer le nouvel employé
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


# ========== PUT modifier un employé ==========
@router.put("/{id_bracelet}", response_model=EmployeeOut)
def update_employee(
    id_bracelet: str,
    employee: EmployeeCreate,
    db: Session = Depends(get_db),
    current_admin: Admin = Depends(get_current_admin)
):
    """Modifier un employé existant"""
    db_employee = db.query(Employee).filter(Employee.id_bracelet == id_bracelet).first()
    if not db_employee:
        raise HTTPException(status_code=404, detail="Employee not found")
    
    db_employee.firstName = employee.firstName
    db_employee.lastName = employee.lastName
    db_employee.metier = employee.metier
    
    db.commit()
    db.refresh(db_employee)
    return db_employee


# ========== DELETE supprimer un employé ==========
@router.delete("/{id_bracelet}", status_code=status.HTTP_204_NO_CONTENT)
def delete_employee(
    id_bracelet: str,
    db: Session = Depends(get_db),
    current_admin: Admin = Depends(get_current_admin)
):
    """Supprimer un employé"""
    employee = db.query(Employee).filter(Employee.id_bracelet == id_bracelet).first()
    if not employee:
        raise HTTPException(status_code=404, detail="Employee not found")
    
    #supprimer aussi ses données de fatigue
    db.query(Data).filter(Data.id_bracelet == id_bracelet).delete()

    db.delete(employee)
    db.commit()
    return None