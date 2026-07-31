from pydantic import BaseModel, EmailStr,field_validator
from datetime import datetime
from typing import Optional

class AdminCreate(BaseModel):
    mail: EmailStr
    password: str
    fullname: str

class AdminLogin(BaseModel):
    mail: EmailStr
    password: str

class AdminOut(BaseModel):
    id: int
    mail: EmailStr
    fullname: str

    class Config:
        from_attributes = True

class Token(BaseModel):

    access_token: str  
    token_type: str   

class TokenData(BaseModel):
    mail: Optional[str] = None

class ForgotPasswordRequest(BaseModel):
    mail: EmailStr

class ResetPasswordRequest(BaseModel):
    token: str
    new_password: str

class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str

class UpdateProfileRequest(BaseModel):
    fullname: Optional[str] = None
    mail: Optional[EmailStr] = None

class EmployeeCreate(BaseModel):
    id_bracelet: int
    firstName: str
    lastName: str
    role: str

class EmployeeOut(BaseModel):
    id_bracelet: int
    lastName: str
    firstName: str
    role: str
    status: str = "offline"                       
    last_seen: Optional[datetime] = None            


    class Config:
        from_attributes = True

class DataCreate(BaseModel):
    timestamp: datetime
    state: int
    id_bracelet: int
    confidence: float
    confidence_vision: Optional[float] = 0.0  
    vision_timestamp: Optional[datetime] = None  


    @field_validator('state')
    def validate_state(cls, v):
        if v not in [0, 1, 2, 3]:
            raise ValueError('state must be 0, 1, 2, or 3')
        return v
    
    @field_validator('confidence')
    def validate_confidence(cls, v):
        if v is not None and (v < 0 or v > 1):
            raise ValueError('confidence must be between 0 and 1')
        return v


class DataOut(BaseModel):
    id: int
    timestamp: datetime
    state: int
    id_bracelet: int
    confidence: float
    confidence_vision: Optional[float] = 0.0
    vision_timestamp: Optional[datetime] = None

    class Config:
        from_attributes = True