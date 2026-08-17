from __future__ import annotations

import asyncio

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from ..config import settings
from ..security.jwt import decode_access_token
from ..services import event_bus

logger = __import__("logging").getLogger("recycle.websocket")

router = APIRouter(tags=["websocket"])

# Subscribers authenticate with the standard JWT in the query string
# (WS clients cannot set headers). Data reads are further authorized by the
# deposit router; this channel only forwards telemetry for the operation the
# user subscribed to.
_AUTH_PARAM = "token"


@router.websocket("/ws/deposits/{operation_id}")
async def ws_deposit_status(websocket: WebSocket, operation_id: str) -> None:
    token = websocket.query_params.get(_AUTH_PARAM, "")
    try:
        decode_access_token(token, settings.jwt_secret)
    except Exception:
        await websocket.close(code=4401, reason="Unauthorized")
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