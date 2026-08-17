from __future__ import annotations

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import User
from ..security import get_current_user
from ..services import PredictService
from ..services.ai_client import AiWireError

router = APIRouter(prefix="/ai", tags=["ai"])


@router.post("/predict")
def predict(
    image: UploadFile = File(...),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    image_bytes = image.file.read()
    if not image_bytes:
        raise HTTPException(status_code=422, detail="Empty image")
    try:
        return PredictService().predict(db, user, image_bytes)
    except AiWireError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc