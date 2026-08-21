from __future__ import annotations

import asyncio

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from ..config import settings
from ..database import SessionLocal
from ..models import DepositSession
from ..security.jwt import decode_access_token
from ..services import event_bus

logger = __import__("logging").getLogger("recycle.websocket")

router = APIRouter(tags=["websocket"])

# Subscribers authenticate with the standard JWT in the query string
# (WS clients cannot set headers). Ownership is enforced below: a token may
# only subscribe to operations that belong to the same user, so no other
# user's prediction / weight / points / operation state can ever be observed.
_AUTH_PARAM = "token"


def _owns_operation(operation_id: str, user_id: str) -> bool:
    db = SessionLocal()
    try:
        session = (
            db.query(DepositSession)
            .filter(DepositSession.operation_id == operation_id)
            .first()
        )
        return session is not None and session.user_id == user_id
    finally:
        db.close()


@router.websocket("/ws/deposits/{operation_id}")
async def ws_deposit_status(websocket: WebSocket, operation_id: str) -> None:
    token = websocket.query_params.get(_AUTH_PARAM, "")
    try:
        claims = decode_access_token(token, settings.jwt_secret)
    except Exception:
        await websocket.close(code=4401, reason="Unauthorized")
        return

    # Session ownership: only the owning user may observe this operation.
    if not _owns_operation(operation_id, str(claims.get("sub", ""))):
        await websocket.accept()
        await websocket.close(code=4403, reason="Forbidden")
        return

    await websocket.accept()
    queue = event_bus.subscribe(operation_id)
    try:
        await websocket.send_json({"type": "subscribed", "operation_id": operation_id})
        while True:
            # Blend queued events with a keep-alive so the socket stays alive
            # during long mechanical waits.
            try:
                message = await asyncio.wait_for(queue.get(), timeout=25.0)
            except asyncio.TimeoutError:
                await websocket.send_json({"type": "keepalive"})
                continue
            await websocket.send_json(message)
    except WebSocketDisconnect:
        pass
    finally:
        event_bus.unsubscribe(operation_id, queue)